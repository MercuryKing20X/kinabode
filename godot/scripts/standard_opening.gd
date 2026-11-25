extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
## Opening-specific content projection and first-meal facts; existing Work owns construction.
const PATH="res://content/openings/standard.json"
const COMPANY_PACING=preload("res://content/company-pacing.json")
const RETIRED_FISHERY_COSTS={"play.standard.south-pen":12,"play.standard.west-pen":12}
var _owner:WeakRef
var world:RefCounted:
	get:return _owner.get_ref()
var config:Dictionary={}
var sites:Dictionary={}
var original_camp_positions:Dictionary={}
var company_chat_after:=0.0
func _init(source:RefCounted)->void:
	_owner=weakref(source);config=JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not valid_config(config):world.error=LocalText.text("ui.opening.config_invalid");config={};return
	for spec in config.get("construction",[]):sites[spec.id]=spec
	for id in world.barbecues:original_camp_positions[id]=world.barbecues[id].station.position.duplicate()
func valid_config(data:Variant)->bool:
	if not data is Dictionary or data.get("version")!=1 or data.get("id")!="standard" or data.get("template_id")!="home-v3" or data.get("implemented")!=true:return false
	var keys:Array=["version","id","template_id","implemented","purpose","companions","spawn_points","hidden_scenery","house","first_farm","storage","forage_ids","forage_anchors","suggestion","first_meal_lines","construction","seat_offsets"]
	if data.size()!=keys.size() or keys.any(func(k):return not data.has(k)) or not data.suggestion is String or data.suggestion.length()>40:return false
	if not data.seat_offsets is Array or data.seat_offsets.size()!=world.life.activity_rules.seat_offsets.size() or data.seat_offsets.any(func(p):return not world.catalog._pair(p)):return false
	if not data.get("companions") is Array or data.companions.size()!=4 or data.companions.any(func(id):return not world.residents.definitions.has(id) or id=="human") or not data.get("spawn_points") is Dictionary:return false
	for id in data.companions:
		if not data.spawn_points.get(id) is Dictionary or data.spawn_points[id].size()!=2 or not data.spawn_points[id].get("anchor") is String or (world.catalog.manifest.get("template_id")=="home-v3" and not world.catalog.regions.home.layout.anchors.has(data.spawn_points[id].anchor)) or not world.catalog._pair(data.spawn_points[id].get("offset")) or not data.get("first_meal_lines",{}).get(id) is String or data.first_meal_lines[id].length()>60:return false
	if not data.get("construction") is Array or data.construction.size()!=6 or not data.get("storage") is Dictionary or not data.get("house") is Dictionary:return false
	if not data.hidden_scenery is Array or data.hidden_scenery.any(func(id):return not id is String or (world.catalog.manifest.get("template_id")=="home-v3" and id not in world.catalog.regions.home.layout.cliffs.map(func(c):return c.id))):return false
	var seen:Array=[]
	var targets:Array=[]
	for spec in data.construction:
		if not spec is Dictionary or spec.size()!=4 or not spec.get("id") is String or not spec.id.begins_with("play.standard.") or spec.id in seen or not spec.get("name") is String or not world._integer(spec.get("wood")) or spec.wood<1 or spec.wood>1000:return false
		if spec.get("target") not in ["home.barbecue","moon.barbecue","moon.lookout","farm.hill","farm.lake","farm.east"]:return false
		if spec.target in targets:return false
		targets.append(spec.target)
		seen.append(spec.id)
	for item in data.storage:
		if item not in ["wood","mushroom","seed.turnip","seed.tomato"] or not world._integer(data.storage[item]) or data.storage[item]<0 or data.storage[item]>80:return false
	return data.get("first_farm")=="farm.home" and data.house.get("site_id")=="home.house.01" and data.house.get("template_id")=="cottage" and data.house.get("furniture") is Array and data.house.furniture.size()==1 and data.house.furniture[0].get("recipe_id")=="chair" and data.get("forage_ids") is Array and data.get("forage_anchors") is Array and data.forage_ids.size()==2 and data.forage_anchors.size()==2
