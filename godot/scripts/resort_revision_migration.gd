extends RefCounted
## Validate the previous geometry before changing any saved material or position.
const OLD="res://content/migrations/resort-v1/world.json"
static func old_world()->RefCounted:
	var w:RefCounted=load("res://content/migrations/resort-v1/world-state.gd").new(OLD)
	w.residents.provision(w)
	return w
static func removed(id:String)->bool:return id.begins_with("homelands.house.") or id.begins_with("homelands.free.")
static func migrate(world:RefCounted,data:Dictionary)->bool:
	if not world.locations.v3():return true
	if data.get("vacation_version",0)==4:return true
	if data.get("vacation_version",0)==3:return flower_isle(world,data)
	if data.get("vacation_version",0)==2:
		if not reduce_villas(world,data):return false
		return flower_isle(world,data,false)
	var old:RefCounted=old_world()
	if not old.error.is_empty():return false
	if data.get("opening_id")=="standard":old.standard.install_geometry()
	var outdoor:Script=load("res://scripts/outdoor_building.gd")
	if not outdoor.install(old,data):return false
	var store:Script=load("res://scripts/save_store.gd")
	if not store._valid(old,data):return false
	var next:Dictionary=data.duplicate(true)
	var refunds:Dictionary={};var total:=0
	for id in next.objects.keys():
		if not removed(id):continue
		var object:Dictionary=next.objects[id]
		var amount:int=int(object.get("invested",0))+int(object.get("delivered",{}).get("wood",0))
		refunds[id]=amount;total+=amount;next.objects.erase(id)
	for id in next.get("outdoor_plots",{}).keys():
		if removed(id):next.outdoor_plots.erase(id)
	var furniture:Dictionary=next.get("interior",{}).get("furniture",{})
	for id in furniture.keys():
		var item:Dictionary=furniture[id]
		if not str(item.get("region_id","")).begins_with("room.") or not removed(str(item.region_id).trim_prefix("room.")):continue
		var amount:int=int(item.invested)
		refunds[id]=amount;total+=amount
		for actor in next.actors.values():
			if actor.get("furniture_id")==id:actor.erase("furniture_id")
		furniture.erase(id)
	if not next.has("storage"):next.storage={"items":{}}
	var inventory:Dictionary=next.storage.items
	if int(inventory.get("wood",0))>9007199254740991-total:return false
	if total>0:inventory.wood=int(inventory.get("wood",0))+total
	# One previous live plant yields once only if actually mature; immature saves
	# retain the original invested seed without receiving premature produce.
	for plot in next.get("farming",{}).get("plots",{}).values():
		if float(plot.get("position",[0,0])[1])<150 or str(plot.get("crop_id","")).is_empty():continue
		var crop:String=plot.crop_id
		var seed:String="seed."+crop
		inventory[seed]=int(inventory.get(seed,0))+1
		var cfg:Dictionary=old.farms.crops[crop]
		if plot.get("watered",false) and float(next.farming.clock)-float(plot.planted_at)>=float(cfg.seconds):inventory[crop]=int(inventory.get(crop,0))+int(cfg.yield)
		plot.crop_id="";plot.watered=false;plot.planted_at=0.0
	for order in next.get("farming",{}).get("orders",{}).values():
		if str(order.get("farm_id","")).begins_with("farm.theirs"):order.status="paused"

	var plaza:Array=world.home_island.config.get("plaza",world.home_island.config.arrival)
	var index:=0
	for actor in next.actors.values():
		var room_removed:bool=str(actor.region_id).begins_with("room.") and removed(str(actor.region_id).trim_prefix("room."))
		var out_of_land:bool=actor.region_id=="home" and float(actor.position[1])>=150 and not world.walkable("home",world.point(actor))
		if room_removed or out_of_land:
			actor.region_id="home";actor.position=[plaza[0]+(index%3-1)*1.8,plaza[1]+3+floori(index/3.0)*1.8];index+=1
	# The same villa identities now occupy their newly authored positions.
	for v in world.resort.config.villas:
		if next.objects.has(v.id):
			next.objects[v.id].position=v.position.duplicate();next.objects[v.id].footprint=v.footprint.duplicate()
	var extra:Dictionary=next.get("extra_barbecues",{}).get("homelands.barbecue",{})
	if not extra.is_empty():
		extra.station.position=world.home_island.config.camp.duplicate()
		for id in extra.patches:
			if world.barbecues["homelands.barbecue"].patches.has(id):extra.patches[id].position=world.barbecues["homelands.barbecue"].patches[id].position.duplicate()
		# Old meal commitments are never resumed; retained meal facts remain.
		if extra.station.has("fireside"):
			var fire:Dictionary=extra.station.fireside
			fire.suspended=true
	var pet:Dictionary=next.get("cat",{})
	if pet.get("region_id")=="home" and float(pet.get("position",[0,0])[1])>=150:pet.position=world.home_island.config.cat_home.duplicate()
	var archive:Dictionary={"plans":{},"memories":[],"interior":[]}
	for id in next.get("projects",{}).get("plans",{}).keys():
		if removed(str(next.projects.plans[id].site_id)):archive.plans[id]=next.projects.plans[id];next.projects.plans.erase(id)
	for memory in next.get("projects",{}).get("memories",[]).duplicate():
		if removed(str(memory.site_id)):archive.memories.append(memory);next.projects.memories.erase(memory)
	for memory in next.get("interior",{}).get("memories",[]).duplicate():
		if removed(str(memory.get("room_id","")).trim_prefix("room.")):archive.interior.append(memory);next.interior.memories.erase(memory)
	if not archive.plans.is_empty() or not archive.memories.is_empty() or not archive.interior.is_empty():next.retired_south_projects=archive
	next.vacation_version=2
	data.clear();data.merge(next)
	world.resort.set_meta("revision_refunds",{"items":refunds,"wood":total})
	if not reduce_villas(world,data,false):return false
	return flower_isle(world,data,false)

