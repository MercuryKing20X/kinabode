extends SceneTree
const Renderer=preload("res://scripts/fishing_renderer.gd")
const RodContract=preload("res://tests/test_rod_tip_binding.gd")
const World=preload("res://scripts/world_state.gd")
var checks:=0
var failed:=false
func check(ok:bool,msg:String)->void:
	checks+=1
	if not ok:failed=true;push_error(msg)
func glm_face_x(image:Image,row:int)->float:
	# The manually checked GLM face is warm skin inside the head crop; unlike
	# a mirror-only check this fails when both labelled directions are swapped.
	var total:=0.0;var count:=0
	for y in range(25,90):
		for x in range(20,76):
			var color:=image.get_pixel(x,row*128+y)
			if color.a>0.5 and color.r>170.0/255 and color.g>110.0/255 and color.b>90.0/255 and color.r-color.g>=12.0/255 and absf(color.g-color.b)<=55.0/255:
				total+=x;count+=1
	return total/count if count>0 else -1.0
func sunflower_face_x(image:Image,row:int,col:int)->float:
	# Reviewed new appearance annotation: same skin classifier, actual head y30:54.
	# Original GLM crop and all original mirror/provenance assertions stay unchanged.
	var total:=0.0;var count:=0
	for y in range(30,54):
		for x in range(20,76):
			var color:=image.get_pixel(col*96+x,row*128+y)
			if color.a>0.5 and color.r>170.0/255 and color.g>110.0/255 and color.b>90.0/255 and color.r-color.g>=12.0/255 and absf(color.g-color.b)<=55.0/255:
				total+=x;count+=1
	return total/count if count>0 else -1.0
func _initialize()->void:call_deferred("run")
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"))
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/fishing-animations/manifest.json"))
	check(manifest.works.size()==RodContract.MIRRORED_WORKS.size()+RodContract.INDEPENDENT_WORKS.size() and RodContract.MIRRORED_WORKS.all(func(id):return manifest.works.has(id)) and manifest.works.has("suit-hulk"),"all original thirteen and authorized new appearance have recorded sources")
	var provenance_path:String=ProjectSettings.globalize_path("res://").path_join("../production/art/suit-hulk-v2-20261106/provenance.json").simplify_path()
	var provenance:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(provenance_path))
	check(provenance.sources["fish-source.png"]==RodContract.SUIT_SOURCE_SHA and FileAccess.get_sha256(provenance_path.get_base_dir().path_join("fish-source.png"))==RodContract.SUIT_SOURCE_SHA,"retained independent four-direction source has exact original provenance hash")
	check(FileAccess.get_sha256("res://content/fishing-animations/suit-hulk.png")==RodContract.SUIT_ATLAS_SHA,"independent runtime atlas is the original reviewed artifact")
	for id in manifest.works:
		var item:Dictionary=manifest.works[id];check(item.status=="independent" and item.frames==28,"authored four directions and seven frames "+id)
		var image:=Image.load_from_file("res://content/fishing-animations/"+str(item.asset))
		check(image!=null and image.get_size()==Vector2i(672,512),"correct atlas geometry "+id)
		if id=="ai-glm":
			var left_face:=glm_face_x(image,1);var right_face:=glm_face_x(image,2)
			check(left_face>=0 and left_face<47.5 and right_face>47.5,"GLM casting face actually points in its labelled direction")
		for col in range(7):
			var left:=image.get_region(Rect2i(col*96,128,96,128));var right:=image.get_region(Rect2i(col*96,256,96,128))
			left.flip_x()
			if id in RodContract.MIRRORED_WORKS:
				check(left.get_data()==right.get_data() and left.get_used_rect().has_area(),"left/right pixels are exact mirrors and visible "+id+" "+str(col))
			else:check(id in RodContract.INDEPENDENT_WORKS and left.get_data()!=right.get_data() and left.get_used_rect().has_area() and right.get_used_rect().has_area(),"retained independently drawn left/right directions both visible "+id+" "+str(col))
			if id=="orange-sunflower-girl":
				var left_face:float=sunflower_face_x(image,1,col);var right_face:float=sunflower_face_x(image,2,col)
				check(left_face>=0 and left_face<47.5 and right_face>47.5,"new Orange casting face points in labelled directions across every authored phase "+str(col))
		for row in [0,3]:
			for col in range(7):check(image.get_region(Rect2i(col*96,row*128,96,128)).get_used_rect().has_area(),"front/back action is visible "+id)
	var game:Node=load("res://scenes/main_v3.tscn").instantiate();game.world=World.new("res://content/home-v3/world.json");root.add_child(game);game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.view.sound_enabled=false;game.island_hud.set_process(false)
	await process_frame
	var w:RefCounted=game.world;w.director.set_all_enabled(false)
	check(preload("res://tests/fishing_fixture.gd").coast(w,"human"),"real World route reaches shore")
	check(w.command("human",{"intent":"fish"}).ok,"actual host fishing job starts")
	w.advance(.1)
	var renderer:=Renderer.new();var tex:Texture2D=renderer.animation_texture(game.view,w.actors.human)
	check(tex!=null,"actual fishing job renders authored pose")
	var id:String=w.library.visual_appearance(w.actors.human);var original:Dictionary=w.library.artworks[id]
	w.library.artworks[id]=original.duplicate(true);w.library.artworks[id].revision+=1;w.library.artworks[id].palette[0]="#ffffffff"
	check(renderer.animation_texture(game.view,w.actors.human)==null,"edited artwork is never replaced by bundled action atlas")
	w.library.artworks[id]=original;game.queue_free();await process_frame
	print("Fishing animation v2: ",checks," checks, failed=",failed);quit(1 if failed else 0)
