class_name FarmSystem
extends RefCounted
signal watered(actor_id:String,farm_id:String,plot_id:String,proof_id:String)
const LocalText=preload("res://scripts/localization.gd")

const DATA_PATH := "res://content/farms.json"
const ACTIONS := ["plant", "water", "harvest", "manage_farm", "assign_farm", "farm_store", "farm_take", "decorate_farm"]
var _owner: WeakRef
var world: RefCounted:
	get: return _owner.get_ref()
var farms: Dictionary = {}
var plots: Dictionary = {}
var containers: Dictionary = {}
var crops: Dictionary = {}
var version := 2
var orders: Dictionary = {}
# Host-issued work only (button or confirmed one-line command). Never saved: a restored
# order stays paused and a companion without manager rights cannot silently resume it.
var host_grants: Dictionary = {}
var memories: Array = []
var clock := Time.get_unix_time_from_system()
var _tick := 0.0
var _stages: Dictionary = {}
var _geometry_ready:Dictionary={}

func _init(source: RefCounted, data_path: String = DATA_PATH, grant_seeds:bool=true) -> void:
	_owner = weakref(source)
	var data: Dictionary = world.locations.read("farms") if data_path==DATA_PATH else JSON.parse_string(FileAccess.get_file_as_string(data_path))
	crops = data.crops
	if not world.locations.v3():
		crops.erase("potato");crops.erase("corn")
	version = int(data.version)
	var initial_seed_sources:Dictionary={}
	for definition in data.farms:
		if str(definition.id).begins_with("farm.theirs") and not world.locations.v3():continue
		var farm: Dictionary = definition.duplicate(true)
		if not world.locations.v3():farm.crop_ids=farm.crop_ids.filter(func(id):return id not in ["potato","corn"])
		farm["flowers"] = 0; farm["harvested"] = 0
		farms[farm.id] = farm
		var source_id:String=str(farm.get("seed_storage",str(farm.id)+".seed"))
		if not initial_seed_sources.has(source_id):initial_seed_sources[source_id]={}
		for crop in farm.crop_ids:
			if crop in ["potato","corn"]:continue
			if str(farm.id).begins_with("farm.theirs"):continue
			initial_seed_sources[source_id]["seed."+crop]=int(farm.grid[0]*farm.grid[1])
		for y in range(int(farm.grid[1])):
			for x in range(int(farm.grid[0])):
				var id: String = farm.id + ".plot.%02d" % (y * int(farm.grid[0]) + x + 1)
				plots[id] = {"id":id,"kind":"farm_plot","region_id":"home","farm_id":farm.id,"position":[farm.first[0] + x * farm.spacing[0], farm.first[1] + y * farm.spacing[1]],"crop_id":"","watered":false,"planted_at":0.0,"harvests":0}

	if data_path==DATA_PATH:sync_beds({})
	if grant_seeds:
		for items in initial_seed_sources.values():world.storage.add(items)

func sync_beds(sites:Variant=null)->void:
	if not world.locations.v3():return
	var source:Dictionary=world.leisure.sites if sites==null and world.leisure!=null else (sites if sites is Dictionary else {})
	var missing:bool=not farms.has("farm.bed.homestead")
	for site in source.values():
		if site.get("template_id")=="outdoor-flowers" and not farms.has("farm.bed."+str(site.id)):missing=true;break
	if not missing:return
	for farm in preload("res://scripts/cultivated_beds.gd").definitions(world,source):
		if farms.has(farm.id):continue
		farms[farm.id]=farm.duplicate(true)
		for y in range(int(farm.grid[1])):
			for x in range(int(farm.grid[0])):
				var id:String=str(farm.id)+".plot.%02d"%(y*int(farm.grid[0])+x+1)
				var definition:Dictionary={"id":id,"kind":"farm_plot","region_id":"home","farm_id":farm.id,"position":[float(farm.first[0])+x*float(farm.spacing[0]),float(farm.first[1])+y*float(farm.spacing[1])],"crop_id":"","watered":false,"planted_at":0.0,"harvests":0}
				plots[id]=JSON.parse_string(JSON.stringify(definition))
