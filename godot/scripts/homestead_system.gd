class_name HomesteadSystem
extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
## One persistent plan per resident. Work owns routes/handling and exact jobs.
const ACTIONS := ["homestead_read","homestead_start","homestead_resume","homestead_build","homestead_cancel"]
const LIVE := ["active","paused","blocked"]
var _owner: WeakRef
var world: RefCounted:
	get:return _owner.get_ref()
var config: Dictionary={}
var site: Dictionary={}
var plans: Dictionary={}
var owned_jobs: Dictionary={}
func _init(source: RefCounted) -> void:
	_owner=weakref(source)
	var data: Variant=world.locations.read("homestead")
	if not valid_config(data):world.error=LocalText.text("system.homestead_system.the_homestead_project_settings_are_invalid");return
	config=data.duplicate(true);config["unlock_recipe"]=world.recipes.recipe_catalog[config.unlock_recipe_id].duplicate(true);reset()
func quantity(value: Variant,maximum: int=1000) -> bool:
	return (value is int or value is float) and is_finite(value) and value==floor(value) and value>=0 and value<=maximum
func valid_config(data: Variant) -> bool:
	if not data is Dictionary or data.get("version")!=1 or not data.get("site") is Dictionary or not data.get("requirements") is Dictionary:return false
	var point: Dictionary=data.site
	if not point.get("id") is String or point.id.is_empty() or point.id.length()>128 or not point.get("name") is String or point.get("region_id")!="home" or not world.catalog._rect(point.get("rect")) or not world.catalog._pair(point.get("entry")):return false
	if not Rect2(Vector2.ZERO,Vector2(world.catalog.regions.home.size[0],world.catalog.regions.home.size[1])).encloses(world.catalog.rectangle(point.rect)) or world.catalog.rectangle(point.rect).has_point(Vector2(point.entry[0],point.entry[1])):return false
	if data.requirements.size()!=2 or not quantity(data.requirements.get("wood"),200) or data.requirements.wood<1 or not quantity(data.requirements.get("crops"),100) or data.requirements.crops<1:return false
	if not world.catalog._number(data.get("build_seconds")) or data.build_seconds<1 or data.build_seconds>60 or not quantity(data.get("job_timeout"),900) or data.job_timeout<30:return false
	return data.get("stages") is Array and data.stages.size()==5 and data.stages.all(func(value):return value is String and value.length()<40) and data.get("unlock_recipe_id") is String and world.recipes.recipe_catalog.has(data.unlock_recipe_id) and world.recipes.recipe_locks.get(data.unlock_recipe_id)==point.id and not world.recipes.recipe_catalog[data.unlock_recipe_id].fish and not world.recipes.recipes.has(data.unlock_recipe_id)
func reset() -> void:
	site={"state":"unstarted","requirements":config.requirements.duplicate(true),"delivered":{},"contributions":{},"progress":0.0,"completion":{}}
	plans.clear();owned_jobs.clear()
func area() -> Rect2:return world.catalog.rectangle(config.site.rect)
func entry() -> Vector2:return Vector2(config.site.entry[0],config.site.entry[1])
func target() -> Dictionary:
	return {"id":config.site.id,"kind":"homestead_site","name":config.site.name,"region_id":config.site.region_id,"position":[area().get_center().x,area().get_center().y]}
func active(id: String) -> bool:return plans.get(id,{}).get("status")=="active"
func completed() -> bool:return site.get("state")=="completed"
func ensure_host_completion() -> void:
	if not completed() or not site.has("host_completion_source"):return
	var completion: Dictionary=site.get("completion",{})
	if not completion.has("id"):completion["id"]="homestead-completion-"+Crypto.new().generate_random_bytes(12).hex_encode()
	if not completion.has("actor_id"):completion["actor_id"]="human"
	if not completion.has("at"):completion["at"]=0
	if not completion.has("recipe_id"):completion["recipe_id"]=config.unlock_recipe.id
	site["completion"]=completion
func blocks(region: String,p: Vector2) -> bool:return region==config.site.region_id and site.state!="unstarted" and area().has_point(p)
func crops() -> Array:return world.farms.crops.keys()
func crop_count(items: Dictionary) -> int:
	var total:=0
	for item in items:
		if item in crops():total+=int(items[item])
	return total
