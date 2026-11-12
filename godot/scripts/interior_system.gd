class_name HouseInterior
extends RefCounted
const LocalText=preload("res://scripts/localization.gd")

const FLOOR := Rect2(1, 1, 24, 8)
const DOOR := Vector2(13.5, 8.5)
const ENTRY := Rect2(12, 7, 3, 2)
var RECIPES := {
	"table": {"name": LocalText.source("system.interior_system.oak_table"), "wood": 6, "size": [2, 2]},
	"chair": {"name": LocalText.source("system.interior_system.cushioned_chair"), "wood": 3, "size": [1, 1]},
	"rug": {"name": LocalText.source("system.interior_system.woven_wood_mat"), "wood": 2, "size": [3, 2]},
	"lamp": {"name": LocalText.source("system.interior_system.warm_wooden_lamp"), "wood": 3, "size": [1, 1]}}
var _owner: WeakRef
var world: RefCounted:
	get: return _owner.get_ref()
var furniture: Dictionary = {}
var serial := 0
var memories: Array = []

func _init(owner_world: RefCounted) -> void: _owner = weakref(owner_world)

func rooms() -> Dictionary:
	var result := {}
	for site in world.objects.values():
		if site.kind != "construction_site" or int(site.get("stage_index", 0)) != 5: continue
		var id := "room." + str(site.id)
		result[id] = {"id": id, "name": site.name + LocalText.text("system.interior_system.indoors"), "site_id": site.id, "origin": [0, 0], "size": [26, 10], "zones": [{"id": id + ".living", "name": LocalText.text("system.interior_system.living_room"), "rect": [1, 1, 24, 8]}], "door": [DOOR.x, DOOR.y], "coordinate_system": "independent room-local tile coordinates"}
	for room in result.values():
		room["owner_id"]=world.objects[room.site_id].get("owner_id","")
	return result

func room_for(site_id: String) -> String: return "room." + site_id
func door(room_id: String) -> Vector2: return DOOR
func outside(room_id: String) -> Vector2:
	var site: Dictionary = world.objects[rooms()[room_id].site_id]
	return world.point(site) + Vector2(0, world.site_size(site).y / 2 + 1.5)

func in_bounds(p: Vector2) -> bool: return FLOOR.has_point(p)
func area(item: Dictionary) -> Rect2:
	var size: Array = RECIPES[item.recipe_id].size
	return Rect2(world.point(item) - Vector2(size[0], size[1]) / 2, Vector2(size[0], size[1]))
func solid(item: Dictionary) -> bool: return item.recipe_id not in ["rug", "chair"]
func placed(item: Dictionary) -> bool: return str(item.get("holder_id", "")).is_empty()
func walkable(region: String, p: Vector2, extra: Dictionary = {}, exclude: String = "") -> bool:
	if not in_bounds(p): return false
	for item in furniture.values():
		if item.id != exclude and placed(item) and item.region_id == region and solid(item) and area(item).has_point(p): return false
	return extra.is_empty() or not solid(extra) or not area(extra).has_point(p)

func placement(region: String, candidate: Dictionary, exclude: String = "", check_actors: bool = true) -> bool:
	if not rooms().has(region): return false
	var box := area(candidate)
	if not FLOOR.encloses(box): return false
	# Keep the full entry strip clear, including rugs, and reject furniture overlap.
	if box.intersects(ENTRY): return false
	for item in furniture.values():
		if item.id == exclude or not placed(item) or item.region_id != region: continue
		if candidate.recipe_id != "rug" and item.recipe_id != "rug" and box.intersects(area(item)): return false
		if candidate.recipe_id == "rug" and item.recipe_id == "rug" and box.intersects(area(item)): return false
	for job in world.work.jobs.values():
		if job.get("intent") == "furnish" and job.get("reservation", {}).get("region_id") == region and job.get("furniture_id", "") != exclude:
			var other: Dictionary = job.reservation
			if candidate.recipe_id != "rug" and other.recipe_id != "rug" and box.intersects(area(other)): return false
	if check_actors and solid(candidate):
		for actor in world.actors.values():
			if actor.region_id == region and box.has_point(world.point(actor)): return false
	if solid(candidate):
		for actor_id in world._routes:
			if world.actors[actor_id].region_id != region: continue
			for point in world._routes[actor_id]:
				if box.has_point(point): return false
	# Flood from the door: never partition the remaining walkable floor.
	var seen := {}; var queue: Array[Vector2i] = [Vector2i(DOOR.floor())]; seen[queue[0]] = true
	var index := 0
	while index < queue.size():
		var cell: Vector2i = queue[index]; index += 1
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + offset
			if not seen.has(next) and walkable(region, Vector2(next) + Vector2(.5, .5), candidate, exclude): seen[next] = true; queue.append(next)
	for y in range(1, 9):
		for x in range(1, 25):
			if walkable(region, Vector2(x + .5, y + .5), candidate, exclude) and not seen.has(Vector2i(x, y)): return false
	return true