func validated_saved(data:Variant,actors:Dictionary,sites:Dictionary)->bool:
	var probe:RefCounted=get_script().new(world,DATA_PATH,false)
	probe.sync_beds(sites)
	return probe.valid_saved(data,actors)
func ready(farm_id:String)->bool:
	if world.get("resort")!=null and farms.has(farm_id) and world.resort.retired({"position":farms[farm_id].meeting_at}):return false
	if farms.has(farm_id) and farms[farm_id].get("raised_bed",false):
		var farm:Dictionary=farms[farm_id]
		if farm.source_kind=="homestead":return world.homestead!=null and world.homestead.completed()
		return world.leisure!=null and world.leisure.sites.get(farm.source_site_id,{}).get("complete",false)
	if not farm_id.begins_with("farm.theirs"):return world.standard==null or world.standard.ready(farm_id)
	var spec:Array={"farm.theirs":["produce-herbgarden","npc.mira"],"farm.theirs.white":["produce-flowerhouse","codex"],"farm.theirs.black":["produce-stargarden","npc.nora"]}.get(farm_id,[])
	return not spec.is_empty() and not world.ingredients.facility(spec[0],spec[1]).is_empty()

func allowed(actor_id: String, farm_id: String) -> bool:
	return farms.has(farm_id) and ready(farm_id) and (actor_id == "human" or farms[farm_id].manager_id == actor_id or _granted(actor_id, farm_id))

func _granted(actor_id: String, farm_id: String) -> bool:
	var grant: Dictionary = host_grants.get(actor_id, {})
	return grant.get("farm_id", "") == farm_id and (grant.get("issuing", false) or (orders.get(actor_id, {}).get("farm_id", "") == farm_id and active(actor_id)))

## The host explicitly asks one resident to fill (plant) or harvest what is ripe (ready).
func preview_host_orders(ids:Array,intent:String,farm_id:String="",crop_id:String="mixed")->Dictionary:
	return preload("res://scripts/farm_host_plan.gd").preview(self,ids,intent,farm_id,crop_id)

func confirm_host_orders(plan:Dictionary,selected_ids:Variant=null)->Dictionary:
	return preload("res://scripts/farm_host_plan.gd").confirm(self,plan,selected_ids)

func host_order(actor_id: String, farm_id: String, crop_id: String, mode: String, plot_ids:Array=[], crop_by_plot:Dictionary={}) -> Dictionary:
	if not world.actors.has(actor_id) or not farms.has(farm_id) or mode not in ["plant", "ready"]: return world._error("invalid_farm_plan")
	var args := {"intent":"manage_farm","farm_id":farm_id,"crop_id":crop_id if mode == "plant" else "","mode":mode}
	if actor_id == "human" and plot_ids.is_empty(): return world.command("human", args)
	# Same gate world.command applies to direct field work; manage_farm itself is not in that list.
	if not world.open_life and actor_id!="human" and world.hunger != null and world.hunger.rank(actor_id) >= 2: return world.work.fail("hungry", LocalText.text("system.farm_system.you_are_hungry_have_something_to_eat_before"))
	if active(actor_id) or world.actors[actor_id].has("world_door_client"):return world._error("busy")
	var brain:RefCounted=world.director.brains.get(actor_id)
	if world.work.jobs.has(actor_id) and (brain==null or not brain.owns_local_job()):return world._error("busy")
	if brain!=null:brain.pause_for_player()
	host_grants[actor_id] = {"farm_id":farm_id,"issuing":true,"plot_ids":plot_ids.duplicate(),"crop_by_plot":crop_by_plot.duplicate(true)}
	var result: Dictionary = world.command(actor_id, args)
	# An accepted explicit host task replaces only this actor's following, never others.
	if result.get("ok",false) and actor_id!="human":world.activities.pause_follow(actor_id)
	if host_grants.has(actor_id): host_grants[actor_id].issuing = false
	if not result.get("ok", false) or not active(actor_id): host_grants.erase(actor_id)
	return result