func active()->bool:return world.opening_id=="standard"
func first_company_day()->bool:return active() and world.days.day()==1
func ready(target:String)->bool:
	if world.barbecues.has(target):
		var camp_plan:Dictionary=world.leisure.sites.get(site_for(target),{})
		if camp_plan.get("world_camp_rebuild",false):return camp_plan.complete
	if not active():return true
	for id in sites:
		if sites[id].target==target:return world.leisure.sites.get(id,{}).get("complete",false)
	return true

func sync_camps()->void:
	for target in world.barbecues:
		world.barbecues[target].station.position=camp_position(target,world.leisure.sites)

func camp_position(target:String,plans:Dictionary)->Array:
	var plan:Dictionary=plans.get(site_for(target),{})
	if original_camp_positions.has(target) and plan.get("world_camp_rebuild",false) and plan.get("complete",false) and world.catalog._pair(plan.get("position")):
		return plan.position.duplicate()
	return original_camp_positions.get(target,world.barbecues[target].station.position).duplicate()
func install_geometry()->void:
	world.life.activity_rules.seat_offsets=config.seat_offsets.duplicate(true)
	for index in range(config.forage_ids.size()):world.life.patches[config.forage_ids[index]].position=world.map_anchor(config.forage_anchors[index])
func site_for(target:String)->String:
	for id in sites:
		if sites[id].target==target:return id
	return ""
func install_sites(library:RefCounted)->void:
	for id in sites:
		if world.leisure.sites.has(id):continue
		var spec:Dictionary=sites[id];var art:Dictionary=library.artworks["play-bench"].duplicate(true)
		art.recreation={"width":3,"depth":3,"behavior":"sit","seconds":5,"entry":[0,1.5],"slots":[[-1,1],[1,1]],"obstacles":[]}
		world.leisure.sites[id]={"id":id,"name":spec.name,"kind":"play_site","region_id":"home","position":position(spec.target),"template_id":"play-bench","invested":0,"complete":false,"artwork":art}
func position(target:String)->Array:
	if world.barbecues.has(target):return world.barbecues[target].station.position.duplicate()
	if world.farms.farms.has(target):return world.farms.farms[target].entrance.duplicate()
	return world.map_anchor("moon.lookout")
func apply(library:RefCounted)->Dictionary:
	install_geometry();install_sites(library)
	var site:Dictionary=world.objects[config.house.site_id];var art:Dictionary=library.artworks[config.house.template_id].duplicate(true);var quote:Dictionary=world.Blueprint.quote(art.structure)
	site["blueprint"]={"id":art.id,"structure":art.structure.duplicate(true),"artwork":art,"wood":quote.wood,"stages":quote.stages.duplicate()}
	site.stage_index=5;site.status="complete";site.stage="complete";site.invested=0;site.delivered={};site["preset_origin"]="standard";site.erase("contributions")
	for definition in config.house.furniture:
		world.interior.serial+=1;var recipe:Dictionary=world.interior.RECIPES[definition.recipe_id];var fid:="furniture."+str(world.interior.serial)
		world.interior.furniture[fid]={"id":fid,"kind":"furniture","recipe_id":definition.recipe_id,"name":recipe.name,"region_id":"room."+site.id,"position":definition.position.duplicate(),"facing":definition.facing,"holder_id":"","invested":0,"items":{},"capacity":0,"artwork":library.artworks["furniture-"+definition.recipe_id].duplicate(true),"preset_origin":"standard"}
	world.storage.restore({"items":config.storage})
	for farm in world.farms.farms.values():farm.manager_id="human"
	for id in config.companions:
		world.actors[id].controller="local";var spec:Dictionary=config.spawn_points[id];var anchor:Array=world.map_anchor(spec.anchor);var at:Vector2=Vector2(anchor[0],anchor[1])+Vector2(spec.offset[0],spec.offset[1]);world.actors[id].position=[at.x,at.y]
	for index in range(config.forage_ids.size()):world.life.patches[config.forage_ids[index]].position=world.map_anchor(config.forage_anchors[index])
	world.opening_id="standard";world._grids.clear();world._terrain_solids.clear();world.revision+=1
	return {"ok":true,"applied":true}
