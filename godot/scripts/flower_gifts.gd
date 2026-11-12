class_name FlowerGifts
extends RefCounted
## Cosmetic roadside gesture. Owns no item, drop, crop, job or model connection.
const Layout = preload("res://scripts/home_layout.gd")
var _owner: WeakRef
var world: RefCounted:
	get: return _owner.get_ref()
var config: Dictionary
var patches: Array[Dictionary] = []
var active: Dictionary = {}
var cooldowns: Dictionary = {}
var next_gift_at := 0.0

func _init(owner_world: RefCounted) -> void:
	_owner = weakref(owner_world)
	config = JSON.parse_string(FileAccess.get_file_as_string("res://content/companions/local-life.json")).flower_gift
	next_gift_at = float(config.first_after)
	_prepare_patches()

func _prepare_patches() -> void:
	var roads: Array = world.catalog.regions.home.layout.roads
	for road_index in range(roads.size()):
		var road: Dictionary = roads[road_index]
		var path := Layout.points(road.points)
		for segment in range(path.size()-1):
			var direction := (path[segment+1]-path[segment]).normalized()
			var normal := Vector2(-direction.y,direction.x)
			var count := maxi(1, int(path[segment].distance_to(path[segment+1]) / 6.0))
			for step in range(count):
				var side := 1 if (road_index+segment+step)%2 == 0 else -1
				var point := path[segment].lerp(path[segment+1], (step+.5)/count) + normal * (float(road.width)+1.0) * side
				var map_layout:Dictionary=world.catalog.regions.home.layout
				if map_layout.get("ground_art",{}).has("formal_plaza") and world.catalog.rectangle(map_layout.plaza).has_point(point):continue
				if world.catalog.regions.home.layout.get("dock_surfaces",[]).any(func(dock):return Geometry2D.is_point_in_polygon(point,Layout.points(dock.polygon))):continue
				if Layout.near_road(world.catalog.regions.home.layout, point, .45) or not world.walkable("home",point): continue
				if world.farms.farms.values().any(func(farm): return world.farms.bounds(farm).grow(1.2).has_point(point)): continue
				if patches.any(func(patch): return patch.point.distance_to(point)<3.5): continue
				patches.append({"id":"roadside.%s.%s.%s"%[road_index,segment,step], "point":point})

func eligible(id: String) -> bool:
	if not active.is_empty() or world.director.time < next_gift_at or world.director.time < float(cooldowns.get(id,0)): return false
	var actor: Dictionary = world.actors[id]
	var human: Dictionary = world.actors.human
	return actor.region_id == "home" and human.region_id == "home" and not world.loaded(id) and world.point(actor).distance_to(world.point(human)) <= float(config.notice_radius)

func start(routine: RefCounted) -> bool:
	if not routine.enabled or routine.blocked() or not eligible(routine.ID): return false
	var candidates: Array = patches.filter(func(patch):
		return world.point(world.actors[routine.ID]).distance_to(patch.point) <= float(config.flower_radius) and world.point(world.actors.human).distance_to(patch.point) <= float(config.notice_radius) and world.walkable("home",patch.point))
	candidates.sort_custom(func(a,b):return world.point(world.actors[routine.ID]).distance_squared_to(a.point)<world.point(world.actors[routine.ID]).distance_squared_to(b.point))
	var attempts := 0
	for patch in candidates:
		# Approach from above or the side: hands and flower stay visible at the feet.
		for offset in [Vector2(0,-.8),Vector2(-.8,0),Vector2(.8,0)]:
			attempts += 1
			if attempts > 6: break
			var destination: Vector2 = patch.point + offset
			if not routine._move_to(destination): continue
			active = {"actor_id":routine.ID,"phase":"approach","elapsed":0.0,"total":0.0,"patch_id":patch.id,"patch":patch.point,"destination":destination,"repaths":0,"delivered":false}
			cooldowns[routine.ID] = world.director.time + routine.decision_rng.randf_range(config.cooldown[0],config.cooldown[1])
			return true
		if attempts > 6: break
	next_gift_at = world.director.time + float(config.failed_retry)
	return false

func cancel(id: String) -> void:
	if active.get("actor_id") != id: return
	active.clear()
	next_gift_at = maxf(next_gift_at, world.director.time + float(config.village_interval))

func presentation(id: String) -> Dictionary:
	if active.get("actor_id") != id: return {}
	return {"phase":active.phase,"carrying":active.phase in ["bringing","offering"],
		"progress":clampf(float(active.elapsed) / float(config.pick_seconds if active.phase == "picking" else config.offer_seconds),0,1),
		"delivered":active.delivered}

func _phase(routine: RefCounted, phase: String, activity: String) -> void:
	active.phase = phase; active.elapsed = 0.0
	world.actors[routine.ID].activity = activity
	world.revision += 1

func _bring_to_player(routine: RefCounted) -> bool:
	var human: Vector2 = world.point(world.actors.human)
	var actor: Vector2 = world.point(world.actors[routine.ID])
	var offsets: Array[Vector2] = [Vector2(-1.8,0),Vector2(1.8,0),Vector2(0,-1.8),Vector2(0,1.8),Vector2(-1.4,-1.4),Vector2(1.4,-1.4)]
	offsets.sort_custom(func(a,b):return (human+a).distance_squared_to(actor)<(human+b).distance_squared_to(actor))
	for offset in offsets:
		if routine._move_to(human+offset):
			active.destination = human+offset
			_phase(routine,"bringing","walking")
			return true
	return false

func advance(routine: RefCounted, delta: float) -> void:
	if active.get("actor_id") != routine.ID: routine.interrupt(8); return
	active.elapsed += delta; active.total += delta
	var actor: Dictionary = world.actors[routine.ID]
	var human: Dictionary = world.actors.human
	if actor.region_id != "home" or human.region_id != "home" or world.point(actor).distance_to(world.point(human)) > float(config.notice_radius) or active.total > float(config.timeout):
		routine.interrupt(12); return
	if active.phase in ["approach","bringing"]:
		if world._routes.has(routine.ID): return
		routine.owns_route = false
		if world.point(actor).distance_to(active.destination) > .45:
			routine.interrupt(12); return
		if active.phase == "approach":
			if not world.walkable("home",active.patch): routine.interrupt(12); return
			routine._face(active.patch)
			_phase(routine,"picking","local_pick_flower")
		elif world.point(actor).distance_to(world.point(human)) > float(config.offer_radius):
			if int(active.repaths) >= 2: routine.interrupt(12); return
			active.repaths += 1
			if not _bring_to_player(routine): routine.interrupt(12)
		else:
			routine._face_human()
			_phase(routine,"offering","local_offer_flower")
	elif active.phase == "picking":
		if active.elapsed >= float(config.pick_seconds) and not _bring_to_player(routine): routine.interrupt(12)
	elif active.phase == "offering":
		if world.point(actor).distance_to(world.point(human)) > float(config.offer_radius): routine.interrupt(12); return
		routine._face_human()
		if not active.delivered and active.elapsed >= float(config.offer_seconds) * .25:
			active.delivered = true
			routine._speak("flower_gift")
		if active.elapsed >= float(config.offer_seconds): routine.interrupt(8)
