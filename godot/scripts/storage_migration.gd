extends RefCounted
const Ledger=preload("res://scripts/system_storage.gd")
# Runs on the parsed private copy, before ordinary save validation. Failed loads
# keep the original file and existing invalid-save backup behavior unchanged.
static func migrate(data:Dictionary,world:RefCounted=null)->bool:
	if not data.get("objects") is Dictionary or not data.get("actors") is Dictionary:return false
	if data.actors.values().any(func(actor):return not actor is Dictionary):return false
	var ledger:=Ledger.new()
	if not ledger.restore(data.get("storage",{"items":{}})):return false
	var legacy:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/legacy-storage.json")).objects
	for id in data.objects.keys():
		var item:Variant=data.objects[id]
		if not item is Dictionary or not item.has("kind") or not item.has("id") or not item.has("region_id") or not item.has("position"):return false
		if item.get("kind")!="chest":continue
		if not legacy.has(id) or not item.get("items") is Dictionary:return false
		var definitions:Array=legacy[id]
		if not definitions.any(func(d):
			if item.get("capacity")!=d.capacity or item.get("id")!=id or item.get("region_id")!=d.get("region_id","home"):return false
			var at:Variant=d.get("position")
			if at==null and world!=null and d.has("anchor"):
				at=world.map_anchor(d.anchor);at=[at[0]+d.offset[0],at[1]+d.offset[1]]
			return at!=null and item.get("position")==at):return false
		if not Ledger.valid_items(item.items) or not _bounded(item.items,int(item.capacity)):return false
		if not ledger.add(item.items):return false
		data.objects.erase(id)
	var farming:Variant=data.get("farming",{})
	if not farming is Dictionary:return false
	if farming.has("containers"):
		if not farming.containers is Dictionary or not farming.get("farms") is Dictionary:return false
		var expected:Dictionary={}
		if world==null:return false
		for farm_id in world.farms.farms:
			# Production beds were introduced after physical farm chests retired.
			# They never had legacy seed/harvest containers to migrate.
			if str(farm_id).begins_with("farm.theirs") or world.farms.farms[farm_id].get("raised_bed",false):continue
			var farm:Variant=farming.farms.get(farm_id)
			if not farm is Dictionary or farm.get("id")!=farm_id:return false
			for role in ["seed","harvest"]:
				var old_id:String=str(farm.get(role+"_storage",str(farm_id)+"."+role))
				if not expected.has(old_id):expected[old_id]={"id":old_id,"kind":"chest","region_id":"home","position":farm.get(role+"_at"),"farm_id":farm_id,"role":role,"capacity":240}
		if farming.containers.size()!=expected.size():return false
		for id in farming.containers:
			if not expected.has(id):return false
			if not farming.containers[id] is Dictionary:return false
			for key in expected[id]:
				if farming.containers[id].get(key)!=expected[id][key]:return false
			var item:Variant=farming.containers[id]
			if not item is Dictionary or item.get("id")!=id or item.get("kind")!="chest" or item.get("capacity")!=240 or not _bounded(item.get("items"),240):return false
			if not Ledger.valid_items(item.items) or not ledger.add(item.items):return false
		farming.erase("containers")
	var inside:Variant=data.get("interior",{})
	if not inside is Dictionary:return false
	if inside.has("furniture"):
		if not inside.furniture is Dictionary or inside.furniture.size()>64:return false
		for item in inside.furniture.values():
			if not item is Dictionary or item.get("recipe_id") not in ["table","chair","chest","rug","lamp"] or not item.get("holder_id") is String:return false
			if not item.get("position") is Array or item.position.size()!=2:return false
		var probe:RefCounted=null
		if inside.furniture.values().any(func(item):return item is Dictionary and (item.get("kind")=="chest" or item.get("recipe_id")=="chest")):
			if world==null:return false
			probe=world.get_script().new(world.source_manifest)
			probe.objects=data.objects.duplicate(true);probe.actors=data.actors.duplicate(true);probe.interior.furniture=inside.furniture.duplicate(true)
			probe.interior.RECIPES["chest"]={"wood":6,"size":[2,1]}
		for id in inside.furniture.keys():
			var item:Variant=inside.furniture[id]
			if not item is Dictionary:return false
			if item.get("recipe_id")!="chest" and item.get("kind")!="chest":continue
			if item.get("recipe_id")!="chest" or item.get("kind")!="chest" or item.get("capacity")!=80 or (not Ledger.valid_items({"wood":item.get("invested")}) or int(item.invested) not in [0,6]) or not _bounded(item.get("items"),80) or not Ledger.valid_items(item.items):return false
			if not _furniture_valid(data,id,item,probe):return false
			if item.invested==0 and item.get("preset_origin")!="showcase":return false
			if not ledger.add(item.items) or not ledger.add({"wood":int(item.invested)}):return false
			inside.furniture.erase(id)
			for actor in data.actors.values():
				if actor.get("furniture_id")==id:actor.erase("furniture_id")
	if not data.get("shared_life",{}) is Dictionary or not data.get("extra_barbecues",{}) is Dictionary:return false
	var lives:Array=[data.get("shared_life",{})]
	for life in data.get("extra_barbecues",{}).values():
		if not life is Dictionary:return false
		lives.append(life)
	for life in lives:
		if not life.get("station",{}) is Dictionary:return false
		var station:Dictionary=life.get("station",{})
		if not station.get("fireside",{}) is Dictionary:return false
		var current:Variant=station.get("fireside",{}).get("current",{})
		if not current is Dictionary:return false
		for key in ["sources","wood_sources"]:
			if not current.has(key):continue
			var source:Variant=current[key]
			if not source is Dictionary:return false
			if source.has("chests"):
				current["storage_migrated"]=true
				if not source.chests is Dictionary or source.chests.keys().any(func(id):return not id is String):return false
				var amounts:Dictionary=source.get("storage",{}).duplicate(true)
				if not Ledger.valid_items(amounts):return false
				for values in source.chests.values():
					if not Ledger.valid_items(values):return false
					for item in values:amounts[item]=int(amounts.get(item,0))+int(values[item])
				source["storage"]=amounts;source.erase("chests")
	if not data.get("homestead",{}) is Dictionary:return false
	var plans:Variant=data.get("homestead",{}).get("plans",{})
	if not plans is Dictionary:return false
	for plan in plans.values():
		if not plan is Dictionary or not plan.get("receipt",{}) is Dictionary:return false
		if not plan.get("receipt",{}).is_empty():plan.receipt.source_id="storage"
	data["storage"]=ledger.saved()
	return true
