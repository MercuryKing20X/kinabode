class_name WoodGathering
extends RefCounted
const LocalText=preload("res://scripts/localization.gd")

# One engine job owns repeated harvest/haul steps. No model callbacks or timers.
var _owner: WeakRef
var world: RefCounted:
	get: return _owner.get_ref()

func _init(source: RefCounted) -> void: _owner = weakref(source)

func start(actor_id: String, args: Dictionary) -> Dictionary:
	for key in args:
		if key not in ["intent", "target_id", "zone_id", "tree_count"]: return world._error("invalid_command")
	if args.has("tree_count") and (not world._integer(args.tree_count) or args.tree_count < 1 or args.tree_count > 100): return world._error("invalid_tree_count")
	for key in ["target_id", "zone_id"]:
		if args.has(key) and (not args[key] is String or args[key].is_empty()): return world._error("invalid_command")
	if world.work.jobs.has(actor_id): return world.work.fail("busy", LocalText.text("system.wood_gathering.finish_your_current_task_or_press_stop"))
	var actor: Dictionary = world.actors[actor_id]
	if not str(actor.get("furniture_id", "")).is_empty(): return world.work.fail("hands_full", LocalText.text("system.wood_gathering.put_down_furniture_or_mushrooms_first"))
	var region_id: String = actor.region_id
	var room_id := ""
	var rooms: Dictionary = world.interior.rooms()
	if rooms.has(region_id):
		room_id = region_id
		region_id = world.objects[rooms[room_id].site_id].region_id
	var zone_id := str(args.get("zone_id", ""))
	if not zone_id.is_empty() and not world.catalog.regions[region_id].zones.any(func(zone): return zone.id == zone_id): return world._error("unknown_zone")
	var first_id := str(args.get("target_id", ""))
	if not first_id.is_empty():
		var first: Dictionary = world.objects.get(first_id, {})
		if first.is_empty() or first.kind != "tree" or first.status != "mature": return world.work.fail("not_a_tree", LocalText.text("system.wood_gathering.choose_a_tree_that_has_not_been_felled"))
		if first.region_id != region_id: return world._error("different_region")
		if not zone_id.is_empty() and first.zone_id != zone_id: return world._error("target_zone_mismatch")
		if world.work.claims.has(first_id): return world.work.fail("claimed", LocalText.text("system.wood_gathering.a_companion_is_working_on_this_tree_choose_another"))
		zone_id = first.zone_id
	world.director.command_received(actor_id, "gather_wood")
	world._routes.erase(actor_id)
	world.work.serial += 1
	var job := {"id": "job-%s" % world.work.serial, "intent": "gather_wood", "phase": "gather_prepare", "target_id": "", "region_id": region_id, "zone_id": zone_id, "first_id": first_id, "room_id": room_id, "tree_count": int(args.get("tree_count", 0)), "trees_cut": 0, "trees_completed": 0, "wood_stored": 0}
	world.work.jobs[actor_id] = job; world.revision += 1
	return {"ok": true, "status": "accepted", "job_id": job.id, "zone_id": zone_id, "tree_count": job.tree_count, "message": LocalText.text("system.wood_gathering.starting_continuous_chopping_and_hauling_stop_at_any_time") if job.tree_count == 0 else LocalText.text("system.wood_gathering.starting_work_on_s_trees_and_hauling_the_wood") % job.tree_count}

func progress(job: Dictionary) -> Dictionary:
	return {"zone_id": job.zone_id, "tree_count": job.tree_count, "trees_cut": job.trees_cut, "trees_completed": job.trees_completed, "wood_stored": job.wood_stored}

func stop_reason(actor_id: String, job: Dictionary, reason: String, completed: bool = false) -> void:
	world.work._finish(actor_id, LocalText.text("system.wood_gathering.fully_hauled_s_trees_and_stored_s_wood_s") % [job.trees_completed, job.wood_stored, reason], completed)

