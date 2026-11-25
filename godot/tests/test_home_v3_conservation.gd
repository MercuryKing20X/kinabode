extends SceneTree
const World=preload("res://scripts/world_state.gd")
const Opening=preload("res://scripts/world_opening.gd")
const Save=preload("res://scripts/save_store.gd")
const F=preload("res://tests/cooking_fixture.gd")
var checks:=0
var failed:=false
var library:RefCounted
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func fresh()->RefCounted:
	var w:=preload("res://tests/main_island_fixture.gd").world();w.library=library;w.residents.provision(w);w.director.set_all_enabled(false);assert(Opening.apply(w,library).ok);return w
func wood(w:RefCounted)->int:
	var total:int=F.amount(w,"wood")
	for drop in w.drops.values():total+=int(drop.wood)
	for o in w.objects.values():
		if o.kind=="construction_site":total+=int(o.invested)+int(o.delivered.get("wood",0))
	return total
func _initialize()->void:
	var directory:String=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(1);return
	library=preload("res://scripts/character_library.gd").new();library.configure(directory)
	var w:=fresh();var tree:Dictionary=w.objects.values().filter(func(o):return o.kind=="tree" and o.zone_id=="home.forest")[0]
	var bridge:Array=w.map_anchor("spring.bridge")
	check(w.walkable("home",Vector2(bridge[0],bridge[1])),"data bridge is walkable through World")
	var cliff:Dictionary=w.catalog.regions.home.layout.cliffs[0]
	check(not w.walkable("home",Vector2(cliff.polygon[0][0]+1,cliff.polygon[0][1]+.5)),"authored cliff blocks route")
	check(w.walkable("home",Vector2(cliff.stairs[0][0]+.5,cliff.stairs[0][1]+.5)),"authored stairs remain connected")
	var before:int=wood(w)
	check(w.command("codex",{"intent":"chop","target_id":tree.id}).ok,"first real resident claims a tree")
	w.advance(.1)
	check(not w.command("human",{"intent":"chop","target_id":tree.id}).ok and wood(w)==before,"claimed target refuses other resident without consuming or creating wood")
	w.command("codex",{"intent":"stop"});w.advance(.1)
	check(wood(w)==before and w.work.claims.is_empty(),"cancel before actual cut conserves inventory and clears exact claim")
	var well:Array=w.map_anchor("well")
	check(not w.command("human",{"intent":"move","x":well[0],"y":well[1]}).ok and wood(w)==before,"unreachable solid target refuses and conserves")
	check(F.job(w,"human",{"intent":"gather_wood","zone_id":tree.zone_id,"target_id":tree.id,"tree_count":40}),"real continuous order ends on genuinely full public storage")
	var cut:int=int(w.work.events[-1].get("progress",{}).get("trees_cut",0))
	check(w.objects.values().filter(func(o):return o.kind=="tree" and o.zone_id==tree.zone_id).all(func(o):return int(o.wood_yield)<=8),"this authored normal-tree zone uses the configured normal yield")
	# A long real job can regrow and cut the same safe anchor again.
	var produced:int=cut*int(w.forest.settings.normal_wood)
	check(wood(w)==before+produced,"continuous order preflights whole-tree capacity and conserves all wood")
	check(cut>30 and cut<=40,"unlimited warehouse continues to requested count or real forest exhaustion")
	check(w.storage.count("wood")>0,"all harvested bundles enter unlimited warehouse")
	check(wood(w)==before+produced,"all real cut wood accounted in warehouse carry and ground drops")
	check(w.actors.human.carry.is_empty() and w.drops.is_empty(),"warehouse removes old box overflow without loss")
	check(Save.save_world(w,directory.path_join("full")),"full-storage cancelled order saves")
	var loaded:=preload("res://tests/main_island_fixture.gd").world();loaded.residents.provision(loaded);loaded.library=library
	var result:Dictionary=Save.load_world(loaded,directory.path_join("full"))
	check(result.ok and result.loaded and wood(loaded)==wood(w) and loaded.work.jobs.is_empty() and loaded.work.claims.is_empty(),"reload conserves overflow and restores no tasks or claims")
	# A zero-investment preset is still a real movable instance; relocating it may
	# never become an invalid save simply because the destination is a newly built room.
	w=fresh();var site:Dictionary=w.objects["home.house.06"]
	check(w.command("human",{"intent":"build_house","target_id":site.id}).ok,"explicit full real house plan on empty sixth plot")
	for tick in range(60000):
		w.advance(.1)
		if not w.projects.active("human"):break
	check(int(site.stage_index)==5 and int(site.invested)>0,"sixth house actually built from stock and real trees")
	if w.loaded("human"):check(F.job(w,"human",{"intent":"store","target_id":"home.chest.01"}),"surplus real wood returned before moving furniture")
	check(F.job(w,"human",{"intent":"enter","target_id":"home.house.01"}),"human explicitly enters own room before touching table")
	var table:Dictionary=w.interior.furniture["furniture.1"]
	check(F.job(w,"human",{"intent":"pickup_furniture","target_id":table.id}),"original table really picked up")
	check(F.job(w,"human",{"intent":"exit"}) and F.job(w,"human",{"intent":"enter","target_id":site.id}),"human explicitly carries table to new house")
	var floor:Rect2=w.interior.FLOOR
	check(F.job(w,"human",{"intent":"place_furniture","x":floor.get_center().x,"y":floor.get_center().y}),"original instance placed in new room")
	check(Save.save_world(w,directory.path_join("moved")),"relocated original preset saves")
	loaded=preload("res://tests/main_island_fixture.gd").world();loaded.residents.provision(loaded);loaded.library=library;result=Save.load_world(loaded,directory.path_join("moved"))
	check(result.ok and result.loaded and loaded.interior.furniture.size()==w.interior.furniture.size() and loaded.interior.furniture[table.id].region_id=="room."+site.id and loaded.interior.furniture[table.id].invested==0,"reload preserves same relocated preset, no duplication/free replacement")
	check(loaded.memories.records.any(func(r):return r.kind=="house_completed") and loaded.memories.records.filter(func(r):return r.kind=="house_completed").size()==1,"only genuinely built sixth house creates a completion memory")
	print("Home v3 conservation: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)
