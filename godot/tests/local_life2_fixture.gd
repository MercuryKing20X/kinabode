extends RefCounted
const F=preload("res://tests/cooking_fixture.gd")
const Fish=preload("res://tests/fishing_fixture.gd")
static func shared_catch(world: RefCounted,id: String="codex") -> bool:
	if not Fish.coast(world,"human"):return false
	var p: Vector2=world.point(world.actors.human);var near:=false
	for offset in [Vector2(2,0),Vector2(-2,0),Vector2(0,2),Vector2(0,-2)]:
		if world.walkable("home",p+offset) and F.job(world,id,{"intent":"move","x":p.x+offset.x,"y":p.y+offset.y}):near=true;break
	if not near:return false
	var fish: Dictionary=Fish.catch_one(world,"human")
	if fish.is_empty():return false
	return world.command("human",{"intent":"stock_fish","fish_id":fish.id,"pen_id":world.fishing.pens.keys()[0]}).ok
