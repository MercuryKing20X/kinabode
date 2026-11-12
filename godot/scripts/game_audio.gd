extends Node
const LocalText=preload("res://scripts/localization.gd")
## Presentation only: reads accepted world facts, never sends commands or consumes resources.
signal sound_test_finished(message:String)
const BUSES=["Music","Ambience","Effects","Voices"]
const DATA="res://content/audio/sounds.json"
const TUNING="res://content/audio/runtime.json"
const MUSIC_SLOTS="res://content/audio/music-slots.json"
const MUSIC_SCENES=["day","dusk","night","rain","fireside","moon"]
var catalog:Dictionary={}
var tuning:Dictionary={}
var error:=""
var enabled:=true
var speech_enabled:=true
var mute_unfocused:=false
var focused:=true
var master:=1.0
var levels:Dictionary={"Music":1.0,"Ambience":1.0,"Effects":1.0,"Voices":1.0}
var config:=ConfigFile.new()
var config_path:=""
var clock:=0.0
var duck_until:=0.0
var duck_gain:=0.0
var listener:=Vector2.ZERO
var region_id:="home"
var active:Array=[]
var idle_players:Array[AudioStreamPlayer]=[]
var last_play:Dictionary={}
var streams:Dictionary={}
var trace:Array=[]
var trace_path:=""
var rng:=RandomNumberGenerator.new()
var world_ref:WeakRef
var view_ref:WeakRef
var observer:RefCounted
var shutting_down:=false
var native_flush_queued:=false
var native_generation:=0
var next_mix_log:=0.0
var sound_test_busy:=false
var music_preview_active:=false
var dropped:Dictionary={}
var last_take_hash:Dictionary={}
var music_slots:Dictionary={"version":1,"slots":{"day":[],"dusk":[],"night":[],"rain":[],"fireside":[],"moon":[]}}

static func number(v:Variant,lo:float,hi:float)->bool:
	return (v is int or v is float) and is_finite(v) and v>=lo and v<=hi
static func sha256(value:Variant)->bool:
	if not value is String or value.length()!=64:return false
	for c in value:
		if c not in "0123456789abcdef":return false
	return true
static func exact(d:Variant,keys:Array)->bool:
	return d is Dictionary and d.size()==keys.size() and keys.all(func(k):return d.has(k))
static func valid_voice(v:Variant)->bool:
	return exact(v,["event","pitch","max_blips"]) and v.event in ["voice.soft","voice.bright","voice.crisp","voice.low"] and number(v.pitch,.5,2) and number(v.max_blips,1,1)
static func valid_date(s:Variant)->bool:
	if not s is String or s.length()!=10 or s[4]!="-" or s[7]!="-":return false
	for i in range(10):
		if i not in [4,7] and s[i] not in "0123456789":return false
	return true
static func valid_clip(clip:Variant,sources:Dictionary)->bool:
	return exact(clip,["file","sha256","source_id"]) and clip.file is String and clip.file.begins_with("res://content/audio/") and ".." not in clip.file and clip.file.get_extension() in ["wav","ogg"] and sha256(clip.sha256) and clip.source_id is String and clip.source_id in sources
static func valid_music_slots(v:Variant)->bool:
	if not exact(v,["version","slots"]) or not number(v.version,1,1) or not exact(v.slots,MUSIC_SCENES):return false
	for scene in MUSIC_SCENES:
		var names:Variant=v.slots[scene]
		if not names is Array or names.size()>16:return false
		for name in names:
			if not name is String or name.length()>180 or not name.begins_with(scene+"-") or "/" in name or "\\" in name or ".." in name or name.get_extension().to_lower() not in ["wav","mp3","ogg","flac","m4a"]:return false
	return true