func funded() -> bool:return int(site.delivered.get("wood",0))==int(site.requirements.wood) and crop_count(site.delivered)==int(site.requirements.crops)
func missing(kind: String) -> int:return int(site.requirements[kind])- (int(site.delivered.get("wood",0)) if kind=="wood" else crop_count(site.delivered))
func occupancy() -> String:
	var rect:=area()
	for y in range(int(floor(rect.position.y)),int(ceil(rect.end.y))):
		for x in range(int(floor(rect.position.x)),int(ceil(rect.end.x))):
			if not world._terrain_walkable(config.site.region_id,Vector2(x+.5,y+.5)):return LocalText.text("system.homestead_system.the_project_ground_or_access_route_is_occupied")
	for farm in world.farms.farms.values():
		if farm.get("source_kind","")=="homestead" and farm.get("source_site_id")==config.site.id:continue
		if rect.intersects(world.farms.bounds(farm).grow(.5)):return LocalText.text("system.homestead_system.the_project_overlaps_a_farm")
	for object in world.objects.values():
		if object.region_id!=config.site.region_id:continue
		if object.kind=="construction_site" and rect.intersects(Rect2(world.point(object)-world.site_size(object)/2,world.site_size(object)).grow(1)):return LocalText.text("system.homestead_system.an_existing_home_site_or_house_occupies_the_project")
		if object.kind in ["tree","chest"] and rect.grow(1).has_point(world.point(object)):return LocalText.text("system.homestead_system.a_tree_or_chest_occupies_the_project_site")
	for other in world.leisure.sites.values():
		var art: Dictionary=world.leisure.art(other)
		var size: Vector2=Vector2(12,10) if art.is_empty() else Vector2(art.recreation.width,art.recreation.depth)
		if rect.intersects(Rect2(world.point(other)-size/2,size)):return LocalText.text("system.homestead_system.an_existing_facility_occupies_the_project_site")
	for actor in world.actors.values():
		if actor.region_id==config.site.region_id and rect.grow(.25).has_point(world.point(actor)):return LocalText.text("system.homestead_system.someone_is_at_the_project_site_clear_the_space")
	for id in world._routes:
		if world.actors[id].region_id!=config.site.region_id:continue
		var previous: Vector2=world.point(world.actors[id])
		for next in world._routes[id]:
			if rect.has_point(previous) or rect.has_point(next):return LocalText.text("system.homestead_system.an_accepted_route_crosses_the_site_wait_until_the")
			var corners: Array=[rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]
			for index in range(4):
				if Geometry2D.segment_intersects_segment(previous,next,corners[index],corners[(index+1)%4])!=null:return LocalText.text("system.homestead_system.an_accepted_route_crosses_the_site_wait_until_the")
			previous=next
	for drop in world.drops.values():
		if drop.region_id==config.site.region_id and rect.grow(.5).has_point(world.point(drop)):return LocalText.text("system.homestead_system.unhauled_wood_remains_at_the_project_site")
	return ""
func summary(id: String) -> Dictionary:
	return {"site":config.site.duplicate(true),"state":site.state,"requirements":site.requirements.duplicate(),"delivered":site.delivered.duplicate(),"contributions":site.contributions.duplicate(true),"completion":site.completion.duplicate(true),"progress":site.progress,"build_seconds":config.build_seconds,"unlock_recipe":{"id":config.unlock_recipe.id,"name":config.unlock_recipe.name,"unlocked":completed()},"plan":plans.get(id,{}).duplicate(true),"blocked_reason":occupancy() if not completed() else ""}
