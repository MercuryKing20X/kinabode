extends SceneTree
const Places=preload("res://scripts/map_locations.gd")
const World = preload("res://scripts/world_state.gd")
const Save = preload("res://scripts/save_store.gd")
const Library = preload("res://scripts/character_library.gd")
const HomePanel = preload("res://scripts/house_panel.gd")
var checks := 0
var failed := false
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failed = true; push_error(message)
func finish(world: RefCounted, actor: String) -> void:
	for i in range(8000):
		if not world.work.jobs.has(actor) and not world._routes.has(actor): return
		world.advance(.1)
	check(false, "task timeout")
func area(points: Array) -> float:
	var total := 0.0
	for i in range(points.size()):
		var a: Array = points[i]; var b: Array = points[(i + 1) % points.size()]
		total += a[0] * b[1] - b[0] * a[1]
	return absf(total) / 2
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var directory := OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"): quit(1); return
	var world := World.new(); var library := Library.new(); library.configure(directory); world.library = library
	check(world.error.is_empty(), "expanded content validates")
	check(area(world.catalog.regions.home.land) > area(world.catalog.regions.home.legacy_land) * 2.5, "real walkable land expands beyond2.5x")
	check(world.catalog.regions.home.size == [160.0, 128.0], "larger region bounds")
	var reachable := true
	for landmark in world.catalog.regions.home.layout.landmarks:
		var result: Dictionary = world.command("human", {"intent": "move", "x": landmark.position[0], "y": landmark.position[1]})
		reachable = reachable and result.ok
		if result.ok: finish(world, "human")
	check(reachable, "every planned landmark reached using real routing")
	check(not world.command("human", {"intent": "move", "x":Places.point("p_113_0_81_0").x,"y":Places.point("p_113_0_81_0").y}).ok, "pond water blocks walking")
	check(world.command("human", {"intent": "move", "x":Places.point("p_123_0_81_0").x,"y":Places.point("p_123_0_81_0").y}).ok, "route around pond")
	var dry := true
	for i in range(8000):
		world.advance(.05)
		dry = dry and world.walkable("home", world.point(world.actors.human))
		if not world._routes.has("human"): break
	check(dry, "pond detour never steps in water")
	check(world.walkable("home", Places.point("p_43_56")) and not world.walkable("home", Places.point("p_43_52")), "gate and fence share actual collision geometry")
	check(world.command("human", {"intent": "move", "x":Places.point("p_38_55").x,"y":Places.point("p_38_55").y}).ok, "garden entry reachable")
	finish(world, "human")
	check(world.point(world.actors.human).distance_to(Places.point("p_38_55")) < .001, "arrive in garden through gate")
	check(library.valid(library.artworks["cottage-blue"]), "new exterior uses same editable work schema")
	check(library.compile_blueprint("cottage-blue").wood == library.compile_blueprint("cottage").wood, "roof color never increases cost")
	check(world.command("human", {"intent": "select_blueprint", "target_id": "home.house.02", "blueprint_id": "cottage-blue"}).ok, "second plot accepts independent exterior")
	check(not world.objects["home.house.01"].has("blueprint"), "second plot selection does not change first")
	var panel := HomePanel.new(); root.add_child(panel); panel.setup(world, library); panel.open_site("home.house.02")
	check(panel.site_id == "home.house.02" and panel.plan.selected == 2, "house UI targets selected plot and matching roof")
	check(panel.materials.text.contains("60") and not panel.plan.disabled, "costs preview before construction")
	panel.queue_free(); await process_frame
	for id in ["home.tree.01", "home.tree.02", "home.tree.03", "home.tree.04", "home.tree.05"]:
		check(world.command("codex", {"intent": "chop", "target_id": id}).ok, "real old-forest harvest")
		finish(world, "codex")
	check(world.command("codex", {"intent": "build", "target_id": "home.house.01"}).ok, "build actual foundation")
	finish(world, "codex")
	var site: Dictionary = world.objects["home.house.01"].duplicate(true)
	check(site.stage_index == 1 and site.invested == 14, "construction consumes delivered foundation cost")
	check(not world.command("human", {"intent": "select_blueprint", "target_id": "home.house.01", "blueprint_id": "cottage-blue"}).ok, "started appearance remains frozen")
	check(world.observe("codex").construction.size() == 2, "AI observes both construction summaries")
	check(Save.save_world(world, directory), "save expanded progress")
	var path := directory.path_join("island-v2.json")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	# A genuine previous map has the same original38objects and no content_version.
	for id in data.objects.keys():
		if int(world.catalog.objects[id].get("introduced_in", 1)) > 1: data.objects.erase(id)
	data.erase("content_version")
	# Keep actors on original land before constructing a legacy-format fixture.
	data.actors.human.position = Places.pair("p_51_44")
	var file := FileAccess.open(path, FileAccess.WRITE); file.store_string(JSON.stringify(data)); file.close()
	var restored := World.new(); restored.library = library
	check(Save.load_world(restored, directory).ok, "old map format adds new content")
	check(restored.objects.size() == world.objects.size(), "new plots forests and chest added")
	check(restored.objects["home.tree.01"].status in ["stump", "sapling"] and restored.objects["home.house.01"].stage_index == site.stage_index and restored.objects["home.house.01"].invested == site.invested and library.render(restored.objects["home.house.01"].blueprint.artwork, "stage_4").get_data() == library.render(site.blueprint.artwork, "stage_4").get_data(), "harvest and locked original house preserved")
	check(restored.storage.saved()==world.storage.saved(),"no fabricated warehouse supplies on upgrade")
	check(Save.save_world(restored, directory), "save content version")
	var again := World.new(); again.library = library
	check(Save.load_world(again, directory).ok and again.objects == restored.objects, "upgrade idempotent")
	var corrupted: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	corrupted.objects.erase("home.tree.02")
	file = FileAccess.open(path, FileAccess.WRITE); file.store_string(JSON.stringify(corrupted)); file.close()
	check(not Save.load_world(World.new(), directory).ok, "new-version missing object cannot silently respawn")
	# Vacate the foundation before committing a new collision footprint.
	var fresh := World.new(); fresh.library = library
	for id in ["home.tree.01", "home.tree.02", "home.tree.03", "home.tree.04", "home.tree.05"]: fresh.command("codex", {"intent": "chop", "target_id": id}); finish(fresh, "codex")
	fresh.command("human", {"intent": "move", "x":Places.point("p_38_0_37_0").x,"y":Places.point("p_38_0_37_0").y}); finish(fresh, "human")
	fresh.command("codex", {"intent": "build", "target_id": "home.house.01"}); finish(fresh, "codex")
	check(fresh.objects["home.house.01"].stage_index == 0 and fresh.objects["home.house.01"].delivered.wood == 14, "occupied foundation blocks commit and keeps deliveries")
	fresh.command("human", {"intent": "move", "x":Places.point("p_51_44").x,"y":Places.point("p_51_44").y}); finish(fresh, "human")
	fresh.command("codex", {"intent": "build", "target_id": "home.house.01"}); finish(fresh, "codex")
	check(fresh.objects["home.house.01"].stage_index == 1, "resume after resident clears site")
	print("Home expansion: %s checks, %s" % [checks, "FAIL" if failed else "PASS"])
	quit(1 if failed else 0)
