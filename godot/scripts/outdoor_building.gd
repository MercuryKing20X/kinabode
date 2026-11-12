extends RefCounted
## Host-only plot registry. Existing construction and Leisure own paid work.
const PREFIX="homelands.free."
static func new_plot(world:RefCounted,at:Vector2)->Dictionary:
	if world.resort!=null and world.resort.contains(at):return world._error("vacation_only")
	if not at.is_finite() or not world.home_island.contains(at):return world._error("invalid_position")
	var ids:Array=world.objects.keys().filter(func(id):return str(id).begins_with(PREFIX))
	if ids.size()>=20:return world._error("plot_limit")
	var site:Dictionary=world.catalog.objects.get("homelands.house.01",{}).duplicate(true)
	if site.is_empty():
		for object in world.catalog.objects.values():
			if object.kind=="construction_site" and str(object.id).begins_with("homelands."):site=object.duplicate(true);break
	if site.is_empty():return world._error("unknown_site")
	var area:=Rect2(at-world.site_size(site)/2,world.site_size(site))
	for y in range(floori(area.position.y)-1,ceili(area.end.y)+2):
		for x in range(floori(area.position.x)-1,ceili(area.end.x)+2):
			if not world.walkable("home",Vector2(x+.5,y+.5)):return world._error("occupied")
	for object in world.objects.values():
		if object.kind=="construction_site" and area.grow(2).intersects(Rect2(world.point(object)-world.site_size(object)/2,world.site_size(object))):return world._error("occupied")
	for route in world._routes.values():
		for point in route:
			if area.grow(1).has_point(point):return world._error("occupied")
	for actor in world.actors.values():
		if actor.region_id=="home" and area.grow(1).has_point(world.point(actor)):return world._error("occupied")
	var index:int=1
	while world.objects.has(PREFIX+str(index)):index+=1
	site.id=PREFIX+str(index);site.position=[at.x,at.y];site.region_id="home";site.stage_index=0;site.invested=0;site.delivered={};site.contributions={};site.erase("preset_origin");site.erase("host_completed");site.erase("host_completion_source")
	world.catalog.objects[site.id]=site.duplicate(true);world.objects[site.id]=site
	world._grids.clear();world.revision+=1
	return {"ok":true,"site_id":site.id}
static func saved(world:RefCounted)->Dictionary:
	var result:Dictionary={}
	for id in world.objects:
		if str(id).begins_with(PREFIX):result[id]=world.catalog.objects[id].duplicate(true)
	return result
static func install(world:RefCounted,data:Dictionary)->bool:
	var plots:Variant=data.get("outdoor_plots",{})
	if not plots is Dictionary or plots.size()>20:return false
	var template:Dictionary={}
	for object in world.catalog.objects.values():
		if object.kind=="construction_site" and str(object.id).begins_with("homelands.") and not str(object.id).begins_with(PREFIX):template=object;break
	for id in plots:
		if not id is String or not id.begins_with(PREFIX) or not id.trim_prefix(PREFIX).is_valid_int() or int(id.trim_prefix(PREFIX))<1 or int(id.trim_prefix(PREFIX))>20 or not plots[id] is Dictionary:return false
		var entry:Dictionary=plots[id]
		if not data.get("objects",{}).has(id) or not world.catalog._pair(entry.get("position")) or not world.home_island.contains(world.point(entry)):return false
		var expected:Dictionary=template.duplicate(true)
		expected.id=id;expected.position=entry.position;expected.region_id="home";expected.stage_index=0;expected.invested=0;expected.delivered={};expected.contributions={};expected.erase("preset_origin");expected.erase("host_completed");expected.erase("host_completion_source")
		if not equivalent(entry,expected):return false
	var occupied:Array=[]
	for id in plots:
		var entry:Dictionary=plots[id]
		var size:Vector2=world.site_size(entry);var area:=Rect2(world.point(entry)-size/2,size)
		for other in occupied:
			if area.grow(2).intersects(other):return false
		for existing in world.catalog.objects.values():
			if existing.kind=="construction_site" and not str(existing.id).begins_with(PREFIX) and area.grow(2).intersects(Rect2(world.point(existing)-world.site_size(existing)/2,world.site_size(existing))):return false
		for y in range(floori(area.position.y)-1,ceili(area.end.y)+2):
			for x in range(floori(area.position.x)-1,ceili(area.end.x)+2):
				if not world.terrain_surface("home",Vector2(x+.5,y+.5)):return false
		occupied.append(area)
	for id in plots:
		world.catalog.objects[id]=plots[id].duplicate(true);world.objects[id]=plots[id].duplicate(true)
	return true

static func equivalent(a:Variant,b:Variant)->bool:
	if (a is int or a is float) and (b is int or b is float):return a==b
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for key in a:
			if not b.has(key) or not equivalent(a[key],b[key]):return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for i in a.size():
			if not equivalent(a[i],b[i]):return false
		return true
	return a==b