func command(id: String,args: Dictionary) -> Dictionary:
	var intent: String=str(args.get("intent",""))
	if intent=="homestead_read":return {"ok":true,"homestead":summary(id)} if args.size()==1 else world._error("invalid_homestead_command")
	var allowed:= ["intent","site_id","wood_limit","crop_limit"] if intent=="homestead_start" else ["intent","plan_id","wood_limit","crop_limit"] if intent=="homestead_resume" else ["intent","plan_id"]
	if args.keys().any(func(key):return key not in allowed):return world._error("invalid_homestead_command")
	if intent=="homestead_start" and args.get("site_id")!=config.site.id:return world._error("unknown_site")
	if intent not in ACTIONS:return world._error("unsupported_action")
	if completed():return world.work.fail("finished",LocalText.text("system.homestead_system.the_flowerbed_is_complete_and_its_recipe_unlocked_no"))
	var plan: Dictionary=plans.get(id,{})
	if intent!="homestead_start" and (plan.is_empty() or args.get("plan_id")!=plan.id):return world._error("unknown_project")
	if intent=="homestead_cancel":
		if plan.status not in LIVE:return world._error("project_finished")
		pause(id,LocalText.text("system.homestead_system.project_canceled_delivered_materials_stay_at_the_site_and"),"cancelled");return {"ok":true,"status":"completed"}
	if intent=="homestead_start" and plan.get("status") in LIVE:return world.work.fail("project_exists",LocalText.text("system.homestead_system.you_already_have_a_homestead_plan_continue_or_cancel"))
	if intent!="homestead_start" and plan.status not in ["paused","blocked"]:return world.work.fail("not_paused",LocalText.text("system.homestead_system.pause_your_current_assignment_before_continuing_this_project"))
	if world.work.jobs.has(id) or world._routes.has(id) or world.projects.active(id) or world.farms.active(id) or world.shared_activity.holds(id):return world.work.fail("busy",LocalText.text("system.homestead_system.finish_your_current_task_before_arranging_a_homestead_project"))
	if world.actors[id].has("furniture_id") or not world.fishing.held(id).is_empty():return world.work.fail("hands_full",LocalText.text("system.homestead_system.put_away_what_you_are_holding_before_starting_a"))
	var reason:=occupancy()
	if not reason.is_empty():return world.work.fail("occupied",reason+LocalText.text("system.homestead_system.existing_contributions_stay_intact"))
	if world.actors[id].region_id==config.site.region_id and world.find_route(id,entry()).is_empty():return world.work.fail("unreachable",LocalText.text("system.homestead_system.the_project_site_cannot_be_reached_existing_contributions_are"))
	var wood: Variant=args.get("wood_limit",site.requirements.wood);var crop: Variant=args.get("crop_limit",site.requirements.crops)
	if not quantity(wood,int(site.requirements.wood)) or not quantity(crop,int(site.requirements.crops)):return world._error("invalid_material_limit")
	if intent=="homestead_build":
		if not funded():return world.work.fail("missing_materials",LocalText.text("system.homestead_system.wood_and_crops_are_not_fully_delivered_construction_will"))
		if world.work.claims.has(config.site.id):return world.work.fail("claimed",LocalText.text("system.homestead_system.a_resident_is_already_building"))
	else:
		if int(wood)+int(crop)==0:return world._error("empty_delivery")

	if intent!="homestead_build" and plan.get("receipt",{}).is_empty() and not funded():
		var wanted: Array=[]
		if int(wood)>0 and missing("wood")>0:wanted.append("wood")
		if int(crop)>0 and missing("crops")>0:wanted.append("crops")
		if not wanted.is_empty() and wanted.all(func(kind):return sources(id,kind).is_empty()):return world.work.fail("missing_materials",LocalText.text("system.homestead_system.the_chest_is_empty_claimed_or_has_no_harvest"))
	if intent=="homestead_start":
		plan={"id":"homestead-"+Crypto.new().generate_random_bytes(12).hex_encode(),"actor_id":id,"status":"paused","reason":"","budget":{"wood":0,"crops":0},"receipt":{}}
		plans[id]=plan
	if not (intent=="homestead_resume" and plan.get("resume_budget",false)):
		plan.budget={"wood":int(wood),"crops":int(crop)}
	plan.erase("resume_budget")
	plan.status="active";plan.reason=""
	world.director.command_received(id,intent);world.work.serial+=1
	var job_id:="job-%s"%world.work.serial
	world.work.jobs[id]={"id":job_id,"intent":"homestead","phase":"homestead_work","homestead_plan_id":plan.id,"step":"build" if intent=="homestead_build" else "deliver" if not plan.receipt.is_empty() else "supply","elapsed":0.0,"target_id":config.site.id}
	owned_jobs[id]=job_id
	if intent=="homestead_build":world.work.claims[config.site.id]=id;site.state="building"
	elif site.state=="unstarted":site.state="funding";world._grids.erase(config.site.region_id)
	world.revision+=1
	return {"ok":true,"status":"accepted","plan_id":plan.id,"job_id":job_id,"message":LocalText.text("system.homestead_system.starting_with_actual_materials_construction_still_needs_explicit_confirmation")}
