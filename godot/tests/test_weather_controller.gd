extends SceneTree
var game: Node
var checks:=0
var failed:=false
var output: String
func _initialize() -> void:call_deferred("run")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failed=true;push_error(message)
func weather(kind: String) -> void:
	for candidate in range(1000):
		game.world.weather.weather_seed=candidate
		if game.world.weather.current().id==kind:return
	check(false,"missing weather seed "+kind)
func pair(name: String) -> void:
	for size in [Vector2i(1280,800),Vector2i(960,640)]:
		root.size=size;game._process(0);game.view.queue_redraw();await process_frame;await process_frame
		check(root.get_visible_rect().encloses(game.day_label.get_global_rect()),"weather on existing HUD fits "+str(size))
		if not output.is_empty():
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().get_size()==size,"actual requested viewport")
			root.get_texture().get_image().save_png(output.path_join(name+"-%dx%d.png"%[size.x,size.y]))
func destination(place: String,phase: String) -> void:
	var world: RefCounted=game.world;var r: RefCounted=world.director.routines.codex
	# C: Explicit free-idle mode for this cosmetic schedule-only fixture.
	world.activities.default_follow_excluded.codex=true;world.activities.release_follow("codex")
	r.set_enabled(false)
	while world.days.phase().id!=phase:world.advance(.5)
	weather("sunny");world.schedules.config.phases[phase]=[{"place":place,"weight":10}];world.schedules.config.first_after=1;world.schedules.config.chance=1
	world.schedules.next_after.clear();r.set_enabled(true);r.set_chatter(false)
	for tick in range(600):
		world.advance(.5)
		if r.kind=="schedule" and not r.owns_route and world.schedules.targets.get("codex",{}).get("place")==place and world.schedules.targets.codex.arrived:break
	check(r.kind=="schedule" and world.schedules.targets.get("codex",{}).get("place")==place and world.schedules.targets.codex.arrived,"real phase-specific schedule reached "+place)
	game.view.center=world.point(world.actors.codex);game.view.zoom=1.05
func run() -> void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):quit(1);return
	output=OS.get_environment("HABITAT_LOCAL_LIFE_CAPTURE_DIR")
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false);root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
	await process_frame
	game.world.director.set_all_enabled(false);game.chat.hide();game.chat_input.release_focus();game.view.sound_enabled=false
	game.world.hunger.enabled=false # Isolate cosmetic weather and idle schedules.
	game.view.center=game.world.point(game.world.actors.human);game.view.zoom=1.05
	var human: Dictionary=game.world.actors.human.duplicate(true)
	weather("rain");game._process(.1)
	check(game.day_label.text.ends_with("小雨") and game.world.weather.current().rain>0,"actual rain reflected in existing noninteractive HUD/renderer")
	await pair("rain")
	weather("fog");await pair("fog")
	await destination("garden","morning");await pair("schedule-garden")
	await destination("camp","dusk");await pair("schedule-camp")
	check(game.world.actors.human==human and game.links.values().all(func(link):return link._pid==-1),"cosmetic/day schedule never moves human or calls model")
	game.queue_free();await process_frame
	print("Weather controller: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)
