extends SceneTree
const M=preload("res://tests/memory_fixture.gd")
const Fish=preload("res://tests/fishing_fixture.gd")
var game: Node
var checks:=0
var failed:=false
var output: String
func _initialize() -> void:call_deferred("run")
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failed=true;push_error(label)
func notices() -> Array:return game.world.director.events.filter(func(event):return event.context=="memory_reminder")
func step(delta: float) -> void:game._process(delta);game.view._process(delta)
func shot(name: String) -> void:
	await process_frame;await process_frame
	if not output.is_empty():await RenderingServer.frame_post_draw
	var entries: Array=game.view.speech_layout().filter(func(entry):return entry.actor_id=="codex")
	check(entries.size()==1 and entries[0].source=="local_rules" and not entries[0].text.begins_with("日常 · "),"real viewport retains local source without daily prefix "+name)
	if not entries.is_empty():check(root.get_visible_rect().encloses(entries[0].box),"memory bubble fits viewport "+name)
	if not output.is_empty():root.get_texture().get_image().save_png(output.path_join(name+".png"))
func run() -> void:
	var directory:=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(1);return
	output=OS.get_environment("HABITAT_MEMORY_CAPTURE_DIR")
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false);root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
	await process_frame
	var world: RefCounted=game.world;world.director.set_all_enabled(false);game.view.sound_enabled=false
	world.hunger.enabled=false # Preserve the original non-hungry reminder-gate fixture.
	check(M.populate(world,directory),"controller creates genuine contributed house and shared barbecue")
	check(Fish.walk(world,"human",[51,44]) and Fish.walk(world,"codex",[53,44]),"explicit real routes bring partners near")
	var reminders: RefCounted=world.director.memory_reminders
	check(reminders.settings==game.local_settings and reminders.path==directory.path_join("local-life.cfg"),"same settings owner avoids overwriting ordinary switches")
	reminders.config.first_after=0;reminders.config.min_age=0;reminders.config.check_interval=.1;reminders.config.kinds=["house_completed"]
	world.days.config.small_after=world.days.day_seconds+1;world.days.config.greeting_after=world.days.day_seconds+1
	# C: idle-reminder fixture must not auto-start an unrelated follow route.
	world.activities.default_follow_excluded["codex"]=true
	var routine: RefCounted=world.director.routines.codex;routine.set_enabled(true);routine.chatter=true;routine.next_speech=0;routine.next_decision=0;routine.last_walk=0
	for key in routine.preferences.weights:routine.preferences.weights[key]=0
	game.chat.hide();game.chat_input.release_focus()
	game._bound_companion_event({"kind":"question","id":"memory-question","text":"先等你回答，再聊旧事。","choices":["稍等"]},"codex")
	step(1)
	check(routine.held and notices().is_empty() and game.chat.visible,"actual pending question holds reminders and keeps dialogue visible")
	game._cancel_resident_turn("codex");game.chat.hide();game.chat_input.release_focus()
	game._stop_resident("codex")
	for tick in range(1190):step(.1)
	check(notices().is_empty(),"cancel and explicit stop quiet period respected in controller")
	for tick in range(1200):
		step(.1)
		if not notices().is_empty():break
	check(notices().size()==1 and notices()[0].source=="local_rules","idle real controller emits one reminder after quiet period")
	check(game.view.speech_by_actor.get("codex",{}).get("source")=="local_rules","existing event drain renders reminder as local speech")
	game.view.follow_player=false;game.view.center=world.point(world.actors.human)+Vector2(1,-1);game.view.zoom=1.35
	root.size=Vector2i(1280,800);await shot("memory-reminder-1280x800")
	root.size=Vector2i(960,640);await shot("memory-reminder-960x640")
	game._save_local_settings();var settings:=ConfigFile.new();settings.load(reminders.path)
	check(settings.get_value(reminders.section("codex"),"mentioned",[]).size()==1,"ordinary settings save retains persisted mention")
	step(301);step(1);check(notices().size()==1,"main loop and reload-safe marker do not repeat same house")
	game._bound_companion_event({"kind":"question","id":"memory-question-2","text":"现在有个新问题。","choices":["稍等"]},"codex");step(.1)
	check(game.chat.visible and game.view.speech_by_actor.get("codex",{}).get("source")=="model", "new actual question replaces local bubble before any reminder can interrupt")
	check(game.links.values().all(func(connection):return connection._pid==-1),"no real model process launched")
	game.queue_free();await process_frame
	print("Memory reminders controller: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)