func owns(id: String,job: Dictionary) -> bool:return plans.has(id) and job.get("homestead_plan_id")==plans[id].id and job.get("id")==owned_jobs.get(id,"")
func stopped(id: String,job: Dictionary) -> void:
	if not owns(id,job):return
	if active(id):plans[id]["resume_budget"]=true;plans[id].status="paused";plans[id].reason=LocalText.text("system.homestead_system.project_paused_delivered_and_in_transit_materials_are_kept")
	owned_jobs.erase(id)
	if site.state=="building":site.state="ready"
func child_finished(id: String,job: Dictionary,outcome: String,message: String) -> void:
	if job.get("intent")!="homestead" or not plans.has(id) or job.get("homestead_plan_id")!=plans[id].id:return
	if outcome!="completed":plans[id].status="blocked";plans[id].reason=message
func pause(id: String,reason: String=LocalText.text("system.homestead_system.the_project_is_paused_materials_are_kept"),status: String="paused") -> void:
	if not plans.has(id) or plans[id].status not in LIVE:return
	if active(id):plans[id]["resume_budget"]=true
	plans[id].status=status;plans[id].reason=reason
	if owns(id,world.work.jobs.get(id,{})):world.work.stop(id,false)
	world.revision+=1
func unrelated_command(id: String) -> void:
	if plans.has(id) and not active(id):plans[id].receipt={}
func _end(id: String,message: String,blocked: bool=false) -> void:
	plans[id].status="blocked" if blocked else "paused";plans[id].reason=message
	if funded() and not completed():site.state="ready"
	world.work._finish(id,message,not blocked)
func sources(id: String,kind: String) -> Array:
	var stock:Dictionary=world.available_items(id)
	if (int(stock.get("wood",0)) if kind=="wood" else crop_count(stock))<=0:return []
	return [{"id":"storage","items":stock}]

func advance(delta: float) -> void:
	for id in owned_jobs.keys():
		var job: Dictionary=world.work.jobs.get(id,{})
		if not owns(id,job):continue
		job.elapsed+=delta
		if job.elapsed>float(config.job_timeout):_end(id,LocalText.text("system.homestead_system.project_waiting_timed_out_contributions_and_carried_materials_are"),true)
func tick(id: String,job: Dictionary,delta: float) -> void:
	if not owns(id,job):world.work.stop(id,false);return
	var plan: Dictionary=plans[id];var actor: Dictionary=world.actors[id]
	if job.elapsed>float(config.job_timeout):_end(id,LocalText.text("system.homestead_system.project_waiting_timed_out_contributions_and_carried_materials_are"),true);return
	var reason:=occupancy()
	if not reason.is_empty():_end(id,reason+LocalText.text("system.homestead_system.existing_contributions_are_kept"),true);return
	if job.step=="build":
		if not world.interior._arrive(id,config.site.region_id,entry()):return
		if not funded():_end(id,LocalText.text("system.homestead_system.materials_are_incomplete_construction_will_not_start"),true);return
		actor.activity="building";world.work.face(actor,target());site.progress=minf(float(config.build_seconds),float(site.progress)+delta)
		job["time"]=site.progress
		if site.progress>=float(config.build_seconds):_complete(id)
		return
	if job.step in ["supply","load","deliver"]:
		if funded():_end(id,LocalText.text("system.homestead_system.materials_are_ready_start_construction_explicitly"));return
		# Legacy in-flight receipts stay with their original owner, never refunded twice.
		var receipt:Dictionary=plan.get("receipt",{})
		if not receipt.is_empty():
			var item:String=receipt.item_id
			var kind:String="wood" if item=="wood" else "crops"
			var amount:int=mini(int(receipt.amount),mini(missing(kind),int(actor.carry.get(item,0))))
			if amount>0:
				preload("res://scripts/carry_retention.gd").consume(actor,item,amount)
				actor.carry[item]-=amount
				if actor.carry[item]==0:actor.carry.erase(item)
				_credit(id,item,amount);plan.budget[kind]=maxi(0,int(plan.budget[kind])-amount)
			plan.receipt={}
		var stock:Dictionary=world.available_items(id)
		for item in stock:
			var kind:String="wood" if item=="wood" else "crops"
			if item!="wood" and item not in crops():continue
			var amount:int=mini(int(stock[item]),mini(missing(kind),int(plan.budget[kind])))
			if amount>0 and world.pay_costs(id,{item:amount}).ok:
				_credit(id,item,amount);plan.budget[kind]-=amount
		if not world.interior._arrive(id,config.site.region_id,entry()):return
		_end(id,LocalText.text("system.homestead_system.materials_are_ready_start_construction_explicitly") if funded() else LocalText.text("system.homestead_system.this_delivery_batch_is_complete_contributions_are_kept_you"))