static func valid_tuning(v:Variant)->bool:
	var keys:Array=["version","default_enabled","default_mute_unfocused","default_master","bus_levels","duck_db","duck_release_seconds","crossfade_seconds","step_walk_tiles","step_run_tiles","step_global_gap_seconds","hunger_intervals_seconds","voice_default","global_oneshot_limit","environment_refresh_seconds","run_step_gain","main_waves_gain","moon_waves_gain"]
	if not v is Dictionary or not v.has_all(keys) or v.keys().any(func(k):return k not in keys+["nature","wind","targets_dbfs","speech_gap_seconds","speech_max_blips","speech_near_tiles"]):return false
	if v.has("nature"):
		if not exact(v.nature,["bird_interval_min","bird_interval_max"]):return false
		if not number(v.nature.bird_interval_min,30,300) or not number(v.nature.bird_interval_max,v.nature.bird_interval_min,300):return false
	if v.has("wind"):
		if not exact(v.wind,["home_base","home_peak","interval_min","interval_max","duration_min","duration_max"]):return false
		for key in ["home_base","home_peak"]:
			if not number(v.wind[key],0,1):return false
		for key in ["interval_min","interval_max","duration_min","duration_max"]:
			if not number(v.wind[key],1,120):return false
	for key in ["speech_gap_seconds","speech_max_blips","speech_near_tiles"]:
		if v.has(key) and not number(v[key],1,60):return false
	if v.has("speech_max_blips") and v.speech_max_blips!=1:return false
	if v.has("targets_dbfs"):
		var targets:Variant=v.targets_dbfs
		if not exact(targets,["voice","ui","ambience","music","duck_floor","peak_max"]):return false
		for category in ["voice","ui","ambience","music"]:
			var bounds:Variant=targets[category]
			if not bounds is Array or bounds.size()!=2 or not number(bounds[0],-120,0) or not number(bounds[1],bounds[0],0):return false
		if not number(targets.duck_floor,-120,0) or not number(targets.peak_max,-60,0):return false
	if v.version!=1 or not v.default_enabled is bool or not v.default_mute_unfocused is bool or not number(v.default_master,0,1) or not exact(v.bus_levels,BUSES):return false
	if v.bus_levels.values().any(func(x):return not number(x,0,1)) or not valid_voice(v.voice_default):return false
	for k in ["duck_release_seconds","crossfade_seconds","step_walk_tiles","step_run_tiles","step_global_gap_seconds"]:
		if not number(v[k],.02,20):return false
	for k in ["environment_refresh_seconds","run_step_gain","main_waves_gain","moon_waves_gain"]:
		if not number(v[k],.05,2):return false
	if not number(v.duck_db,-18,0) or not number(v.global_oneshot_limit,1,32) or v.global_oneshot_limit!=floor(v.global_oneshot_limit):return false
	return v.hunger_intervals_seconds is Array and v.hunger_intervals_seconds.size()==3 and v.hunger_intervals_seconds.all(func(x):return number(x,10,600)) and v.hunger_intervals_seconds[0]>=v.hunger_intervals_seconds[1] and v.hunger_intervals_seconds[1]>=v.hunger_intervals_seconds[2]