func state(region: String) -> Dictionary:
	var entries: Array = []
	for item in furniture.values():
		if item.region_id != region or not placed(item): continue
		var copy: Dictionary = item.duplicate(true); copy.erase("artwork"); copy["occupant_id"] = world.work.claims.get(item.id, ""); entries.append(copy)
	var floor_cells: Array = []
	if rooms().has(region):
		for y in range(1, 9):
			for x in range(1, 25):
				if walkable(region, Vector2(x + .5, y + .5)): floor_cells.append([x + .5, y + .5])
	return {"furniture": entries, "recipes": RECIPES.duplicate(true), "walkable_positions": floor_cells, "memories": memories.duplicate(true)}

func start(actor_id: String, args: Dictionary) -> Dictionary:
	var intent := str(args.intent); var actor: Dictionary = world.actors[actor_id]
	if intent=="take":return world._error("retired_storage_action")
	if world.work.jobs.has(actor_id): return world.work.fail("busy", LocalText.text("system.interior_system.finish_your_current_action_or_press_stop"))
	var allowed: Array = ["intent"]
	if intent in ["enter", "sit", "pickup_furniture", "take"]: allowed.append("target_id")
	if intent == "rotate_furniture": allowed += ["target_id", "facing"]
	if intent == "furnish": allowed += ["target_id", "recipe_id", "x", "y", "facing"]
	if intent == "place_furniture": allowed += ["x", "y", "facing"]
	for key in args:
		if key not in allowed: return world._error("invalid_command")
	var job := {"intent": intent, "phase": "house_work", "step": intent, "time": 0.0, "target_id": str(args.get("target_id", ""))}
	if intent == "enter":
		job["room_id"] = room_for(job.target_id)
		if not rooms().has(job.room_id): return world.work.fail("unfinished_house", LocalText.text("system.interior_system.finish_the_house_before_moving_in"))
	elif intent == "exit":
		if not rooms().has(actor.region_id): return world.work.fail("already_outside", LocalText.text("system.interior_system.you_are_already_outside"))
		job["room_id"] = actor.region_id
	elif intent in ["furnish", "place_furniture"]:
		if not world.catalog._number(args.get("x")) or not world.catalog._number(args.get("y")): return world._error("invalid_position")
		if str(args.get("facing", "down")) not in ["up", "down"]: return world._error("invalid_facing")
		var item: Dictionary
		if intent == "furnish":
			var recipe := str(args.get("recipe_id", ""))
			if not RECIPES.has(recipe): return world._error("unknown_recipe")
			if actor.has("furniture_id"): return world.work.fail("hands_full", LocalText.text("system.interior_system.put_down_what_you_are_holding_first"))
			# Existing furniture carry validation remains strict. The material debit can
			# empty the held wood; otherwise ask for the instant warehouse deposit.
			var after_cost:Dictionary=actor.carry.duplicate(true)
			after_cost["wood"]=maxi(0,int(after_cost.get("wood",0))-int(RECIPES[recipe].wood))
			if int(after_cost.wood)==0:after_cost.erase("wood")
			if after_cost.keys().any(func(k):return not (actor.get("pocketed",false) and world.pocket_item(str(k)))):return world.work.fail("hands_full",LocalText.text("storage.deposit_before_furniture"))
			if furniture.size() >= 64: return world.work.fail("furniture_limit", LocalText.text("system.interior_system.place_the_furniture_you_already_made_first"))
			var region := room_for(job.target_id)
			if not rooms().has(region): return world.work.fail("unfinished_house", LocalText.text("system.interior_system.finish_building_the_house_first"))
			if int(world.available_items(actor_id).get("wood",0)) < RECIPES[recipe].wood: return world._error("missing_materials")
			serial += 1
			item = {"id": "furniture.%s" % serial, "kind": "furniture", "recipe_id": recipe, "name": RECIPES[recipe].name, "region_id": region, "position": [args.x, args.y], "facing": args.get("facing", "down"), "holder_id": "", "invested": RECIPES[recipe].wood, "items": {}, "capacity": 0, "artwork": {}}
			if world.library != null: item.artwork = world.library.artworks["furniture-" + recipe].duplicate(true)
			job.step = "supply"; job["reservation"] = item.duplicate(true)
		else:
			var id := str(actor.get("furniture_id", ""))
			if not furniture.has(id): return world.work.fail("empty_hands", LocalText.text("system.interior_system.you_are_not_holding_any_furniture"))
			item = furniture[id].duplicate(true); item.position = [args.x, args.y]; item.region_id = actor.region_id; item.facing = args.get("facing", "down")
			job.step = "place"
		if not placement(item.region_id, item, item.id): return world.work.fail("invalid_placement", LocalText.text("system.interior_system.it_will_not_fit_here_or_it_would_block"))
		job["candidate"] = item; job["furniture_id"] = item.id; job["room_id"] = item.region_id
	elif intent in ["sit", "pickup_furniture", "rotate_furniture"]:
		if not furniture.has(job.target_id) and not (intent == "take" and world.objects.has(job.target_id)): return world._error("unknown_furniture")
		var item: Dictionary = world.object_by_id(job.target_id)
		if not placed(item): return world.work.fail("being_carried", LocalText.text("system.interior_system.the_furniture_is_being_carried"))
		if world.work.claims.has(job.target_id): return world.work.fail("claimed", LocalText.text("system.interior_system.a_companion_is_using_it"))
		if world.loaded(actor_id): return world.work.fail("hands_full", LocalText.text("system.interior_system.put_down_what_you_are_holding_first"))
		if intent == "sit" and item.get("recipe_id") != "chair": return world._error("not_a_chair")
		if intent in ["pickup_furniture", "rotate_furniture"] and item.region_id != actor.region_id: return world._error("different_region")
		if intent == "rotate_furniture":
			if args.get("facing") not in ["up", "down"]: return world._error("invalid_facing")
			job["facing"] = args.facing
		world.work.claims[job.target_id] = actor_id
	else: return world._error("unsupported_action")
	world.work.serial += 1; job["id"] = "job-%s" % world.work.serial
	world.work.jobs[actor_id] = job; world._routes.erase(actor_id); world.revision += 1
	return {"ok": true, "status": "accepted", "job_id": job.id, "message": LocalText.text("system.interior_system.here_we_go")}