func _credit(id:String,item:String,amount:int)->void:
	site.delivered[item]=int(site.delivered.get(item,0))+amount
	if not site.contributions.has(id):site.contributions[id]={}
	site.contributions[id][item]=int(site.contributions[id].get(item,0))+amount
	world.revision+=1

func _complete(id: String) -> void:
	if completed():return
	site.state="completed";site.completion={"id":"homestead-completion-"+Crypto.new().generate_random_bytes(12).hex_encode(),"actor_id":id,"at":Time.get_unix_time_from_system(),"recipe_id":config.unlock_recipe.id}
	world.rescue_obstructed()
	world.recipes.recipes[config.unlock_recipe.id]=config.unlock_recipe.duplicate(true)
	for who in plans:
		if plans[who].status=="cancelled":continue
		plans[who].status="completed";plans[who].reason=LocalText.text("system.homestead_system.flowerbed_complete_unlocked")+config.unlock_recipe.name+"。"
		if who!=id and owns(who,world.work.jobs.get(who,{})):world.work.stop(who,false)
	world._grids.erase(config.site.region_id);world.revision+=1
	world.work._finish(id,LocalText.text("system.homestead_system.s_is_complete_unlocked_s")%[config.site.name,config.unlock_recipe.name])
func saved() -> Dictionary:return {"version":1,"site":site.duplicate(true),"plans":plans.duplicate(true)}
func restore(data: Dictionary) -> void:
	reset();world.recipes.recipes.erase(config.unlock_recipe.id)
	if not data.is_empty():site=data.site.duplicate(true);plans=data.plans.duplicate(true)
	ensure_host_completion()
	for plan in plans.values():
		if plan.status=="active":plan["resume_budget"]=true;plan.status="paused";plan.reason=LocalText.text("system.homestead_system.after_returning_to_the_game_continue_explicitly_materials_and")
	if site.state=="building":site.state="ready"
	if completed():world.recipes.recipes[config.unlock_recipe.id]=config.unlock_recipe.duplicate(true)
	world._grids.erase(config.site.region_id)
func valid_items(items: Variant) -> bool:
	return items is Dictionary and items.keys().all(func(key):return key=="wood" or key in crops()) and items.values().all(func(n):return quantity(n,200))
