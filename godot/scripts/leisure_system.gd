class_name LeisureSystem
extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
const Rules=preload("res://scripts/leisure_rules.gd")
var _owner: WeakRef
var world: RefCounted:
	get:return _owner.get_ref()
var sites: Dictionary={}
var serial:=0
func cost(site:Dictionary)->int:
	return int(world.standard.sites[site.id].wood) if world.standard!=null and world.standard.sites.has(site.id) else Rules.cost(art(site).recreation)
func _init(source: RefCounted) -> void:
	_owner=weakref(source)
	for entry in world.locations.section("leisure"):
		entry.merge({"kind":"play_site","region_id":"home","invested":0,"complete":false,"artwork":{}})
		sites[entry.id]=entry

func art(site: Dictionary) -> Dictionary:
	return site.artwork if not site.artwork.is_empty() else world.library.artworks.get(site.template_id,{}) if world.library!=null else {}
func snapshot() -> Dictionary:
	var list: Array=[]
	for site in sites.values():
		var entry: Dictionary=site.duplicate(true);entry.erase("artwork")
		var work:=art(site)
		if not work.is_empty():entry["configuration"]=work.recreation.duplicate(true);entry["required_wood"]=cost(site)
		entry["occupants"]={}
		for id in world.work.jobs:
			var job: Dictionary=world.work.jobs[id]
			if job.get("target_id")==site.id:entry.occupants[id]=job.get("slot",-1)
		list.append(entry)
	return {"sites":list}
func blocked(region: String,p: Vector2) -> bool:
	if region!="home":return false
	for site in sites.values():
		if world.standard!=null and world.standard.sites.has(site.id):continue
		if not site.complete:continue
		var work:=art(site)
		if work.is_empty():continue
		for box in work.recreation.obstacles:
			if Rect2(world.point(site)+Vector2(box[0],box[1]),Vector2(box[2],box[3])).has_point(p):return true
	return false
func command(id: String,args: Dictionary) -> Dictionary:
	for key in args:
		if key not in ["intent","target_id"]:return world._error("invalid_command")
	if world.projects.active(id) or world.farms.active(id) or world.work.jobs.has(id):return world._error("busy")
	var actor: Dictionary=world.actors[id]
	var intent: String=args.intent;var site: Dictionary=sites.get(str(args.get("target_id","")),{})
	if site.is_empty():return world._error("unknown_facility")
	if site.id.begins_with("play.moon.") and world.standard!=null and not world.standard.ready("moon.lookout"):return world.work.fail("unbuilt_platform",LocalText.text("system.leisure_system.build_the_moon_viewing_platform_before_placing_a_bench"))
	if intent=="build_facility" and world.resort!=null and world.resort.retired(site) and world.their_island.grants.get(id)!=site.id:return world._error("vacation_only")
	var work:=art(site)
	if work.is_empty() or not Rules.valid(work.get("recreation")):return world._error("invalid_facility")
	var job: Dictionary={"intent":intent,"phase":"leisure_work","target_id":site.id,"step":"entry","time":0.0}
	if intent=="build_facility":
		if work.recreation.get("game")=="gomoku" and not site.complete and not chess_space_clear(site,work.recreation):return world.work.fail("chess_space_blocked",LocalText.text("system.leisure_system.the_area_around_the_chess_table_is_occupied_place"))
		if not world.residents.supports(actor,"build_facility") and world.their_island.grants.get(id)!=site.id:return world._error("unsupported_capability")
		if site.complete:return world._error("already_built")
		if actor.has("furniture_id"):return world._error("hands_full")
		if world.work.claims.has(site.id):return world._error("claimed")
		if site.artwork.is_empty():site.artwork=work.duplicate(true)
		job.step="supply";world.work.claims[site.id]=id
	else:
		if world.standard!=null and world.standard.sites.has(site.id):return world._error("construction_only")
		if work.recreation.get("game")=="gomoku":return world.work.fail("open_chess_table",LocalText.text("system.leisure_system.click_the_table_to_invite_a_companion_sit_down"))
		if not site.complete:return world.work.fail("unfinished_facility",LocalText.text("system.leisure_system.build_the_facility_before_using_it"))
		if world.loaded(id):return world.work.fail("hands_full",LocalText.text("system.leisure_system.put_away_what_you_are_holding_before_playing"))
		var slot:=-1
		for index in range(work.recreation.slots.size()):
			if not world.work.claims.has(site.id+".slot.%s"%index):slot=index;break
		if slot<0:return world.work.fail("full",LocalText.text("system.leisure_system.all_spots_are_occupied_wait_for_a_companion_to"))
		job["slot"]=slot;world.work.claims[site.id+".slot.%s"%slot]=id
	world.director.command_received(id,intent)
	world.work.serial+=1;job["id"]="job-%s"%world.work.serial;world.work.jobs[id]=job;world._routes.erase(id);world.revision+=1
	return {"ok":true,"status":"accepted","job_id":job.id}
