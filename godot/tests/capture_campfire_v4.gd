extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var output:=OS.get_environment("HABITAT_CAMPFIRE_STUDY_OUTPUT")
	assert(not output.is_empty() and OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"))
	root.content_scale_size=Vector2i.ZERO
	var scene:Node=load("res://scenes/campfire_v4_study.tscn").instantiate();root.add_child(scene)
	var records:Array=[]
	for biome in ["mainland","moon"]:
		for period in ["day","night"]:
			for dimensions in [Vector2i(1280,800),Vector2i(960,640)]:
				DisplayServer.window_set_size(dimensions);root.size=dimensions
				scene.biome=biome;scene.period=period;scene.frozen=true;scene.animation_time=1.2;scene.queue_redraw()
				await process_frame;await process_frame;await RenderingServer.frame_post_draw
				var file:String="F-"+biome+"-"+period+"-%sx%s.png"%[dimensions.x,dimensions.y]
				var image:=root.get_texture().get_image();assert(image.get_size()==dimensions and image.save_png(output.path_join(file))==OK)
				records.append({"file":file,"pixels":[dimensions.x,dimensions.y],"actual_viewport":true,"native_pixel_scale":1,"source":"reused-original-study","new_generation_successes":0,"source_generation_status":"401","world_instantiated":false,"model_calls_in_game":0})
	var f:=FileAccess.open(output.path_join("F-viewports.json"),FileAccess.WRITE);f.store_string(JSON.stringify(records,"  "));f.close()
	scene.queue_free();await process_frame;print("Campfire v4 study: eight real viewport captures, reused original study; new generation unavailable (401)");quit()