static func valid_manifest(v:Variant)->bool:
	if not exact(v,["version","events","sources"]) or v.version!=1 or not v.events is Dictionary or not v.sources is Dictionary or v.events.size()>128:return false
	for source in v.sources.values():
		if not exact(source,["kind","script","parameters","license","url","sha256"]) or source.kind not in ["synthesis","soundfont","recording","licensed_music"] or not source.script is String or not source.parameters is Dictionary or not source.license is String or source.license.is_empty() or not source.url is String or not sha256(source.sha256):return false
		if source.parameters.has("rms_dbfs") != source.parameters.has("peak_dbfs"):return false
		if source.parameters.has("rms_dbfs") and (not number(source.parameters.rms_dbfs,-120,0) or not number(source.parameters.peak_dbfs,source.parameters.rms_dbfs,0)):return false
		if source.kind=="licensed_music":
			var p:Dictionary=source.parameters
			if not exact(p,["file","title","author","license","url","sha256","rms_dbfs","peak_dbfs"]) or source.license not in ["CC0-1.0","CC-BY-4.0"] or not p.author is String or p.author.is_empty() or not p.title is String or not source.url.begins_with("https://") or p.license!=source.license or p.url!=source.url or p.sha256!=source.sha256:return false
		if source.kind=="recording":
			var p:Dictionary=source.parameters
			if not exact(p,["author","download_date","archive_url","archive_sha256","input_file","input_sha256","sample_rate","lowpass_hz","compression_exponent","target_rms_dbfs","rms_dbfs","peak_dbfs"]):return false
			if source.license!="CC0-1.0" or not source.url.begins_with("https://") or not p.author is String or p.author.is_empty() or not valid_date(p.download_date) or not p.archive_url is String or not p.archive_url.begins_with("https://") or not sha256(p.archive_sha256) or not sha256(p.input_sha256):return false
			if not p.input_file is String or not p.input_file.begins_with("tmp/sound-v2-downloads/raw/") or ".." in p.input_file or p.sample_rate!=24000 or not number(p.lowpass_hz,100,12000) or not number(p.compression_exponent,.2,1) or not number(p.target_rms_dbfs,-120,0):return false
	for id in v.events:
		var e:Variant=v.events[id]
		var required:Array=["bus","variants","selected","volume_db","pitch_min","pitch_max","max_instances","near_tiles","far_tiles","loop","cooldown_seconds"]
		if not id is String or id.is_empty() or not e is Dictionary or not e.has_all(required) or e.keys().any(func(k):return k not in required+["selection_key"]):return false
		if e.bus not in BUSES or not e.loop is bool or not e.variants is Dictionary or e.variants.is_empty() or e.variants.size()>3 or not e.selected is String or e.selected not in e.variants:return false
		if not number(e.volume_db,-60,0) or not number(e.pitch_min,.5,2) or not number(e.pitch_max,e.pitch_min,2) or not number(e.max_instances,1,8) or e.max_instances!=floor(e.max_instances) or not number(e.near_tiles,0,64) or not number(e.far_tiles,e.near_tiles+.01,128) or not number(e.cooldown_seconds,0,600):return false
		for key in e.variants:
			var clip:Variant=e.variants[key]
			if key not in ["A","B","C"] or not clip is Dictionary or not clip.has_all(["file","sha256","source_id"]) or clip.keys().any(func(k):return k not in ["file","sha256","source_id","takes"]):return false
			var first:Dictionary={"file":clip.file,"sha256":clip.sha256,"source_id":clip.source_id}
			if not valid_clip(first,v.sources):return false
			if clip.has("takes"):
				if not clip.takes is Array or clip.takes.size()<2 or clip.takes.size()>3 or clip.takes[0]!=first:return false
				var hashes:Dictionary={}
				for take in clip.takes:
					if not valid_clip(take,v.sources) or hashes.has(take.sha256):return false
					hashes[take.sha256]=true
	for id in v.events:
		var e:Dictionary=v.events[id]
		if not e.has("selection_key"):continue
		if e.bus!="Music" or not e.selection_key is String or e.selection_key==id or not v.events.has(e.selection_key):return false
		var selector:Dictionary=v.events[e.selection_key]
		if selector.bus!="Music" or selector.has("selection_key") or selector.variants.keys().any(func(k):return not e.variants.has(k)):return false
	return true
func setup(world:RefCounted,view:Node,directory:String)->void:
	world_ref=weakref(world);view_ref=weakref(view);rng.seed=3103107
	var raw:Variant=JSON.parse_string(FileAccess.get_file_as_string(DATA))
	var rules:Variant=JSON.parse_string(FileAccess.get_file_as_string(TUNING))
	if not valid_manifest(raw) or not valid_tuning(rules):error=LocalText.text("system.game_audio.the_sound_manifest_is_invalid_audio_was_safely_skipped");return
	if FileAccess.file_exists(MUSIC_SLOTS):
		var slots:Variant=JSON.parse_string(FileAccess.get_file_as_string(MUSIC_SLOTS))
		if valid_music_slots(slots):music_slots=slots
		else:error=LocalText.text("system.game_audio.the_music_catalog_is_invalid_music_is_unavailable")
	view.sound_enabled=false
	for legacy_player in view.sounds.values():legacy_player.stop()
	catalog=raw;load_user_music();tuning=rules;levels=tuning.bus_levels.duplicate();enabled=tuning.default_enabled;mute_unfocused=tuning.default_mute_unfocused;master=tuning.default_master
	config_path=directory.path_join("audio.cfg");config.load(config_path)
	for key in ["enabled","mute_unfocused","speech_enabled"]:
		var value:Variant=config.get_value("audio",key,get(key))
		if value is bool:set(key,value)
	var stored:Variant=config.get_value("audio","master",master)
	if number(stored,0,1):master=float(stored)
	for bus in BUSES:
		stored=config.get_value("audio",bus,levels[bus])
		if number(stored,0,1):levels[bus]=float(stored)
		if AudioServer.get_bus_index(bus)<0:AudioServer.add_bus();AudioServer.set_bus_name(AudioServer.bus_count-1,bus);AudioServer.set_bus_send(AudioServer.bus_count-1,"Master")
	trace_path=OS.get_environment("HABITAT_AUDIO_TRACE")
	apply_mix()
	observer=preload("res://scripts/game_audio_observer.gd").new(self)
