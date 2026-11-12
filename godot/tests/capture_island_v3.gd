extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var output:=OS.get_environment("HABITAT_ISLAND_V3_CAPTURE")
	if output.is_empty() or not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):quit(1);return
	var sample:Node=load("res://scenes/island_v3_sample.tscn").instantiate();root.content_scale_size=Vector2i.ZERO;root.add_child(sample)
	var records:Array=[]
	for size in [Vector2i(1280,800),Vector2i(960,640)]:
		root.size=size
		for period in ["afternoon","night"]:
			sample.time_of_day=period;sample.pixel_scale=1;sample.detail=false;sample.queue_redraw()
			await process_frame;await process_frame;await RenderingServer.frame_post_draw
			var file:String=period+"-"+str(size.x)+"x"+str(size.y)+".png";var image:=root.get_texture().get_image();image.save_png(output.path_join(file))
			records.append({"file":file,"pixels":[image.get_width(),image.get_height()],"physical_scale":sample.get_global_transform_with_canvas().get_scale().x*sample.pixel_scale,"terrain_cache_builds":sample.renderer.cache_builds})
	root.size=Vector2i(1280,800);sample.time_of_day="afternoon";sample.detail=true;sample.pixel_scale=2;sample.queue_redraw()
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("detail-2x.png"))
	records.append({"file":"detail-2x.png","pixels":[1280,800],"physical_scale":2,"terrain_cache_builds":sample.renderer.cache_builds,"actual_viewport_zoom":true})
	var f:=FileAccess.open(output.path_join("viewport-records.json"),FileAccess.WRITE);f.store_string(JSON.stringify(records,"  "))
	sample.queue_free();await process_frame;quit()
