class_name SharedLife
extends RefCounted
const LocalText=preload("res://scripts/localization.gd")

const COOK_HALF := 12.0
const EAT_SECONDS := 9.0
const SIT_SECONDS := .55
const REST_SECONDS := 1.6
const RISE_SECONDS := .5
var _owner: WeakRef
var world: RefCounted:
	get: return _owner.get_ref()
var station: Dictionary = {"id": "home.barbecue", "kind": "barbecue", "region_id": "home", "state": "cold", "supplies": {}, "portions": 0, "fuel_used": 0, "meals_eaten": 0, "timer": 0.0, "turned": false, "artwork_id": "camp-grill", "artwork": {}}
var patches: Dictionary = {}
var memories: Array = []
var activity_rules: Dictionary = {}
var fireside:RefCounted

func _init(owner_world: RefCounted,configuration:Dictionary={}) -> void:
	_owner = weakref(owner_world)
	fireside=preload("res://scripts/fireside.gd").new(self)
	station.merge(world.locations.read("recipes").station,true)
	var rules: Variant = world.locations.read("shared-activities")
	if not rules is Dictionary or rules.get("version") != 1 or not rules.get("barbecue") is Dictionary:
		world.error = LocalText.text("system.shared_life.the_shared_activity_settings_are_invalid"); return
	activity_rules = rules.barbecue
	activity_rules.merge(configuration.get("activity_rules",{}),true)
	if not activity_rules.get("seat_offsets") is Array or activity_rules.seat_offsets.size() < 2 or activity_rules.seat_offsets.size() > 16:
		world.error = LocalText.text("system.shared_life.the_camp_seating_settings_are_invalid"); return
	if not configuration.is_empty():
		station.merge({"id":configuration.id,"name":configuration.name,"position":configuration.position if configuration.has("position") else world.map_anchor(configuration.anchor),"region_id":configuration.get("region_id","home"),"place_id":configuration.place_id},true)
		activity_rules.seat_offsets=configuration.seat_offsets.duplicate(true)
	var offsets: Array = []
	for offset in activity_rules.seat_offsets:
		if not world.catalog._pair(offset) or offset in offsets: world.error = LocalText.text("system.shared_life.the_camp_seating_settings_are_invalid"); return
		offsets.append(offset)
	for key in ["arrival_timeout", "job_timeout", "host_radius", "decision_timeout"]:
		if not world.catalog._number(activity_rules.get(key)) or activity_rules[key] <= 0 or activity_rules[key] > 600:
			world.error = LocalText.text("system.shared_life.the_camp_activity_time_limits_are_invalid"); return
	for entry in (world.locations.section("mushrooms") if configuration.is_empty() else configuration.get("mushrooms",[])):
		patches[entry.id] = {"id":entry.id,"kind":"mushroom_patch","region_id":station.region_id,"position":entry.position.duplicate(),"amount":4,"ready_at":0.0}

func start(actor_id:String,intent:String,target_id:String="")->Dictionary:
	var work:RefCounted=world.work
	if work.jobs.has(actor_id):return work.fail("busy",LocalText.text("system.shared_life.finish_or_stop_your_current_task_before_coming"))
	var actor:Dictionary=world.actors[actor_id]
	if intent == "forage":
		if not patches.has(target_id): return work.fail("unknown_patch", LocalText.text("system.shared_life.choose_a_mushroom_patch"))
		var patch: Dictionary = patches[target_id]
		if int(patch.amount) <= 0: return work.fail("not_ready", LocalText.text("system.shared_life.these_mushrooms_are_not_ready_yet"))
		if work.claims.has(target_id): return work.fail("claimed", LocalText.text("system.shared_life.a_companion_is_gathering_this_patch"))
		if actor.has("furniture_id"):return work.fail("hands_full",LocalText.text("system.shared_life.store_what_you_are_holding_first"))
		var result: Dictionary = work._begin(actor_id, {"intent": intent, "target_id": target_id, "phase": "life_forage", "time": 0.0}, patch)
		if result.ok: work.claims[target_id] = actor_id
		return result
	if intent=="store":return work.start(actor_id,intent,target_id)
	if target_id != station.id: return work.fail("unknown_station", LocalText.text("system.shared_life.choose_a_barbecue_spot_on_the_grass"))
	return work.fail("retired_action",LocalText.text("system.shared_life.at_the_fire_choose_barbecue_invite_companions_then_start"))

func batch_size() -> int: return int(station.get("batch_size", 2))

func seats()->Array:return fire_seats()
func fire_seats()->Array:
	var result:Array=[]
	for index in range(fireside.config.seat_offsets.size()):
		var offset:Array=fireside.config.seat_offsets[index]
		result.append({"id":station.id+".seat."+str(index),"kind":"seat","region_id":station.region_id,"position":[station.position[0]+offset[0],station.position[1]+offset[1]]})
	return result

func item_count(items: Dictionary) -> int:
	var total := 0
	for amount in items.values(): total += int(amount)
	return total

func advance(delta: float) -> void:
	for patch in patches.values():
		if patch.amount == 0 and float(patch.ready_at) > 0 and Time.get_unix_time_from_system() >= float(patch.ready_at):
			patch.amount = 4; patch.ready_at = 0; world.revision += 1
	fireside.tick(delta)

func tick_job(actor_id: String, job: Dictionary, delta: float) -> void:
	var actor: Dictionary = world.actors[actor_id]
	var work: RefCounted = world.work
	match str(job.phase):
		"life_forage":
			actor.activity = "gathering"; job.time += delta
			if job.time < 2.0: return
			var patch: Dictionary = patches[job.target_id]
			if actor_id!="human" and work.carry_space(actor_id)<int(patch.amount):
				if actor_id=="human":world.deposit_all(actor_id)
				else:job["storage_resume"]="life_forage";job.phase="storage_delivery";world.deliveries.request(actor_id)
				return
			if actor_id=="human":world.storage.add({"mushroom":int(patch.amount)})
			else:actor.carry["mushroom"]=int(actor.carry.get("mushroom",0))+int(patch.amount)
			if actor_id=="human":world.ingredients.note_obtained("mushroom")
			if actor_id!="human" and int(patch.amount)>0:work.visual_event("mushroom_gathered",patch,actor_id)
			patch.amount=0;patch.ready_at=Time.get_unix_time_from_system()+21600
			work.claims.erase(job.target_id)
			if actor_id=="human":
				work._finish(actor_id,LocalText.text("storage.collected"))
			else:job.phase="storage_delivery";world.deliveries.request(actor_id)

func record_meal(event: Dictionary) -> void:
	if self!=world.life:world.life.record_meal(event);return
	memories.append(event)
	if memories.size()>32:memories.pop_front()
	world.memories.sync()

func _event(actor_id: String, message: String) -> void:
	var event := {"id": "life-%s" % world.revision, "actor_id": actor_id, "status": "progress", "message": message}
	if world.shared_activity != null and world.shared_activity.active() and world.shared_activity.life==self: event["shared_activity_id"] = world.shared_activity.session.id
	world.work.events.append(event)
	if world.work.events.size() > 32: world.work.events.pop_front()

func state() -> Dictionary:
	return {"station": station.duplicate(true), "patches": patches.duplicate(true), "memories": memories.duplicate(true)}
