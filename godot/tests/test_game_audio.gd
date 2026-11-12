extends SceneTree
const Audio=preload("res://scripts/game_audio.gd")
const Helper=preload("res://tests/test_barbecue_v2.gd")
var checks:=0
var failed:=false
func check(ok:bool,msg:String)->void:
	checks+=1
	if not ok:failed=true;push_error(msg)
func _initialize()->void:call_deferred("run")
func count(audio:Node,event:String)->int:return audio.trace.filter(func(e):return e.action=="scheduled" and e.event==event).size()
func run()->void:
	var temp:String=OS.get_environment("HABITAT_DATA_DIR");assert(temp.contains("youqi-test-"))
	var helper:=Helper.new();var w:RefCounted=helper.fresh(temp);w.intelligence.activate_presets()
	var view:Node=preload("res://scripts/island_view.gd").new();view.world=w;view.library=w.library;view.font=load("res://assets/fonts/NotoSansSC.ttf");view.sound_enabled=false;root.add_child(view);view.hide();view.set_process(false);view.center=w.point(w.life.station)
	w.work.visual_event("hit",w.life.station,"human")
	var audio:=Audio.new();root.add_child(audio);audio.setup(w,view,temp)
	check(audio.error.is_empty() and Audio.valid_manifest(audio.catalog) and Audio.valid_tuning(audio.tuning),"strict current data loads")
	for bus in Audio.BUSES:check(AudioServer.get_bus_index(bus)>=0,"bus exists "+bus)
	var invalid:Dictionary=audio.tuning.duplicate(true);invalid.duck_db=100;check(not Audio.valid_tuning(invalid),"out of range presentation mix rejected")
	invalid=audio.tuning.duplicate(true);invalid.speed=999;check(not Audio.valid_tuning(invalid),"unknown gameplay key rejected")
	var pack:Dictionary=audio.voice(w,"companion-2");var previous:String=w.actors["companion-2"].appearance_id
	w.actors["companion-2"].appearance_id="ai-deepseek";check(audio.voice(w,"companion-2")==pack,"voice follows personality after changing appearance")
	w.actors["companion-2"].appearance_id=previous
	var rev:int=w.revision;var rng_state:int=w.fishing.rng.state
	audio.advance(.02);check(count(audio,"tree.hit")==0,"new observer baselines old committed visual ring")
	w.work.visual_event("hit",w.life.station,"human");audio.advance(.02);audio.advance(.02)
	check(count(audio,"tree.hit")==1,"one committed hit played once")
	check(w.revision==rev and w.fishing.rng.state==rng_state,"audio advances no gameplay state or fishing RNG")
	check(audio.attenuation("tree.hit",view.center,"other")==0 and audio.attenuation("tree.hit",view.center+Vector2(1000,0),"home")==0,"region and far sounds silent")
	check(audio.attenuation("tree.hit",view.center,"home")==1,"near listener gains fully")
	var event:Dictionary=audio.catalog.events[pack.event];var cooldown:float=event.cooldown_seconds;event.cooldown_seconds=0
	for i in range(int(event.max_instances)+3):audio.play_event(pack.event,view.center,"home","companion-2")
	check(audio.active.filter(func(a):return a.event==pack.event).size()<=int(event.max_instances),"same-event polyphony capped")
	event.cooldown_seconds=cooldown;audio.advance(.02)
	check(audio.duck_gain<0,"voice playback ducks music")
	audio.advance(2);check(is_zero_approx(audio.duck_gain),"duck gain releases")
	audio.master=.32;audio.levels.Music=.21;audio.mute_unfocused=true;audio.persist()
	var preferences:=ConfigFile.new();check(preferences.load(temp.path_join("audio.cfg"))==OK and is_equal_approx(preferences.get_value("audio","master"),.32) and preferences.get_value("audio","mute_unfocused"),"local configuration persists outside world")
	audio.mute_unfocused=false;audio.master=.8;audio.apply_mix()
	check(helper.pickup(w,"wood",2) and helper.pickup(w,"mushroom",2) and helper.approach(w,w.life),"real acquired meal fixture")
	view.center=w.point(w.life.station);view.show();audio.advance(.02)
	check(w.life.fireside.light_host().ok and w.life.fireside.invite(["codex"]).ok and w.life.fireside.roast_host("single:mushroom").ok,"explicit real fire and meal accepted")
	for frame in range(6000):
		w.advance(.02);view.clock+=.02;audio.advance(.02)
		if w.life.fireside.state.current.get("eaters",[]).has("codex"):break
	check(count(audio,"fire.ignite")==1 and count(audio,"ui.invite")>=1,"real fire and committed invitation emit")
	check(count(audio,"meal.bite")>0 and count(audio,"meal.chew")>0 and count(audio,"meal.satisfied")>0,"real eating columns and completion emit bite chew satisfaction")
	check(w.hunger.rank("codex")==0 and w.life.fireside.state.current.eaters.has("codex"),"sound did not replace actual eating")
	view.center=w.point(w.actors["companion-2"])
	var before_voice:int=count(audio,pack.event)
	view.say("今天海边很暖和。","local_rules","companion-2");audio.advance(.02)
	check(count(audio,pack.event)>before_voice,"only accepted visible bubble gets resident voice")
	var emitted:int=count(audio,"tree.hit");audio.advance(0);check(count(audio,"tree.hit")==emitted,"zero delta never emits")
	for row in audio.trace:
		if row.action=="scheduled":check(int(row.instances)<=int(audio.catalog.events[row.event].max_instances),"logged event respects per-event cap")
	print("Game audio: ",checks," checks; temporary fixture, not player mouse acceptance")
	await process_frame;await process_frame
	var watched_before:int=audio.observer.watched.size()
	for i in range(100):audio.play_event("ui.click");audio.advance(.15)
	var loop_bound:int=0
	for e in audio.catalog.events.values():
		if e.loop:loop_bound+=int(e.max_instances)
	check(audio.get_child_count()<=int(audio.tuning.global_oneshot_limit)+loop_bound,"100 cues without idle frames retain bounded native players")
	await process_frame;await process_frame
	check(audio.observer.watched.size()==watched_before and audio.observer.connections.size()==watched_before,"transient audio players never accumulate UI callbacks")
	var popup:=AcceptDialog.new();root.add_child(popup);await process_frame;await process_frame
	check(audio.observer.watched.size()>watched_before,"new UI window is observed")
	popup.queue_free();await process_frame;await process_frame
	check(audio.observer.watched.size()==watched_before and audio.observer.connections.size()==watched_before,"closed UI removes its callbacks")
	audio.levels.Music=0;audio.apply_mix();check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")),"zero category slider truly mutes")
	audio.enabled=false;audio.apply_mix()
	for player in audio.get_children():
		if player is AudioStreamPlayer:player.stop();player.stream=null
	await process_frame;await create_timer(.1).timeout
	audio.queue_free();view.queue_free();helper.free();await process_frame;await create_timer(.1).timeout;quit(1 if failed else 0)
