class_name IslandWork
extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
const CarryRetention=preload("res://scripts/carry_retention.gd")

const CARRY_LIMIT := 20
const CHOP_SECONDS := 4.8
const BUILD_SECONDS := 3.0
const STAGE_WOOD := [12, 12, 16, 12, 12]
var stop_audit:Array=[]
var _owner: WeakRef
var world: RefCounted:
	get: return _owner.get_ref()
var jobs: Dictionary = {}
var claims: Dictionary = {}
var events: Array = []
var gift_rules: Dictionary={}
var serial := 0
var visual_events: Array = []
var visual_serial := 0

func _init(owner_world: RefCounted) -> void:
	_owner = weakref(owner_world)
	gift_rules=JSON.parse_string(FileAccess.get_file_as_string("res://content/gifts.json"))

func carry_space(actor_id: String) -> int:
	return maxi(0, CARRY_LIMIT - world.life.item_count(world.actors[actor_id].carry))

func start(actor_id: String, intent: String, target_id: String = "") -> Dictionary:
	if jobs.has(actor_id): return fail("busy", LocalText.text("system.work_system.finish_your_current_task_or_press_stop"))
	var actor: Dictionary = world.actors[actor_id]
	if intent == "store":
		if actor_id=="human":return world.deposit_all(actor_id)
		if actor.carry.is_empty():return world._error("empty_hands")
		world.deliveries.request(actor_id,true,true)
		return {"ok":true,"status":"accepted"}
	if intent == "take":
		if actor_id!="human":return world._error("host_only")
		return world.take_storage_host("wood",mini(carry_space(actor_id),world.storage.count("wood")))
	if not world.objects.has(target_id): return fail("unknown_object", LocalText.text("system.work_system.this_target_cannot_be_found"))
	var target: Dictionary = world.objects[target_id]
	if target.region_id != actor.region_id: return fail("different_region", LocalText.text("system.work_system.the_target_is_on_another_island"))
	if claims.has(target_id): return fail("claimed", LocalText.text("system.work_system.a_companion_is_already_working_on_this_target"))
	if intent == "chop":
		if target.kind != "tree": return fail("not_a_tree", LocalText.text("system.work_system.this_is_not_a_tree"))
		if target.status != "mature": return fail("tree_growing", LocalText.text("system.work_system.this_tree_is_regrowing_come_back_when_it"))
		if actor.has("furniture_id"):return fail("hands_full",LocalText.text("system.work_system.put_away_what_you_are_holding_first"))
		var hits:int=int(world.forest.settings.large_hits if int(target.wood_yield)>8 else world.forest.settings.normal_hits)
		var paid:int=int(floor((6-int(target.get("health",6)))*hits/6.0))
		var result := _begin(actor_id, {"intent": intent, "target_id": target_id, "phase": "chop", "time": paid*float(world.forest.settings.swing_seconds), "strikes":paid}, target)
		if result.ok: claims[target_id] = actor_id
		return result
	if intent == "build":
		if target.kind != "construction_site": return fail("not_a_site", LocalText.text("system.work_system.this_is_not_a_home_site"))
		if not target.has("blueprint") and world.library != null and int(target.get("stage_index", 0)) == 0 and target.delivered.is_empty():
			var selection: Dictionary = world.select_blueprint(target_id, "cottage")
			if not selection.ok: return selection
		var stage := int(target.get("stage_index", 0))
		if stage >= STAGE_WOOD.size(): return fail("finished", LocalText.text("system.work_system.the_house_is_already_complete"))
		var needed: int = stage_costs(target)[stage] - int(target.get("delivered", {}).get("wood", 0))
		var available:int=int(world.available_items(actor_id).get("wood",0))
		if needed>0 and available<=0:return fail("missing_materials",LocalText.text("system.work_system.bring_some_wood_first_this_stage_has_s")%[int(target.delivered.get("wood",0)),stage_costs(target)[stage]])
		if not world.can_approach(actor_id,target):return world._error("unreachable")
		var amount:int=mini(maxi(0,needed),available)
		if amount>0:
			if not world.pay_costs(actor_id,{"wood":amount}).ok:return world._error("insufficient_materials")
			target.delivered["wood"]=int(target.delivered.get("wood",0))+amount
			world.projects.contribution(actor_id,target,amount)
		var result:=_begin(actor_id,{"intent":intent,"target_id":target_id,"phase":"build_delivery","time":0.0},target)
		if result.ok:claims[target_id]=actor_id
		return result
	return fail("unsupported_action", LocalText.text("system.work_system.this_action_is_not_supported_yet"))