# Separate licensed music manifest; absence keeps the legal silent state.
func load_user_music()->void:
	var path:="res://content/audio/user-music.json"
	if not FileAccess.file_exists(path):return
	var data:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not exact(data,["version","tracks"]) or data.version!=1 or not data.tracks is Dictionary:return
	for scene in data.tracks:
		var t:Variant=data.tracks[scene]
		if scene not in ["day","dusk","night","rain","fireside","moon","dark","their"] or not exact(t,["file","title","author","license","url","sha256","rms_dbfs","peak_dbfs"]):continue
		if not t.file is String or not t.file.begins_with("res://content/audio/user-music/") or ".." in t.file or t.file.get_extension() not in ["wav","ogg"] or not sha256(t.sha256):continue
		if t.license not in ["CC0-1.0","CC-BY-4.0"] or not t.url is String or not t.url.begins_with("https://") or not t.title is String or not t.author is String:continue
		if not number(t.rms_dbfs,-120,0) or not number(t.peak_dbfs,t.rms_dbfs,0) or FileAccess.get_sha256(t.file)!=t.sha256:continue
		var id:String="music."+scene
		catalog.sources[id]={"kind":"licensed_music","script":"tools/audio/prepare_user_music.py","parameters":t.duplicate(true),"license":t.license,"url":t.url,"sha256":t.sha256}
		catalog.events[id]={"bus":"Music","variants":{"A":{"file":t.file,"sha256":t.sha256,"source_id":id}},"selected":"A","volume_db":-6.0,"pitch_min":1.0,"pitch_max":1.0,"max_instances":1,"near_tiles":0.0,"far_tiles":128.0,"loop":true,"cooldown_seconds":0.0}
func music_status()->String:
	return LocalText.text("ui.audio.music_empty") if not catalog.get("events",{}).keys().any(func(id):return str(id).begins_with("music.")) else LocalText.text("ui.audio.music_ready")
func persist()->void:
	if config_path.is_empty():return
	for key in ["enabled","mute_unfocused","speech_enabled","master"]:config.set_value("audio",key,get(key))
	for bus in BUSES:config.set_value("audio",bus,levels[bus])
	if config.save(config_path)!=OK:error=LocalText.text("system.game_audio.sound_preferences_could_not_be_saved")
func apply_mix()->void:
	if not speech_enabled:
		for i in range(active.size()-1,-1,-1):
			if str(active[i].event).begins_with("voice."):recycle(active[i].player);active.remove_at(i)
	AudioServer.set_bus_mute(0,not enabled or master<=0 or (mute_unfocused and not focused))
	AudioServer.set_bus_volume_db(0,linear_to_db(maxf(master,.0001)))
	for bus in BUSES:
		var index:int=AudioServer.get_bus_index(bus)
		if index>=0:
			AudioServer.set_bus_mute(index,float(levels.get(bus,1))<=0)
			AudioServer.set_bus_volume_db(index,linear_to_db(maxf(float(levels.get(bus,1)),.0001))+(duck_gain if bus=="Music" else 0.0))
func _notification(what:int)->void:
	if what==NOTIFICATION_PREDELETE:shutdown()
	elif what==NOTIFICATION_APPLICATION_FOCUS_IN:focused=true;apply_mix()
	elif what==NOTIFICATION_APPLICATION_FOCUS_OUT:focused=false;apply_mix()
func attenuation(id:String,at:Vector2,region:String)->float:
	if region!=region_id:return 0.0
	var e:Dictionary=catalog.events[id];var d:float=listener.distance_to(at)
	return 1.0-smoothstep(float(e.near_tiles),float(e.far_tiles),d)
func voice(world:RefCounted,id:String)->Dictionary:
	var main:String=str(world.intelligence.preset(id).get("main_trait",world.intelligence.tag(id)))
	return world.intelligence.catalog.traits.get(main,{}).get("voice",tuning.voice_default).duplicate(true)
