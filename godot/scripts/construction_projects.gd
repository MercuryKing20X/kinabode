class_name ConstructionProjects
extends RefCounted
const LocalText=preload("res://scripts/localization.gd")

const LIVE := ["active", "paused", "blocked"]
const LABELS := {"preparing": ("system.construction_projects.checking_materials"), "gathering": ("system.construction_projects.gathering_wood"), "delivering": ("system.construction_projects.delivering_to_site"), "building": ("system.construction_projects.building"), "waiting_partner": ("system.construction_projects.waiting_for_a_companion_to_finish_this_step"), "leaving": ("system.construction_projects.leaving_the_house"), "storing": ("system.construction_projects.storing_carried_items")}
var _owner: WeakRef
var world: RefCounted:
	get: return _owner.get_ref()
var plans: Dictionary = {}
var memories: Array = []
var cooldown := 0.0
var host_team_site := ""
var host_team_members:Array=[]

func _init(source: RefCounted) -> void: _owner = weakref(source)
func active(actor_id: String) -> bool: return plans.get(actor_id, {}).get("status") == "active"
func site_locked(site_id: String) -> bool:
	return plans.values().any(func(plan): return plan.site_id == site_id and plan.status in LIVE)

func state(actor_id: String) -> Dictionary:
	if not plans.has(actor_id): return {}
	var result: Dictionary = plans[actor_id].duplicate(true)
	result["construction"] = world.construction_state(result.site_id)
	result["contributors"] = world.objects[result.site_id].get("contributions", {}).duplicate(true)
	var job: Dictionary = world.work.jobs.get(actor_id, {})
	if active(actor_id) and job.get("project_id") == result.id:
		if job.intent == "build": result.step = "building" if job.phase == "building" else "delivering"
	result["step_label"] = LocalText.text(LABELS.get(result.step, result.step))
	return result

func command(actor_id: String, args: Dictionary) -> Dictionary:
	var intent := str(args.intent)
	if intent == "build_house":
		for key in args:
			if key not in ["intent", "target_id"]: return world._error("invalid_command")
		var target_id := str(args.get("target_id", ""))
		if not world.objects.has(target_id) or world.objects[target_id].kind != "construction_site": return world._error("unknown_site")
		if world.work.jobs.has(actor_id): return world.work.fail("busy", LocalText.text("system.construction_projects.finish_your_current_task_before_building_together"))
		if plans.get(actor_id, {}).get("status") in LIVE: return world.work.fail("project_exists", LocalText.text("system.construction_projects.a_house_plan_already_exists_continue_pause_or_cancel"))
		if site_locked(target_id) and not (host_team_site==target_id and actor_id in host_team_members): return world.work.fail("project_claimed", LocalText.text("system.construction_projects.a_companion_has_a_plan_for_this_house_you"))
		var site: Dictionary = world.objects[target_id]
		if int(site.get("stage_index", 0)) >= 5: return world.work.fail("finished", LocalText.text("system.construction_projects.this_house_is_complete_step_inside"))
		var actor: Dictionary = world.actors[actor_id]
		if not str(actor.get("furniture_id", "")).is_empty(): return world.work.fail("hands_full", LocalText.text("system.construction_projects.put_down_the_furniture_before_planning_a_house"))
		var region_id: String = actor.region_id
		if world.interior.rooms().has(region_id): region_id = "home"
		if region_id != site.region_id: return world._error("different_region")
		if not site.has("blueprint") and int(site.get("stage_index", 0)) == 0 and site.delivered.is_empty() and world.library != null:
			var selection: Dictionary = world.select_blueprint(target_id, "cottage")
			if not selection.ok: return selection
		world.director.command_received(actor_id, intent); world._routes.erase(actor_id)
		var id := "project-" + Crypto.new().generate_random_bytes(12).hex_encode()
		plans[actor_id] = {"id": id, "actor_id": actor_id, "site_id": target_id, "status": "active", "step": "preparing", "reason": "", "blueprint_id": site.get("blueprint", {}).get("id", "legacy"), "started_at": Time.get_unix_time_from_system(), "completed_at": 0.0, "started_stage": int(site.get("stage_index", 0)), "last_stage": int(site.get("stage_index", 0)), "zone_id": ""}
		world.revision += 1
		_emit(plans[actor_id], "project_started", LocalText.text("system.construction_projects.let_us_finish_s_use_existing_materials_first_then") % site.name)
		return {"ok": true, "status": "accepted", "project_id": id, "message": LocalText.text("system.construction_projects.house_plan_started_work_follows_actual_materials_through_completion")}
	for key in args:
		if key not in ["intent", "project_id"]: return world._error("invalid_command")
	var plan: Dictionary = plans.get(actor_id, {})
	if plan.is_empty() or args.get("project_id") != plan.id: return world._error("unknown_project")
	if intent == "resume_project":
		if plan.status not in ["paused", "blocked"]: return world.work.fail("not_paused", LocalText.text("system.construction_projects.this_plan_does_not_need_continuing_right_now"))
		if world.work.jobs.has(actor_id): return world.work.fail("busy", LocalText.text("system.construction_projects.finish_your_current_action_before_continuing_the_plan"))
		if world.loaded(actor_id) and not str(world.actors[actor_id].get("furniture_id", "")).is_empty(): return world.work.fail("hands_full", LocalText.text("system.construction_projects.put_down_the_furniture_first"))
		world.director.command_received(actor_id, intent); world._routes.erase(actor_id)
		plan.status = "active"; plan.step = "preparing"; plan.reason = ""; world.revision += 1
		_emit(plan, "project_resumed", LocalText.text("system.construction_projects.continuing_this_home_first_check_what_is_still_needed"))
		return {"ok": true, "status": "accepted", "project_id": plan.id}
	if intent not in ["pause_project", "cancel_project"]: return world._error("unsupported_action")
	if plan.status not in LIVE: return world._error("project_finished")
	pause(actor_id, LocalText.text("system.construction_projects.paused_materials_and_progress_are_kept"), "cancelled" if intent == "cancel_project" else "paused")
	return {"ok": true, "status": "completed", "project_id": plan.id}

