extends SceneTree
const Audio=preload("res://scripts/game_audio.gd")
const Helper=preload("res://tests/test_barbecue_v2.gd")
var checks:=0
var failed:=false
func check(ok:bool,msg:String)->void:
	checks+=1
	if not ok:failed=true;push_error(msg)
func _initialize()->void:call_deferred("run")
func song(audio:Node)->String:
	for item in audio.active:
		if str(item.event).begins_with("music.") and item.target>0:return item.event
	return ""
func run()->void:
	var temp:String=OS.get_environment("HABITAT_DATA_DIR");assert(temp.contains("youqi-test-"))
	var helper:=Helper.new();var w:RefCounted=helper.fresh(temp);w.intelligence.activate_presets()
	var view:Node=preload("res://scripts/island_view.gd").new();view.world=w;view.library=w.library;view.font=load("res://assets/fonts/NotoSansSC.ttf");view.sound_enabled=false;root.add_child(view);view.set_process(false);view.center=w.point(w.actors.human)
	var audio:=Audio.new();root.add_child(audio);audio.setup(w,view,temp);audio.advance(.3)
	check(audio.error.is_empty(),"production music starts without error")
	var shipped:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/audio/user-music.json"))
	for scene in shipped.tracks:
		check(audio.catalog.events.has("music."+scene),"licensed production track loaded "+scene)
		var clip:Dictionary=audio.catalog.events["music."+scene].variants.A
		check(FileAccess.get_sha256(clip.file)==clip.sha256,"production track exact hash "+scene)
	check(Audio.valid_manifest(audio.catalog),"production music preserves strict manifest contract")
	if shipped.tracks.has("dark") and shipped.tracks.has("their"):
		view.region_id="dark";audio.advance(.3)
		check(song(audio)=="music.dark","dark region chooses licensed mysterious guitar")
		view.region_id="home";var home_bounds:Array=w.home_island.config.bounds
		view.center=Vector2(home_bounds[0]+home_bounds[2]/2.0,home_bounds[1]+home_bounds[3]/2.0);audio.advance(.3)
		check(song(audio)=="music.their","real south island camera selects music box")
		view.center=w.point(w.actors.human)
	# Test the legal no-file state independently of the shipped recordings.
	for item in audio.active:audio.recycle(item.player)
	audio.active.clear()
	for id in audio.catalog.events.keys():
		if str(id).begins_with("music."):audio.catalog.events.erase(id)
	for id in audio.catalog.sources.keys():
		if str(id).begins_with("music."):audio.catalog.sources.erase(id)
	audio.trace.clear();audio.advance(.3)
	check(song(audio).is_empty(),"missing music remains silent")
	check(audio.music_status().begins_with("音乐为空"),"empty music UI status")
	# Test-only looping clips reuse short bundled synthesis, never the retired music.
	# Keep the complete validated manifest in the isolated data directory.
	var fixture:Dictionary=audio.catalog.duplicate(true)
	var selector:Dictionary=fixture.events["ui.click"].duplicate(true)
	selector.bus="Music";selector.loop=true;selector.volume_db=-22.0
	fixture.events["music.sample30"]=selector
	for id in ["day","dusk","night","rain","fireside","moon"]:
		var event:Dictionary=selector.duplicate(true);event.selection_key="music.sample30"
		fixture.events["music."+id]=event
	var manifest_path:String=temp.path_join("music-fixture.json")
	var file:=FileAccess.open(manifest_path,FileAccess.WRITE);file.store_string(JSON.stringify(fixture));file=null
	var loaded:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	check(Audio.valid_manifest(loaded),"temporary music manifest and sources validate")
	audio.catalog=loaded;audio.advance(.3)
	for id in ["day","dusk","night","rain","fireside","moon"]:
		check(audio.catalog.events.has("music."+id) and audio.catalog.events["music."+id].loop,"music loop declared "+id)
	check(song(audio)==("music.rain" if w.weather.current().id=="rain" else "music.day"),"initial music follows actual weather/day")
	for i in range(20):audio.advance(.25)
	var previous:String=song(audio)
	var bounds:Array=w.moon.config.bounds;view.center=Vector2(bounds[0]+bounds[2]/2.0,bounds[1]+bounds[3]/2.0);audio.advance(.3)
	check(song(audio)=="music.moon","camera at real moon island selects moon score")
	var incoming:Dictionary={};var outgoing:Dictionary={}
	for item in audio.active:
		if item.event=="music.moon":incoming=item
		if item.event==previous:outgoing=item
	check(not incoming.is_empty() and incoming.gain<.1 and incoming.target==1,"new track starts silent and targets full")
	check(not outgoing.is_empty() and outgoing.target==0 and outgoing.gain>0,"old track fades during overlap")
	for i in range(20):audio.advance(.25)
	check(audio.active.filter(func(a):return str(a.event).begins_with("music.")).size()==1,"crossfade releases old stream")
	view.center=w.point(w.life.station)
	check(helper.pickup(w,"wood",2) and helper.pickup(w,"mushroom",2) and helper.approach(w,w.life),"real warm meal fixture")
	check(w.life.fireside.light_host().ok and w.life.fireside.invite(["codex"]).ok and w.life.fireside.roast_host("single:mushroom").ok,"explicit real cooking")
	for i in range(600):
		w.advance(.1);audio.advance(.1)
		if w.work.jobs.get("human",{}).get("phase")=="fire_eat":break
	for i in range(4):w.advance(.1);audio.advance(.1)
	check(song(audio)=="music.fireside","actual seated meal chooses warm fireside track")
	for i in range(20):audio.advance(.1)
	check(audio.duck_gain<0,"actual eating ducks score")
	for i in range(3200):
		w.advance(.5);audio.advance(.5)
		if w.days.phase().id=="night":break
	for i in range(5):w.advance(.1);audio.advance(.1)
	check(song(audio)==("music.rain" if w.weather.current().id=="rain" else "music.night"),"actual late night selects original day projection/weather priority")
	for clip in audio.catalog.events.values():
		if clip.bus=="Music":check(float(clip.volume_db)<float(audio.catalog.events["ambience.wind"].volume_db),"score uses lower source gain than environment")
	var invalid:Dictionary=audio.catalog.duplicate(true);invalid.events["music.day"]["selection_key"]="music.day"
	check(not Audio.valid_manifest(invalid),"linked music cannot select itself")
	invalid=audio.catalog.duplicate(true);invalid.events["music.sample30"]["selection_key"]="music.day"
	check(not Audio.valid_manifest(invalid),"linked music cannot create a selection chain")
	invalid=audio.catalog.duplicate(true);invalid.events["music.day"].variants.erase("C")
	check(not Audio.valid_manifest(invalid),"linked music provides every sample choice")
	var previous_choice:String=audio.catalog.events["music.sample30"].selected
	audio.catalog.events["music.sample30"].selected="B"
	check(Audio.valid_manifest(audio.catalog) and audio.selected_variant("music.moon")=="B","sample B selects full moon arrangement B")
	check(audio.play_event("music.moon",Vector2.ZERO,"","",1,1,"variant-B-test"),"full moon B actually starts")
	var linked_clip:Dictionary=audio.catalog.events["music.moon"].variants.B
	check(audio.trace[-1].event=="music.moon" and audio.trace[-1].variant=="B" and audio.streams.has(linked_clip.file) and FileAccess.get_sha256(linked_clip.file)==linked_clip.sha256,"scheduled trace and loaded full B resource match manifest SHA")
	await process_frame;await process_frame
	check(audio.trace.any(func(e):return e.action=="native_start" and e.event=="music.moon" and e.variant=="B"),"full B resource actually starts on an engine idle")
	audio.catalog.events["music.sample30"].selected=previous_choice
	audio.enabled=false;audio.apply_mix()
	for p in audio.get_children():
		if p is AudioStreamPlayer:p.stop();p.stream=null
	await process_frame;await create_timer(.1).timeout;audio.queue_free();view.queue_free();helper.free();await process_frame;await create_timer(.1).timeout
	print("Audio music: ",checks," checks; real-advance fixture, not player mouse acceptance");quit(1 if failed else 0)