func _log(row:Dictionary)->void:
	row["time"]=snappedf(clock,.001);trace.append(row)
	if trace.size()>256:trace.pop_front()
	if not trace_path.is_empty():
		var f:=FileAccess.open(trace_path,FileAccess.READ_WRITE if FileAccess.file_exists(trace_path) else FileAccess.WRITE)
		if f!=null:f.seek_end();f.store_line(JSON.stringify(row))
func selected_variant(id:String)->String:
	var e:Dictionary=catalog.events[id]
	return str(catalog.events[e.selection_key].selected) if e.has("selection_key") else str(e.selected)
func signal_levels(id:String,variant:String,gain_db:float,take:int=-1)->Dictionary:
	var clip:Dictionary=catalog.events[id].variants[variant]
	if take>=0:clip=clip.takes[take]
	var parameters:Dictionary=catalog.sources[clip.source_id].parameters
	if not parameters.has("rms_dbfs"):return {}
	return {"rms_dbfs":float(parameters.rms_dbfs)+gain_db,"peak_dbfs":float(parameters.peak_dbfs)+gain_db}
func _stream(id:String,clip:Dictionary)->AudioStream:
	var path:String=clip.file
	if not streams.has(path):
		if FileAccess.get_sha256(path)!=clip.sha256:error=LocalText.text("system.game_audio.sound_file_validation_failed")+id;return null
		streams[path]=AudioStreamWAV.load_from_file(path) if (path.begins_with("res://content/audio/cat/") or path.begins_with("res://content/audio/user-music/")) and path.ends_with(".wav") else load(path)
	return streams[path]
func priority(id:String,key:String="")->int:
	if key.begins_with("sound-test:"):return 6
	if id.begins_with("voice."):return 5
	if id in ["fishing.bite","fire.ignite","fire.refuel","meal.satisfied","fish.release","ui.fish_card","ui.invite","fishing.cast","fish.flap","ui.click","torch.ignite","torch.plant","torch.lift","torch.warning","dark.kindling","dark.beacon"]:return 4
	if id.begins_with("step."):return 3
	if id.begins_with("ambience."):return 2
	return 1
func drop_event(id:String,reason:String,actor:String="")->void:
	dropped[id]=int(dropped.get(id,0))+1
	_log({"action":"dropped","event":id,"reason":reason,"actor":actor,"active_total":active.size()})
