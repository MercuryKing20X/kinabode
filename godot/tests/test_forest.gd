extends SceneTree
const World = preload("res://scripts/world_state.gd")
const Save = preload("res://scripts/save_store.gd")
var checks := 0
var failed := false
var world: RefCounted
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failed = true; push_error(label)
func wood() -> int:
	var total := 0
	for item in [{"id":"storage","items":world.storage.saved().items,"capacity":9007199254740991,"kind":"storage"}]: total += int(item.items.get("wood", 0))
	for actor in world.actors.values(): total += int(actor.carry.get("wood", 0))
	for drop in world.drops.values(): total += int(drop.wood)
	return total
func harvest(id: String) -> void:
	var result: Dictionary = world.command("codex", {"intent": "chop", "target_id": id})
	check(result.ok, "regrown tree accepted through ordinary rules")
	for i in range(8000):
		if not world.work.jobs.has("codex") and not world.deliveries.active("codex"): break
		world.advance(.1)
	check(not world.work.jobs.has("codex") and world.drops.is_empty(), "physical chopping and hauling completes")

func run() -> void:
	var directory := OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"): quit(1); return
	world = World.new(); world.director.set_all_enabled(false)
	var tree: Dictionary = {}
	for candidate in world.objects.values():
		if candidate.kind == "tree" and world.forest.blocked_reason(candidate).is_empty(): tree = candidate; break
	check(not tree.is_empty(), "available original forest anchor")
	if tree.is_empty(): quit(1); return
	var objects_before: int = world.objects.size()
	harvest(tree.id)
	check(wood() == 3 and tree.status == "stump", "first harvest generates exactly three physical wood")
	check(tree.mature_at > tree.sprout_at and tree.sprout_at > world.forest.clock, "fresh stump has delayed sprout and maturity")
	world.forest.clock = float(tree.sprout_at) + 1
	world.forest.refresh()
	check(tree.status == "sapling" and world.walkable("home", world.point(tree)), "green sapling is nonblocking")
	check(world.command("codex", {"intent": "chop", "target_id": tree.id}).error == "tree_growing", "sapling yields no early wood")
	world.forest.clock = float(tree.mature_at) + 1
	var human_position: Array = world.actors.human.position.duplicate()
	world.actors.human.position = tree.position.duplicate()
	world.forest.refresh()
	check(tree.status == "sapling" and world.forest.blocked[tree.id] == "resident_nearby", "no trunk grows under resident")
	world.actors.human.position = human_position
	world._routes.human = [world.point(tree)]
	world.forest.refresh()
	check(tree.status == "sapling" and world.forest.blocked[tree.id] == "reserved_route", "accepted path stays clear")
	world._routes.clear()
	var old_wood := {"id": "drop."+tree.id, "region_id": "home", "position": tree.position.duplicate(), "wood": 2}
	world.drops[old_wood.id] = old_wood
	world.forest.refresh()
	check(tree.status == "sapling" and world.drops[old_wood.id].wood == 2, "remaining logs cannot be overwritten by another harvest")
	world.drops.clear()
	world.catalog.regions.home.layout.roads.append({"points": [tree.position, [tree.position[0]+3,tree.position[1]]], "width": 1})
	world.forest.refresh()
	check(tree.status == "sapling" and world.forest.blocked[tree.id] == "road", "roads suppress regrowth")
	world.catalog.regions.home.layout.roads.pop_back()
	var farm_rect: Array = world.farms.farms["farm.home"].rect.duplicate()
	world.farms.farms["farm.home"].rect = [tree.position[0]-2, tree.position[1]-2, 4, 4]
	world.forest.refresh()
	check(tree.status == "sapling" and world.forest.blocked[tree.id] == "farm", "whole farming zone stays reserved")
	world.farms.farms["farm.home"].rect = farm_rect
	var house: Dictionary = world.objects["home.house.01"]
	var house_position: Array = house.position.duplicate()
	house.position = tree.position.duplicate(); world.forest.refresh()
	check(tree.status == "sapling" and world.forest.blocked[tree.id] == "house", "unbuilt house plot also stays reserved")
	house.position = house_position
	world._grids.home = AStarGrid2D.new()
	world.forest.refresh()
	check(tree.status == "mature" and tree.health == 6 and not world._grids.has("home"), "maturity restores health and invalidates navigation cache")
	check(not world.walkable("home", world.point(tree)) and wood() == 3 and world.objects.size() == objects_before, "mature trunk collides without spawning wood or new objects")
	harvest(tree.id)
	check(wood() == 6 and world.actors.codex.carry.is_empty(), "same tree can supply a second real harvest with conserved bundles")
	check(Save.save_world(world, directory), "growth timestamps saved")
	var reload: RefCounted = World.new()
	check(Save.load_world(reload, directory).ok and absf(float(reload.objects[tree.id].mature_at)-float(tree.mature_at)) < .01, "reload preserves deadline without resetting timer")
	var offline: RefCounted = World.new(); offline.forest.clock = float(tree.mature_at)+1
	check(Save.load_world(offline, directory).ok and offline.objects[tree.id].status == "mature", "offline growth reaches one maturity without harvest")
	check([{"id":"storage","items":offline.storage.saved().items,"capacity":9007199254740991,"kind":"storage"}].reduce(func(total,item): return total+int(item.items.get("wood",0)),0) == 6, "offline growth does not add inventory")
	var path := directory.path_join("island-v2.json")
	var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	old.erase("ecology_version"); old.erase("forest_clock"); old.erase("day_cycle")
	old.objects[tree.id].erase("sprout_at"); old.objects[tree.id].erase("mature_at")
	var file := FileAccess.open(path, FileAccess.WRITE); file.store_string(JSON.stringify(old)); file.close()
	var legacy: RefCounted = World.new()
	check(Save.load_world(legacy, directory).ok and legacy.objects[tree.id].status == "sapling", "old bare forest gains shoots without resetting save")
	check(legacy.objects[tree.id].mature_at > legacy.forest.clock and legacy.world_id == world.world_id, "legacy shoots still need full maturation and retain world identity")
	var deadline: float = legacy.objects[tree.id].mature_at
	legacy.forest.restore()
	check(legacy.objects[tree.id].mature_at == deadline, "migration is idempotent")
	old.objects[tree.id]["sprout_at"] = 100
	old.objects[tree.id]["mature_at"] = 90
	file = FileAccess.open(path, FileAccess.WRITE); file.store_string(JSON.stringify(old)); file.close()
	var invalid: RefCounted = World.new(); var invalid_result: Dictionary = Save.load_world(invalid, directory)
	check(not invalid_result.ok and FileAccess.file_exists(invalid_result.backup), "invalid growth timestamps preserve recoverable save")
	print("Forest regrowth: %s checks" % checks)
	quit(1 if failed else 0)
