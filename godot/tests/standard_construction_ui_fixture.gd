extends RefCounted
## Required genuine stock for the original construction and one fire renewal.
static func required_wood(world:RefCounted,station_id:String)->int:
	var site_id:String="play.standard.camp" if station_id=="home.barbecue" else "play.standard.moon-camp"
	var site:Dictionary=world.leisure.sites[site_id]
	return maxi(0,world.leisure.cost(site)-int(site.invested))+2*int(world.barbecues[station_id].fireside.config.wood)
static func unobstructed_tree_click(view:Node,pixel:Vector2)->bool:
	return not view.speech_layout().any(func(entry):return entry.box.has_point(pixel))
