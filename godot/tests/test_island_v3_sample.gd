extends SceneTree
var checks:=0
var failed:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func files(path:String)->Array:
	var result:Array=[]
	for name in DirAccess.get_files_at(path):result.append(path.path_join(name))
	for name in DirAccess.get_directories_at(path):result.append_array(files(path.path_join(name)))
	return result
func _initialize()->void:call_deferred("run")
func run()->void:
	var directory:=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(1);return
	var before:=files(directory);var manifest:=FileAccess.get_file_as_string("res://content/world.json")
	var sample:Node=load("res://scenes/island_v3_sample.tscn").instantiate();root.content_scale_size=Vector2i.ZERO;root.add_child(sample)
	check(sample.ready_for_capture and sample.data.snapshot_only,"separate read-only art scene ready")
	check(sample.data.houses.size()==3 and sample.data.actors.size()>=3,"three houses and original resident scale references")
	var traits:Dictionary={}
	for house in sample.data.houses:traits[house.personality]=true
	check(traits.size()==3,"three distinct yard personalities")
	for id in sample.library.artworks:
		var work:Dictionary=sample.library.artworks[id];var folder: String="characters" if work.get("kind","character")=="character" else "works"
		var original:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/"+folder+"/"+id+".json"))
		check(work==original,"original editable artwork unchanged "+id)
	var required:Dictionary={}
	for prop in sample.data.props:required[prop.kind]=true
	for id in ["well","notice","campfire","lamp","planter","bench","crates","grass","flowers","mailbox","telescope","bookshelf"]:check(required.has(id),"sample has required prop "+id)
	check(sample.props.textures.size()==15,"all original prop atlas states generated")
	check(sample.renderer.cache_builds==1,"terrain baked once before composition")
	for size in [Vector2i(1280,800),Vector2i(960,640)]:
		root.size=size;await process_frame
		var visible:=Rect2(Vector2.ZERO,Vector2(size));var origin:Vector2=sample.origin()
		check(sample.get_global_transform_with_canvas().get_scale()==Vector2.ONE,"native pixel canvas "+str(size))
		for entry in sample.entries:
			if entry.type not in ["house","actor"]:continue
			var id:String=entry.value.template_id if entry.type=="house" else entry.value.artwork_id
			var art:Dictionary=sample.library.artworks[id]
			var box:=Rect2(origin+entry.position-Vector2(art.anchor[0],art.anchor[1]),Vector2(art.width,art.height))
			check(visible.encloses(box),"house/actor entirely inside viewport "+id+" "+str(size))
		for period in ["afternoon","night"]:
			sample.time_of_day=period;sample.queue_redraw();await process_frame;await process_frame
	check(sample.renderer.cache_builds==1,"window/time changes reuse static ground")
	sample.detail=true;sample.pixel_scale=2;check(sample.pixel_scale==floor(sample.pixel_scale),"detail uses actual integer canvas zoom")
	check(not sample.has_method("command") and not sample.has_method("_unhandled_input") and not sample.is_processing(),"sample has no gameplay commands, controls or simulation loop")
	check(files(directory)==before,"sample never writes save/config/artwork data")
	check(FileAccess.get_file_as_string("res://content/world.json")==manifest,"active world manifest unchanged")
	sample.queue_free();await process_frame
	print("Island v3 sample: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)