func _begin(actor_id: String, job: Dictionary, target: Dictionary) -> Dictionary:
	if not world.approach(actor_id, target): return fail("unreachable", LocalText.text("system.work_system.the_target_cannot_be_reached"))
	if not job.has("id"):
		serial += 1
		job["id"] = "job-%s" % serial
	jobs[actor_id] = job
	world.revision += 1
	return {"ok": true, "status": "accepted", "job_id": job.id, "message": LocalText.text("system.work_system.work_has_started")}

func take_food_host(_storage_id:String,item_id:String,quantity:int)->Dictionary:
	return world.take_storage_host(item_id,quantity)

func stop(actor_id: String, report: bool = true) -> void:
	if not world.activities.squad_leader.is_empty() and jobs.has(actor_id):
		var origin:Array=[]
		for frame in get_stack().slice(1,5):origin.append(str(frame.source).get_file()+":"+str(frame.function)+":"+str(frame.line))
		stop_audit.append({"actor":actor_id,"job_id":jobs[actor_id].get("id",""),"origin":origin,"clock":world.forest.clock})
		if stop_audit.size()>512:stop_audit.pop_front()
	if world.homestead!=null:world.homestead.stopped(actor_id,jobs.get(actor_id,{}))
	if world.days!=null:world.days.job_stopped(actor_id,jobs.get(actor_id,{}))
	if world.gomoku!=null and jobs.get(actor_id,{}).get("intent")=="play_gomoku":world.gomoku.pause_actor(actor_id)
	if report and world.projects.active(actor_id): world.projects.pause(actor_id, LocalText.text("system.work_system.paused_materials_and_progress_are_kept"))
	if report and jobs.get(actor_id, {}).get("intent") == "gather_wood": record_event(actor_id, jobs[actor_id], "cancelled", LocalText.text("system.work_system.wood_gathering_stopped_carried_and_dropped_wood_are"))
	if world.deliveries!=null:world.deliveries.cancel(actor_id)
	jobs.erase(actor_id)
	world._routes.erase(actor_id)
	for key in claims.keys():
		if claims[key] == actor_id: claims.erase(key)
	world.actors[actor_id].activity = "idle"
	world.revision += 1

func record_event(actor_id: String, job: Dictionary, status: String, message: String) -> void:
	var event := {"intent":job.get("intent",""),"id": "%s-%s" % [world.revision, events.size()], "actor_id": actor_id, "job_id": job.get("id", ""), "status": status, "message": message}
	if job.get("source")=="promise":event["source"]="promise"
	if job.get("intent") == "gather_wood": event["progress"] = world.gathering.progress(job)
	if job.has("project_id"): event["project_id"] = job.project_id
	if job.has("shared_activity_id"): event["shared_activity_id"] = job.shared_activity_id
	if status=="completed" and actor_id=="human" and job.get("intent","") in ["chop","gather_wood"]:
		for who in world.director.brains:
			if jobs.has(who) and jobs[who].get("intent","") in ["chop","gather_wood"] and world.actors[who].region_id==world.actors.human.region_id and world.point(world.actors[who]).distance_to(world.point(world.actors.human))<=12:
				world.director.brains[who].interactions.enqueue("helped","work_receipt:"+str(event.id))
	if status=="completed" and world.director.brains.has(actor_id) and job.get("intent","") in ["chop","gather_wood","forage","build","manage_farm"]:
		world.director.brains[actor_id].interactions.enqueue("finished","completed_job:"+str(job.get("id","")))
	events.append(event)
	if events.size() > 32: events.pop_front()

