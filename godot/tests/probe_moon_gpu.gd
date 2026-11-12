extends "res://tests/capture_home_v3_ui_polish.gd"
func run()->void:
	output=OS.get_environment("HABITAT_MOON_EVIDENCE")
	if output.is_empty() or not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):quit(1);return
	game=load("res://scenes/main_v3.tscn").instantiate();game.world=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");root.add_child(game)
	game.save_enabled=false;game.set_process(false);game.set_process_input(false);game.island_hud.set_process(false);game.view.set_process(false);game.view.set_process_unhandled_input(false);game.view.sound_enabled=false;game.world.director.set_all_enabled(false)
	game.world.catalog.regions.home.layout.art_cameras.island=game.world.map_anchor("moon.overview")
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	phase("afternoon");DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);Engine.max_fps=0
	await probe("island",10,true);await probe("plaza",1,true)
	var file:=FileAccess.open(output.path_join("B-performance.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"samples":performance,"adapter":RenderingServer.get_video_adapter_name(),"west_cache_size":[game.view.static_west.size.x,game.view.static_west.size.y],"grid_cells":350*128},"  "))
	print("Moon GPU preflight actual viewport: "+str(performance));quit()