func pause(actor_id: String, reason: String, status: String = "paused") -> void:
	if not plans.has(actor_id) or plans[actor_id].status not in LIVE: return
	var plan: Dictionary = plans[actor_id]
	if world.work.jobs.get(actor_id, {}).get("project_id") == plan.id: world.work.stop(actor_id, false)
	plan.status = status; plan.reason = reason; world.revision += 1
	_emit(plan, "project_" + status, LocalText.text("system.construction_projects.house_plan_canceled_contributions_and_items_are_kept") if status == "cancelled" else reason)

func _emit(plan: Dictionary, status: String, message: String) -> void:
	world.revision += 1
	world.work.record_event(plan.actor_id, {"id": plan.id, "project_id": plan.id}, status, message)

func _launch(plan: Dictionary, result: Dictionary, step: String) -> void:
	if not result.ok:
		pause(plan.actor_id, str(result.get("message", result.get("error", LocalText.text("system.construction_projects.this_step_is_blocked_for_now")))), "blocked"); return
	var job: Dictionary = world.work.jobs[plan.actor_id]
	job["project_id"] = plan.id; plan.step = step; world.revision += 1

func advance(delta: float) -> void:
	cooldown -= delta
	if cooldown > 0: return
	cooldown = .2
	for actor_id in plans.keys():
		var plan: Dictionary = plans[actor_id]
		if plan.status != "active": continue
		var site: Dictionary = world.objects[plan.site_id]
		var actor: Dictionary = world.actors[actor_id]
		var stage := int(site.get("stage_index", 0))
		if stage >= 5:
			_complete(plan); continue
		if stage > int(plan.last_stage):
			plan.last_stage = stage
			_emit(plan, "project_progress", LocalText.text("system.construction_projects.the_home_has_s_5_stages_complete_let_us") % stage)
		var job: Dictionary = world.work.jobs.get(actor_id, {})
		if not job.is_empty():
			if job.get("project_id") != plan.id:
				pause(actor_id, LocalText.text("system.construction_projects.another_task_is_active_the_house_plan_is_paused"))
				continue
			# Stop an un-felled tree when real new supplies fund this stage.
			if job.intent == "gather_wood" and job.phase in ["gather_prepare", "chop"] and _stage_available(actor_id, site):
				world.work.stop(actor_id, false); plan.step = "preparing"
			continue
		if actor.region_id != site.region_id:
			if not world.interior.rooms().has(actor.region_id): pause(actor_id, LocalText.text("system.construction_projects.the_target_is_on_another_island_and_cannot_be"), "blocked"); continue
			_launch(plan, world.interior.start(actor_id, {"intent": "exit"}), "leaving"); continue
		if not str(actor.get("furniture_id", "")).is_empty(): pause(actor_id, LocalText.text("system.construction_projects.put_down_the_furniture_before_continuing_the_house"), "blocked"); continue
		if world.work.claims.has(site.id) and world.work.claims[site.id] != actor_id:
			if plan.step != "waiting_partner":
				plan.step = "waiting_partner";world.revision += 1
				world.approach(actor_id,site)
			continue
		var needed: int = world.work.stage_costs(site)[stage] - int(site.delivered.get("wood", 0))
		if needed <= 0 or int(actor.carry.get("wood", 0)) > 0 or int(world.available_items(actor_id).get("wood",0))>0:
			_launch(plan, world.work.start(actor_id, "build", site.id), "delivering"); continue
		# Recover reachable drops before cutting another tree. Re-evaluate after each haul.
		var drops: Array = world.drops.values().filter(func(drop): return drop.region_id == site.region_id and not world.work.claims.has(drop.id))
		world.gathering._sort_near(actor, drops)
		var recovering := false
		for drop in drops:
			if not world.can_approach(actor_id, drop): continue
			_launch(plan, world.work.collect(actor_id, drop.id), "gathering"); recovering = true; break
		if recovering: continue
		var args := {"intent": "gather_wood", "tree_count": 1}
		if not plan.zone_id.is_empty(): args["zone_id"] = plan.zone_id
		_launch(plan, world.gathering.start(actor_id, args), "gathering")

