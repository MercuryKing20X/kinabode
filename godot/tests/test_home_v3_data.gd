extends SceneTree
const Catalog=preload("res://scripts/world_catalog.gd")
var checks:=0
var failed:=false
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failed=true;push_error(message)
func _initialize()->void:
	var catalog:=Catalog.new();var old:=FileAccess.get_file_as_string("res://content/world.json")
	check(catalog.load_world("res://content/home-v3/world.json"),"new pack passes existing catalog validation: "+catalog.error)
	if catalog.regions.is_empty():quit(1);return
	var home:Dictionary=catalog.regions.home;var data:Dictionary=home.layout
	check(home.template_id=="home-v3" and home.layout.mainland_size[0]==160 and home.layout.mainland_size[1]==128 and home.size[0]==360 and home.size[1]==330 and home.layout.homelands.offset[0]==-19 and home.layout.homelands.offset[1]==150,"160x128 template, stable home runtime ID")
	check(catalog.regions.has("pine") and catalog.regions.has("moon") and catalog.region_packs.pine.id=="core","old neighbouring previews reused from canonical core pack")
	check(data.residential.size()==6,"five assigned houses and one empty plot")
	var owners:Array=[]
	for plot in data.residential:
		if not str(plot.owner_id).is_empty():owners.append(plot.owner_id)
	check(owners.size()==5 and owners.has("human") and owners.has("npc.mira"),"ownership binds stable actor IDs")
	check(home.objects.filter(func(o):return o.kind=="tree" and o.zone_id=="home.forest").size()==40,"40 spaced eastern tree anchors")
	check(data.farms.size()==4 and data.farms.all(func(f):return f.grid[0]==4 and f.grid[1]==3),"four 4x3 fields")
	check(data.fisheries.size()==2,"two waterfront fisheries")
	check(data.anchors.has("chess.first") and data.anchors.has("chess.second"),"two chess tables")
	check(data.roads.any(func(r):return r.width==2 and r.get("curb",false)),"main ring has two-tile width and curb")
	check(data.roads.any(func(r):return r.width==.6),"small stepping paths")
	for key in data.anchors:
		var point:Variant=data.anchors[key]
		if point is Array:check(Rect2(catalog.local_origin(home),Vector2(home.size[0],home.size[1])).has_point(Vector2(point[0],point[1])),"anchor in map "+key)
	check(data.wear_paths.is_empty() and data.ground_art.formal_plaza.material=="stone","plaza has no internal dirt wear")
	for plot in data.residential:
		var site:Dictionary=catalog.objects[plot.site_id]
		check(site.stage_index==0 and site.invested==0 and site.delivered.is_empty(),"base map doesn't pretend showcase is earned construction")
	check(FileAccess.get_file_as_string("res://content/world.json")==old,"default manifest unchanged until opening/reset phase")
	print("Home v3 data: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)