func _has_seed(_farm_id: String, crop: String, actor_id:String="human") -> bool:
	return int(world.available_items(actor_id).get("seed."+crop,0))>0

## Mixed planting keeps its fixed per-plot pattern, but uses another suitable crop
## that really has seed instead of stopping the whole order on one empty seed type.
func _mixed_crop(farm_id: String, plot: Dictionary, actor_id:String="human") -> String:
	var ids: Array = farms[farm_id].crop_ids.filter(func(id):return id not in ["potato","corn"])
	var first := int(str(plot.id).get_slice(".plot.",1)) - 1
	for offset in range(ids.size()):
		var crop: String = ids[(first + offset) % ids.size()]
		if _has_seed(farm_id, crop, actor_id): return crop
	return ids[first % ids.size()]

func active(actor_id: String) -> bool:
	return orders.get(actor_id, {}).get("status") in ["working", "waiting"]

func pause(actor_id: String, message: String = LocalText.text("system.farm_system.the_farm_order_is_paused")) -> void:
	if not active(actor_id): return
	orders[actor_id].status = "paused"; orders[actor_id].message = message; host_grants.erase(actor_id)
	world.work.stop(actor_id, false); world.revision += 1

func state(actor_id: String) -> Dictionary:
	var list: Array = []
	for farm in farms.values():
		var copy: Dictionary = farm.duplicate(true)
		copy["can_manage"] = allowed(actor_id, farm.id)
		copy["seed_chest"] = {"items":world.available_items(actor_id)}
		copy["harvest_chest"] = {"items":world.available_items(actor_id)}
		copy["plots"] = []
		for plot in farm_plots(farm.id):
			var entry: Dictionary = plot.duplicate(true)
			entry["stage"] = stage(plot); entry["ready_in_seconds"] = remaining(plot)
			entry["claimed_by"] = world.work.claims.get(plot.id, "")
			copy.plots.append(entry)
		list.append(copy)
	return {"farms":list,"crops":crops.duplicate(true),"order":orders.get(actor_id, {}).duplicate(true),"memories":memories.duplicate(true),"offline_policy":LocalText.text("system.farm_system.watered_crops_matured_for_this_batch_while_away")}

func farm_plots(id: String) -> Array:
	return plots.values().filter(func(plot): return plot.farm_id == id)

func remaining(plot: Dictionary) -> float:
	if plot.crop_id.is_empty() or not plot.watered: return -1.0
	return maxf(0, float(crops[plot.crop_id].seconds) - (clock - float(plot.planted_at)))

func stage(plot: Dictionary) -> String:
	if plot.crop_id.is_empty(): return "empty"
	if not plot.watered: return "dry"
	var left := remaining(plot)
	return "mature" if left <= 0 else "growing" if left < float(crops[plot.crop_id].seconds) * .65 else "seedling"