func _arrive(actor_id: String, region: String, destination: Vector2) -> bool:
	var actor: Dictionary = world.actors[actor_id]; var current := str(actor.region_id)
	if current != region:
		if rooms().has(current):
			if world.point(actor).distance_to(door(current)) > .1:
				if not world.route_to(actor_id, door(current)): world.work._finish(actor_id, LocalText.text("system.interior_system.the_doorway_is_blocked_for_now"), false)
				return false
			var landing := outside(current)
			var outside_region:String=world.objects[rooms()[current].site_id].region_id
			if not world.walkable(outside_region, landing): world.work._finish(actor_id, LocalText.text("system.interior_system.the_outside_doorway_is_blocked"), false); return false
			actor.region_id = outside_region; actor.position = [landing.x, landing.y]; world.revision += 1
			return false
		if not rooms().has(region): world.work._finish(actor_id, LocalText.text("system.interior_system.this_room_cannot_be_found"), false); return false
		var site_region:String=world.objects[rooms()[region].site_id].region_id
		if actor.region_id!=site_region:world.work._finish(actor_id, LocalText.text("system.interior_system.the_house_entrance_cannot_be_reached"),false);return false
		var entrance := outside(region)
		if world.point(actor).distance_to(entrance) > .1:
			if not world.route_to(actor_id, entrance): world.work._finish(actor_id, LocalText.text("system.interior_system.the_house_entrance_cannot_be_reached"), false)
			return false
		actor.region_id = region; actor.position = [door(region).x, door(region).y]; world.revision += 1
		return false
	if world.point(actor).distance_to(destination) <= .1: return true
	if not world.route_to(actor_id, destination): world.work._finish(actor_id, LocalText.text("system.interior_system.the_way_is_blocked_for_now_you_keep_your"), false)
	return false

