extends SceneTree
var checks:=0
var failed:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func files(path:String)->Array:
	var result:Array=[]
	for file in DirAccess.get_files_at(path):result.append(path.path_join(file))
	for folder in DirAccess.get_directories_at(path):result.append_array(files(path.path_join(folder)))
	return result
func _initialize()->void:call_deferred("run")
func run()->void:
	var directory:=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(1);return
	var before:=files(directory);var manifest:=FileAccess.get_file_as_string("res://content/world.json");root.content_scale_size=Vector2i.ZERO
	for id in ["A","B"]:
		var scene:Node=load("res://scenes/art_study_"+id+".tscn").instantiate();root.add_child(scene)
		check(scene.ready_for_capture and scene.ground.cache_builds==1,"snapshot-only scene ready "+id)
		check(not scene.has_method("command") and not scene.has_method("_unhandled_input") and not scene.is_processing(),"no input, World commands or simulation "+id)
		var valid_geometry:=true
		for command in scene.ground.commands:
			if command.kind=="surface" and Geometry2D.triangulate_polygon(command.shape).is_empty():valid_geometry=false
		check(valid_geometry,"all cached irregular/feather polygons triangulate "+id)
		if id=="A":
			for entry in scene.entries:
				if entry.type=="prop" and entry.value.has("nominal_pixels"):
					var actual:Vector2=entry.texture.get_size()*entry.scale
					check(actual.x==entry.value.nominal_pixels[0] and actual.y==entry.value.nominal_pixels[1],"real texture size matches layout "+entry.value.id)
		for size in [Vector2i(1280,800),Vector2i(960,640)]:
			root.size=size;await process_frame
			check(scene.get_global_transform_with_canvas().get_scale()==Vector2.ONE,"native pixel canvas "+id+str(size))
			for entry in scene.entries:
				if entry.type not in ["house","actor"]:continue
				var box:=Rect2(scene.origin()+entry.point-entry.anchor*entry.scale,entry.texture.get_size()*entry.scale)
				check(Rect2(Vector2.ZERO,Vector2(size)).encloses(box),"complete house/actor "+id+str(size))
			for period in ["afternoon","night"]:
				scene.period=period;scene.queue_redraw();await process_frame;await process_frame
		check(scene.ground.cache_builds==1,"size and period do not rebuild ground "+id)
		if id=="B":
			check(scene.light_masks.size()==2,"night emissions use both real house window masks")
			for entry in scene.entries:
				if entry.type!="house":continue
				var mask:Image=scene.light_masks[entry.art.id].get_image()
				var raster:Image=scene.library.render(entry.art,"stage_4")
				var lit:=0;var only_glass:=true
				for y in range(mask.get_height()):
					for x in range(mask.get_width()):
						if mask.get_pixel(x,y).a<.1:continue
						lit+=1
						var original:=raster.get_pixel(x,y)
						if original.b<=original.r*1.2 or original.g<=original.r*.9:only_glass=false
				check(lit>0,"night house has actual lit glass "+entry.art.id)
				check(only_glass,"plaster/wood not mistaken for window glass "+entry.art.id)
		scene.detail=true;scene.pixel_scale=2;scene.queue_redraw();await process_frame
		check(scene.pixel_scale==2,"actual two-times detail camera "+id)
		check(files(directory)==before,"no save/config/artwork files written "+id)
		scene.queue_free();await process_frame
	check(FileAccess.get_file_as_string("res://content/world.json")==manifest,"active world manifest unchanged")
	print("Art study scenes: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)