static func valid_archive(value:Variant)->bool:
	if not value is Dictionary or value.size()!=3 or not value.get("plans") is Dictionary or not value.get("memories") is Array or not value.get("interior") is Array:return false
	if value.plans.size()>6 or value.memories.size()>32 or value.interior.size()>32:return false
	for id in value.plans:
		var p:Variant=value.plans[id]
		if not p is Dictionary or p.get("actor_id")!=id or not removed(str(p.get("site_id",""))) or p.get("status") not in ["active","paused","blocked","completed","cancelled"]:return false
	for m in value.memories:
		if not m is Dictionary or not removed(str(m.get("site_id",""))) or not m.get("project_id") is String or not m.get("contributors") is Dictionary or not (m.get("at") is float or m.get("at") is int):return false
	for m in value.interior:
		if not m is Dictionary or m.get("kind")!="sat_together" or not (removed(str(m.get("room_id","")).trim_prefix("room.")) or str(m.get("room_id","")).begins_with("room.resort.villa.")) or not m.get("actors") is Array or m.actors.size()!=2 or not (m.get("at") is float or m.get("at") is int):return false
	return true

static func reduce_villas(world:RefCounted,data:Dictionary,validate:bool=true)->bool:
	if validate:
		var previous:RefCounted=load("res://content/migrations/resort-v2/world-state.gd").new("res://content/migrations/resort-v2/world.json")
		previous.residents.provision(previous)
		if data.get("opening_id")=="standard":previous.standard.install_geometry()
		if not load("res://scripts/save_store.gd")._valid(previous,data):return false
	var next:Dictionary=data.duplicate(true)
	var keep:Array=world.resort.config.villas.map(func(v):return v.id)
	var gone:Array=[];var wood:=0
	for id in next.objects.keys():
		if str(id).begins_with("resort.villa.") and id not in keep:
			var site:Dictionary=next.objects[id];wood+=int(site.get("invested",0))+int(site.get("delivered",{}).get("wood",0));gone.append(id);next.objects.erase(id)
	for id in next.interior.furniture.keys():
		var item:Dictionary=next.interior.furniture[id]
		if str(item.region_id).trim_prefix("room.") in gone:
			wood+=int(item.invested);next.interior.furniture.erase(id)
			for actor in next.actors.values():
				if actor.get("furniture_id")==id:actor.erase("furniture_id")
	if int(next.storage.items.get("wood",0))>9007199254740991-wood:return false
	if wood>0:next.storage.items.wood=int(next.storage.items.get("wood",0))+wood
	for v in world.resort.config.villas:
		if next.objects.has(v.id):next.objects[v.id].position=v.position.duplicate()
	var index:=0
	for actor in next.actors.values():
		if str(actor.region_id).trim_prefix("room.") in gone or (actor.region_id=="home" and float(actor.position[1])>=150 and not world.walkable("home",world.point(actor))):
			actor.region_id="home";actor.position=[81+(index%3-1)*2,181+floori(index/3.0)*2];index+=1
	for memory in next.interior.memories.duplicate():
		if str(memory.get("room_id","")).trim_prefix("room.") in gone:
			if not next.has("retired_south_projects"):next.retired_south_projects={"plans":{},"memories":[],"interior":[]}
			next.retired_south_projects.interior.append(memory);next.interior.memories.erase(memory)
	next.vacation_version=3
	data.clear();data.merge(next)
	world.resort.set_meta("two_villa_refund",wood)
	return true

