extends RefCounted
## Read-only artist composition helpers, not World entities or movement.
static func point(config:Dictionary,entry:Dictionary)->Vector2:
	if entry.has("house"):
		for house in config.get("houses",[]):
			if house.id==entry.house:return Vector2(house.position[0]+entry.offset[0],house.position[1]+entry.offset[1])
	var value:Variant=entry.get("position",[])
	if entry.has("anchor_path"):
		value=config
		for key in entry.anchor_path:value=value[key]
	return Vector2(value[0],value[1])
static func by_id(config:Dictionary,id:String)->Dictionary:
	for prop in config.get("props",[]):
		if prop.id==id:return prop
	return {}