func _finish(actor_id: String, message: String, ok: bool = true, status: String = "") -> void:
	var job: Dictionary = jobs.get(actor_id, {}).duplicate(true)
	var outcome := status if not status.is_empty() else "completed" if ok else "blocked"
	if world.director!=null and world.director.brains.has(actor_id):world.director.brains[actor_id].job_outcome(job,outcome)
	if world.days!=null:world.days.job_finished(actor_id,job,outcome)
	if not job.has("project_id") and job.get("source")!="local_rules": record_event(actor_id, job, outcome, message)
	stop(actor_id, false)
	world.projects.child_finished(actor_id, job, outcome, message)
	if world.homestead!=null:world.homestead.child_finished(actor_id,job,outcome,message)
	if not world.actors[actor_id].carry.is_empty() and world.actors[actor_id].carry.keys().all(func(k):return world.pocket_item(str(k))):world.stow_loose(actor_id)

func _waiting_materials(actor_id: String, site: Dictionary) -> void:
	var delivered := int(site.delivered.get("wood", 0))
	var cost: int = stage_costs(site)[int(site.get("stage_index", 0))]
	_finish(actor_id, LocalText.text("system.work_system.this_stage_has_s_s_wood_with_s") % [delivered, cost, maxi(0, cost - delivered)], false, "waiting_materials")

func visual_event(kind: String, target: Dictionary, actor_id: String) -> void:
	visual_serial += 1
	visual_events.append({"serial": visual_serial, "kind": kind, "target_id": target.id, "position": target.position.duplicate(), "actor_id": actor_id, "region_id": target.get("region_id", world.actors[actor_id].region_id)})
	if visual_events.size() > 64: visual_events.pop_front()

func face(actor: Dictionary, target: Dictionary) -> void:
	var offset: Vector2 = world.point(target) - world.point(actor)
	actor.facing = "right" if offset.x > 0 else "left"
	if absf(offset.y) >= absf(offset.x): actor.facing = "down" if offset.y > 0 else "up"

func handle_bundle(actor: Dictionary, job: Dictionary, target: Dictionary, delta: float, activity: String) -> bool:
	actor.activity = activity
	face(actor, target)
	job["handling_time"] = float(job.get("handling_time", 0)) + delta*(world.cooperation.factor(str(actor.id),job,target,activity) if world.cooperation!=null else 1.0)
	if float(job.handling_time) < .45: return false
	job.handling_time = 0.0
	return true