func play_event(id:String,at:Vector2=Vector2.ZERO,region:String="",actor:String="",pitch:float=1,gain:float=1,key:String="")->bool:
	if id.begins_with("voice.") and not speech_enabled:return false
	if shutting_down or catalog.is_empty() or not catalog.events.has(id) or not enabled or (mute_unfocused and not focused):return false
	var e:Dictionary=catalog.events[id]
	var preview:bool=key.begins_with("sound-test:")
	if not preview and clock-float(last_play.get(id,-1000))<float(e.cooldown_seconds):drop_event(id,"cooldown",actor);return false
	if not preview and active.filter(func(a):return a.event==id).size()>=int(e.max_instances):drop_event(id,"event_limit",actor);return false
	var spatial:float=attenuation(id,at,region) if not region.is_empty() else 1.0
	if spatial<=.001 or gain<=.001:return false
	var variant:String=selected_variant(id);var clip:Dictionary=e.variants[variant];var take:=-1
	if clip.has("takes"):
		var candidates:Array=[]
		for i in range(clip.takes.size()):
			if clip.takes[i].sha256!=last_take_hash.get(id,""):candidates.append(i)
		if candidates.is_empty():
			for i in range(clip.takes.size()):candidates.append(i)
		take=int(candidates[rng.randi_range(0,candidates.size()-1)]);clip=clip.takes[take]
	var stream:AudioStream=_stream(id,clip)
	if stream==null:return false
	if active.size()>=int(tuning.global_oneshot_limit):
		var lowest:int=priority(id,key);var victim:=-1
		for i in range(active.size()):
			var value:int=priority(active[i].event,active[i].key)
			if active[i].loop and float(active[i].target)<=.001:value=0
			if value<lowest:lowest=value;victim=i
		if victim<0:drop_event(id,"global_limit",actor);return false
		var removed:Dictionary=active[victim];drop_event(removed.event,"preempted",removed.actor);recycle(removed.player);active.remove_at(victim)
	if e.loop and stream is AudioStreamWAV:
		stream=stream.duplicate();stream.loop_mode=AudioStreamWAV.LOOP_FORWARD;stream.loop_end=int(stream.get_length()*stream.mix_rate)
	elif e.loop and stream is AudioStreamOggVorbis:stream=stream.duplicate();stream.loop=true
	var player:AudioStreamPlayer=idle_players.pop_back() if not idle_players.is_empty() else AudioStreamPlayer.new();player.bus=e.bus;player.stream=stream;player.pitch_scale=clampf(pitch*rng.randf_range(e.pitch_min,e.pitch_max),.4,2.5);player.volume_db=float(e.volume_db)+linear_to_db(spatial*(.0001 if e.loop else gain));if player.get_parent()==null:add_child(player)
	var entry:Dictionary={"event":id,"variant":variant,"take":take,"key":key,"player":player,"native_started":false,"loop":e.loop,"at":at,"region":region,"actor":actor,"gain":0.0 if e.loop else gain,"target":gain,"end":clock+stream.get_length()/player.pitch_scale}
	if take>=0:last_take_hash[id]=clip.sha256
	active.append(entry);last_play[id]=clock
	if not native_flush_queued:
		native_flush_queued=true;call_deferred("flush_native",native_generation)
	if e.bus=="Voices" or id in ["meal.bite","meal.chew"]:duck_until=maxf(duck_until,clock+stream.get_length()/player.pitch_scale+.2)
	var gain_db:float=player.volume_db+linear_to_db(maxf(master*float(levels[e.bus]),.0001))+(duck_gain if e.bus=="Music" else 0.0)
	var measured:Dictionary=signal_levels(id,variant,gain_db,take)
	_log({"action":"scheduled","event":id,"variant":variant,"take":take,"file_sha256":clip.sha256,"actor":actor,"region":region,"position":[at.x,at.y],"volume_db":player.volume_db,"gain_db":gain_db,"effective_db":measured.get("rms_dbfs",gain_db),"peak_dbfs":measured.get("peak_dbfs",null),"pitch":player.pitch_scale,"instances":active.filter(func(a):return a.event==id).size(),"active_total":active.size(),"key":key})
	return true
func flush_native(generation:int)->void:
	if shutting_down or generation!=native_generation:return
	native_flush_queued=false
	# One native dispatch per actual engine idle. A virtual simulation can advance
	# many times before that idle; retired requests must never flood the mixer.
	for item in active:
		if item.native_started or not is_instance_valid(item.player) or item.player.stream==null:continue
		item.player.play();item.native_started=true
		var bus:String=catalog.events[item.event].bus
		var gain_db:float=item.player.volume_db+linear_to_db(maxf(master*float(levels[bus]),.0001))+(duck_gain if bus=="Music" else 0.0)
		var measured:Dictionary=signal_levels(item.event,item.variant,gain_db,int(item.take))
		_log({"action":"native_start","event":item.event,"variant":item.variant,"take":item.take,"actor":item.actor,"region":item.region,"position":[item.at.x,item.at.y],"volume_db":item.player.volume_db,"gain_db":gain_db,"effective_db":measured.get("rms_dbfs",gain_db),"peak_dbfs":measured.get("peak_dbfs",null),"pitch":item.player.pitch_scale,"key":item.key,"wall_msec":Time.get_ticks_msec(),"instances":active.filter(func(a):return a.event==item.event and a.native_started).size(),"active_total":active.size()})
func test_sounds()->void:
	if sound_test_busy or shutting_down:return
	sound_test_busy=true
	var missing_music:=false
	var missing_sound:=false
	for id in ["voice.soft","step.grass","ambience.fire","music.day"]:
		await get_tree().create_timer(.3).timeout
		if shutting_down or not is_inside_tree():break
		if not catalog.events.has(id):
			if id.begins_with("music."):missing_music=true
			else:missing_sound=true
			continue
		var bus:String=catalog.events[id].bus
		if not enabled or master<=0 or float(levels.get(bus,0))<=0 or (mute_unfocused and not focused):missing_sound=true;continue
		var key:String="sound-test:"+id
		if not play_event(id,Vector2.ZERO,"","",1,1,key):missing_sound=true;continue
		var seconds:=1.0
		for item in active:
			if item.key!=key:continue
			seconds=minf(1.0,item.player.stream.get_length())
			if item.loop:item.gain=1.0;item.player.volume_db=float(catalog.events[id].volume_db)
		await get_tree().create_timer(seconds).timeout
		if shutting_down or not is_inside_tree():break
		for i in range(active.size()-1,-1,-1):
			if active[i].key==key:recycle(active[i].player);active.remove_at(i)
	sound_test_busy=false
	if not shutting_down:
		var result:=LocalText.text("system.game_audio.some_sounds_did_not_play_check_switches_and_volume") if missing_sound else LocalText.text("system.game_audio.test_finished")
		if missing_music:result+=LocalText.text("system.game_audio.no_music_tracks_added")
		sound_test_finished.emit(result)
