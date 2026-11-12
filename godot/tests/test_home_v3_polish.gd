extends SceneTree
const World=preload("res://scripts/world_state.gd")
const Opening=preload("res://scripts/world_opening.gd")
const Layout=preload("res://scripts/home_layout.gd")
var checks:=0
var failed:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):quit(1);return
	var lib=preload("res://scripts/character_library.gd").new();lib.configure(OS.get_environment("HABITAT_DATA_DIR"))
	var w:=World.new("res://content/home-v3/world.json");w.library=lib;w.residents.provision(w);w.director.set_all_enabled(false)
	check(w.error.is_empty() and Opening.apply(w,lib).ok,"valid unchanged showcase with new coordinates")
	var l:Dictionary=w.catalog.regions.home.layout
	check(w.catalog.rectangle(l.plaza)==Rect2(55,34,40,34) and Layout.plaza_shape(l)==PackedVector2Array([Vector2(55,34),Vector2(95,34),Vector2(95,68),Vector2(55,68)]),"exact unchanged plaza footprint, complete stone polygon")
	check(l.ground_art.formal_plaza.material=="stone" and l.ground_art.formal_plaza.variants==3 and l.wear_paths.is_empty(),"three stone variations; no internal dirt shortcut")
	var terrain=preload("res://scripts/polygon_study_ground.gd").new()
	var roads:Array=l.roads.duplicate(true)
	for road in roads:road.width/=2.0
	terrain.prepare({"region":w.catalog.regions.home,"camera":w.map_anchor("well"),"plaza":Array(Layout.plaza_shape(l)),"paving":l.ground_art.paving,"roads":roads,"well":w.map_anchor("well"),"shortcut":[],"variant_regions":l.ground_art.variant_regions,"formal_plaza":l.ground_art.formal_plaza})
	var coverage:=true
	for y in range(34,68):
		for x in range(55,95):
			var material:=""
			if not Geometry2D.is_point_in_polygon(Vector2(x+.5,y+.5),terrain.visual_plaza):continue
			for command in terrain.commands:
				if command.kind=="surface" and Geometry2D.is_point_in_polygon(Vector2(x+.5,y+.5)*32,command.shape):material=command.material
			if not material.begins_with("slab"):coverage=false
	check(coverage,"every plaza sample has opaque stone as uppermost ground material")
	check(w.flower_gifts.patches.all(func(p):return not w.catalog.rectangle(l.plaza).has_point(p.point)),"roadside flower anchors remain outside paved plaza")
	check(l.plaza_planters.size()==4,"four quadrant tree planters")
	var boxes:Array=[]
	for prop in l.solid_props:
		var at:Array=w.map_anchor(prop.anchor)
		boxes.append({"id":prop.anchor,"rect":Rect2(Vector2(at[0]+prop.offset[0],at[1]+prop.offset[1]),Vector2(prop.size[0],prop.size[1]))})
	for site in w.leisure.sites.values():
		for box in w.leisure.art(site).recreation.obstacles:boxes.append({"id":site.id,"rect":Rect2(w.point(site)+Vector2(box[0],box[1]),Vector2(box[2],box[3]))})
	var disjoint:=true
	for i in range(boxes.size()):
		for j in range(i):
			if boxes[i].id!=boxes[j].id and boxes[i].rect.intersects(boxes[j].rect):push_error(str(boxes[i].id)+" overlaps "+str(boxes[j].id));disjoint=false
	check(disjoint,"all facilities, well, notice, planter and lamp collisions disjoint")
	var benches:Array=l.facilities.filter(func(f):return f.id.begins_with("play.well.bench.") or f.id in ["play.gazebo.bench","play.chess.bench"])
	check(benches.size()==6 and benches.all(func(f):return f.has("look_at") and f.has("facing")),"six directed benches with explicit viewing targets")
	for f in benches:check(w.leisure.sites[f.id].facing==f.facing,"bench facing projected to real seating "+f.id)
	check(l.plaza_lamps.size()==8 and l.plaza_lamps.filter(func(p):return p.role=="entrance").size()==6 and l.plaza_lamps.filter(func(p):return p.role=="functional").size()==2,"six entrance/two functional lamps; corners removed")
	check(l.roads.filter(func(p):return p.id.begins_with("beach-path-")).size()==2 and not l.roads.any(func(p):return p.id.begins_with("beach-passage-")),"two winding paths replace five comb teeth")
	var street:Dictionary=l.roads.filter(func(p):return p.id=="north-street")[0]
	check(street.width==2 and street.points.size()>3,"two-tile meandering village street")
	check(l.forest_clusters.size()==8,"eight irregular forest groups")
	for group in l.forest_clusters:
		check(group.tree_ids.size()>=4 and group.tree_ids.size()<=9,"four to nine actual trees per cluster")
		var connected:={group.tree_ids[0]:true}
		for pass_index in range(group.tree_ids.size()):
			for id in group.tree_ids:
				for other in connected.keys():
					if w.point(w.objects[id]).distance_to(w.point(w.objects[other]))<=5:connected[id]=true
		check(connected.size()==group.tree_ids.size(),"cluster connected by three-to-five tile neighbours "+group.id)
	for key in ["south","west"]:
		var at:Array=w.map_anchor("dock."+key+".end")
		check(w.walkable("home",Vector2(at[0],at[1])),"pier end is real World-walkable surface "+key)
	var palette:Array=[]
	for id in ["cottage","cottage-blue","cottage-large"]:
		var master:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/works/"+id+".json"))
		palette.append_array(master.palette)
	for plot in l.residential:
		if plot.owner_id.is_empty():continue
		var art:Dictionary=w.objects[plot.site_id].blueprint.artwork
		check(art.palette.all(func(color):return color in palette),"roof uses only original three master palettes "+plot.owner_id)
	for tick in range(600):w.advance(.1)
	check(w.memories.records.is_empty() and w.work.jobs.is_empty(),"presentation creates no memory/resource task after real advance")
	for side in ["south","west"]:
		var at:Array=w.map_anchor("dock."+side+".end")
		check(preload("res://tests/cooking_fixture.gd").job(w,"human",{"intent":"move","x":at[0],"y":at[1]}),"explicit real walk to offshore pier "+side)
		var before:Dictionary=w.actors.human.carry.duplicate(true)
		var store=preload("res://scripts/save_store.gd")
		check(store.save_world(w,OS.get_environment("HABITAT_DATA_DIR")),"save accepts actual offshore surface "+side)
		var restored:=World.new("res://content/home-v3/world.json");restored.library=lib
		var loaded:Dictionary=store.load_world(restored,OS.get_environment("HABITAT_DATA_DIR"))
		check(loaded.ok and loaded.loaded and restored.point(restored.actors.human).distance_to(Vector2(at[0],at[1]))<.7 and restored.actors.human.carry==before and restored.work.jobs.is_empty(),"pier reload preserves position/carry and resumes no work "+side)
	print("Home v3 polish: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)