func advance(delta: float) -> void:
	if not jobs.is_empty(): world.revision += 1
	for actor_id in jobs.keys():
		# A failed shared step may pause and remove other participants' jobs.
		if not jobs.has(actor_id): continue
		if world._routes.has(actor_id): continue
		var job: Dictionary = jobs[actor_id]
		if actor_id=="human" and world.dark!=null and world.dark.hands_busy(delta):continue
		var actor: Dictionary = world.actors[actor_id]
		if job.get("intent")=="resort":world.resort.tick(actor_id,job,delta);continue
		if job.get("phase")=="storage_delivery" or job.get("intent")=="jieqi":continue
		if job.get("intent")=="homestead":world.homestead.tick(actor_id,job,delta);continue
		if job.get("intent")=="play_gomoku":world.gomoku.tick(actor_id,job,delta);continue
		if job.get("intent")=="gesture":
			preload("res://scripts/game_actions.gd").tick(world,actor_id,job,delta);continue
		if job.get("intent")=="fish":
			world.fishing.tick_job(actor_id,job,delta);continue
		if job.phase == "activity_work":
			world.activities.tick(actor_id,job,delta);continue
		if job.phase == "leisure_work":
			world.leisure.tick(actor_id,job,delta);continue
		if job.phase == "farm_work":
			world.farms.tick_job(actor_id, job, delta)
			continue
		if job.phase == "house_work":
			world.interior.tick_job(actor_id, job, delta)
			continue
		if str(job.phase).begins_with("fire_"):
			world.life_for_job(job).fireside.tick_job(actor_id,job,delta);continue
		if str(job.phase).begins_with("life_"):
			world.life_for_job(job).tick_job(actor_id, job, delta)
			continue
		match job.phase:
			"gather_prepare": world.gathering.tick(actor_id, job)
			"deliver_wood":
				var site: Dictionary = world.objects[job.target_id]
				if not handle_bundle(actor, job, site, delta, "putting_down"): continue
				var amount := _deliver_material(actor_id, site)
				_finish(actor_id, LocalText.text("system.work_system.delivered_s_wood_anything_left_in_your_hands") % amount if amount > 0 else LocalText.text("system.work_system.this_stage_has_enough_wood_you_keep_what"))
			"chop":
				actor.activity = "chopping"
				job.time += delta
				var target: Dictionary = world.objects[job.target_id]
				face(actor, target)
				# Hit at .48s of each .8s swing; recovery continues until 4.8s.
				var swing:float=float(world.forest.settings.swing_seconds)
				var hits:int=int(world.forest.settings.large_hits if int(target.wood_yield)>8 else world.forest.settings.normal_hits)
				var health := maxi(0, 6 - int(floor(float(job.time)/ (swing*hits)*6)))
				var strikes:int=mini(hits,int(floor(float(job.time)/swing)))
				for hit in range(int(job.get("strikes",0)),strikes):visual_event("hit",target,actor_id)
				job["strikes"]=strikes
				if health != int(target.get("health", 6)):
					target["health"] = health
					world.revision += 1
				if job.time < swing*hits: continue
				target.status = "stump"
				world.forest.cut(target)
				if job.intent == "gather_wood": job.trees_cut += 1
				world._grids.erase(target.region_id)
				var drop_id: String = "drop." + target.id
				world.drops[drop_id] = {"id": drop_id, "region_id": target.region_id, "position": target.position.duplicate(), "wood": int(world.forest.settings.large_wood if int(target.wood_yield)>8 else world.forest.settings.normal_wood)}
				claims.erase(target.id)
				claims[drop_id] = actor_id
				job["drop_id"] = drop_id
				job.phase = "fall_wait"
				actor.activity = "idle"
				job.time = 0.0
				visual_event("fall", target, actor_id)
				world.revision += 1
			"fall_wait":
				actor.activity = "idle"
				job.time += delta
				if float(job.time) >= .65:
					job.phase = "pickup"
					if not world.approach(actor_id, world.drops[job.drop_id]): _finish(actor_id, LocalText.text("system.work_system.the_wood_remains_on_the_ground_out_of"), false)
			"pickup":
				var drop: Dictionary = world.drops.get(job.drop_id, {})
				if drop.is_empty():
					if job.intent == "gather_wood": world.gathering.after_delivery(actor_id, job)
					else: _finish(actor_id, LocalText.text("system.work_system.the_wood_is_already_stored"))
					continue
				if not handle_bundle(actor, job, drop, delta, "picking_up"): continue
				visual_event("pickup", drop, actor_id)
				var amount := int(drop.wood) if actor_id=="human" else mini(carry_space(actor_id), int(drop.wood))
				if amount<=0:
					if actor_id=="human":world.deposit_all(actor_id)
					else:job.phase="storage_delivery";world.deliveries.request(actor_id)
					continue
				if actor_id=="human":
					world.storage.add({"wood":amount})
					if job.intent=="gather_wood":job.wood_stored+=amount
					record_event(actor_id,job,"progress","+%s %s"%[amount,LocalText.text("journey.wood")])
				else:actor.carry["wood"] = int(actor.carry.get("wood", 0)) + amount
				drop.wood -= amount
				if int(drop.wood) == 0:
					world.drops.erase(job.drop_id)
					claims.erase(job.drop_id)
				if actor_id=="human":
					if world.drops.has(job.drop_id):job.phase="pickup"
					elif job.intent=="gather_wood":world.gathering.after_delivery(actor_id,job)
					else:_finish(actor_id,LocalText.text("storage.collected"))
				else:
					job.phase="storage_delivery";world.deliveries.request(actor_id)
				world.revision+=1
			"build_delivery":
				var site:Dictionary=world.objects[job.target_id]
				if int(site.delivered.get("wood",0))<int(stage_costs(site)[int(site.stage_index)]):_waiting_materials(actor_id,site);continue
				job.phase="building";job.time=0.0
			"building":
				actor.activity = "building"
				job.time += delta
				if job.time < BUILD_SECONDS: continue
				var site: Dictionary = world.objects[job.target_id]
				var footprint := Rect2(world.point(site) - world.site_size(site) / 2, world.site_size(site))
				var occupied := false
				if int(site.get("stage_index", 0)) == 0:
					for resident in world.actors.values():
						if resident.region_id == site.region_id and footprint.has_point(world.point(resident)): occupied = true
				if occupied: _finish(actor_id, LocalText.text("system.work_system.someone_is_inside_the_foundation_the_materials_are"), false); continue
				site["invested"] = int(site.get("invested", 0)) + int(site.delivered.get("wood", 0))
				site.delivered.clear()
				site["stage_index"] = int(site.get("stage_index", 0)) + 1
				world.rescue_obstructed()
				world.projects.contribution(actor_id, site, 0, 1)
				world._grids.erase(site.region_id)
				site["status"] = "complete" if int(site.stage_index) == 5 else "building"
				_finish(actor_id, LocalText.text("system.work_system.the_house_is_complete") if site.status == "complete" else LocalText.text("system.work_system.this_stage_is_complete"))

