extends SceneTree
var checks:=0
var failed:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var data:=OS.get_environment("HABITAT_DATA_DIR");assert(data.contains("youqi-test-"))
	var files_before:Array=Array(DirAccess.get_files_at(data))
	var scene:Node=load("res://scenes/campfire_v4_study.tscn").instantiate();root.add_child(scene);await process_frame
	check(scene.ready_for_capture and scene.characters.size()==5,"five repository artwork references ready")
	check(scene.get_child_count()==0 and scene.library.resident_world==null,"snapshot study has no world or runtime game controllers")
	var bytes:=0
	for texture in scene.assets.values():bytes+=texture.get_image().get_data_size()
	check(bytes<8*1024*1024,"study raster texture memory below 8MiB")
	for biome in ["mainland","moon"]:
		var hashes:Array=[]
		for frame in range(4):hashes.append(scene.assets[biome+"-fire-"+str(frame)].get_image().get_data().hex_encode().sha256_text())
		check(hashes.all(func(h):return hashes.count(h)==1),"four distinct manually derived fire frames: "+biome)
		for period in ["day","night"]:
			for dimensions in [Vector2i(1280,800),Vector2i(960,640)]:
				root.size=dimensions;scene.biome=biome;scene.period=period;scene.queue_redraw();await process_frame
				var origin:Vector2=scene.local_origin()
				check(scene.characters.all(func(c):return Rect2(Vector2(0,50),Vector2(dimensions)-Vector2(0,90)).has_point(origin+c.point)),"all five reference footpoints inside viewport "+biome+period+str(dimensions))
	check(Array(DirAccess.get_files_at(data))==files_before,"study never writes world saves or artwork")
	scene.queue_free();await process_frame;print("Campfire v4 study: ",checks," checks, failed=",failed,"; raster_bytes=",bytes,"; new generation successes=0 (401)");quit(1 if failed else 0)