func _stage_available(actor_id: String, site: Dictionary) -> bool:
	var cost: int = world.work.stage_costs(site)[int(site.get("stage_index", 0))]
	var amount := int(site.delivered.get("wood", 0)) + int(world.actors[actor_id].carry.get("wood", 0))
	if amount >= cost: return true
	amount += world.storage.count("wood")
	return amount >= cost

func child_finished(actor_id: String, job: Dictionary, status: String, message: String) -> void:
	var plan: Dictionary = plans.get(actor_id, {})
	if plan.is_empty() or plan.status != "active" or job.get("project_id") != plan.id: return
	if job.intent == "gather_wood" and plan.zone_id.is_empty(): plan.zone_id = job.zone_id
	if status in ["completed", "waiting_materials"]: plan.step = "preparing"; return
	# WorldWork has already released the child. Keep the actual reason, don't retry forever.
	pause(actor_id, message, "blocked")

func _complete(plan: Dictionary) -> void:
	if world.work.jobs.get(plan.actor_id, {}).get("project_id") == plan.id: world.work.stop(plan.actor_id, false)
	plan.status = "completed"; plan.step = "completed"; plan.reason = ""; plan.completed_at = Time.get_unix_time_from_system(); plan.last_stage = 5
	var site: Dictionary = world.objects[plan.site_id]
	var contributors: Dictionary = site.get("contributions", {}).duplicate(true)
	memories.append({"project_id": plan.id, "site_id": site.id, "at": plan.completed_at, "contributors": contributors})
	if memories.size() > 32: memories.pop_front()
	world.memories.sync()
	_emit(plan, "project_completed", LocalText.text("system.construction_projects.s_is_complete_step_inside") % site.name)

func contribution(actor_id: String, site: Dictionary, wood: int = 0, stages: int = 0) -> void:
	if not site.has("contributions"): site["contributions"] = {}
	if not site.contributions.has(actor_id): site.contributions[actor_id] = {"wood": 0, "stages": 0}
	site.contributions[actor_id].wood += wood; site.contributions[actor_id].stages += stages

