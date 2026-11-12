extends SceneTree
const Places=preload("res://scripts/map_locations.gd")
const World = preload("res://scripts/world_state.gd")
const Library = preload("res://scripts/character_library.gd")
const Save = preload("res://scripts/save_store.gd")
var checks := 0
var failed := false
var world: RefCounted
var directory: String
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failed = true; push_error(label)
func complete(actor: String) -> void:
	for tick in range(16000):
		if not world.work.jobs.has(actor): return
		if world.work.jobs[actor].get("step") == "seated": return
		world.advance(.15)
	check(false, "job timed out: " + str(world.work.jobs.get(actor)))
func run_job(actor: String, args: Dictionary) -> void:
	var response: Dictionary = world.command(actor, args)
	check(response.ok, "accept " + str(args) + str(response))
	if response.ok: complete(actor)
func wood() -> int:
	var count := 0
	count += world.storage.count("wood")
	for actor in world.actors.values(): count += int(actor.carry.get("wood", 0))
	for drop in world.drops.values(): count += int(drop.wood)
	for site in world.objects.values():
		if site.kind == "construction_site": count += int(site.get("invested", 0)) + int(site.delivered.get("wood", 0))
	for item in world.interior.furniture.values(): count += int(item.invested)
	return count
func _initialize() -> void: call_deferred("run")
func run() -> void:
	directory = OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"): quit(1); return
	world = World.new(); var library := Library.new(); library.configure(directory); world.library = library
	check(not world.command("human", {"intent": "enter", "target_id": "home.house.01"}).ok, "unfinished house rejects entry")
	while wood()<96:
		var trees:Array=[]
		for tree in world.objects.values():
			if tree.kind=="tree" and tree.status=="mature" and int(tree.wood_yield)<=8 and not world.approach_route("codex",tree).is_empty():
				trees.append(tree);break
		if trees.is_empty():world.advance(float(world.forest.settings.mature_seconds)+float(world.forest.settings.spread_seconds)+1);continue
		run_job("codex", {"intent":"chop", "target_id":trees[0].id})
	for i in range(5): run_job("codex", {"intent": "build", "target_id": "home.house.01"})
	var room := "room.home.house.01"
	check(world.interior.rooms().has(room), "completed house exposes stable room")
	run_job("human", {"intent": "enter", "target_id": "home.house.01"})
	check(world.actors.human.region_id == room and world.actors.codex.region_id == "home", "independent resident regions")
	var snapshot: Dictionary = world.observe("human")
	check(snapshot.region.id == room and snapshot.interior.walkable_positions.size() == 192, "room-local read includes floor coordinates")
	check(not world.command("human", {"intent": "chop", "target_id": "home.tree.13"}).ok and not world.command("human", {"intent": "forage", "target_id": "home.mushroom.01"}).ok, "outdoor tasks never target room coordinates")
	check(not world.command("human", {"intent": "furnish", "target_id": "home.house.01", "recipe_id": "table", "x": 13.5, "y": 8}).ok, "entry corridor protected")
	check(not world.command("human", {"intent": "furnish", "target_id": "home.house.01", "recipe_id": "chair", "x": NAN, "y": 3}).ok, "finite placement validation")
	for placement in [["rug",8.5,5.5],["table",8.5,5.5],["chair",6.5,6.5],["chair",10.5,6.5],["table",3.5,2.5],["lamp",12.5,2.5]]:
		run_job("codex", {"intent": "furnish", "target_id": "home.house.01", "recipe_id": placement[0], "x": placement[1], "y": placement[2]})
	check(world.interior.furniture.size() == 6 and wood() == 96, "six real crafted objects conserve harvested wood")
	check(not world.walkable(room, Vector2(8.5,5.5)), "table footprint blocks movement")
	check(not world.command("human", {"intent": "furnish", "target_id": "home.house.01", "recipe_id": "table", "x": 8.5, "y": 5.5}).ok, "overlap rejected before taking materials")
	var chairs: Array = world.interior.furniture.values().filter(func(item): return item.recipe_id == "chair")
	run_job("human", {"intent": "sit", "target_id": chairs[0].id})
	check(not world.command("codex", {"intent": "sit", "target_id": chairs[0].id}).ok, "seat ownership rejects competing resident")
	run_job("codex", {"intent": "sit", "target_id": chairs[1].id})
	check(world.actors.human.activity == "local_rest" and world.actors.codex.activity == "local_rest" and world.interior.memories.size() == 1, "two residents can actually sit together")
	check(not world.command("human", {"intent": "pickup_furniture", "target_id": chairs[1].id}).ok, "occupied furniture cannot be moved")
	world.command("human", {"intent": "stop"}); world.command("codex", {"intent": "stop"})
	check(not world.work.claims.has(chairs[0].id), "standing releases seat")
	run_job("human", {"intent": "rotate_furniture", "target_id": chairs[0].id, "facing": "up"})
	check(world.interior.furniture[chairs[0].id].facing == "up", "physical rotation updates facing")
	run_job("human", {"intent": "pickup_furniture", "target_id": chairs[0].id})
	check(world.loaded("human") and wood() == 96, "pickup carries same invested object")
	check(not world.command("human", {"intent": "take", "target_id": "home.chest.01"}).ok, "cannot load materials while carrying furniture")
	check(Save.save_world(world, directory), "save while furniture carried")
	var restored := World.new(); restored.library = library
	check(Save.load_world(restored, directory).ok, "schema4 indoor save loads")
	world = restored
	check(world.actors.human.region_id == room and world.actors.human.get("furniture_id") == chairs[0].id and world.work.jobs.is_empty() and wood() == 96, "reload preserves region object and all materials, stops jobs")
	run_job("human", {"intent": "place_furniture", "x": 6.5, "y": 6.5})
	var chest: Dictionary = world.interior.furniture.values().filter(func(item): return item.recipe_id == "table")[1]
	var stored:int=world.storage.count("wood")
	check(world.storage.take({"wood":2}).ok,"warehouse withdrawal is atomic indoors")
	world.actors.human.carry["wood"]=2
	check(world.deposit_all("human").ok and world.storage.count("wood")==stored and wood()==96,"indoor deposit uses same global ledger without hauling")
	run_job("human", {"intent": "exit"})
	# Cancel during supply, then during transport of completed furniture.
	check(world.command("codex", {"intent": "furnish", "target_id": "home.house.01", "recipe_id": "lamp", "x": 4.5, "y": 7.5}).ok, "start cancellable craft")
	for i in range(16000):
		world.advance(.1)
		if world.actors.codex.has("furniture_id"): break
	world.command("codex", {"intent": "stop"})
	check(wood() == 96 and world.actors.codex.has("furniture_id"), "cancel supply leaves wood in hands")
	run_job("codex", {"intent": "place_furniture", "x": 3.5, "y": 7.5})
	check(world.command("codex", {"intent": "furnish", "target_id": "home.house.01", "recipe_id": "lamp", "x": 4.5, "y": 7.5}).ok, "restart intentional craft")
	check(not world.command("human", {"intent": "furnish", "target_id": "home.house.01", "recipe_id": "chair", "x": 4.5, "y": 7.5}).ok, "concurrent destination reservation")
	var observed: Dictionary = world.observe("codex")
	check(not observed.self.job.candidate.has("artwork") and not observed.jobs.codex.reservation.has("artwork"), "model task snapshots omit raster pixel payloads")
	for i in range(16000):
		world.advance(.1)
		if world.actors.codex.has("furniture_id"): break
	world.command("codex", {"intent": "stop"})
	check(wood() == 96 and world.actors.codex.has("furniture_id"), "cancel crafted transport preserves exact item")
	check(Save.save_world(world, directory), "save cancelled transport")
	var later := World.new(); later.library = library
	check(Save.load_world(later, directory).ok, "cancelled transport reloads")
	world = later; check(wood() == 96, "all materials conserved after second reload")
	# Reject a corrupted object without overwriting the file; recoverable backup made.
	var path := directory.path_join("island-v2.json")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path)); data.interior.furniture[chest.id].position = Places.pair("p_13_5_8_0")
	var file := FileAccess.open(path,FileAccess.WRITE); file.store_string(JSON.stringify(data)); file.close()
	var bad := World.new(); var rejected: Dictionary = Save.load_world(bad,directory)
	check(not rejected.ok and FileAccess.file_exists(rejected.backup), "invalid doorway placement retained in recovery copy")
	var old_world := World.new(); var old_dir := directory.path_join("legacy")
	Save.save_world(old_world, old_dir)
	var old_path := old_dir.path_join("island-v2.json")
	var old_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(old_path)); old_data.schema_version = 3; old_data.erase("interior")
	var old_file := FileAccess.open(old_path, FileAccess.WRITE); old_file.store_string(JSON.stringify(old_data)); old_file.close()
	check(Save.load_world(old_world, old_dir).ok and old_world.interior.furniture.is_empty(), "schema3 upgrades without fabricating furniture")
	print("Interior checks: %s" % checks)
	quit(1 if failed else 0)
