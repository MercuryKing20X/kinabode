extends SceneTree
const Comparison=preload("res://scripts/art_comparison.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var output:=OS.get_environment("HABITAT_ART_STUDY_CAPTURE")
	if output.is_empty() or not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):quit(1);return
	var config:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/art-studies/scenes.json"))
	var game:Node=load("res://scenes/main.tscn").instantiate();root.add_child(game)
	game.save_enabled=false;game.set_process(false);game.set_process_input(false);game.set_process_unhandled_input(false);game.view.set_process(false);game.view.set_process_unhandled_input(false);game.view.sound_enabled=false;game.view.follow_player=false;game.view.clock=0
	for routine in game.world.director.routines.values():routine.set_enabled(false)
	for child in game.get_children():
		if child is CanvasLayer:child.hide()
	game.atlas.hide();root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1280,800)
	var original_human_position:Array=game.world.actors.human.position.duplicate()
	var new_records:Array=JSON.parse_string(FileAccess.get_file_as_string(output.path_join("viewport-records.json")));var records:Array=[]
	for id in ["A","B"]:
		if id=="B":
			game._house_scenario()
			if game.world.objects["home.house.01"].stage_index!=5:push_error("Actual temporary World/Work build failed; no pretend completion screenshot.");quit(1);return
		var seed:=0
		while game.world.weather.current().id!="sunny" and seed<512:game.world.weather.weather_seed=seed;seed+=1
		game.view.center=Vector2(config[id].camera[0],config[id].camera[1]);game.view.zoom=1;game.view.queue_redraw()
		await process_frame;await process_frame;await RenderingServer.frame_post_draw
		var name:String="reference-"+id+"-current-island.png";var original:=root.get_texture().get_image();original.save_png(output.path_join(name))
		var transform:Vector2=game.view.get_global_transform_with_canvas().get_scale()
		var meta:Dictionary={"file":name,"camera_tile":[game.view.center.x,game.view.center.y],"pixels":[original.get_width(),original.get_height()],"world_pixels_per_tile":32*game.view.zoom*transform.x,"actual_viewport":true,"weather":game.world.weather.current().id,"human_automatically_moved":false,"house_stage":game.world.objects["home.house.01"].stage_index}
		var reference:Dictionary={}
		for record in new_records:
			if record.file==id+"-afternoon-1280x800.png":reference=record
		assert(Comparison.same_camera(meta,reference))
		var study:=Image.load_from_file(output.path_join(reference.file));var joined:Image=Comparison.join(original,study)
		var comparison_name:String="comparison-"+("ground" if id=="A" else "houses")+".png";joined.save_png(output.path_join(comparison_name))
		records.append({"study":id,"left":meta,"right":reference,"comparison":comparison_name,"pixels":[joined.get_width(),joined.get_height()],"operation":"lossless side-by-side, left existing / right study; no resizing or retouching"})
	assert(game.world.actors.human.position==original_human_position)
	var pids:Dictionary={}
	for id in game.links:
		var pid:Variant=game.links[id].get("_pid");pids[id]=pid
		assert(pid==null or int(pid)<=0)
	var file:=FileAccess.open(output.path_join("comparison-records.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"records":records,"model_process_ids":pids,"real_model_calls":0,"player_save_read":false,"original_source_modified":false,"house_reference":"real eight-tree chop and five-stage build in temporary world"},"  "))
	game.queue_free();await process_frame;print("Two actual existing-island references and lossless comparisons completed.");quit()
