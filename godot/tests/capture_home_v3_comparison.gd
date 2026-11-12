extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var output:String=OS.get_environment("HABITAT_STAGE2_EVIDENCE")
	if output.is_empty() or not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):quit(1);return
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1280,800)
	var records:Array=[]
	for profile in ["legacy","showcase"]:
		var game:Node=load("res://scenes/main.tscn").instantiate()
		game.world=preload("res://scripts/world_state.gd").new("res://content/world.json" if profile=="legacy" else "res://content/home-v3/world.json")
		root.add_child(game);game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.view.sound_enabled=false;game.world.director.set_all_enabled(false)
		for child in game.get_children():
			if child is CanvasLayer:child.hide()
		var human:Array=game.world.actors.human.position.duplicate()
		if profile=="legacy":
			game._house_scenario();assert(game.world.objects["home.house.01"].stage_index==5)
		for seed in range(1000):
			game.world.weather.weather_seed=seed
			if game.world.weather.current().id=="sunny":break
		var size:Array=game.world.catalog.regions.home.size;game.view.center=Vector2(size[0]/2.0,size[1]/2.0);game.view.follow_player=false;game.view.zoom=1.0/6
		if profile=="showcase":game.view.overview=true;game.view.overview_factor=6
		game.view.queue_redraw();await process_frame;await process_frame;await RenderingServer.frame_post_draw
		var filename:String="comparison-"+profile+"-overview-1over6.png";assert(root.get_texture().get_image().save_png(output.path_join(filename))==OK)
		assert(game.world.actors.human.position==human)
		for link in game.links.values():assert(link._pid<=0)
		records.append({"file":filename,"profile":profile,"camera":[game.view.center.x,game.view.center.y],"zoom":1.0/6,"pixels_per_tile":32.0/6,"actual_viewport":true,"human_moved":false,"legacy_reference":"temporary fresh world, genuine eight-tree chop/five-stage build" if profile=="legacy" else "authorized showcase preset, not earned progress"})
		game.queue_free();await process_frame
	var f:=FileAccess.open(output.path_join("comparison-records.json"),FileAccess.WRITE);f.store_string(JSON.stringify(records,"  "));print("Two actual full-island references at identical integer-factor sampling.");quit()