static func _bounded(items:Variant,maximum:int)->bool:
	if not Ledger.valid_items(items):return false
	var allowed:Array=["firefly.jar","wood","mushroom","turnip","tomato","pumpkin","daisy","blueberry","apple","seed.turnip","seed.tomato","seed.pumpkin","seed.daisy","seed.blueberry","seed.apple"]
	if items.keys().any(func(item):return item not in allowed):return false
	var total:=0
	for n in items.values():total+=int(n)
	return total<=maximum

static func _furniture_valid(data:Dictionary,id:Variant,item:Dictionary,probe:RefCounted)->bool:
	if not id is String or not id.begins_with("furniture.") or not id.trim_prefix("furniture.").is_valid_int():return false
	var serial:int=int(id.trim_prefix("furniture."))
	if item.get("id")!=id or serial<1 or serial>int(data.interior.get("serial",0)):return false
	if not item.get("name") is String or item.name.length()>48 or item.get("facing") not in ["up","down"]:return false
	var position:Variant=item.get("position")
	if not position is Array or position.size()!=2:return false
	for n in position:
		if not (n is float or n is int) or not is_finite(float(n)):return false
	var room:Variant=item.get("region_id")
	if not room is String or not room.begins_with("room."):return false
	var house:Variant=data.objects.get(room.trim_prefix("room."),{})
	if not house is Dictionary or house.get("kind")!="construction_site" or house.get("stage_index")!=5:return false
	if not item.get("holder_id") is String:return false
	if not item.holder_id.is_empty():
		if not data.actors.has(item.holder_id) or data.actors[item.holder_id].get("furniture_id")!=id or not item.items.is_empty():return false
		var actor:Dictionary=data.actors[item.holder_id]
		if not actor.get("carry") is Dictionary:return false
		if not actor.carry.is_empty() and not (actor.get("pocketed",false) and actor.carry.keys().all(func(k):return probe.pocket_item(str(k)))):return false
		if data.interior.furniture.values().any(func(other):return other is Dictionary and other.get("id")!=id and other.get("holder_id")==item.holder_id):return false
	elif probe==null or not probe.interior.placement(room,item,id,false):return false
	var art:Variant=item.get("artwork")
	if not art is Dictionary:return false
	if not art.is_empty():
		if not preload("res://scripts/character_library.gd").new().valid(art) or art.get("id")!="furniture-chest" or art.get("kind")!="facility" or art.get("facility_type")!="furniture":return false
	return true
