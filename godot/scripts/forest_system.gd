class_name ForestSystem
extends RefCounted
## Original tree anchors regrow; never create wood or place new forest objects.
var _owner: WeakRef
var world: RefCounted:
	get: return _owner.get_ref()
var settings: Dictionary = {}
var clock := Time.get_unix_time_from_system()
var elapsed := 0.0
var blocked: Dictionary = {}

func _init(source: RefCounted) -> void:
	_owner = weakref(source)
	settings = JSON.parse_string(FileAccess.get_file_as_string("res://content/forest.json"))

func cut(tree: Dictionary) -> void:
	clock = maxf(clock, Time.get_unix_time_from_system())
	tree["sprout_at"] = clock + float(settings.sprout_seconds)
	tree["mature_at"] = clock + float(settings.mature_seconds) + spread(tree.id)
	blocked.erase(tree.id)

func spread(id: String) -> float:
	return float(posmod(id.hash(), int(settings.spread_seconds) + 1))

func restore(saved_clock: float = 0.0) -> void:
	clock = maxf(clock, saved_clock)
	blocked.clear()
	for tree in world.objects.values():
		if tree.kind != "tree" or tree.status == "mature": continue
		if not tree.has("sprout_at"):
			# Old saves did not record cutting time. Start recovery now: green shoots
			# immediately, harvestable timber only after a full new growth interval.
			tree["sprout_at"] = clock
			tree["mature_at"] = clock + float(settings.mature_seconds) + spread(tree.id)
	refresh()

func advance(delta: float) -> void:
	clock = maxf(clock + delta, Time.get_unix_time_from_system())
	elapsed += delta
	if elapsed < float(settings.scan_seconds): return
	elapsed = 0.0
	refresh()

func refresh() -> void:
	for tree in world.objects.values():
		if tree.kind != "tree" or tree.status == "mature" or not tree.has("sprout_at"): continue
		if clock < float(tree.sprout_at): continue
		var reason := blocked_reason(tree)
		if not reason.is_empty():
			blocked[tree.id] = reason
			continue
		blocked.erase(tree.id)
		if tree.status == "stump":
			tree.status = "sapling"; tree.health = 0
			world.revision += 1
		if clock < float(tree.mature_at): continue
		tree.status = "mature"; tree.health = 6
		tree.erase("sprout_at"); tree.erase("mature_at")
		world._grids.erase(tree.region_id)
		world.revision += 1

func blocked_reason(tree: Dictionary) -> String:
	var point: Vector2 = world.point(tree)
	var region: Dictionary = world.catalog.regions[tree.region_id]
	if world.Layout.near_road(region.get("layout", {}), point, .9): return "road"
	if not world._terrain_walkable(tree.region_id, point): return "terrain"
	for farm in world.farms.farms.values():
		if world.catalog.rectangle(farm.rect).grow(1).has_point(point): return "farm"
	for object in world.objects.values():
		if object.id == tree.id or object.region_id != tree.region_id: continue
		if object.kind == "construction_site" and Rect2(world.point(object) - world.site_size(object)/2, world.site_size(object)).grow(2).has_point(point): return "house"
	for site in world.leisure.sites.values():
		if site.region_id != tree.region_id: continue
		var art: Dictionary = world.leisure.art(site)
		var size := Vector2(6, 6) if art.is_empty() else Vector2(art.recreation.width, art.recreation.depth)
		if Rect2(world.point(site) - size/2, size).grow(1).has_point(point): return "facility"
	if world.work.claims.has(tree.id): return "working"
	for drop in world.drops.values():
		if drop.region_id == tree.region_id and point.distance_to(world.point(drop)) < 1.2: return "wood_on_ground"
	for actor in world.actors.values():
		if actor.region_id != tree.region_id: continue
		var previous: Vector2 = world.point(actor)
		if point.distance_to(previous) < 1.2: return "resident_nearby"
		# Do not grow an obstacle under a walking actor or on an accepted route.
		for waypoint in world._routes.get(actor.id, []):
			if point.distance_to(Geometry2D.get_closest_point_to_segment(point, previous, waypoint)) < 1.2: return "reserved_route"
			previous = waypoint
	return ""

func describe(tree: Dictionary) -> Dictionary:
	return {"stage": tree.status, "ready_in_seconds": maxf(0, float(tree.get("mature_at", clock))-clock),
		"blocked_by": blocked.get(tree.id, ""), "offline_growth": true}

static func valid_tree(tree: Dictionary, number_check: Callable) -> bool:
	if tree.get("status") not in ["mature", "stump", "sapling"]: return false
	if tree.has("sprout_at") != tree.has("mature_at"): return false
	if tree.has("sprout_at"):
		if not number_check.call(tree.sprout_at) or not number_check.call(tree.mature_at): return false
		if float(tree.sprout_at) < 0 or float(tree.mature_at) <= float(tree.sprout_at) or tree.status == "mature": return false
	elif tree.status == "sapling": return false
	return true
