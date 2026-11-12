extends RefCounted
const F=preload("res://tests/cooking_fixture.gd")
const B=preload("res://tests/backpack_fixture.gd")
static func prepare(world: RefCounted,directory: String) -> bool:
	if world.library==null:world.library=preload("res://scripts/character_library.gd").new();world.library.configure(directory)
	world.residents.provision(world);world.director.set_all_enabled(false)
	if not world.command("human",{"intent":"select_blueprint","target_id":"home.house.01","blueprint_id":"cottage-large"}).ok:return false
	if not B.wood(world,6,"human"):return false
	for id in ["codex","human"]:
		if not F.withdraw(world,id,"wood",8):return false
	# Keep genuine surplus outside the two participants' available stock so each original bundle is exactly8.
	if not F.withdraw(world,"companion-2","wood",2):return false
	var site: Dictionary=world.objects["home.house.01"];var point: Vector2=world.point(site)+Vector2(0,world.site_size(site).y/2+1.5)
	for id in ["codex","human"]:
		if not F.job(world,id,{"intent":"move","x":point.x,"y":point.y}):return false
	return true
static func begin(world: RefCounted) -> bool:
	return world.command("codex",{"intent":"build","target_id":"home.house.01"}).ok and world.command("human",{"intent":"deliver_wood","target_id":"home.house.01"}).ok
