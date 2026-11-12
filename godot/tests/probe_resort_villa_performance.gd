extends "res://tests/probe_resort_performance.gd"
func run()->void:
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	OS.set_environment("HABITAT_OPENING","standard")
	var game:Node=load("res://scenes/main_v3.tscn").instantiate()
	game.world=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json")
	root.add_child(game);game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.island_hud.set_process(false);game.chat.hide()
	await process_frame;await process_frame
	game.view.center=Vector2(80,310);game.view.follow_player=false;await process_frame
	await click_at(game.view.screen(Vector2(80,310)))
	for i in range(6000):
		game._process(.1)
		if i%20==0:await process_frame
		if not game.world._routes.has("human"):break
	check(game.world.point(game.world.actors.human).distance_to(Vector2(80,310))<1,"native original World walk reaches villa extension approach")
	await measure_walk(game,Vector2(135,365),"villa-courtyard-walk")
	check(metrics.back().arrived,"native villa courtyard target reached")
	var result:Dictionary={"metrics":metrics,"failed":failed,"display":DisplayServer.get_name(),"viewport":[1280,800],"memory_static_bytes":OS.get_static_memory_usage()}
	FileAccess.open(OS.get_environment("HABITAT_DATA_DIR").path_join("performance.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("VILLA_PERFORMANCE ",JSON.stringify(result));game.queue_free();await process_frame;quit(1 if failed else 0)