func restore(data: Dictionary) -> void:
	plans = data.get("plans", {}).duplicate(true); memories = data.get("memories", []).duplicate(true)
	for plan in plans.values():
		if plan.status == "active": plan.status = "paused"; plan.reason = LocalText.text("system.construction_projects.after_returning_to_the_game_press_continue_before_working")
	cooldown = 0

func valid_saved(data: Variant, saved: Dictionary) -> bool:
	if not data is Dictionary or not data.get("plans") is Dictionary or not data.get("memories") is Array or data.plans.size() > 6 or data.memories.size() > 32: return false
	var ids := {}; var live_sites := {}
	for actor_id in data.plans:
		var plan: Variant = data.plans[actor_id]
		if not saved.actors.has(actor_id) or not plan is Dictionary or plan.get("actor_id") != actor_id: return false
		if not plan.get("id") is String or not plan.id.begins_with("project-") or plan.id.length() > 64 or ids.has(plan.id): return false
		ids[plan.id] = true
		if not plan.get("site_id") is String or not saved.objects.has(plan.site_id): return false
		var site: Dictionary = saved.objects[plan.site_id]
		if site.kind != "construction_site" or not plan.get("blueprint_id") is String or (plan.get("status") != "cancelled" and plan.blueprint_id != site.get("blueprint", {}).get("id", "legacy")): return false
		if plan.get("status") not in ["active", "paused", "blocked", "completed", "cancelled"] or plan.get("step") not in ["preparing", "gathering", "delivering", "building", "waiting_partner", "leaving", "storing", "completed"]: return false
		if not plan.get("reason") is String or plan.reason.length() > 500 or not plan.get("zone_id") is String: return false
		if not plan.zone_id.is_empty() and not world.catalog.regions[site.region_id].zones.any(func(zone): return zone.id == plan.zone_id): return false
		for key in ["started_at", "completed_at"]:
			if not world.catalog._number(plan.get(key)) or plan[key] < 0: return false
		for key in ["started_stage", "last_stage"]:
			if not world._integer(plan.get(key)) or plan[key] < 0 or plan[key] > int(site.get("stage_index", 0)): return false
		if plan.started_stage >= 5 or plan.last_stage < plan.started_stage: return false
		if plan.status == "completed" and (int(site.get("stage_index", 0)) != 5 or plan.completed_at <= 0): return false
		if plan.status in LIVE:
			if live_sites.has(plan.site_id): return false
			live_sites[plan.site_id] = true
	var memory_ids := {}
	for memory in data.memories:
		if not memory is Dictionary or not memory.get("project_id") is String or memory.project_id.length() > 64 or memory_ids.has(memory.project_id): return false
		memory_ids[memory.project_id] = true
		if not saved.objects.has(memory.get("site_id", "")) or not world.catalog._number(memory.get("at")) or memory.at <= 0: return false
		var site: Dictionary = saved.objects[memory.site_id]
		if site.kind != "construction_site" or int(site.get("stage_index", 0)) != 5 or memory.get("contributors") != site.get("contributions", {}): return false
	return true

func valid_contributions(site: Dictionary, actors: Dictionary) -> bool:
	var ledger: Variant = site.get("contributions", {})
	if not ledger is Dictionary or ledger.size() > actors.size(): return false
	var wood := 0; var stages := 0
	for id in ledger:
		if not actors.has(id) or not ledger[id] is Dictionary or ledger[id].size() != 2: return false
		for key in ["wood", "stages"]:
			if not world._integer(ledger[id].get(key)) or ledger[id][key] < 0: return false
		wood += int(ledger[id].wood); stages += int(ledger[id].stages)
	return wood <= int(site.get("invested", 0)) + int(site.delivered.get("wood", 0)) and stages <= int(site.get("stage_index", 0))

# Scoped host multiselect only. Ordinary model commands retain the site lock.
func invite_team(ids:Array,site_id:String)->Array:
	var results:Array=[]
	if site_locked(site_id):return [{"ok":false,"error":"project_claimed"}]
	host_team_site=site_id;host_team_members=ids.duplicate()
	for id in ids:
		results.append(world.host_command(id,{"intent":"build_house","target_id":site_id}))
	host_team_site="";host_team_members.clear()
	return results
