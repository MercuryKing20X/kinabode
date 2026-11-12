extends RefCounted
const F=preload("res://tests/cooking_fixture.gd")
const B=preload("res://tests/backpack_fixture.gd")
static func stock(world: RefCounted) -> bool:
	return B.wood(world,8) and F.harvest(world,"turnip") and F.harvest(world,"turnip") and F.harvest(world,"pumpkin")
static func amount(world: RefCounted,item: String) -> int:
	return (B.wood_total(world) if item=="wood" else F.amount(world,item))+int(world.homestead.site.delivered.get(item,0))
static func deliver(world: RefCounted,id: String,wood: int=24,crop: int=10) -> bool:
	var plan: Dictionary=world.homestead.plans.get(id,{})
	var args: Dictionary={"intent":"homestead_start","site_id":world.homestead.config.site.id,"wood_limit":wood,"crop_limit":crop}
	if plan.get("status") in ["paused","blocked"]:args={"intent":"homestead_resume","plan_id":plan.id,"wood_limit":wood,"crop_limit":crop}
	return F.job(world,id,args)
static func build(world: RefCounted,id: String) -> bool:
	return F.job(world,id,{"intent":"homestead_build","plan_id":world.homestead.plans[id].id})
