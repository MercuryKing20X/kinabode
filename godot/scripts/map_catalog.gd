class_name MapCatalog
extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
var _owner: WeakRef
var world: RefCounted:
	get: return _owner.get_ref()
func _init(source: RefCounted) -> void: _owner=weakref(source)

func summary(id: String) -> Dictionary:
	var region: Dictionary=world.catalog.regions[id]
	var pack_info: Dictionary=world.catalog.region_packs.get(id,{})
	var counts: Dictionary={}
	for object in world.objects.values():
		if object.region_id==id:counts[object.kind]=int(counts.get(object.kind,0))+1
	var value:Dictionary={"id":id,"name":region.name,"origin":region.origin.duplicate(),"local_origin":region.get("local_origin",[0,0]).duplicate(),"size":region.size.duplicate(),"walking_areas":[{"id":"home.moon","name":LocalText.text("system.map_catalog.crescent_island"),"availability":"walkable","access":"walking_bridge","bridge_id":"moon.bridge"}] if id=="home" and not region.get("layout",{}).get("moon",{}).is_empty() else [],"availability":"home" if id=="home" else "preview_only","travel_available":false,"pack":pack_info.duplicate(true),"object_counts":counts,"fisheries":world.fishing.pens.values().filter(func(pen):return pen.region_id==id).map(func(pen):return {"id":pen.id,"name":pen.name,"rect":pen.rect.duplicate(),"capacity":pen.capacity})}

	if id=="home" and region.get("layout",{}).has("homelands"):
		value.walking_areas.append({"id":"home.homelands","name":LocalText.text("content.homeisland.name"),"availability":"walkable","access":"walking_bridge","bridge_id":"homelands.bridge"})
	return value

func read(actor_id: String, query: Dictionary={}) -> Dictionary:
	if not world.actors.has(actor_id):return {"ok":false,"error":"unknown_resident"}
	for key in query:
		if key not in ["region_id","offset","limit","revision"]:return {"ok":false,"error":"invalid_map_query"}
	for key in ["region_id","revision"]:
		if query.has(key) and (not query[key] is String or query[key].is_empty() or query[key].length()>128):return {"ok":false,"error":"invalid_map_query"}
	var offset: Variant=query.get("offset",0);var limit: Variant=query.get("limit",24)
	for value in [offset,limit]:
		if not (value is int or value is float) or not is_finite(value) or value!=floor(value):return {"ok":false,"error":"invalid_map_query"}
	if offset<0 or offset>10000 or limit<1 or limit>100:return {"ok":false,"error":"invalid_map_query"}
	var ids: Array=world.catalog.regions.keys();ids.sort()
	var entries: Array=[]
	for id in ids:entries.append(summary(id))
	var revision: String=JSON.stringify([world.world_id,world.catalog.manifest,world.catalog.regions,world.catalog.region_packs,world.fishing.rules]).sha256_text()
	if (offset>0 and not query.has("revision")) or (query.has("revision") and query.revision!=revision):return {"ok":false,"error":"stale_map","revision":revision}
	var result: Dictionary={"ok":true,"schema_version":1,"world_id":world.world_id,"self_actor_id":actor_id,"revision":revision,"world_bounds":world.catalog.manifest.bounds.duplicate(),"regions":entries.slice(int(offset),int(offset+limit)),"total":entries.size(),"next_offset":int(offset+limit) if offset+limit<entries.size() else -1,"capabilities":{"list":true,"detail":true,"pack_validation":"host_development_only","pack_import":false,"hot_reload":false,"cross_island_travel":false,"new_outdoor_play":false,"supported_pack_object_kinds":["tree","farm_plot","construction_site"]}}
	if query.has("region_id"):
		if not world.catalog.regions.has(query.region_id):return {"ok":false,"error":"unknown_region"}
		result["region"]=summary(query.region_id)
		result.region["land"]=world.catalog.regions[query.region_id].land.duplicate(true)
		result.region["local_origin"]=world.catalog.regions[query.region_id].get("local_origin",[0,0]).duplicate()
		result.region["land_extensions"]=world.catalog.regions[query.region_id].get("land_extensions",[]).duplicate(true)
		result.region["walking_available"]=query.region_id=="home"
		result.region["walking_areas"]=world.catalog.regions[query.region_id].get("layout",{}).get("moon",{}).duplicate(true)
		result.region["bridges"]=world.catalog.regions[query.region_id].get("layout",{}).get("dock_surfaces",[]).filter(func(s):return s.get("id")=="moon.bridge").duplicate(true)
		result.region["zones"]=world.catalog.regions[query.region_id].zones.duplicate(true)
	return result.duplicate(true)