func valid_saved(data: Variant,saved_world: Dictionary) -> bool:
	if not data is Dictionary or data.size()!=3 or data.get("version")!=1 or not data.get("site") is Dictionary or not data.get("plans") is Dictionary or data.plans.size()>world.residents.capacity:return false
	var s: Dictionary=data.site
	if s.has("host_completion_source"):
		if s.get("state")!="completed" or s.host_completion_source not in ["unstarted","funding","ready"]:return false
		var event: Variant=s.get("completion")
		if not event is Dictionary:return false
		if not event.is_empty():
			if event.keys().any(func(key):return key not in ["id","actor_id","at","recipe_id"]):return false
			if event.has("id") and (not event.id is String or not event.id.begins_with("homestead-completion-") or event.id.length()!=45 or not event.id.substr(21).is_valid_hex_number(false)):return false
			if event.has("actor_id") and event.actor_id!="human":return false
			if event.has("at") and event.at!=0:return false
			if event.has("recipe_id") and event.recipe_id!=config.unlock_recipe.id:return false
		var original:Dictionary=data.duplicate(true)
		original.site.state=s.host_completion_source;original.site.erase("host_completion_source");original.site.completion={}
		return valid_saved(original,saved_world)
	if s.has("preset_origin"):
		return preload("res://scripts/world_opening.gd").allowed_preset(world,s.preset_origin) and s.size()==7 and s.get("state")=="completed" and s.get("requirements")==config.requirements and s.get("delivered",{"invalid":1}).is_empty() and s.get("contributions",{"invalid":1}).is_empty() and s.get("progress")==0 and s.get("completion",{"invalid":1}).is_empty() and data.plans.is_empty()
	if s.size()!=6 or s.get("state") not in ["unstarted","funding","ready","building","completed"] or not s.get("requirements") is Dictionary or s.requirements.size()!=2 or not quantity(s.requirements.get("wood"),200) or s.requirements.wood<1 or not quantity(s.requirements.get("crops"),100) or s.requirements.crops<1:return false
	if not valid_items(s.get("delivered")) or int(s.delivered.get("wood",0))>int(s.requirements.wood) or crop_count(s.delivered)>int(s.requirements.crops) or not s.get("contributions") is Dictionary or s.contributions.size()>world.residents.capacity:return false
	var totals: Dictionary={}
	for id in s.contributions:
		if not saved_world.actors.has(id) or not valid_items(s.contributions[id]):return false
		for item in s.contributions[id]:totals[item]=int(totals.get(item,0))+int(s.contributions[id][item])
	if world.memories._canonical(totals)!=world.memories._canonical(s.delivered):return false
	if not world.catalog._number(s.get("progress")) or s.progress<0 or s.progress>float(config.build_seconds) or not s.get("completion") is Dictionary:return false
	var full: bool=int(s.delivered.get("wood",0))==int(s.requirements.wood) and crop_count(s.delivered)==int(s.requirements.crops)
	if s.state in ["ready","building","completed"] and not full:return false
	if s.state=="unstarted" and (not s.delivered.is_empty() or not s.contributions.is_empty() or s.progress!=0 or not data.plans.is_empty()):return false
	if s.state=="completed":
		var event: Dictionary=s.completion
		if s.progress!=float(config.build_seconds) or event.size()!=4 or not event.get("id") is String or not event.id.begins_with("homestead-completion-") or event.id.length()!=45 or not event.id.substr(21).is_valid_hex_number(false) or not saved_world.actors.has(event.get("actor_id","")) or not world.catalog._number(event.get("at")) or event.at<=0 or event.at>253402300799 or event.get("recipe_id")!=config.unlock_recipe.id:return false
	elif not s.completion.is_empty() or s.progress>=float(config.build_seconds):return false
	var ids: Dictionary={}
	for id in data.plans:
		var plan: Variant=data.plans[id]
		if not saved_world.actors.has(id) or not plan is Dictionary or (plan.size()!=6 and plan.size()!=7) or plan.get("actor_id")!=id or not plan.get("id") is String or not plan.id.begins_with("homestead-") or plan.id.length()!=34 or not plan.id.substr(10).is_valid_hex_number(false) or ids.has(plan.id) or plan.get("status") not in LIVE+["cancelled","completed"] or not plan.get("reason") is String or plan.reason.length()>300:return false
		if plan.keys().any(func(k):return k not in ["id","actor_id","status","reason","budget","receipt","resume_budget"]):return false
		if plan.has("resume_budget") and not plan.resume_budget is bool:return false
		ids[plan.id]=true
		if not plan.get("budget") is Dictionary or plan.budget.size()!=2 or not quantity(plan.budget.get("wood"),200) or not quantity(plan.budget.get("crops"),100) or not plan.get("receipt") is Dictionary:return false
		if (plan.status=="completed")!= (s.state=="completed" and plan.status!="cancelled"):return false
		if plan.status=="active" and saved_world.get("projects",{}).get("plans",{}).get(id,{}).get("status")=="active":return false
		var r: Dictionary=plan.receipt
		if not r.is_empty():
			if r.size()!=3 or not r.get("item_id") is String or not r.get("source_id") is String or r.source_id.length()>128 or r.item_id not in ["wood"]+crops() or not quantity(r.get("amount"),world.work.CARRY_LIMIT) or r.amount<1 or int(saved_world.actors[id].carry.get(r.item_id,0))<int(r.amount):return false
			if r.source_id=="storage":continue
			if r.item_id=="wood":
				var source: Dictionary=saved_world.objects.get(r.get("source_id",""),saved_world.get("interior",{}).get("furniture",{}).get(r.get("source_id",""),{}))
				if source.get("kind")!="chest":return false
			else:
				var source: Dictionary=world.farms.containers.get(r.get("source_id",""),{})
				if source.get("role")!="harvest":return false
	if s.state=="completed" and not data.plans.has(s.completion.actor_id):return false
	return true
