extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
## Host-only initial content. Never a model action or a progress migration.
const CONFIG="res://content/openings/showcase.json"
static func config()->Dictionary:return JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
static func v3(world:RefCounted)->bool:return world.catalog.manifest.get("template_id","")=="home-v3"
static func allowed_preset(world:RefCounted,origin:Variant)->bool:return v3(world) and origin in ["showcase","standard"]
static func house(world:RefCounted,id:String)->bool:
	return v3(world) and world.catalog.regions.home.layout.residential.any(func(plot):return plot.site_id==id and not str(plot.owner_id).is_empty())
static func furniture(world:RefCounted,item:Dictionary)->bool:
	if v3(world) and preload("res://scripts/resort_system.gd").valid_furniture(item):return true
	if not allowed_preset(world,item.get("preset_origin")) or item.get("invested")!=0:return false
	if item.get("preset_origin")=="standard":return item.get("id")=="furniture.1" and item.get("recipe_id")==world.standard.config.house.furniture[0].recipe_id
	var id:String=str(item.get("id",""))
	if not id.begins_with("furniture.") or not id.trim_prefix("furniture.").is_valid_int():return false
	var serial:int=int(id.trim_prefix("furniture."));var definitions:Array=config().furniture
	var count:int=10000000
	# Initial identity follows a real movable instance; ordinary placement validation
	# separately checks its current room, including a subsequently built sixth house.
	return serial>=1 and serial<=count and definitions.any(func(d):return d.recipe_id==item.get("recipe_id"))
static func apply(world:RefCounted,library:RefCounted,chosen:String="showcase")->Dictionary:
	if not v3(world):return {"ok":false,"error":"opening_template_mismatch"}
	if chosen not in ["standard","showcase"]:return {"ok":false,"error":"unknown_opening"}
	if world.opening_id==chosen:return {"ok":true,"applied":false}
	if not world.opening_id.is_empty():return {"ok":false,"error":"opening_already_chosen"}
	if not world.memories.records.is_empty() or not world.drops.is_empty() or not world.work.jobs.is_empty():return {"ok":false,"error":"opening_requires_empty_world"}
	install_templates(world,library)
	if chosen=="standard":return world.standard.apply(library)
	for id in world.actors:
		if id!="human":world.actors[id].controller="local"
	var rules:=config()
	for plot in world.catalog.regions.home.layout.residential:
		if str(plot.owner_id).is_empty():continue
		var art:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(plot.get("artwork_path","res://content/house-retrofits/houses/"+plot.retrofit_id+".json")))
		if not library.valid(art):return {"ok":false,"error":"invalid_opening_art"}
	for plot in world.catalog.regions.home.layout.residential:
		if str(plot.owner_id).is_empty():continue
		var site:Dictionary=world.objects[plot.site_id]
		var art:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(plot.get("artwork_path","res://content/house-retrofits/houses/"+plot.retrofit_id+".json")))
		if library.artworks.has(art.id) and JSON.stringify(library.artworks[art.id])!=JSON.stringify(art):art.id="showcase-"+world.world_id.substr(0,8)+"-"+art.id
		library.artworks[art.id]=art.duplicate(true)
		var quote:Dictionary=world.Blueprint.quote(art.structure)
		site["blueprint"]={"id":art.id,"structure":art.structure.duplicate(true),"artwork":art.duplicate(true),"wood":quote.wood,"stages":quote.stages.duplicate()}
		site.stage_index=5;site.status="complete";site.stage="complete";site.invested=0;site.delivered={};site["preset_origin"]="showcase";site.erase("contributions")
		if str(plot.owner_id)!="human" and world.actors.has(plot.owner_id):
			var entry:Vector2=world.interior.outside("room."+site.id);world.actors[plot.owner_id].position=[entry.x,entry.y]
		for definition in rules.furniture:
			world.interior.serial+=1
			var recipe:Dictionary=world.interior.RECIPES[definition.recipe_id];var fid:String="furniture."+str(world.interior.serial)
			world.interior.furniture[fid]={"id":fid,"kind":"furniture","recipe_id":definition.recipe_id,"name":recipe.name,"region_id":"room."+site.id,"position":definition.position.duplicate(),"facing":definition.facing,"holder_id":"","invested":0,"items":{},"capacity":0,"artwork":library.artworks["furniture-"+definition.recipe_id].duplicate(true),"preset_origin":"showcase"}
	if not world.leisure.sites.has("play.gomoku.2"):
		var second:Dictionary=world.leisure.sites["play.gomoku"].duplicate(true);second.id="play.gomoku.2";second.name=LocalText.source("system.world_opening.shaded_chess_table_ii");world.leisure.sites[second.id]=second
	for id in rules.facility_anchors:
		world.leisure.sites[id].position=world.map_anchor(str(rules.facility_anchors[id]))
	for site in world.leisure.sites.values():
		site.artwork=library.artworks[site.template_id].duplicate(true);site.complete=true;site.invested=0;site["preset_origin"]="showcase"
	world.homestead.site.state="completed";world.homestead.site["preset_origin"]="showcase"
	world.recipes.recipes[world.homestead.config.unlock_recipe.id]=world.homestead.config.unlock_recipe.duplicate(true)
	# Replace only the brand-new baseline inventory with the opening's physical stock.
	world.storage.restore({"items":rules.storage})
	for farm in world.farms.farms.values():
		if str(farm.id).begins_with("farm.theirs") or farm.get("raised_bed",false):continue
		var plots:Array=world.farms.farm_plots(farm.id)
		var initial_crops:Array=farm.crop_ids.filter(func(id):return id not in ["potato","corn"])
		for i in range(plots.size()):
			var crop:String=initial_crops[i%initial_crops.size()];var p:Dictionary=plots[i]
			p.crop_id=crop;p.watered=true;p.planted_at=world.farms.clock-float(world.farms.crops[crop].seconds)*float(rules.crop_phases[i%rules.crop_phases.size()])
	world.opening_id="showcase";world._grids.clear();world._terrain_solids.clear();world._routes.clear();world._forced_runs.clear();world.revision+=1
	return {"ok":true,"applied":true}

static func manifest_from_args()->String:
	return "res://content/home-v3/world.json" if "--opening=showcase" in OS.get_cmdline_user_args() or "--opening=standard" in OS.get_cmdline_user_args() else "res://content/world.json"

static func install_templates(world:RefCounted,library:RefCounted)->void:
	if not v3(world):return
	for path in world.catalog.regions.home.layout.get("profile_templates",[]):
		var template:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
		if not library.artworks.has(template.get("id","")) and library.valid(template):library.artworks[template.id]=template
	for plot in world.catalog.regions.home.layout.residential:
		if str(plot.get("retrofit_id","")).is_empty():continue
		var art:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(plot.get("artwork_path","res://content/house-retrofits/houses/"+plot.retrofit_id+".json")))
		# Authored defaults only fill missing entries; published player templates win.
		if not library.artworks.has(art.get("id","")) and library.valid(art):library.artworks[art.id]=art