func tick(id: String,job: Dictionary,delta: float) -> void:
	var actor: Dictionary=world.actors[id];var site: Dictionary=sites[job.target_id];var work:=art(site);var config: Dictionary=work.recreation
	var entry: Vector2=Vector2(job.get("steward_entry",world.point(site)+Vector2(config.entry[0],config.entry[1])))
	if job.intent=="build_facility":
		if actor.region_id!="home":world.interior._arrive(id,"home",entry);return
		var needed:=cost(site)-int(site.invested)
		if job.step=="supply":
			var amount: int=mini(needed,int(world.available_items(id).get("wood",0)))
			if amount>0 and world.pay_costs(id,{"wood":amount}).ok:
				site.invested+=amount;world.revision+=1
			if site.invested<cost(site):world.work._finish(id,LocalText.text("system.leisure_system.not_enough_wood_existing_construction_contributions_are_kept"),false);return
			job.step="deliver"
		if job.step=="deliver":
			if not world.interior._arrive(id,"home",entry):return
			job.step="finish"
		if job.step=="finish":
			actor.activity="building";job.time+=delta
			if job.time>=3:
				for other in world.actors.values():
					if other.region_id!="home":continue
					for box in config.obstacles:
						if Rect2(world.point(site)+Vector2(box[0],box[1]),Vector2(box[2],box[3])).has_point(world.point(other)):
							world.work._finish(id,LocalText.text("system.leisure_system.someone_is_in_the_building_area_clear_the_space"),false);return
				site.complete=true
				if id=="human":preload("res://scripts/brain_interactions.gd").host_event(world,"host_built","facility:"+str(site.id))
				world._grids.clear();world._terrain_solids.erase(str(site.region_id))
				world.rescue_obstructed()
				if world.their_island!=null:world.their_island.construction_completed(id,site.id)
				world.work._finish(id,LocalText.text("system.leisure_system.the_facility_is_complete_invite_everyone_to_play"))
		return
	if job.step=="entry":
		if not world.interior._arrive(id,"home",entry):return
		job.step="seat"
	var p: Array=config.slots[int(job.slot)];var destination: Vector2=world.point(site)+Vector2(p[0],p[1])
	if not world.interior._arrive(id,"home",destination):return
	actor.facing=site.get("facing","down");actor.activity={"swing":"swinging","sit":"seated","dance":"dancing"}[config.behavior]
	job.step="using";job.time+=delta
	if job.time>=float(config.seconds):world.work._finish(id,LocalText.text("system.leisure_system.a_little_time_playing_now_a_rest"))
func place(template_id: String,point: Vector2,authorized_owner:String="") -> Dictionary:
	var validation:=validate_place(template_id,point,authorized_owner)
	if not validation.ok:return validation
	var work:Dictionary=world.library.artworks[template_id]
	serial+=1;var id:="play.custom.%s"%serial
	sites[id]={"id":id,"name":work.get("name",template_id),"kind":"play_site","region_id":"home","position":[point.x,point.y],"template_id":template_id,"invested":0,"complete":false,"artwork":work.duplicate(true)};world.revision+=1
	return {"ok":true,"status":"completed","site_id":id}
func chess_space_clear(site: Dictionary,config: Dictionary) -> bool:
	var area:=Rect2(world.point(site)-Vector2(config.width,config.depth)/2,Vector2(config.width,config.depth))
	for y in range(int(floor(area.position.y)),int(ceil(area.end.y))):
		for x in range(int(floor(area.position.x)),int(ceil(area.end.x))):
			if not world.walkable("home",Vector2(x+.5,y+.5)):return false
	for farm in world.farms.farms.values():
		if area.intersects(world.farms.bounds(farm).grow(1)):return false
	for other in sites.values():
		if other.id==site.id:continue
		var artwork:=art(other)
		if not artwork.is_empty() and area.grow(.5).intersects(Rect2(world.point(other)-Vector2(artwork.recreation.width,artwork.recreation.depth)/2,Vector2(artwork.recreation.width,artwork.recreation.depth))):return false
	for object in world.objects.values():
		if object.get("kind")=="construction_site" and area.intersects(Rect2(world.point(object)-world.site_size(object)/2,world.site_size(object))):return false
	return true
