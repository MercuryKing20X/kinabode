# DIRECTION 2026-11-07: 主角鱼直接入库；以原真实实例验证后续流程。
extends RefCounted
const World=preload("res://scripts/world_state.gd")
const Barbecue=preload("res://tests/barbecue_fixture.gd")
static func fresh()->RefCounted:
	var world:=World.new();world.residents.provision(world);world.director.set_all_enabled(false);return world
static func wait(world: RefCounted,id: String) -> bool:
	for tick in range(18000):
		world.advance(.1)
		if not world.work.jobs.has(id) and not world._routes.has(id) and not world.deliveries.active(id):return true
	return false
static func job(world: RefCounted,id: String,args: Dictionary) -> bool:
	return world.command(id,args).ok and wait(world,id)
static func harvest(world: RefCounted,crop: String) -> bool:
	for farm in world.farms.farms.values():
		if crop not in farm.crop_ids:continue
		if not job(world,"human",{"intent":"assign_farm","farm_id":farm.id,"manager_id":"codex"}):return false
		var options: Array=world.farms.farm_plots(farm.id).filter(func(plot):return plot.crop_id.is_empty())
		if options.is_empty():continue
		var plot: Dictionary=options[0]
		if not job(world,"human",{"intent":"plant","target_id":plot.id,"crop_id":crop}):return false
		if not job(world,"human",{"intent":"water","target_id":plot.id}):return false
		# Real elapsed growth; no crop inventory or save injection.
		world.advance(float(world.farms.crops[crop].seconds)+1)
		return job(world,"human",{"intent":"harvest","target_id":plot.id}) and world.deposit_all("human").ok
	return false
static func amount(world: RefCounted,item: String) -> int:
	var result:=0
	result+=world.storage.count(item)
	for actor in world.actors.values():result+=int(actor.carry.get(item,0))
	for life in world.barbecues.values():result+=int(life.station.supplies.get(item,0))
	return result
static func mushroom(world: RefCounted) -> bool:
	return job(world,"codex",{"intent":"forage","target_id":"home.mushrooms.1"}) and amount(world,"mushroom")>0
static func serve(world:RefCounted,recipe:String,fish_id:String="",guests:Array=["human","codex"])->bool:
	if not fish_id.is_empty() and preload("res://tests/fishing_fixture.gd").unplaced(world).get("id")!=fish_id:return false
	return Barbecue.start(world,"recipe:"+recipe,guests).ok and Barbecue.ready(world)
static func eat(world:RefCounted,id:String)->bool:return Barbecue.ate(world,id)
static func cleanup(world:RefCounted)->bool:
	var fire:RefCounted=world.life.fireside
	if not fire.active() or fire.state.current.is_empty() or fire.state.current.eaten==0:return false
	Barbecue.end(world);return true

# Isolated inventory fixture: reallocate genuine warehouse stock, never mint it.
static func withdraw(world:RefCounted,actor:String,item:String,amount:int=20)->bool:
	var count:int=mini(amount,mini(world.work.carry_space(actor),world.storage.count(item)))
	if count<=0:return false
	if actor=="human":return world.take_storage_host(item,count).ok
	if not world.storage.take({item:count}).ok:return false
	world.actors[actor].carry[item]=int(world.actors[actor].carry.get(item,0))+count
	return true