func command(actor_id: String, args: Dictionary) -> Dictionary:
	for key in args:
		if key not in ["intent","target_id","farm_id","crop_id","mode","manager_id","item_id"]: return world._error("invalid_command")
		if not args[key] is String: return world._error("invalid_command")
	var intent: String = args.intent
	var target_id := str(args.get("target_id", ""))
	var target: Dictionary = plots.get(target_id, {})
	var farm_id := str(args.get("farm_id", target.get("farm_id", "")))
	if not farms.has(farm_id) or (not target.is_empty() and target.farm_id != farm_id): return world._error("unknown_farm")
	if intent == "assign_farm":
		if actor_id != "human": return world._error("host_only")
		var manager := str(args.get("manager_id", ""))
		if not manager.is_empty() and (not world.actors.has(manager) or not world.residents.supports(world.actors[manager],"manage_farm")): return world._error("unknown_resident")
		for id in orders:
			if orders[id].farm_id == farm_id: pause(id, LocalText.text("system.farm_system.the_manager_changed_please_arrange_the_work_again"))
		for id in world.work.jobs.keys():
			if world.work.jobs[id].get("farm_id") == farm_id: world.work.stop(id)
		farms[farm_id].manager_id = manager; world.revision += 1
		return {"ok":true,"status":"completed"}
	if not allowed(actor_id, farm_id): return world.work.fail("farm_permission", LocalText.text("system.farm_system.another_companion_manages_this_farm_ask_the_host"))
	if world.actors[actor_id].region_id != "home": return world._error("different_region")
	if world.work.jobs.has(actor_id): return world._error("busy")
	if not str(world.actors[actor_id].get("furniture_id", "")).is_empty(): return world._error("hands_full")
	if intent == "manage_farm":
		var crop := str(args.get("crop_id", "")); var mode := str(args.get("mode", "once"))
		if mode not in ["once","repeat","harvest","plant","ready"] or (mode not in ["harvest","ready"] and crop not in farms[farm_id].crop_ids and not (mode == "plant" and crop == "mixed")): return world._error("invalid_farm_plan")
		if active(actor_id): return world._error("farm_order_active")
		var previous: Dictionary = orders.get(actor_id,{})
		if host_grants.get(actor_id,{}).get("plot_ids",[]).is_empty() and previous.get("status") == "paused" and previous.get("farm_id") == farm_id and previous.get("crop_id") == crop and previous.get("mode") == mode:
			previous.status = "working"; previous.message = LocalText.text("system.farm_system.continuing_the_previous_farm_order")
			world.director.command_received(actor_id,intent); world.revision += 1
			return {"ok":true,"status":"accepted","message":previous.message}
		orders[actor_id] = {"farm_id":farm_id,"crop_id":crop,"mode":mode,"status":"working","completed":[],"message":LocalText.text("system.farm_system.starting_work_on_the_farm")}
		world.director.command_received(actor_id, intent); world.revision += 1
		return {"ok":true,"status":"accepted","message":LocalText.text("system.farm_system.farm_order_accepted_planting_watering_and_hauling_run")}
	if active(actor_id): return world._error("farm_order_active")
	return _start(actor_id, intent, farm_id, target_id, str(args.get("crop_id", "")), str(args.get("item_id", "")))

func _start(actor_id: String, intent: String, farm_id: String, target_id: String, crop_id: String = "", item_id: String = "") -> Dictionary:
	var actor: Dictionary = world.actors[actor_id]
	var target: Dictionary = plots.get(target_id, {})
	var job := {"intent":intent,"phase":"farm_work","step":intent,"farm_id":farm_id,"target_id":target_id,"crop_id":crop_id,"item_id":item_id}
	if intent in ["plant","water","harvest"]:
		if not plots.has(target_id) or (target.farm_id != farm_id): return world._error("unknown_plot")
		if world.work.claims.has(target_id): return world._error("claimed")
		if intent == "plant":
			if crop_id not in farms[farm_id].crop_ids or not target.crop_id.is_empty(): return world._error("invalid_crop")
			job.item_id = "seed." + crop_id
			if int(world.available_items(actor_id).get(job.item_id,0))<1:return world._error("no_seed")
			job.step="plant"

		elif intent == "water" and (target.crop_id.is_empty() or target.watered): return world._error("water_not_needed")
		elif intent == "harvest":
			if stage(target) != "mature": return world._error("not_ready")

	elif intent == "farm_store":
		if actor_id=="human":world.deposit_all(actor_id)
		else:world.deliveries.request(actor_id,true,true)
		return {"ok":true,"status":"completed"}
	elif intent == "farm_take":return world._error("retired_storage_action")
	elif intent == "decorate_farm":
		target={"id":farm_id,"region_id":"home","position":farms[farm_id].meeting_at}
		job.item_id="daisy"
		if int(world.available_items(actor_id).get("daisy",0))<2:return world._error("missing_harvest")

	else: return world._error("unsupported_action")
	world.director.command_received(actor_id, intent)
	var result: Dictionary = world.work._begin(actor_id, job, target)
	if result.ok:
		if plots.has(target_id): world.work.claims[target_id] = actor_id
	return result