func tick(actor_id: String, job: Dictionary) -> void:
	var actor: Dictionary = world.actors[actor_id]
	if actor.region_id != job.region_id:
		world.interior._arrive(actor_id, job.region_id, world.interior.outside(job.room_id))
		return
	if int(actor.carry.get("wood", 0)) > 0:
		if not deposit(actor_id, job): stop_reason(actor_id, job, LocalText.text("system.wood_gathering.there_is_no_reachable_chest_with_space_the_wood"))
		return
	if job.tree_count > 0 and job.trees_completed >= job.tree_count:
		stop_reason(actor_id, job, LocalText.text("system.wood_gathering.the_requested_gathering_amount_is_complete"), true); return
	# Reclaim interrupted hauling before creating more drops.
	var drops: Array = world.drops.values().filter(func(drop): return drop.region_id == job.region_id and (job.zone_id.is_empty() or drop_zone(drop) == job.zone_id) and not world.work.claims.has(drop.id))
	_sort_near(actor, drops)
	if not drops.is_empty():
		for drop in drops:
			if not world.approach(actor_id, drop): continue
			if job.zone_id.is_empty(): job.zone_id = drop_zone(drop)
			job.target_id = drop.id; job["drop_id"] = drop.id; job.phase = "pickup"; world.work.claims[drop.id] = actor_id
			return
	var trees: Array = world.objects.values().filter(func(tree): return tree.kind == "tree" and tree.region_id == job.region_id and tree.status == "mature" and (job.zone_id.is_empty() or tree.zone_id == job.zone_id))
	_sort_near(actor, trees)
	if not job.first_id.is_empty():
		var first: Dictionary = world.objects[job.first_id]
		if first in trees: trees.erase(first); trees.push_front(first)
		job.first_id = ""
	var available := false
	for tree in trees:
		if world.work.claims.has(tree.id): continue
		available = true
		if not world.approach(actor_id, tree): continue
		if job.zone_id.is_empty(): job.zone_id = tree.zone_id
		job.target_id = tree.id; job["active_tree_id"] = tree.id; job.phase = "chop"
		job["time"] = (6 - int(tree.get("health", 6))) * (world.work.CHOP_SECONDS / 6)
		job.erase("handling_time"); world.work.claims[tree.id] = actor_id
		return
	if trees.is_empty() and not drops.is_empty():
		stop_reason(actor_id, job, LocalText.text("system.wood_gathering.dropped_wood_cannot_be_reached_for_now_it_stays"))
	elif trees.is_empty():
		stop_reason(actor_id, job, LocalText.text("system.wood_gathering.there_are_no_trees_ready_to_cut_in_this"), job.tree_count == 0)
	elif not available: stop_reason(actor_id, job, LocalText.text("system.wood_gathering.companions_are_working_on_all_remaining_trees_stopping_here"))
	else: stop_reason(actor_id, job, LocalText.text("system.wood_gathering.the_remaining_trees_cannot_be_reached_stopping_here"))

func drop_zone(drop: Dictionary) -> String:
	var tree: Dictionary = world.objects.get(str(drop.id).trim_prefix("drop."), {})
	return str(tree.get("zone_id", world.catalog.zone_at(drop.region_id, world.point(drop))))

func _sort_near(actor: Dictionary, entries: Array) -> void:
	entries.sort_custom(func(a, b):
		var da: float = world.point(actor).distance_squared_to(world.point(a)); var db: float = world.point(actor).distance_squared_to(world.point(b))
		return str(a.id) < str(b.id) if is_equal_approx(da, db) else da < db)

func deposit(actor_id:String,job:Dictionary)->bool:
	if actor_id=="human":
		var wood:int=int(world.actors[actor_id].carry.get("wood",0))
		if not world.deposit_all(actor_id).ok:return false
		job.wood_stored+=wood;after_delivery(actor_id,job)
		return true
	job.phase="storage_delivery";return world.deliveries.request(actor_id)

func after_delivery(actor_id: String, job: Dictionary) -> void:
	if job.has("active_tree_id"):
		job.trees_completed += 1; job.erase("active_tree_id")
		if not job.has("project_id"): world.work.record_event(actor_id, job, "progress", LocalText.text("system.wood_gathering.wood_gathering_fully_hauled_s_trees_and_stored_s") % [job.trees_completed, job.wood_stored])
	job.erase("drop_id"); job.erase("chest_id"); job.erase("handling_time")
	job.target_id = ""; job.phase = "gather_prepare"