# v0.9: remove holiday fixtures only after strict validation in the preceding
# two-villa geometry. All refunds use the original committed investment.
static func flower_isle(world:RefCounted,data:Dictionary,validate:bool=true)->bool:
	if validate:
		var previous:RefCounted=load("res://content/migrations/flower-predecessor/world-state.gd").new("res://content/home-v3/world.json")
		previous.residents.provision(previous)
		if data.get("opening_id")=="standard":previous.standard.install_geometry()
		if not load("res://scripts/save_store.gd")._valid(previous,data):return false
	var next:Dictionary=data.duplicate(true)
	var removed_rooms:Array=[]
	var total:=0
	for id in next.objects.keys():
		if str(id).begins_with("resort.villa.") and id!="resort.villa.human":
			var site:Dictionary=next.objects[id]
			total+=int(site.get("invested",0))+int(site.get("delivered",{}).get("wood",0))
			removed_rooms.append("room."+id);next.objects.erase(id)
	for id in next.interior.furniture.keys():
		var item:Dictionary=next.interior.furniture[id]
		if item.region_id not in removed_rooms:continue
		total+=int(item.get("invested",0))
		for actor in next.actors.values():
			if actor.get("furniture_id")==id:actor.erase("furniture_id")
		next.interior.furniture.erase(id)
	for id in next.get("leisure",{}).get("sites",{}).keys():
		var item:Dictionary=next.leisure.sites[id]
		if item.get("region_id","home")=="home" and world.home_island.contains(world.point(item)):
			total+=int(item.get("invested",0));next.leisure.sites.erase(id)
	if total>9007199254740991-int(next.storage.items.get("wood",0)):return false
	if total:next.storage.items.wood=int(next.storage.items.get("wood",0))+total
	for actor in next.actors.values():
		if actor.region_id in removed_rooms:
			actor.region_id="home";actor.position=[75,205]
		if actor.region_id=="home" and float(actor.position[1])>=150:actor.position=nearest_open(world,world.point(actor))
	var pet:Dictionary=next.get("cat",{})
	if pet.get("region_id") in removed_rooms:pet.region_id="home";pet.position=[75,205]
	if pet.get("region_id")=="home" and float(pet.get("position",[0,0])[1])>=150:pet.position=nearest_open(world,world.point(pet))
	for item in next.drops.values():
		if item.region_id=="home" and float(item.position[1])>=150:item.position=nearest_open(world,world.point(item))
	for memory in next.interior.memories.duplicate():
		if memory.get("room_id","") in removed_rooms:
			if not next.has("retired_south_projects"):next.retired_south_projects={"plans":{},"memories":[],"interior":[]}
			next.retired_south_projects.interior.append(memory);next.interior.memories.erase(memory)
	next.vacation_version=4
	data.clear();data.merge(next)
	world.resort.set_meta("flower_isle_refund",total)
	return true

static func nearest_open(world:RefCounted,at:Vector2)->Array:
	if world.walkable("home",at):return [at.x,at.y]
	# Increasing distance search, deterministic ties. Same World collision test.
	var best:=Vector2(81,180);var distance:=INF
	for y in range(162,255):
		for x in range(14,149):
			var p:=Vector2(x,y);var d:float=at.distance_squared_to(p)
			if d<distance and world.walkable("home",p):distance=d;best=p
	return [best.x,best.y]