func advance(delta: float) -> void:
	sync_beds()
	for farm_id in farms:
		if farms[farm_id].get("raised_bed",false):continue
		var built:bool=ready(farm_id)
		if _geometry_ready.has(farm_id) and _geometry_ready[farm_id]!=built:
			world._terrain_solids.erase("home");world._grids.erase("home")
		_geometry_ready[farm_id]=built
	clock += delta; _tick += delta
	if _tick < 1: return
	_tick = 0
	for plot in plots.values():
		var current := stage(plot)
		if _stages.get(plot.id,current) != current: world.revision += 1
		_stages[plot.id] = current
	for actor_id in orders.keys():
		if not active(actor_id) or world.work.jobs.has(actor_id) or world.deliveries.active(actor_id): continue
		var order: Dictionary = orders[actor_id]
		if not allowed(actor_id, order.farm_id): pause(actor_id, LocalText.text("system.farm_system.farm_permissions_changed")); continue
		var actor: Dictionary = world.actors[actor_id]
		if actor_id!="human" and world.work.carry_space(actor_id)<4:
			world.deliveries.request(actor_id);continue
		var pending := false; var action := {}; var available_plots := farm_plots(order.farm_id)
		for plot in available_plots:
			var scope:Array=host_grants.get(actor_id,{}).get("plot_ids",[])
			if (not scope.is_empty() and plot.id not in scope) or preload("res://scripts/farm_host_plan.gd").reserved(self,plot.id,actor_id):continue
			if order.mode != "repeat" and plot.id in order.completed: continue
			if world.work.claims.has(plot.id):
				if order.mode != "ready": pending = true
				continue
			var current := stage(plot)
			if order.mode == "ready" and current != "mature": continue
			if order.mode == "plant" and current not in ["empty","dry"]: continue
			if current == "mature": action = {"intent":"harvest","plot":plot}; break
			if current == "dry": action = {"intent":"water","plot":plot}; break
			if current == "empty" and order.mode != "harvest": action = {"intent":"plant","plot":plot}; break
			if current != "empty": pending = true
		if not action.is_empty():
			_accept_order_step(actor_id, _start(actor_id, action.intent, order.farm_id, action.plot.id, str(host_grants.get(actor_id,{}).get("crop_by_plot",{}).get(action.plot.id,_mixed_crop(order.farm_id, action.plot, actor_id) if order.crop_id=="mixed" else order.crop_id))))
		elif pending:
			if order.status != "waiting": order.status = "waiting"; order.message = LocalText.text("system.farm_system.waiting_for_the_crops_to_grow"); world.revision += 1
		else:
			# Completion includes the original physical handover, not just picking.
			if actor_id!="human" and not actor.carry.is_empty():
				world.deliveries.request(actor_id);continue
			var scoped_plant:bool=order.mode=="plant" and not host_grants.get(actor_id,{}).get("plot_ids",[]).is_empty()
			order.status = "completed"; order.message = {"plant":LocalText.text("system.farm_system.the_field_is_fully_planted_and_watered"),"ready":LocalText.text("system.farm_system.all_ripe_crops_are_in_the_harvest_chest")}.get(order.mode, LocalText.text("system.farm_system.this_round_is_complete_the_harvest_is_stored")); host_grants.erase(actor_id)
			if scoped_plant:order.message=LocalText.text("farm.help.assigned_done")
			world.work.record_event(actor_id, {}, "farm_completed", order.message); world.revision += 1

func _accept_order_step(actor_id: String, result: Dictionary) -> void:
	if not result.ok: pause(actor_id, str(result.get("message", result.get("error", LocalText.text("system.farm_system.farm_work_is_blocked_for_now")))))
	else: orders[actor_id].status = "working"; orders[actor_id].message = LocalText.text("system.farm_system.tending_the_field")

