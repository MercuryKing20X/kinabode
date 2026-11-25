# DIRECTION「用户试玩 1a4ebbc 与第八轮」：容量不设上限，钓到的鱼总能放进去。
extends SceneTree
const Fixture=preload("res://tests/fishing_fixture.gd")
var checks:=0
var failed:=false
func check(ok:bool,msg:String)->void:
	checks+=1
	if not ok:failed=true;push_error(msg)
func _initialize()->void:call_deferred("run")
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"))
	var world:=preload("res://scripts/world_state.gd").new();world.director.set_all_enabled(false)
	check(Fixture.coast(world,"human"),"real route to sea")
	var fish_ids:Dictionary={};var first_pen:=""
	for n in range(49):
		var result:Dictionary=world.command("human",{"intent":"fish"})
		for retry in range(200):
			if result.ok:break
			world.advance(10.0);result=world.command("human",{"intent":"fish"})
		check(result.ok,"real catch starts "+str(n))
		if not result.ok:break
		for tick in range(200):
			world.advance(1.0)
			if not world.work.jobs.has("human"):break
		var entry:Dictionary=preload("res://tests/fishing_fixture.gd").unplaced(world)
		check(not entry.is_empty() and not fish_ids.has(entry.id),"real unique caught fish "+str(n))
		if entry.is_empty():break
		fish_ids[entry.id]=true
		var stock:Dictionary=world.fishing.host_stock_nearest(entry.id)
		var pen_id:String=world.fishing.fish[entry.id].location
		if first_pen.is_empty():first_pen=pen_id
		check(stock.ok and world.fishing.pens.has(pen_id) and pen_id==first_pen,"stock actual fish into same nearest fishery "+str(n))
	check(world.fishing.pen_count(first_pen)==49,"the nearest fishery retains all catches above the old limit")
	check(world.fishing.fish.size()==49 and fish_ids.size()==49,"all 49 actual catches remain unique and conserved")
	check(world.fishing.display_fish(first_pen).size()==world.fishing.DISPLAY_FISH_LIMIT,"draw load stays bounded above old limit")
	var directory:=OS.get_environment("HABITAT_DATA_DIR").path_join("unlimited-fishery")
	var save=preload("res://scripts/save_store.gd")
	check(save.save_world(world,directory),"above-capacity fishery saves")
	var loaded:=preload("res://scripts/world_state.gd").new()
	check(save.load_world(loaded,directory).ok and loaded.fishing.fish.keys().all(func(id):return fish_ids.has(id)) and loaded.fishing.pen_count(first_pen)==49,"reload indexes every exact caught instance")
	print("Fishing stock capacity v2: ",checks," checks, failed=",failed);quit(1 if failed else 0)
