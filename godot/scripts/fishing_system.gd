class_name FishingSystem
extends RefCounted
signal shared_catch(actor_id:String,fish_id:String,others:Array)
const LocalText=preload("res://scripts/localization.gd")
## Engine-owned fish instances. Rendering and cards never grant catches.
const ACTIONS := ["fish", "stock_fish", "release_fish"]
var _owner: WeakRef
var world: RefCounted:
	get: return _owner.get_ref()
var rules: Dictionary={}
var pens: Dictionary={}
var spots: Dictionary={} # Legacy source references only, never active fishing positions.
var seas: Dictionary={}
var aliases: Dictionary={}
var coast_points: Array=[]
var probe_cache: Dictionary={}
var life: RefCounted
var fish: Dictionary={}
var waters: Dictionary={}
var memories: Array=[]
var clock:=0.0
var rng:=RandomNumberGenerator.new()

func _init(source: RefCounted) -> void:
	_owner=weakref(source);rng.randomize()
	var data: Variant=world.locations.read("fishing")
	if data is Dictionary:
		for extra in data.get("extra_seas",[]):
			if world.catalog.regions.has(extra.get("region_id","")):
				var added:Dictionary=extra.duplicate(true);added.optional_legacy=true;data.seas.append(added)
	if not data is Dictionary or not valid_rules(data):world.error=LocalText.text("system.fishing_system.the_fishing_settings_are_invalid");return
	rules=data
	life=preload("res://scripts/fishing_life.gd").new(world)
	for pen in rules.pens:pens[pen.id]=pen.duplicate(true)
	for sea in rules.seas:
		seas[sea.id]=sea.duplicate(true);aliases[sea.legacy_id]=sea.id
		waters[sea.id]={"available":int(sea.stock_capacity),"next_at":float(rules.regrow_seconds)}
		for entry in sea.legacy_spots:
			var legacy: Dictionary=entry.duplicate(true);legacy["water_id"]=sea.id;legacy["pen_id"]=sea.legacy_id;spots[legacy.id]=legacy
	_build_coast_points()