func _beside(item: Dictionary) -> Vector2:
	var box := area(item) if item.has("recipe_id") else Rect2(world.point(item) - Vector2.ONE, Vector2(2, 2))
	for p in [Vector2(box.get_center().x, box.end.y + .6), Vector2(box.position.x - .6, box.get_center().y), Vector2(box.end.x + .6, box.get_center().y), Vector2(box.get_center().x, box.position.y - .6)]:
		if world.walkable(item.region_id, p): return p
	return Vector2(-100, -100)

func tick_job(actor_id: String, job: Dictionary, delta: float) -> void:
	var actor: Dictionary = world.actors[actor_id]
	match job.step:
		"enter":
			if _arrive(actor_id, job.room_id, door(job.room_id)): world.work._finish(actor_id, LocalText.text("system.interior_system.inside_at_last"))
		"exit":
			if _arrive(actor_id, "home", outside(job.room_id)): world.work._finish(actor_id, LocalText.text("system.interior_system.back_in_the_yard"))
		"supply":
			if not world.pay_costs(actor_id,{"wood":int(job.candidate.invested)}).ok:world.work._finish(actor_id,LocalText.text("system.interior_system.not_enough_materials_existing_materials_are_kept"),false);return
			var item:Dictionary=job.candidate.duplicate(true)
			item.holder_id=actor_id;furniture[item.id]=item;actor["furniture_id"]=item.id
			job.step="craft"
		"craft":
			if not _arrive(actor_id, "home", outside(job.room_id)): return
			actor.activity = "building"; job.time += delta
			if job.time < 3: return
			var item: Dictionary = job.candidate.duplicate(true)
			actor["furniture_id"] = item.id; item.holder_id = actor_id
			furniture[item.id] = item; job.step = "place"
		"place":
			var candidate: Dictionary = job.candidate
			if not _arrive(actor_id, job.room_id, _beside(candidate)): return
			if not world.work.handle_bundle(actor, job, candidate, delta, "putting_down"): return
			# Ignore our own reservation; all other placements and residents rechecked at commit.
			job.erase("reservation")
			if not placement(job.room_id, candidate, candidate.id): world.work._finish(actor_id, LocalText.text("system.interior_system.this_spot_is_occupied_you_keep_the_furniture_choose"), false); return
			candidate.holder_id = ""; furniture[candidate.id] = candidate.duplicate(true); actor.erase("furniture_id")
			world._grids.erase(job.room_id); world.work._finish(actor_id, LocalText.content(str(candidate.name)) + " " + LocalText.text("system.interior_system.placed"))
		"sit", "pickup_furniture", "rotate_furniture":
			var item: Dictionary = world.object_by_id(job.target_id)
			var destination: Vector2 = world.point(item) if job.step == "sit" else _beside(item)
			if not _arrive(actor_id, item.region_id, destination): return
			if not world.work.handle_bundle(actor, job, item, delta, "sitting_down" if job.step == "sit" else "picking_up"): return
			if job.step == "sit":
				actor.facing = item.facing; actor.activity = "local_rest"; job.step = "seated"; _record_together(actor_id, item.region_id)
			elif job.step == "pickup_furniture":
				item.holder_id = actor_id; actor["furniture_id"] = item.id; world._grids.erase(item.region_id); world.work._finish(actor_id, LocalText.text("system.interior_system.picked_up_choose_an_empty_spot_in_the_room"))
			elif job.step == "rotate_furniture": item.facing = job.facing; world.work._finish(actor_id, LocalText.text("system.interior_system.turned_around"))
		"seated": actor.activity = "local_rest"

func _record_together(actor_id: String, region: String) -> void:
	for other in world.work.jobs:
		if other != actor_id and world.actors[other].region_id == region and world.work.jobs[other].get("step") == "seated":
			memories.append({"event_id":Crypto.new().generate_random_bytes(12).hex_encode(), "kind": "sat_together", "actors": [other, actor_id], "room_id": region, "at": Time.get_unix_time_from_system()})
			if memories.size() > 32: memories.pop_front()
			world.memories.sync()
			return