func saved() -> Dictionary:return {"serial":serial,"sites":sites}
func restore(data: Dictionary) -> void:
	serial=int(data.serial)
	var new_corner: Dictionary=sites["play.gomoku"].duplicate(true)
	var added:Dictionary={}
	for id in sites:
		if id.begins_with("play.moon."):added[id]=sites[id]
	sites=data.sites.duplicate(true)
	for id in added:
		if not sites.has(id):sites[id]=added[id]
	if not sites.has("play.gomoku"):sites["play.gomoku"]=new_corner
func valid_saved(data: Variant) -> bool:
	if not data is Dictionary or not Rules.integer(data.get("serial"),0,100000) or not data.get("sites") is Dictionary or data.sites.size()>64:return false
	var validator=load("res://scripts/character_library.gd").new()
	for id in data.sites:
		var site: Variant=data.sites[id]
		if not id is String or not id.begins_with("play."):return false
		if not site is Dictionary or site.get("id")!=id or site.get("region_id")!="home" or not Rules.pair(site.get("position")) or not site.get("complete") is bool or not Rules.integer(site.get("invested"),0,1000) or not site.get("template_id") is String or not site.get("name") is String:return false
		if site.get("kind")!="play_site" or not world.terrain_surface("home",world.point(site)):return false
		if id.begins_with("play.custom.") and (not id.trim_prefix("play.custom.").is_valid_int() or int(id.trim_prefix("play.custom."))<1 or int(id.trim_prefix("play.custom."))>int(data.serial)):return false
		if not site.get("artwork") is Dictionary:return false
		if site.artwork.is_empty():
			if site.invested!=0 or site.complete or not sites.has(id) or site.template_id!=sites[id].template_id or world.point(site).distance_to(world.point(sites[id]))>.001:return false
		else:
			if not validator.valid(site.artwork) or not Rules.valid(site.artwork.get("recreation")) or site.invested>cost(site):return false
			var initial:bool=preload("res://scripts/world_opening.gd").allowed_preset(world,site.get("preset_origin")) and preload("res://scripts/world_opening.gd").config().facility_anchors.has(id) and site.invested==0
			if site.has("host_completed") and (not site.host_completed is bool or site.host_completed!=true or not site.complete):return false
			if site.complete and site.invested!=cost(site) and not initial and not site.get("host_completed",false):return false
	return true

func validate_place(template_id:String,point:Vector2,authorized_owner:String="")->Dictionary:
	if not authorized_owner.is_empty() and (not world.director.model_controlled(authorized_owner) or not world.their_island.within(authorized_owner,point,template_id)):return world._error("outside_own_territory")
	if authorized_owner.is_empty() and world.resort!=null and world.resort.contains(point):return world._error("vacation_only")
	if sites.size()>=64:return world._error("facility_limit")
	if not point.is_finite() or point.x<0 or point.y<0 or point.x>world.catalog.regions.home.size[0] or point.y>world.catalog.regions.home.size[1]:return world._error("invalid_position")
	if world.library==null or not world.library.artworks.has(template_id):return world._error("unknown_template")
	var work: Dictionary=world.library.artworks[template_id]
	if not Rules.valid(work.get("recreation")):return world._error("invalid_facility")
	var config: Dictionary=work.recreation;var area:=Rect2(point-Vector2(config.width,config.depth)/2,Vector2(config.width,config.depth))
	for y in range(int(area.position.y),int(ceil(area.end.y))+1):
		for x in range(int(area.position.x),int(ceil(area.end.x))+1):
			if not world.walkable("home",Vector2(x+.5,y+.5)):return world._error("occupied")
	for farm in world.farms.farms.values():
		if area.intersects(world.farms.bounds(farm).grow(1)):return world._error("farm_land")
	for site in sites.values():
		var other:=art(site)
		if not other.is_empty() and area.grow(1).intersects(Rect2(world.point(site)-Vector2(other.recreation.width,other.recreation.depth)/2,Vector2(other.recreation.width,other.recreation.depth))):return world._error("occupied")
	for actor in world.actors.values():
		if actor.region_id=="home" and area.has_point(world.point(actor)):return world._error("occupied")
	return {"ok":true}