func count(value: Variant, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(value) and value==floor(value) and value>=0 and value<=maximum
func valid_rules(data: Dictionary) -> bool:
	if data.get("version")!=2 or not data.get("pens") is Array or data.pens.is_empty() or data.pens.size()>64:return false
	for key in ["cast_seconds","reel_seconds","bite_seconds","cast_min","cast_max","job_timeout","regrow_seconds","shore_reach","shore_spacing"]:
		if not world.catalog._number(data.get(key)) or data[key]<=0 or data[key]>3600:return false
	if data.cast_min<3 or data.cast_max<data.cast_min or data.cast_max>16 or not world.catalog._pair(data.get("nibble_delay")) or data.nibble_delay[0]<3 or data.nibble_delay[1]<data.nibble_delay[0]:return false
	if not count(data.get("max_fish"),10000) or data.max_fish<64 or data.get("pending_limit")!=1:return false
	for key in ["species","colors","sizes","waits"]:
		if not data.get(key) is Array or data[key].is_empty() or data[key].size()>64:return false
		var total:=0;var seen: Dictionary={}
		for entry in data[key]:
			if not entry is Dictionary or not count(entry.get("weight"),100) or entry.weight<1:return false
			if key=="species" and entry.has("night_only") and not entry.night_only is bool:return false
			total+=int(entry.weight)
			if key!="waits":
				if not entry.get("id") is String or entry.id.is_empty() or entry.id.length()>64 or seen.has(entry.id) or not entry.get("name") is String:return false
				seen[entry.id]=true
			if key in ["sizes","waits"]:
				if not world.catalog._number(entry.get("min")) or not world.catalog._number(entry.get("max")) or entry.min<=0 or entry.max<entry.min or entry.max> (8 if key=="sizes" else 120):return false
				if key=="sizes" and entry.min<1:return false
			if key=="colors" and (not entry.get("tint") is String or not Color.html_is_valid(entry.tint)):return false
		if total!=100:return false
	var ids: Dictionary={};var occupied: Array[Rect2]=[]
	for pen in data.pens:
		if not pen is Dictionary or not pen.get("id") is String or pen.id.is_empty() or ids.has(pen.id) or not pen.get("name") is String or not world.catalog.regions.has(pen.get("region_id","")) or not world.catalog._rect(pen.get("rect")):return false
		if not count(pen.get("capacity"),128) or pen.capacity<1 :return false
		ids[pen.id]=true
		var rect: Rect2=world.catalog.rectangle(pen.rect)
		var origin: Array=world.catalog.regions[pen.region_id].origin
		if not world.catalog.rectangle(world.catalog.manifest.bounds).encloses(Rect2(rect.position+Vector2(origin[0],origin[1]),rect.size)):return false
		for other in occupied:
			if rect.intersects(other):return false
		occupied.append(rect)
		# Enclosures are water, never new walkable land or reset farms.
		for x in range(5):
			for y in range(5):
				if Geometry2D.is_point_in_polygon(rect.position+rect.size*Vector2(x/4.0,y/4.0),world.catalog.polygon(world.catalog.regions[pen.region_id])):return false
	if not data.get("seas") is Array or data.seas.is_empty() or data.seas.size()>64:return false
	var legacy_ids: Dictionary={}
	for sea in data.seas:
		if not sea is Dictionary or not sea.get("id") is String or sea.id.is_empty() or ids.has(sea.id) or not sea.get("name") is String or not world.catalog.regions.has(sea.get("region_id","")) or not world.catalog._pair(sea.get("anchor")) or not count(sea.get("stock_capacity"),256) or sea.stock_capacity<1:return false
		if not sea.get("legacy_id") is String or legacy_ids.has(sea.legacy_id) or not sea.get("legacy_spots") is Array:return false
		ids[sea.id]=true;legacy_ids[sea.legacy_id]=true
		for spot in sea.legacy_spots:
			if not spot is Dictionary or not spot.get("id") is String or ids.has(spot.id) or not world.catalog._pair(spot.get("position")) or not world.catalog._pair(spot.get("hook")):return false
			ids[spot.id]=true

	return true

func pending(actor_id: String) -> Array:
	return fish.values().filter(func(entry):return entry.owner_id==actor_id and entry.location=="pending")
func residents_fish(pen_id: String) -> Array:
	return fish.values().filter(func(entry):return entry.location==pen_id)
func _pick(entries: Array) -> Dictionary:
	var value:=rng.randi_range(1,100)
	for entry in entries:
		value-=int(entry.weight)
		if value<=0:return entry
	return entries[-1]
func fishing_island(region:String,at:Vector2)->String:
	if region=="dark":return "dark"
	if region=="moon":return "moon"
	if region=="homelands":return "south"
	if region=="home" and world.home_island!=null and world.catalog.rectangle(world.home_island.config.get("bounds",[20,162,125,90])).has_point(at):return "south"
	if region=="home" and world.locations.v3() and at.x<0:return "moon"
	return "main"
func fishing_season()->String:
	return ["summer","autumn","winter","spring"][int((world.days.day()-1)/28)%4]
func species_available(entry:Dictionary,region:String,at:Vector2)->bool:
	if entry.get("night_only",false) and world.days.phase().id!="night":return false
	if entry.has("island") and entry.island!=fishing_island(region,at):return false
	if entry.get("appearance","any")=="night" and world.days.phase().id!="night":return false
	if entry.get("appearance","any")=="summer" and fishing_season()!="summer":return false
	if entry.get("weather","any")!="any" and entry.weather!=world.weather.current().id:return false
	return true
func pick_species(region:String="home",at:Vector2=Vector2.ZERO)->Dictionary:
	var roll:=rng.randi_range(1,100)
	for entry in rules.species:
		roll-=int(entry.weight)
		if roll<=0:return entry if species_available(entry,region,at) else rules.species[0]
	return rules.species[0]
func valid_water_keys(data:Dictionary)->bool:
	if data.waters.size()>waters.size():return false
	var normalized:Array=[]
	for key in data.waters:
		if not known_water(key) or sea_id(key) in normalized:return false
		normalized.append(sea_id(key))
	for sea in rules.seas:
		if not sea.get("optional_legacy",false) and sea.id not in normalized:return false
	return true
func describe(entry: Dictionary) -> Dictionary:
	var result:=entry.duplicate(true)
	for pair in [["species","species_id"],["colors","color_id"],["sizes","size_id"]]:
		for option in rules[pair[0]]:
			if option.id==entry[pair[1]]:result[pair[0]+"_name"]=option.name
	return result
func known_water(id: String) -> bool:return seas.has(id) or aliases.has(id)
func sea_id(id: String) -> String:return str(aliases.get(id,id))
func _sea_for(region_id: String, point: Vector2) -> String:
	var nearest:="";var distance:=INF
	for sea in seas.values():
		if sea.region_id!=region_id:continue
		var d:=point.distance_squared_to(Vector2(sea.anchor[0],sea.anchor[1]))
		if d<distance:nearest=sea.id;distance=d
	return nearest
func _ocean(region_id: String, point: Vector2) -> bool:
	if world.catalog.on_land(world.catalog.regions[region_id],point):return false
	for pen in pens.values():
		if pen.region_id==region_id and world.catalog.rectangle(pen.rect).grow(.5).has_point(point):return false
	var origin: Array=world.catalog.regions[region_id].origin
	return world.catalog.rectangle(world.catalog.manifest.bounds).has_point(point+Vector2(origin[0],origin[1]))
func probe_position(region_id: String, point: Vector2) -> Dictionary:
	if not world.catalog.regions.has(region_id) or _sea_for(region_id,point).is_empty() or not world.walkable(region_id,point):return {}
	var cache_key:=JSON.stringify([region_id,point.x,point.y])
	if probe_cache.has(cache_key):return probe_cache[cache_key].duplicate(true)
	if probe_cache.size()>=1024:probe_cache.clear()
	for step in range(1,int(float(rules.shore_reach)*2)+1):
		var distance: float=step*.5
		for i in range(24):
			var hook:=point+Vector2.from_angle(i*TAU/24)*distance
			if not _ocean(region_id,hook):continue
			# Reach detects the shore; the cast continues into open water.
			var direction: Vector2=(hook-point).normalized()
			var far:=Vector2.INF
			for extra in range(int(rules.cast_max*2),int(rules.cast_min*2)-1,-1):
				var clear:=true
				for sample in range(1,extra+1):
					if not _ocean(region_id,hook+direction*sample*.5):clear=false;break
				if clear:far=hook+direction*extra*.5;break
			if not far.is_finite():continue
			hook=far
			var water_id:=_sea_for(region_id,hook)
			var found: Dictionary={"region_id":region_id,"position":[point.x,point.y],"hook":[hook.x,hook.y],"water_id":water_id}
			probe_cache[cache_key]=found
			return found.duplicate(true)
	probe_cache[cache_key]={}
	return {}
func shore(actor_id: String) -> Dictionary:
	var actor: Dictionary=world.actors[actor_id]
	return probe_position(actor.region_id,world.point(actor))
func _build_coast_points() -> void:
	for region_id in world.catalog.regions:
		if _sea_for(region_id,Vector2.ZERO).is_empty():continue
		var region: Dictionary=world.catalog.regions[region_id]
		var center:=Vector2(region.size[0],region.size[1])/2
		var land: PackedVector2Array=world.catalog.polygon(region)
		for i in range(0,land.size(),3):
			var point: Vector2=land[i]+(center-land[i]).normalized()*2.2
			var found:=probe_position(region_id,point)
			if not found.is_empty():coast_points.append(found)
		for extension in region.get("land_extensions",[]):
			var contour:PackedVector2Array=preload("res://scripts/home_layout.gd").points(extension)
			for i in range(0,contour.size(),3):
				for direction in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
					var found:Dictionary=probe_position(region_id,contour[i]+direction*2.2)
					if not found.is_empty():coast_points.append(found);break
# Session-only reservations from the host's single stewardship director.
var team_shores:Dictionary={}
func contiguous_shores(leader:String,ids:Array)->Dictionary:
	var region:String=world.actors[leader].region_id
	for anchor in nearby_shores(leader,128):
		var origin:=Vector2(anchor.position[0],anchor.position[1])
		var normal:Vector2=(Vector2(anchor.hook[0],anchor.hook[1])-origin).normalized()
		var tangent:=Vector2(-normal.y,normal.x)
		var selected:Dictionary={}
		for index in ids.size():
			var id:String=ids[index]
			var point:Vector2=origin+tangent*(index-(ids.size()-1)/2.0)*maxf(2.1,float(rules.shore_spacing))
			var candidate:Dictionary=probe_position(region,point)
			if candidate.is_empty() or candidate.water_id!=anchor.water_id or not world.walkable(region,point):break
			if world.work.jobs.values().any(func(job):return job.get("intent")=="fish" and job.get("region_id")==region and point.distance_to(Vector2(job.position[0],job.position[1]))<maxf(2.0,float(rules.shore_spacing))):break
			if world.point(world.actors[id]).distance_to(point)>.1 and world.find_route(id,point).is_empty():break
			selected[id]=candidate
		if selected.size()==ids.size() and int(waters[anchor.water_id].available)>=ids.size():return selected
	return {}
func nearby_shores(actor_id: String, limit:=12) -> Array:
	var point: Vector2=world.point(world.actors[actor_id])
	var options: Array=coast_points.filter(func(entry):return entry.region_id==world.actors[actor_id].region_id and world.walkable(entry.region_id,Vector2(entry.position[0],entry.position[1])))
	options.sort_custom(func(a,b):return point.distance_squared_to(Vector2(a.position[0],a.position[1]))<point.distance_squared_to(Vector2(b.position[0],b.position[1])))
	return options.slice(0,limit).duplicate(true)
func held(actor_id: String) -> Dictionary:
	var entries:=pending(actor_id)
	return entries[0] if not entries.is_empty() else {}
func snapshot(actor_id: String) -> Dictionary:
	var listed: Array=[];var ocean: Array=[]
	for pen in pens.values():
		var entry: Dictionary=pen.duplicate(true);entry["fish_count"]=residents_fish(pen.id).size();listed.append(entry)
	for sea in seas.values():
		var reserved: int=world.work.jobs.values().filter(func(job):return job.get("intent")=="fish" and job.get("water_id")==sea.id).size()
		ocean.append({"id":sea.id,"name":sea.name,"region_id":sea.region_id,"available":waters[sea.id].available,"reserved":reserved})
	var own: Array=[]
	for entry in fish.values():
		if entry.owner_id==actor_id:own.append(describe(entry))
	var job: Dictionary=world.work.jobs.get(actor_id,{})
	return {"pens":listed,"seas":ocean,"nearby_shore":shore(actor_id),"coast_targets":nearby_shores(actor_id),"own_fish":own,"pending":pending(actor_id).map(describe),"held_fish_id":str(held(actor_id).get("id","")),"active":{"job_id":job.id,"water_id":job.water_id,"phase":job.phase,"position":job.position,"hook":job.hook} if job.get("intent")=="fish" else {},"memories":memories.duplicate(true),"direct_stock":true,"barbecue_link":false}

func command(actor_id: String, args: Dictionary) -> Dictionary:
	var action: String=args.get("intent","")
	var allowed: Array=["intent","target_id"] if action=="fish" else ["intent","fish_id","pen_id"] if action=="stock_fish" else ["intent","fish_id"]
	for key in args:
		if key not in allowed:return world._error("invalid_command")
	for key in allowed:
		if key!="intent" and args.has(key) and (not args[key] is String or args[key].length()>128):return world._error("invalid_command")
	if action=="fish":return start(actor_id,str(args.get("target_id","")))
	var id:=str(args.get("fish_id",""));var entry: Dictionary=fish.get(id,{})
	if entry.is_empty() or entry.owner_id!=actor_id:return world._error("fish_not_owned")
	if entry.location=="cooking":return world.work.fail("fish_in_preparation",LocalText.text("system.fishing_system.this_fish_is_being_prepared_for_cooking_it"))
	if world.work.jobs.has(actor_id):return world.work.fail("busy",LocalText.text("system.fishing_system.put_away_your_fishing_rod_before_placing_the"))
	if action=="stock_fish":
		var pen_id:=str(args.get("pen_id",""))
		if world.standard!=null and not world.standard.ready(pen_id):return world.work.fail("unbuilt_fishery",LocalText.text("system.fishing_system.build_the_fish_pen_first_you_keep_the"))
		if not pens.has(pen_id):return world._error("unknown_fishery")
		if entry.location not in ["pending","storage"]:return world._error("fish_already_placed")
		if residents_fish(pen_id).size()>=int(pens[pen_id].capacity):return world.work.fail("fishery_full",LocalText.text("system.fishing_system.this_pen_is_full_your_fish_stays_with"))
		entry.location=pen_id;world.revision+=1;life.trigger(actor_id,"stock")
		return {"ok":true,"status":"completed","fish_id":id,"message":LocalText.text("system.fishing_system.the_fish_has_entered")+str(pens[pen_id].name)+LocalText.text("system.fishing_system.you_do_not_need_to_walk_there")}
	if action=="release_fish":
		var coast: Dictionary=shore(actor_id) if entry.location in ["pending","storage"] else {}
		if entry.location in ["pending","storage"] and coast.is_empty():return world.work.fail("release_needs_sea",LocalText.text("system.fishing_system.bring_the_fish_to_the_coast_to_release"))
		var at: Array=pens[entry.location].rect.slice(0,2) if pens.has(entry.location) else coast.hook.duplicate()
		if pens.has(entry.location):at=[float(at[0])+float(pens[entry.location].rect[2])/2,float(at[1])+float(pens[entry.location].rect[3])/2]
		world.work.visual_event("fish_release",{"id":id,"position":at,"region_id":seas[sea_id(entry.source_id)].region_id},actor_id)
		world.work.visual_events[-1]["fish"]=entry.duplicate(true)
		fish.erase(id);world.revision+=1;life.trigger(actor_id,"release")
		# Releases do not refund a second catch or replenish a different water.
		return {"ok":true,"status":"completed","message":LocalText.text("system.fishing_system.the_fish_swam_back_to_sea")}
	return world._error("unsupported_action")

func host_pending_action(fish_id:String,action:String,pen_id:String="")->Dictionary:
	# This narrow host-only entry is called by explicit UI controls. It never
	# grants the owner extra model commands or changes another fish instance.
	var entry:Dictionary=fish.get(fish_id,{})
	if entry.is_empty() or entry.get("location") not in ["pending","storage"] or (entry.get("location")=="storage" and entry.get("owner_id")!="human") or not world.actors.has(entry.get("owner_id","")):return world._error("fish_not_owned")
	if action not in ["stock_fish","release_fish"]:return world._error("unsupported_action")
	var args:Dictionary={"intent":action,"fish_id":fish_id}
	if action=="stock_fish":args["pen_id"]=pen_id
	return command(str(entry.owner_id),args)

func host_stock_nearest(fish_id:String)->Dictionary:
	var entry:Dictionary=fish.get(fish_id,{})
	if entry.is_empty() or entry.get("location") not in ["pending","storage"] or (entry.get("location")=="storage" and entry.get("owner_id")!="human") or not world.actors.has(entry.get("owner_id","")):return world._error("fish_not_owned")
	var actor:Dictionary=world.actors[entry.owner_id];var candidates:Array=[]
	for pen in pens.values():
		if pen.region_id!=actor.region_id or (world.standard!=null and not world.standard.ready(pen.id)) or residents_fish(pen.id).size()>=int(pen.capacity):continue
		candidates.append(pen)
	candidates.sort_custom(func(a,b):return world.catalog.rectangle(a.rect).get_center().distance_squared_to(world.point(actor))<world.catalog.rectangle(b.rect).get_center().distance_squared_to(world.point(actor)))
	if candidates.is_empty():return world.work.fail("fishery_full",LocalText.text("system.fishing_system.all_usable_pens_are_full_or_unbuilt_you"))
	return host_pending_action(fish_id,"stock_fish",str(candidates[0].id))

func start(actor_id: String, target_id: String="") -> Dictionary:
	var work: RefCounted=world.work;var actor: Dictionary=world.actors[actor_id]
	if not target_id.is_empty():return work.fail("sea_only",LocalText.text("system.fishing_system.go_to_a_natural_coast_and_choose_fish"))
	if work.jobs.has(actor_id) or world._routes.has(actor_id):return work.fail("busy",LocalText.text("system.fishing_system.finish_or_stop_your_current_action_before_fishing"))
	if world.loaded(actor_id):return work.fail("hands_full",LocalText.text("system.fishing_system.put_away_your_materials_before_taking_the_fishing"))
	if not pending(actor_id).is_empty():return work.fail("pending_fish",LocalText.text("system.fishing_system.place_the_fish_you_are_holding_in_a"))
	if fish.size()>=int(rules.max_fish):return work.fail("fish_limit",LocalText.text("system.fishing_system.place_or_release_your_current_fish_first"))
	var spot:=shore(actor_id)
	if spot.is_empty():return work.fail("not_near_sea",LocalText.text("system.fishing_system.go_to_the_coast_before_trying_to_fish"))
	for other_id in work.jobs:
		var other: Dictionary=work.jobs[other_id]
		if other.get("intent")=="fish" and other.get("region_id")==actor.region_id and world.point(actor).distance_to(Vector2(other.position[0],other.position[1]))<float(rules.shore_spacing):return work.fail("shore_occupied",LocalText.text("system.fishing_system.the_shore_is_crowded_step_aside_a_little"))
	var reserved: int=work.jobs.values().filter(func(job):return job.get("intent")=="fish" and job.get("water_id")==spot.water_id).size()
	if int(waters[spot.water_id].available)<=reserved:return work.fail("water_resting",LocalText.text("system.fishing_system.this_sea_is_quiet_for_now_come_back"))
	return _accept(actor_id,spot)
func _accept(actor_id: String,spot: Dictionary,approach:=false) -> Dictionary:
	var work: RefCounted=world.work
	work.serial+=1
	var wait:=_pick(rules.waits)
	var target: String="shore-"+JSON.stringify([world.actors[actor_id].region_id,spot.position]).sha256_text().substr(0,24)
	work.jobs[actor_id]={"id":"job-%s"%work.serial,"intent":"fish","target_id":target,"water_id":spot.water_id,"region_id":world.actors[actor_id].region_id,"position":spot.position,"hook":spot.hook,"phase":"fish_approach" if approach else "fish_cast","time":0.0,"wait_seconds":rng.randf_range(wait.min,wait.max),"nibble_at":life.rng.randf_range(rules.nibble_delay[0],rules.nibble_delay[1]),"nibbles":0,"elapsed":0.0,"caught":false}
	work.claims[target]=actor_id;world.revision+=1
	if not approach:life.trigger(actor_id,"cast")
	return {"ok":true,"status":"accepted","job_id":work.jobs[actor_id].id,"message":LocalText.text("system.fishing_system.cast_your_rod_and_wait_for_a_surprise")}

func invite_host(ids: Array) -> Dictionary:
	var anchor:=shore("human")
	if anchor.is_empty():return world.work.fail("not_near_sea",LocalText.text("system.fishing_system.go_to_the_coast_before_inviting_companions_to"))
	var accepted: Array=[];var skipped: Array=[]
	var normal:=Vector2(anchor.hook[0]-anchor.position[0],anchor.hook[1]-anchor.position[1]).normalized()
	var tangent:=Vector2(-normal.y,normal.x)
	for id in ids:
		if not id is String or id=="human" or id in accepted or not world.actors.has(id) or not world.residents.supports(world.actors[id],"move"):skipped.append(id);continue
		if world.hunger.rank(id)>=3:skipped.append(id);continue
		if world.actors[id].region_id!=anchor.region_id or world.projects.active(id) or world.farms.active(id) or world.activities.members.has(id) or world.shared_activity.holds(id) or world.loaded(id) or not pending(id).is_empty():skipped.append(id);continue
		var current: Dictionary=world.work.jobs.get(id,{})
		var routine:RefCounted=world.director.routines.get(id)
		if world.activities.following.has(id) and (routine==null or not routine.held) and current.is_empty():world.activities.release_follow(id)
		if routine==null or routine.held or world.activities.blocked(id):skipped.append(id);continue
		var owned_local:bool=routine.owns_job()
		if (not current.is_empty() and not owned_local) or (world._routes.has(id) and not routine.owns_route and not owned_local):skipped.append(id);continue
		var chosen: Dictionary={}
		for index in range(1,world.residents.capacity+1):
			var offset: float=ceilf(index/2.0)*(maxf(2.0,float(rules.shore_spacing))+.6)*(1 if index%2 else -1)
			var point: Vector2=world.point(world.actors.human)+tangent*offset
			var candidate:=probe_position(anchor.region_id,point)
			if candidate.is_empty():continue
			var occupied: bool=world.work.jobs.values().any(func(job):return job.get("intent")=="fish" and job.get("region_id")==anchor.region_id and point.distance_to(Vector2(job.position[0],job.position[1]))<maxf(2.0,float(rules.shore_spacing)))
			if occupied or point.distance_to(world.point(world.actors.human))<maxf(2.0,float(rules.shore_spacing)):continue
			var reserved: int=world.work.jobs.values().filter(func(job):return job.get("intent")=="fish" and job.get("water_id")==candidate.water_id).size()
			if waters[candidate.water_id].available<=reserved:continue
			if world.find_route(id,point).is_empty() and world.point(world.actors[id]).distance_to(point)>.05:continue
			chosen=candidate;break
		if chosen.is_empty():skipped.append(id);continue
		world.director.command_received(id,"fish")
		if not world.route_to(id,Vector2(chosen.position[0],chosen.position[1])):skipped.append(id);continue
		_accept(id,chosen,true);accepted.append(id);life.trigger(id,"invited")
	return {"ok":not accepted.is_empty(),"accepted":accepted,"skipped":skipped,"message":invitation_message(skipped)}

func invitation_message(skipped:Array,reasons:Dictionary={})->String:
	var lines:PackedStringArray=[]
	for id in skipped:
		if not world.actors.has(id):continue
		var why:String=str(reasons.get(id,""))
		if why.is_empty():
			if world.hunger.rank(id)>=3:why=LocalText.text("system.fishing_system.too_hungry")
			elif not pending(id).is_empty():why=LocalText.text("system.fishing_system.holding_a_fish")
			elif world.loaded(id):why=LocalText.text("system.fishing_system.hands_full")
			elif world.actors[id].region_id!=world.actors.human.region_id:why=LocalText.text("system.fishing_system.not_nearby")
			elif world.work.jobs.has(id) or world.projects.active(id) or world.farms.active(id):why=LocalText.text("system.fishing_system.busy")
			elif world.director.routines.get(id)!=null and world.director.routines[id].held:why=LocalText.text("system.fishing_system.waiting_for_your_reply")
			else:why=LocalText.text("system.fishing_system.no_free_shore_spot_found")
		lines.append(str(world.actors[id].name)+why+LocalText.text("system.fishing_system.did_not_come"))
	return "；".join(lines)

func tick_job(actor_id: String, job: Dictionary, delta: float) -> void:
	var actor: Dictionary=world.actors[actor_id];var spot: Dictionary=job
	world.work.face(actor,{"position":spot.hook})
	actor.activity=job.phase;job.time+=delta
	match str(job.phase):
		"fish_approach":
			job.phase="fish_cast";job.time=0.0;life.trigger(actor_id,"cast")
		"fish_cast":
			if job.time>=float(rules.cast_seconds):
				job.phase="fish_wait";job.time=0.0
				world.work.visual_event("fish_splash",{"id":job.target_id,"position":job.hook,"region_id":actor.region_id},actor_id)
		"fish_wait":
			if job.time>=float(job.nibble_at) and job.nibbles<2 and job.time<job.wait_seconds-3:
				job.nibbles+=1;job.nibble_at=job.time+17.0
				life.trigger(actor_id,"nibble")
				world.work.visual_event("fish_nibble",{"id":job.target_id,"position":job.hook,"region_id":actor.region_id},actor_id)
			if job.time>=float(job.wait_seconds):
				job.phase="fish_bite";job.time=0.0;life.trigger(actor_id,"bite")
				world.work.visual_event("fish_bite",{"id":job.target_id,"position":job.hook,"region_id":actor.region_id},actor_id)
		"fish_bite":
			if job.time>=float(rules.bite_seconds):job.phase="fish_reel";job.time=0.0
		"fish_reel":
			if job.time<float(rules.reel_seconds):return
			if int(waters[job.water_id].available)<=0 or fish.size()>=int(rules.max_fish):world.work._finish(actor_id,LocalText.text("system.fishing_system.the_sea_has_quieted_down_putting_the_rod"),false);return
			var species:=pick_species(actor.region_id,world.point(actor));var color:=_pick(rules.colors);var size:=_pick(rules.sizes)
			if species.id=="tuna":size=rules.sizes.filter(func(option):return option.id=="giant")[0]
			var id: String="fish-"+Crypto.new().generate_random_bytes(12).hex_encode()
			var entry: Dictionary={"id":id,"owner_id":actor_id,"source_id":job.water_id,"spot_id":job.target_id,"species_id":species.id,"color_id":color.id,"size_id":size.id,"scale":snappedf(rng.randf_range(size.min,size.max),.01),"location":"storage" if actor_id=="human" else "pending","caught_at":Time.get_unix_time_from_system(),"caught_day":world.days.day()}
			fish[id]=entry;waters[job.water_id].available-=1;job.caught=true
			if actor_id=="human":world.ingredients.note_obtained("fish")
			var discovery: bool=world.journal.record_catch(id)
			world.days.queue_catch(id)
			if actor_id=="human":
				var scene:String="host_rare_fish" if entry.color_id=="aurora" else "host_big_fish" if float(entry.scale)>=2.0 else "host_fish"
				preload("res://scripts/brain_interactions.gd").host_event(world,scene,"fish:"+id)
			var companions: Array=[]
			for other in world.actors.values():
				if other.id!=actor_id and other.region_id==actor.region_id and world.point(other).distance_to(world.point(actor))<8:companions.append(other.id)
			memories.append({"id":id,"actor_id":actor_id,"companions":companions,"species_id":species.id,"color_id":color.id,"scale":entry.scale,"water_id":job.water_id,"at":entry.caught_at})
			if memories.size()>32:memories.pop_front()
			world.memories.sync()
			var fishing_peers:Array=companions.filter(func(other):return other!="human" and world.work.jobs.get(other,{}).get("intent","")=="fish" and world.work.jobs[other].get("phase","") in ["fish_cast","fish_wait","fish_bite","fish_reel"] and not world._routes.has(other))
			if actor_id!="human" and not fishing_peers.is_empty():shared_catch.emit(actor_id,id,fishing_peers)
			world.work.visual_event("fish_caught",{"id":id,"position":actor.position,"region_id":actor.region_id},actor_id)
			world.work.visual_event("fish_caught_shadow",{"id":id,"position":job.hook,"region_id":actor.region_id},actor_id)
			world.work.visual_events[-1]["fish"]=entry.duplicate(true)
			life.trigger(actor_id,"giant" if entry.scale>=7 else "catch",discovery)
			world.work._finish(actor_id,LocalText.text("system.fishing_system.caught_a_s_times_life_size_s_choose")%[entry.scale,species.name]+(LocalText.text("system.fishing_system.a_new_page_in_the_discovery_book") if discovery else ""))

func advance(delta: float) -> void:
	clock+=delta
	if life!=null:life.advance(delta)
	for id in waters:
		var stock: Dictionary=waters[id]
		if clock>=float(stock.next_at):
			stock.available=mini(int(seas[id].stock_capacity),int(stock.available)+1+int((clock-float(stock.next_at))/float(rules.regrow_seconds)))
			stock.next_at=clock+float(rules.regrow_seconds)
	for actor_id in world.work.jobs.keys():
		var job: Dictionary=world.work.jobs[actor_id]
		if job.get("intent")!="fish":continue
		job.elapsed+=delta
		if job.elapsed>float(rules.job_timeout):world.work._finish(actor_id,LocalText.text("system.fishing_system.the_wait_at_this_shore_took_too_long"),false)
func saved() -> Dictionary:
	return {"version":2,"clock":clock,"saved_at":Time.get_unix_time_from_system(),"fish":fish.duplicate(true),"waters":waters.duplicate(true),"memories":memories.duplicate(true)}
func restore(data: Dictionary) -> void:
	if data.is_empty():return
	clock=float(data.clock);fish=data.fish.duplicate(true);memories=data.memories.duplicate(true)
	for id in waters:
		if seas[id].get("optional_legacy",false) and not data.waters.has(id):waters[id]={"available":0,"next_at":float(data.clock)+float(rules.regrow_seconds)}
	for id in data.waters:waters[sea_id(id)]=data.waters[id].duplicate(true)
	var offline: float=clampf(Time.get_unix_time_from_system()-float(data.saved_at),0,float(rules.regrow_seconds)*256)
	advance(offline)
func valid_saved(data: Variant, actors: Dictionary) -> bool:
	if not data is Dictionary or (data.get("version")!=1 and data.get("version")!=2) or not data.get("fish") is Dictionary or data.fish.size()>int(rules.max_fish) or not data.get("waters") is Dictionary or not valid_water_keys(data) or not data.get("memories") is Array or data.memories.size()>32:return false
	for key in ["clock","saved_at"]:
		if not world.catalog._number(data.get(key)) or data[key]<0 or data[key]>253402300799:return false
	var pending_counts: Dictionary={};var counts: Dictionary={}
	for id in data.fish:
		var entry: Variant=data.fish[id]
		if not entry is Dictionary or entry.size() not in [10,11] or entry.keys().any(func(key):return key not in ["id","owner_id","source_id","spot_id","species_id","color_id","size_id","scale","location","caught_at","caught_day"]) or entry.get("id")!=id or not id is String or not id.begins_with("fish-") or id.length()!=29 or not id.substr(5).is_valid_hex_number(false) or not actors.has(entry.get("owner_id","")) or not entry.get("source_id") is String or not known_water(entry.source_id) or not entry.get("spot_id") is String or not _valid_source(entry):return false
		if entry.has("caught_day") and (not count(entry.caught_day,1000000) or int(entry.caught_day)<1):return false
		if not entry.get("location") is String or (entry.location not in ["pending","storage","cooking"] and not pens.has(entry.location)):return false
		if entry.location=="storage" and entry.owner_id!="human":return false
		for pair in [["species","species_id"],["colors","color_id"],["sizes","size_id"]]:
			if not entry.get(pair[1]) is String or not rules[pair[0]].any(func(option):return option.id==entry[pair[1]]):return false
		if not world.catalog._number(entry.get("scale")) or entry.scale<1 or entry.scale>8 or not world.catalog._number(entry.get("caught_at")) or entry.caught_at<=0 or entry.caught_at>253402300799:return false
		for size in rules.sizes:
			if size.id==entry.size_id and (entry.scale<size.min or entry.scale>size.max):return false
		if entry.location=="pending":
			pending_counts[entry.owner_id]=int(pending_counts.get(entry.owner_id,0))+1
			if pending_counts[entry.owner_id]>1:return false
		elif entry.location not in ["cooking","storage"]:
			counts[entry.location]=int(counts.get(entry.location,0))+1
			if counts[entry.location]>int(pens[entry.location].capacity):return false
	for id in data.waters:
		var stock: Variant=data.waters[id]
		if not known_water(id) or (data.version==1 and not aliases.has(id)) or (data.version==2 and not seas.has(id)) or not stock is Dictionary or stock.size()!=2 or not count(stock.get("available"),int(seas[sea_id(id)].stock_capacity)) or not world.catalog._number(stock.get("next_at")) or stock.next_at<data.clock or stock.next_at>data.clock+float(rules.regrow_seconds)*2:return false
	var seen: Dictionary={}
	for memory in data.memories:
		if not memory is Dictionary or memory.size()!=8 or not memory.get("id") is String or seen.has(memory.id) or not actors.has(memory.get("actor_id","")) or not memory.get("water_id") is String or not known_water(memory.water_id) or not memory.get("companions") is Array or memory.companions.size()>actors.size():return false
		seen[memory.id]=true
		if not memory.companions.all(func(id):return actors.has(id) and id!=memory.actor_id) or memory.companions.size()!=_unique(memory.companions).size():return false
		if not rules.species.any(func(s):return s.id==memory.get("species_id")) or not rules.colors.any(func(c):return c.id==memory.get("color_id")) or not world.catalog._number(memory.get("scale")) or memory.scale<1 or memory.scale>8 or not world.catalog._number(memory.get("at")) or memory.at<=0:return false
	return true
func _unique(items: Array) -> Dictionary:
	var result: Dictionary={}
	for item in items:result[item]=true
	return result

func _valid_source(entry: Dictionary) -> bool:
	if aliases.has(entry.source_id):return spots.has(entry.spot_id) and spots[entry.spot_id].pen_id==entry.source_id
	return entry.spot_id.begins_with("shore-") and entry.spot_id.length()==30 and entry.spot_id.substr(6).is_valid_hex_number(false)

# Explicit host text may invite residents from inland; only their validated
# natural shore routes are issued. The host actor never moves implicitly.
func invite_from_host_text(ids:Array,use_host_anchor:bool=true)->Dictionary:
	if use_host_anchor and not shore("human").is_empty():return invite_host(ids)
	var accepted:Array=[];var skipped:Array=[]
	for id in ids:
		if id=="human" or not world.actors.has(id) or (use_host_anchor and world.actors[id].region_id!=world.actors.human.region_id) or world.hunger.rank(id)>=3 or world.loaded(id) or not pending(id).is_empty() or world.work.jobs.has(id) or world.farms.active(id) or world.projects.active(id) or world.activities.blocked(id):skipped.append(id);continue
		var chosen:Dictionary={}
		var assigned:Dictionary=team_shores.get(id,{})
		team_shores.erase(id)
		for candidate in ([assigned] if not assigned.is_empty() else nearby_shores(id,32)):
			var spot:Dictionary=probe_position(candidate.region_id,Vector2(candidate.position[0],candidate.position[1]))
			if spot.is_empty():continue
			var reserved:int=world.work.jobs.values().filter(func(job):return job.get("intent")=="fish" and job.get("water_id")==spot.water_id).size()
			if int(waters[spot.water_id].available)<=reserved:continue
			if world.work.jobs.values().any(func(job):return job.get("intent")=="fish" and job.get("region_id")==spot.region_id and Vector2(job.position[0],job.position[1]).distance_to(Vector2(spot.position[0],spot.position[1]))<maxf(2.0,float(rules.shore_spacing))):continue
			if world.find_route(id,Vector2(spot.position[0],spot.position[1])).is_empty():continue
			chosen=spot;break
		if chosen.is_empty():skipped.append(id);continue
		world.director.command_received(id,"fish")
		if not world.route_to(id,Vector2(chosen.position[0],chosen.position[1])):skipped.append(id);continue
		_accept(id,chosen,true);accepted.append(id);life.trigger(id,"invited")
	return {"ok":not accepted.is_empty(),"accepted":accepted,"skipped":skipped,"message":invitation_message(skipped)}