func tick_job(actor_id: String, job: Dictionary, delta: float) -> void:
	if not allowed(actor_id, job.farm_id): _finish(actor_id, LocalText.text("system.farm_system.farm_permissions_changed"), false); return
	var actor: Dictionary = world.actors[actor_id]
	var plot: Dictionary = plots.get(job.target_id, {})
	var step: String = job.step
	var target: Dictionary = plot
	if step == "decorate_farm": target = {"id":job.farm_id,"region_id":"home","position":farms[job.farm_id].meeting_at}
	if step in ["plant","water","harvest"]:
		actor.activity = "watering" if step == "water" else "picking_up"
		world.work.face(actor,target)
		job["field_time"] = float(job.get("field_time",0)) + delta
		if float(job.field_time) < 1.3: return
	if not world.work.handle_bundle(actor, job, target, delta, "picking_up" if step in ["load_seed","load_harvest","harvest","farm_take"] else "putting_down"): return
	match step:
		"plant":
			if not plot.crop_id.is_empty() or not world.pay_costs(actor_id,{str(job.item_id):1}).ok: _finish(actor_id, LocalText.text("system.farm_system.the_plot_changed_you_keep_the_seeds"), false); return
			plot.crop_id = job.crop_id; plot.watered = false; plot.planted_at = clock
			if actor_id=="human":preload("res://scripts/brain_interactions.gd").host_event(world,"host_plant","plant:"+str(job.id))
			_finish(actor_id, LocalText.text("system.farm_system.seed_planted_it_needs_one_watering_next"))
		"water":
			if plot.crop_id.is_empty(): _finish(actor_id, LocalText.text("system.farm_system.the_plot_changed"), false); return
			if not plot.watered:
				plot.watered = true; plot.planted_at = clock
				watered.emit(actor_id,str(job.farm_id),str(plot.id),str(job.id))
			if active(actor_id) and orders[actor_id].mode=="plant" and plot.id not in orders[actor_id].completed:orders[actor_id].completed.append(plot.id)
			_finish(actor_id, LocalText.text("system.farm_system.watered_it_will_grow_slowly_even_while_you"))
		"harvest":
			if stage(plot) != "mature": _finish(actor_id, LocalText.text("system.farm_system.this_plot_cannot_be_harvested_yet"), false); return
			var crop: Dictionary = crops[plot.crop_id]
			if actor_id!="human" and world.work.carry_space(actor_id)<int(crop.yield)+1:
				job["storage_resume"]="farm_work";job.phase="storage_delivery";world.deliveries.request(actor_id);return
			var harvested:Dictionary={str(plot.crop_id):int(crop.yield),"seed."+str(plot.crop_id):1}
			if actor_id=="human":world.storage.add(harvested)
			if actor_id!="human":
				for item in harvested:actor.carry[item]=int(actor.carry.get(item,0))+int(harvested[item])
			if actor_id=="human" and plot.crop_id not in world.ingredients.discovered:world.ingredients.discovered.append(plot.crop_id)
			farms[job.farm_id].harvested += int(crop.yield); plot.harvests += 1
			if actor_id=="human":preload("res://scripts/brain_interactions.gd").host_event(world,"host_harvest","harvest:"+str(job.id))
			if crop.regrow: plot.planted_at = clock; plot.watered = true
			else: plot.crop_id = ""; plot.watered = false
			if active(actor_id) and plot.id not in orders[actor_id].completed: orders[actor_id].completed.append(plot.id)
			_finish(actor_id,LocalText.text("system.farm_system.picked_up"))
			if actor_id!="human" and not active(actor_id):world.deliveries.request(actor_id)
		"farm_store":
			if actor_id=="human":world.deposit_all(actor_id)
			else:world.deliveries.request(actor_id)
			_finish(actor_id,LocalText.text("system.farm_system.picked_up"))
		"decorate_farm":
			if not world.pay_costs(actor_id,{str(job.item_id):2}).ok: _finish(actor_id, LocalText.text("system.farm_system.you_are_not_holding_enough_produce"), false); return
			farms[job.farm_id].flowers += 2
			memories.append({"actor_id":actor_id,"farm_id":job.farm_id,"kind":step,"item_id":job.item_id,"amount":2,"at":clock})
			if memories.size() > 32: memories.pop_front()
			_finish(actor_id, LocalText.text("system.farm_system.flowers_you_grew_are_now_decorating_the_field"))
	world.revision += 1


