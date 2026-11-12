extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var output:=OS.get_environment("HABITAT_ART_STUDY_CAPTURE")
	if output.is_empty() or not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):quit(1);return
	var records:Array=[];root.content_scale_size=Vector2i.ZERO
	for id in ["A","B"]:
		var scene:Node=load("res://scenes/art_study_"+id+".tscn").instantiate();root.add_child(scene)
		for size in [Vector2i(1280,800),Vector2i(960,640)]:
			root.size=size
			for period in ["afternoon","night"]:
				scene.period=period;scene.pixel_scale=1;scene.detail=false;scene.queue_redraw()
				await process_frame;await process_frame;await RenderingServer.frame_post_draw
				var name:String=id+"-"+period+"-"+str(size.x)+"x"+str(size.y)+".png"
				var image:=root.get_texture().get_image();image.save_png(output.path_join(name))
				records.append({"file":name,"pixels":[image.get_width(),image.get_height()],"camera_tile":scene.config.camera,"world_pixels_per_tile":32,"ground_cache_builds":scene.ground.cache_builds,"actual_viewport":true})
		root.size=Vector2i(1280,800);scene.period="afternoon";scene.detail=true;scene.pixel_scale=2;scene.queue_redraw()
		await process_frame;await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(id+"-detail-2x.png"))
		records.append({"file":id+"-detail-2x.png","pixels":[1280,800],"world_pixels_per_tile":64,"actual_viewport":true,"ground_cache_builds":scene.ground.cache_builds})
		scene.queue_free();await process_frame
	var file:=FileAccess.open(output.path_join("viewport-records.json"),FileAccess.WRITE);file.store_string(JSON.stringify(records,"  "));print("Ten actual art-study viewport captures completed.");quit()
