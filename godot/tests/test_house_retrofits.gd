extends SceneTree
const Library=preload("res://scripts/character_library.gd")
const Study=preload("res://scripts/house_retrofit_study.gd")
var checks:=0
var failed:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func read(path:String)->Dictionary:return JSON.parse_string(FileAccess.get_file_as_string(path))
func _initialize()->void:call_deferred("run")
func run()->void:
	var directory:=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(1);return
	var lib:=Library.new();lib.configure(directory)
	var manifest:=read("res://content/house-retrofits/manifest.json")
	var approved:Dictionary={}
	for name in manifest.source_hashes:
		var path:String="res://content/works/"+name+".json";var original:=read(path)
		check(FileAccess.get_sha256(path)==manifest.source_hashes[name],"original master unchanged "+name)
		for color in original.palette:approved[color]=true
	for name in manifest.parts:
		var art:=read("res://content/house-retrofits/parts/"+name+".json");check(lib.valid(art),"editable derived part "+name)
		var proof:Dictionary=art.provenance;var source:Image=lib.render(read("res://content/works/"+proof.parent+".json"),proof.frame)
		var part:Image=lib.render(art,"down");var identical:=true;var opaque:=0
		for y in range(part.get_height()):
			for x in range(part.get_width()):
				var c:=part.get_pixel(x,y)
				if c.a==0:continue
				opaque+=1
				if c!=source.get_pixel(x+int(proof.rect[0]),y+int(proof.rect[1])):identical=false
		check(identical and opaque>0,"cutout copies original pixels without repainting "+name)
	for id in manifest.houses:
		var art:=read("res://content/house-retrofits/houses/"+id+".json")
		check(lib.valid(art),"editable five-stage full-master derivative "+id)
		check(not lib.artworks.has(art.id),"not live registered "+id)
		var allowed:=true
		for color in art.palette:
			if Color(color).a>0 and not approved.has(color):allowed=false
		check(allowed,"only existing colors "+id)
		var master:=read("res://content/works/"+art.provenance.parent+".json")
		check(art.width==master.width and art.height==master.height and art.anchor==master.anchor and art.structure==master.structure,"original dimensions/anchor/structure preserved "+id)
		for frame in master.frames:
			var base:Dictionary=art.duplicate(true);base.frames[frame]=[art.frames[frame][0]]
			var derived:Image=lib.render(base,frame);var original:Image=lib.render(master,frame)
			if id=="lively":original.flip_x()
			if id!="quiet":check(derived.get_data()==original.get_data(),"complete master pixels retained "+id+frame)
			else:
				var eligible:=true
				for y in range(derived.get_height()):
					for x in range(derived.get_width()):
						if derived.get_pixel(x,y)!=original.get_pixel(x,y) and y<132:eligible=false
				check(eligible,"darkening never alters roof/upper outline "+frame)
		check(art.provenance.has("fallback"),"honest composition fallback documented "+id)
	root.content_scale_size=Vector2i.ZERO
	var scene:=Study.new();root.add_child(scene)
	check(scene.entries.filter(func(e):return e.type=="house").size()==5,"exactly five full houses")
	check(not scene.has_method("command") and not scene.is_processing(),"no World commands or simulation")
	for size in [Vector2i(1280,800),Vector2i(960,640)]:
		root.size=size;await process_frame
		for entry in scene.entries:
			if entry.type!="house":continue
			var box:=Rect2(scene.origin()+entry.point-entry.anchor,entry.texture.get_size())
			check(Rect2(Vector2.ZERO,Vector2(size)).encloses(box),"complete native-size house "+entry.value.id+str(size))
	check(scene.ground.cache_builds==1,"no terrain rebuild for window size")
	scene.queue_free();await process_frame
	var pair:=Study.new();pair.comparison_id="human";root.add_child(pair)
	check(pair.entries.size()==2 and pair.entries[0].scale==pair.entries[1].scale,"actual equal-scale master comparison")
	pair.queue_free();await process_frame
	print("House master retrofits: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)
