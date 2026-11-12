extends SceneTree
const Places=preload("res://scripts/map_locations.gd")
const World = preload("res://scripts/world_state.gd")
const Save = preload("res://scripts/save_store.gd")
const Library = preload("res://scripts/character_library.gd")
const Endpoint = preload("res://scripts/read_endpoint.gd")
var failed := false
var checks := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failed = true; push_error(message)

func total_wood(world: RefCounted) -> int:
	var amount:int = world.storage.count("wood")
	for actor in world.actors.values(): amount += int(actor.carry.get("wood", 0))
	for drop in world.drops.values(): amount += int(drop.wood)
	for object in world.objects.values():
		if object.kind == "chest": amount += int(object.items.get("wood", 0))
		if object.kind == "construction_site": amount += int(object.get("invested", 0)) + int(object.delivered.get("wood", 0))
	return amount

func finish(world: RefCounted, actor: String) -> void:
	for tick in range(5000):
		if not world.work.jobs.has(actor) and not world._routes.has(actor) and not world.deliveries.active(actor): return
		world.advance(.2)
		if int(world.actors[actor].carry.get("wood", 0)) > world.work.CARRY_LIMIT:
			check(false, "bundle overflow"); return
	check(false, "job failed to finish")

func _initialize() -> void:
	var directory := OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"): push_error("isolated test directory required"); quit(1); return
	var world := World.new()
	check(world.error.is_empty(), "content validates: " + world.error)
	if not world.error.is_empty(): quit(1); return
	var human_start: Array = world.actors.human.position.duplicate()
	check(world.command("codex", {"intent": "chop", "target_id": "home.tree.01"}).ok, "chop accepted")
	check(world.command("human", {"intent": "chop", "target_id": "home.tree.01"}).error == "claimed", "exclusive tree claim")
	check(world.command("codex", {"intent": "move", "x":Places.point("p_53_0_44_0").x,"y":Places.point("p_53_0_44_0").y}).error == "busy", "work cannot be silently replaced")
	finish(world, "codex")
	check(world.objects["home.tree.01"].status == "stump", "real tree falls")
	check(int({"id":"storage","items":world.storage._items,"capacity":9007199254740991,"kind":"storage","region_id":"home","position":world.actors.human.position}.items.get("wood", 0)) == 3, "all three wood hauled in one bundle")
	check(world.drops.is_empty() and world.actors.codex.carry.is_empty(), "no phantom drop/carry after delivery")
	check(world.actors.human.position == human_start, "AI never moves human")
	check(total_wood(world) == 3, "wood conservation")
	check(world.command("codex", {"intent": "chop", "target_id": "home.tree.01"}).error == "tree_growing", "cannot harvest stump again")
	check(world.command("codex", {"intent": "build", "target_id": "home.house.01"}).ok, "partial wood can be delivered")
	finish(world, "codex")
	check(world.objects["home.house.01"].stage_index == 0 and world.objects["home.house.01"].delivered.get("wood", 0) == 3, "partial delivery waits before foundation construction")
	world.command("codex", {"intent": "chop", "target_id": "home.tree.02"})
	for tick in range(5000):
		world.advance(.1)
		if not world.actors.codex.carry.is_empty(): break
	check(int(world.actors.codex.carry.get("wood", 0)) == 3, "all three carried at pickup")
	check(total_wood(world) == 6, "partial haul conserves dropped remainder")
	world.command("codex", {"intent": "stop"})
	check(total_wood(world) == 6 and world.work.claims.is_empty(), "stop releases claims without losing wood")
	check(Save.save_world(world, directory), "atomic save")
	var restored := World.new()
	var restored_result: Dictionary = Save.load_world(restored, directory)
	check(restored_result.ok and restored_result.get("loaded", false), "restore valid save")
	if not restored_result.ok: quit(1); return
	check(total_wood(restored) == 6 and restored.world_id == world.world_id, "restore preserves identity and all wood")
	check(restored.work.jobs.is_empty() and restored._routes.is_empty(), "restart leaves no automatic jobs")
	check(restored.command("codex", {"intent": "store"}).ok, "resume physical storage")
	finish(restored, "codex")
	check(restored.drops.is_empty(), "whole tree fits in one bundle after restart")
	check(not restored.command("human", {"intent": "collect", "target_id": "drop.home.tree.02"}).ok, "already hauled drop cannot be collected twice")
	check(total_wood(restored) == 6 and restored.drops.is_empty(), "recovered remainder")
	world = restored
	check(world.command("codex", {"intent":"gather_wood","zone_id":"home.forest","tree_count":2}).ok,"gather actual remaining foundation supply")
	finish(world,"codex")
	check(world.command("human", {"intent": "build", "target_id": "home.house.01"}).ok, "stage accepted")
	check(world.command("codex", {"intent": "build", "target_id": "home.house.01"}).error == "claimed", "site exclusive claim")
	finish(world, "human")
	check(int(world.objects["home.house.01"].stage_index) == 1 and int(world.objects["home.house.01"].invested) == 12, "foundation built from delivered materials")
	check(total_wood(world) == 12, "building transfers rather than duplicates wood")
	check(world.command("codex", {"intent":"gather_wood","zone_id":"home.forest","tree_count":18}).ok,"more real harvest for unchanged64 wood house")
	finish(world,"codex")
	for stage in range(1, 5):
		check(world.command("codex", {"intent": "build", "target_id": "home.house.01"}).ok, "next stage accepted")
		finish(world, "codex")
	check(world.objects["home.house.01"].status == "complete", "five-stage house complete")
	check(total_wood(world) == 66 and world.objects["home.house.01"].invested == 64, "complete house has exactly invested harvest")
	check(not world.command("codex", {"intent": "build", "target_id": "home.house.01"}).ok, "cannot build stage six")
	var endpoint := Endpoint.new(); endpoint.world = world; endpoint.session = "session"; endpoint.bindings = {"token": "codex"}
	var request := {"session": "session", "token": "token", "request_id": "once", "expires": Time.get_unix_time_from_system() + 100, "operation": "act", "query": {"intent": "stop"}}
	check(endpoint.handle(request).ok, "bound action accepted")
	check(endpoint.handle(request).error == "duplicate_request", "replay blocked")
	request.request_id = "identity"; request.query = {"intent": "stop", "actor_id": "human"}
	check(not endpoint.handle(request).ok, "cannot inject different actor")
	endpoint.free()
	var library := Library.new(); library.configure(directory)
	check(library.valid(library.artworks["white-haired-girl"]), "editable character validates")
	check(library.valid(library.artworks["human-starter"]), "human uses same format")
	var first: Dictionary = library.read_frame("white-haired-girl", "down_0")
	var pixels_before: Array = first.layers[0].pixels.duplicate()
	var other_before: Array = library.read_frame("white-haired-girl", "up_0").layers[0].pixels.duplicate()
	var patch := {"base_revision": first.revision, "frame": "down_0", "layer": 0, "pixels": [{"x": 0, "y": 0, "color": "#fa1100ff"}]}
	check(library.patch("white-haired-girl", patch).ok, "AI/local versioned pixel change")
	check(library.read_frame("white-haired-girl", "up_0").layers[0].pixels == other_before, "other frame unchanged")
	check(library.patch("white-haired-girl", patch).error == "stale_artwork", "stale AI change rejected")
	check(library.undo_publish("white-haired-girl").ok, "undo applied change")
	check(library.read_frame("white-haired-girl", "down_0").layers[0].pixels == pixels_before, "undo restores exact pixels")
	var draft: Dictionary = library.artworks["human-starter"].duplicate(true)
	var new_pixels: Array = []; new_pixels.resize(96 * 128); new_pixels.fill(0); new_pixels[0] = 1
	draft.frames.down_0.append({"id": "free", "name": "new contour", "visible": true, "pixels": new_pixels})
	check(library.publish(draft, int(draft.revision)).ok, "arbitrary new layer accepted")
	var next := Library.new(); next.configure(directory)
	check(next.artworks["human-starter"].frames.down_0.size() == 2, "editable layers survive reopening")
	check(next.render(next.artworks["human-starter"], "down_0").get_width() == 96, "same artwork compiles to game image")
	var replica := next.ensure_resident("companion-2")
	check(replica != "human-starter" and replica != "white-haired-girl", "companions do not share mutable appearance identity")
	print("Playable slice: %s checks, %s" % [checks, "FAIL" if failed else "PASS"])
	quit(1 if failed else 0)