func _finish(actor_id: String, message: String, ok: bool = true) -> void:
	if not ok and active(actor_id): orders[actor_id].status = "paused"; orders[actor_id].message = message;host_grants.erase(actor_id)
	world.work._finish(actor_id, message, ok)
	if not active(actor_id) and not world.actors[actor_id].carry.is_empty() and world.actors[actor_id].carry.keys().all(func(k):return world.pocket_item(str(k))):world.stow_loose(actor_id)

func saved() -> Dictionary:
	sync_beds()
	var saved_orders:Dictionary=orders.duplicate(true)
	for order in saved_orders.values():order.erase("host_order_id")
	return {"version":version,"clock":clock,"farms":farms,"plots":plots,"orders":saved_orders,"memories":memories}

func restore(data: Dictionary) -> void:
	host_grants.clear()
	sync_beds()
	if int(data.version) == version:
		for id in data.farms:
			for key in ["manager_id","flowers","harvested"]:farms[id][key]=data.farms[id][key]
		for id in data.plots:
			for key in ["crop_id","watered","planted_at","harvests"]:plots[id][key]=data.plots[id][key]
		containers=data.get("containers",{}).duplicate(true)
	else:
		# Move the same living plants and containers into the compact layout. No stock refill.
		for id in data.farms:
			for key in ["manager_id","flowers","harvested"]: farms[id][key] = data.farms[id][key]
		for id in data.plots:
			for key in ["crop_id","watered","planted_at","harvests"]: plots[id][key] = data.plots[id][key]
		for id in data.get("containers",{}):
			if containers.has(id):containers[id].items = data.containers[id].items.duplicate(true)
	orders = data.orders.duplicate(true); memories = data.memories.duplicate(true)
	clock = maxf(Time.get_unix_time_from_system(), float(data.clock))
	for order in orders.values():
		order.erase("host_order_id")
		if order.status in ["working","waiting"]: order.status = "paused"; order.message = LocalText.text("system.farm_system.after_returning_to_the_game_confirm_before_continuing")

func valid_saved(data: Variant, actors: Dictionary) -> bool:
	if version == 2 and data is Dictionary and data.get("version") == 1:
		var legacy: RefCounted = get_script().new(world,"res://content/farms-v1.json",false)
		return legacy.valid_saved(data,actors)
	if not data is Dictionary or data.get("version") != version or not world.catalog._number(data.get("clock")) or float(data.clock) < 0: return false
	for key in ["farms","plots","orders"]:
		if not data.get(key) is Dictionary: return false
	for added_id in farms.keys().filter(func(id):return str(id).begins_with("farm.theirs") or str(id).begins_with("farm.bed.")):
		if not data.farms.has(added_id) and farms.has(added_id):
			var migrated:Dictionary=data.duplicate(true)
			migrated.farms[added_id]=farms[added_id].duplicate(true)
			for id in plots:
				if plots[id].farm_id==added_id:migrated.plots[id]=plots[id].duplicate(true)
			return valid_saved(migrated,actors)
	if data.farms.size() != farms.size() or data.plots.size() != plots.size() or data.orders.size() > actors.size(): return false
	var Save = load("res://scripts/save_store.gd")
	for id in farms:
		if not data.farms.get(id) is Dictionary: return false
		var farm: Dictionary = data.farms[id]
		for key in farms[id]:
			if key=="crop_ids" and id in ["farm.home","farm.east"]:
				var original:Array=["turnip","tomato","pumpkin"] if id=="farm.home" else ["turnip","tomato","pumpkin","daisy"]
				if farm.get(key)!=original and farm.get(key)!=farms[id][key]:return false
			elif key not in ["manager_id","flowers","harvested"] and farm.get(key) != farms[id][key]: return false
		if not farm.get("manager_id") is String or (not farm.manager_id.is_empty() and not actors.has(farm.manager_id)): return false
		if not Save._quantity(farm.get("flowers")) or not Save._quantity(farm.get("harvested")): return false
	if data.has("containers"):
		if not data.containers is Dictionary:return false
		for item in data.containers.values():
			if not item is Dictionary or not Save._wood(item.get("items"),240):return false
	for id in plots:
		if not data.plots.get(id) is Dictionary: return false
		var plot: Dictionary = data.plots[id]
		for key in ["id","kind","region_id","farm_id","position"]:
			if plot.get(key) != plots[id][key]: return false
		if not plot.get("crop_id") is String or (not plot.crop_id.is_empty() and plot.crop_id not in farms[plot.farm_id].crop_ids): return false
		if not plot.get("watered") is bool or not world.catalog._number(plot.get("planted_at")) or plot.planted_at < 0 or plot.planted_at > data.clock or not Save._quantity(plot.get("harvests")): return false
	for actor_id in data.orders:
		var order: Variant = data.orders[actor_id]
		if not actors.has(actor_id) or not order is Dictionary or not farms.has(order.get("farm_id", "")): return false
		if order.get("mode") not in ["once","repeat","harvest","plant","ready"] or order.get("status") not in ["working","waiting","paused","completed"]: return false
		if order.get("mode") not in ["harvest","ready"] and order.get("crop_id") not in farms[order.farm_id].crop_ids and not (order.mode=="plant" and order.get("crop_id")=="mixed"): return false
		if not order.get("message") is String or not order.get("completed") is Array or order.completed.size() > farm_plots(order.farm_id).size(): return false
		var seen := {}
		for id in order.completed:
			if not plots.has(id) or plots[id].farm_id != order.farm_id or seen.has(id): return false
			seen[id] = true
	if not data.get("memories") is Array or data.memories.size() > 32: return false
	for memory in data.memories:
		if not memory is Dictionary or not actors.has(memory.get("actor_id", "")) or not farms.has(memory.get("farm_id", "")) or memory.get("kind") not in ["farm_meal","decorate_farm"] or not crops.has(memory.get("item_id", "")) or memory.get("amount") != 2 or not world.catalog._number(memory.get("at")): return false
	return true

