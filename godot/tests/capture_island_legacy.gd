extends SceneTree
const Places=preload("res://scripts/map_locations.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var output:=OS.get_environment("HABITAT_ISLAND_LEGACY_CAPTURE")
	if output.is_empty() or not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):quit(1);return
	var game:Node=load("res://scenes/main.tscn").instantiate();root.add_child(game)
	game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.view.sound_enabled=false
	game.world.weather.weather_seed=1027;game.view.clock=0
	for routine in game.world.director.routines.values():routine.set_enabled(false)
	root.size=Vector2i(1280,800);root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
	for entry in Places.section("legacy_capture"):
		game.view.center=Places.point(entry.point);game.view.zoom=entry.zoom;game.view.queue_redraw()
		await process_frame;await process_frame;await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png(output.path_join(entry.id+".png"))
	game.queue_free();await process_frame;quit()
