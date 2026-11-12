extends SceneTree
const Terrain=preload("res://scripts/tile_terrain_data.gd")
const Renderer=preload("res://scripts/tile_terrain_renderer.gd")
var checks:=0
var failed:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/island-v3-sample.json"));var style:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/island-v3-style.json"))
	var layer:=Terrain.new();check(layer.load_data(data),"sample terrain loads from bounded data")
	check(not layer.walkable(Vector2i(-1,2)) and not layer.walkable(Vector2i(40,2)),"outside terrain blocked")
	check(not layer.walkable(Vector2i(20,24)) and not layer.walkable(Vector2i(3,16)),"deep and shallow water blocked")
	check(layer.walkable(Vector2i(20,15)),"stone plaza walkable")
	check(layer.cliff(Vector2i(5,12)) and not layer.walkable(Vector2i(5,12)),"half-height cliff collision comes from data")
	check(not layer.can_step(Vector2i(5,11),Vector2i(5,12)),"cannot walk through cliff face")
	for y in range(10,14):check(layer.can_step(Vector2i(20,y),Vector2i(20,y+1)),"stairs connect both heights at row "+str(y))
	check(not layer.can_step(Vector2i(20,10),Vector2i(21,11)),"no diagonal shortcuts")
	check(layer.edge_mask(Vector2i(12,15))!=0,"neighbor-based transition mask")
	var read:Dictionary=layer.cell(Vector2i(20,15));read.material="deep_water";check(layer.walkable(Vector2i(20,15)),"terrain queries deep copy")
	var renderer:=Renderer.new();renderer.configure(layer,style);renderer.ensure_baked()
	check(renderer.cache_builds==1 and renderer.ground.get_size()==Vector2i(1280,800),"one static terrain bake")
	check(renderer.ground.detect_alpha()==Image.ALPHA_NONE,"no transparent seams across half-height stair transitions")
	var before:=renderer.ground.get_data()
	for frame in range(600):renderer.ensure_baked()
	check(renderer.cache_builds==1 and before==renderer.ground.get_data(),"600 frames never rebuild static terrain")
	var revision:int=layer.revision
	check(not layer.set_cell(Vector2i(1,1),{"material":"invalid","height":0,"stairs":false}) and layer.revision==revision,"invalid edits rejected atomically")
	check(layer.set_cell(Vector2i(20,15),{"material":"sand","height":0,"stairs":false}),"valid terrain edit increments revision")
	renderer.ensure_baked();check(renderer.cache_builds==2 and renderer.ground.get_data()!=before,"terrain revision invalidates cached ground")
	var same:=Renderer.new();same.configure(layer,style);same.ensure_baked();check(same.ground.get_data()==renderer.ground.get_data(),"same seed/data has byte-identical terrain")
	var bad:Dictionary=data.duplicate(true);bad.patches[0].rect=[0,0,9999,9999];var previous:int=layer.revision
	check(not layer.load_data(bad) and layer.revision==previous and layer.width==40,"invalid replacement preserves prior terrain")
	var world:RefCounted=load("res://scripts/world_state.gd").new();check(not world.catalog.regions.has("island-v3-sample") and world.catalog.regions.home.size[0]==160,"sample never registers or replaces active home")
	renderer.free();same.free();print("Tile terrain foundation: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)