func bounds(farm: Dictionary) -> Rect2:
	return world.catalog.rectangle(farm.rect)

func bed(plot: Dictionary) -> Rect2:
	var authored: Array=farms[plot.farm_id].bed_size if farms[plot.farm_id].has("bed_size") else JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH)).farms[0].bed_size
	var size := Vector2(authored[0],authored[1])
	return Rect2(world.point(plot)-size/2,size)

func fences(farm: Dictionary) -> Array:
	if farm.get("raised_bed",false):return []
	if world.standard!=null and not world.standard.ready(farm.id):return []
	var rect := bounds(farm).grow(.6)
	if farm.get("gate",{}).get("side")=="north":
		var center:float=float(farm.rect[0])+float(farm.gate.offset);var half:float=float(farm.gate.width)/2
		return [[rect.position,Vector2(center-half,rect.position.y)],[Vector2(center+half,rect.position.y),Vector2(rect.end.x,rect.position.y)],[rect.position,Vector2(rect.position.x,rect.end.y)],[Vector2(rect.position.x,rect.end.y),rect.end],[Vector2(rect.end.x,rect.position.y),rect.end]]
	var gate_y: float = float(farm.first[1])+4.0
	return [[rect.position,Vector2(rect.end.x,rect.position.y)], [rect.position,Vector2(rect.position.x,rect.end.y)], [Vector2(rect.position.x,rect.end.y),rect.end], [Vector2(rect.end.x,rect.position.y),Vector2(rect.end.x,gate_y-1.15)], [Vector2(rect.end.x,gate_y+1.15),rect.end]]

func blocked(point: Vector2) -> bool:
	for farm in farms.values():
		if not ready(farm.id):continue
		if not bounds(farm).grow(1.3).has_point(point): continue
		for fence in fences(farm):
			if point.distance_to(Geometry2D.get_closest_point_to_segment(point,fence[0],fence[1])) < .55: return true
	return false

func container_id(farm_id:String,role:String)->String:return str(farms[farm_id].get(role+"_storage",farm_id+"."+role))

func storage_allowed(actor_id:String,chest:Dictionary)->bool:
	if allowed(actor_id,str(chest.farm_id)):return true
	return world.locations.v3() and chest.id in ["home.tools.seed","home.tools.harvest"] and farms.values().any(func(f):return f.manager_id==actor_id)
