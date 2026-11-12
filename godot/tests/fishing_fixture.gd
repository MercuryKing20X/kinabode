extends RefCounted
static func walk(world: RefCounted,id: String,point: Array) -> bool:
	var result: Dictionary=world.command(id,{"intent":"move","x":point[0],"y":point[1]})
	if not result.ok:return false
	for i in range(2000):
		world.advance(.1)
		if not world._routes.has(id):return true
	return false
static func coast(world: RefCounted,id: String) -> bool:
	for target in world.fishing.nearby_shores(id):
		if walk(world,id,target.position) and not world.fishing.shore(id).is_empty():return true
	return false
static func catch_one(world: RefCounted,id: String) -> Dictionary:
	var previous:Array=world.fishing.fish.keys()
	var result: Dictionary=world.command(id,{"intent":"fish"})
	if not result.ok:return {}
	for i in range(1200):
		world.advance(.1)
		if not world.work.jobs.has(id):
			var caught:Array=world.fishing.fish.values().filter(func(f):return f.owner_id==id and f.id not in previous)
			return caught[0] if caught.size()==1 else {}
	return {}
static func write_json(path: String,data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(data));file.close()

static func unplaced(world:RefCounted,id:String="human")->Dictionary:
	var entries:Array=world.fishing.fish.values().filter(func(f):return f.owner_id==id and f.location in ["pending","storage"])
	return entries[0] if not entries.is_empty() else {}