func collect(actor_id: String, drop_id: String) -> Dictionary:
	if jobs.has(actor_id): return fail("busy", LocalText.text("system.work_system.finish_your_current_task_first"))
	if not world.drops.has(drop_id): return fail("missing_drop", LocalText.text("system.work_system.there_is_no_wood_here"))
	if claims.has(drop_id): return fail("claimed", LocalText.text("system.work_system.a_companion_is_hauling_this_wood"))
	if world.loaded(actor_id): return fail("hands_full", LocalText.text("system.work_system.put_away_what_you_are_holding_first"))
	var drop: Dictionary = world.drops[drop_id]
	if drop.region_id != world.actors[actor_id].region_id: return fail("different_region", LocalText.text("system.work_system.the_wood_is_on_another_island"))
	var result := _begin(actor_id, {"intent": "collect", "target_id": drop_id, "drop_id": drop_id, "phase": "pickup"}, drop)
	if result.ok: claims[drop_id] = actor_id
	return result

func fail(code: String, message: String) -> Dictionary:
	return {"ok": false, "error": code, "message": message}

func stage_costs(site: Dictionary) -> Array:
	return site.get("blueprint", {}).get("stages", STAGE_WOOD)

func deliver(actor_id: String, site_id: String) -> Dictionary:
	if jobs.has(actor_id): return fail("busy", LocalText.text("system.work_system.finish_your_current_task_first"))
	var actor: Dictionary = world.actors[actor_id]
	var site: Dictionary = world.objects.get(site_id, {})
	if site.is_empty() or site.kind != "construction_site": return fail("unknown_site", LocalText.text("system.work_system.choose_a_home_site"))
	if actor.region_id != site.region_id: return fail("different_region", LocalText.text("system.work_system.go_to_the_island_where_the_house_is"))
	if int(world.available_items(actor_id).get("wood",0))<=0:return world._error("insufficient_materials")
	if int(site.get("stage_index", 0)) >= 5: return fail("finished", LocalText.text("system.work_system.the_house_is_complete_you_keep_the_wood"))
	if not site.has("blueprint") and world.library != null and int(site.get("stage_index", 0)) == 0 and site.delivered.is_empty():
		var selection: Dictionary = world.select_blueprint(site_id, "cottage")
		if not selection.ok: return selection
	return _begin(actor_id, {"intent": "deliver_wood", "phase": "deliver_wood", "target_id": site_id}, site)