func loop_event(key:String,id:String,gain:float,at:Vector2=Vector2.ZERO,region:String="")->void:
	if id.begins_with("ambience.") and gain>.001:
		var claimed:int=active.filter(func(a):return str(a.event).begins_with("ambience.") and float(a.target)>.001).size()
		var existing:bool=active.any(func(a):return a.key==key and a.event==id and float(a.target)>.001)
		if not existing and claimed>=maxi(1,int(tuning.global_oneshot_limit)-2):return
	for item in active:
		if item.key==key and item.event==id:item.target=gain;item.at=at;item.region=region;return
	if gain>.001:play_event(id,at,region,"",1,gain,key)
func advance(delta:float)->void:
	if shutting_down or delta<=0 or catalog.is_empty():return
	clock+=delta
	if view_ref!=null and is_instance_valid(view_ref.get_ref()):
		var view:Node=view_ref.get_ref();listener=view.center;region_id=view.region_id
	duck_gain=move_toward(duck_gain,float(tuning.duck_db) if clock<duck_until else 0,delta*absf(float(tuning.duck_db))/float(tuning.duck_release_seconds));apply_mix()
	for i in range(active.size()-1,-1,-1):
		var item:Dictionary=active[i]
		if not item.loop and clock>=float(item.end):recycle(item.player);active.remove_at(i);continue
		if item.loop:
			item.gain=move_toward(float(item.gain),float(item.target),delta/float(tuning.crossfade_seconds))
			var spatial:float=attenuation(item.event,item.at,item.region) if not str(item.region).is_empty() else 1.0
			item.player.volume_db=float(catalog.events[item.event].volume_db)+linear_to_db(maxf(float(item.gain)*spatial,.0001))
			if float(item.gain)<=.001 and float(item.target)<=.001:_log({"action":"stop","event":item.event,"key":item.key});recycle(item.player);active.remove_at(i)
	if observer!=null:observer.advance(delta)
	if clock>=next_mix_log:
		next_mix_log=clock+1.0
		for item in active:
			if item.loop:
				var bus:String=catalog.events[item.event].bus
				var gain_db:float=item.player.volume_db+linear_to_db(maxf(master*float(levels[bus]),.0001))+(duck_gain if bus=="Music" else 0.0)
				var measured:Dictionary=signal_levels(item.event,item.variant,gain_db,int(item.take))
				_log({"action":"mix","event":item.event,"key":item.key,"gain":item.gain,"target":item.target,"volume_db":item.player.volume_db,"duck_db":duck_gain,"gain_db":gain_db,"effective_db":measured.get("rms_dbfs",gain_db),"peak_dbfs":measured.get("peak_dbfs",null)})

func recycle(player:AudioStreamPlayer)->void:
	player.stop();player.stream=null;idle_players.append(player)
func shutdown()->void:
	if shutting_down:return
	shutting_down=true;native_generation+=1;native_flush_queued=false
	if observer!=null:observer.dispose();observer=null
	for player in get_children():
		if player is AudioStreamPlayer:player.stop();player.stream=null
	# AudioServer releases stopped native playbacks on its mixer thread. Drain
	# two actual driver boundaries before the tree can quit on this same frame.
	# This is shutdown only; it never advances/changes any world clock or rule.
	if not active.is_empty():
		for boundary in range(2):
			var next_mix:float=maxf(0.0,AudioServer.get_time_to_next_mix())
			OS.delay_usec(int(ceil(minf(.25,next_mix+2.0/AudioServer.get_mix_rate())*1000000.0)))
	active.clear();idle_players.clear();streams.clear()

func _exit_tree()->void:
	shutdown()