func _deliver_material(actor_id: String, site: Dictionary) -> int:
	var stage := int(site.get("stage_index", 0))
	if stage >= 5: return 0
	var actor: Dictionary = world.actors[actor_id]
	var cost: int = stage_costs(site)[stage]
	var amount:int=mini(int(world.available_items(actor_id).get("wood",0)),maxi(0,cost-int(site.delivered.get("wood",0))))
	if amount>0 and world.pay_costs(actor_id,{"wood":amount}).ok:
		site.delivered["wood"]=int(site.delivered.get("wood",0))+amount
		world.projects.contribution(actor_id,site,amount)
		world.revision+=1

	return amount

func give(actor_id: String,args: Dictionary) -> Dictionary:
	if args.keys().any(func(key):return key not in ["intent","receiver_id","item_id","quantity"]):return world._error("invalid_gift")
	var receiver: String=str(args.get("receiver_id",""));var item: String=str(args.get("item_id",""));var quantity: Variant=args.get("quantity")
	if not world.actors.has(receiver) or receiver==actor_id or item.is_empty() or not (quantity is int or quantity is float) or not is_finite(quantity) or quantity!=floor(quantity) or quantity<1:return world._error("invalid_gift")
	var donor: Dictionary=world.actors[actor_id];var target: Dictionary=world.actors[receiver]
	if donor.region_id!=target.region_id:return world._error("different_region")
	if world.point(donor).distance_to(world.point(target))>float(gift_rules.max_distance):return fail("too_far",LocalText.text("system.work_system.come_within_2_tiles_first_giving_never_moves"))
	for id in [actor_id,receiver]:
		if world.actors[id].has("furniture_id"):return fail("hands_reserved",LocalText.text("system.work_system.put_down_the_furniture_first_so_its_materials"))
		if gift_rules.reject_busy_inventory and (jobs.has(id) or world.farms.active(id) or world.projects.active(id) or world.homestead.active(id) or (world.deliveries!=null and world.deliveries.active(id))):return fail("inventory_busy",LocalText.text("system.work_system.you_are_handling_materials_wait_until_you_are"))
		if gift_rules.reject_reserved_receipt and id==actor_id and not world.homestead.plans.get(id,{}).get("receipt",{}).is_empty():return fail("inventory_reserved",LocalText.text("system.work_system.these_materials_belong_to_a_delivery_in_progress"))
	if int(donor.carry.get(item,0))<quantity:return world._error("insufficient_owned_items")
	if carry_space(receiver)<quantity:return world._error("receiver_full")
	var facts: Dictionary={"giver_id":actor_id,"receiver_id":receiver,"item_id":item,"quantity":int(quantity)}
	if not world.memories.engine_facts_valid("gift",facts,[actor_id,receiver],world.actors):return world._error("invalid_gift_item")
	# No awaits, job transitions or callbacks between debit and credit.
	CarryRetention.consume(donor,item,int(quantity))
	donor.carry[item]=int(donor.carry[item])-int(quantity)
	if donor.carry[item]==0:donor.carry.erase(item)
	target.carry[item]=int(target.carry.get(item,0))+int(quantity)
	CarryRetention.mark(target,item,int(quantity))
	if actor_id=="human" and world.director.brains.has(receiver):world.director.brains[receiver].interactions.enqueue("helped","gift:"+item+":"+str(quantity))
	world.memories.record_event("gift","gift-"+Crypto.new().generate_random_bytes(12).hex_encode(),[actor_id,receiver],facts)
	world.revision+=1;return {"ok":true,"status":"completed","quantity":int(quantity),"message":LocalText.text("system.work_system.the_whole_gift_has_been_delivered")}
