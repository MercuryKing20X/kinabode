extends SceneTree
const World = preload("res://scripts/world_state.gd")
const Motion = preload("res://scripts/actor_motion.gd")
const Save = preload("res://scripts/save_store.gd")
const Library = preload("res://scripts/character_library.gd")
var checks := 0
var failed := false
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failed = true; push_error(message)
func wood(world: RefCounted) -> int:
	var total:int = world.storage.count("wood")
	for actor in world.actors.values(): total += int(actor.carry.get("wood", 0))
	for drop in world.drops.values(): total += int(drop.wood)
	for object in world.objects.values():
		if object.kind == "chest": total += int(object.items.get("wood", 0))
	return total
func _initialize() -> void:
	var directory := OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"): quit(1); return
	var world := World.new()
	var motion := Motion.new()
	var before: Dictionary = world.observe("codex", {})
	before.erase("observed_at")
	motion.advance(.1, world.actors)
	check(motion.states.human.blink_at != motion.states.codex.blink_at, "residents have staggered blink timing")
	motion.attend()
	for i in range(240):
		motion.advance(.03, world.actors)
		motion.pose(world.actors.codex, {}, world.actors)
	var after: Dictionary = world.observe("codex", {})
	after.erase("observed_at")
	check(after == before, "presentation cannot change position, facing, revision or gameplay")
	world.command("codex", {"intent": "chop", "target_id": "home.tree.01"})
	for i in range(5000):
		world.advance(.02)
		if world.actors.codex.activity == "chopping": break
	check(int(world.objects["home.tree.01"].health) == 6, "windup does not damage tree")
	motion.attend()
	var pose: Dictionary = motion.pose(world.actors.codex, world.work.jobs.codex, world.actors)
	check(str(pose.frame).begins_with("chop_" + world.actors.codex.facing), "working pose overrides conversational attention")
	for i in range(5000):
		world.advance(.02)
		if world.work.jobs.codex.phase == "fall_wait": break
	var hits := 0
	for event in world.work.visual_events:
		if event.kind == "hit": hits += 1
	check(hits == 6, "six impacts emitted exactly once")
	check(wood(world) == 3 and world.actors.codex.carry.is_empty(), "fall creates physical drop before pickup")
	for i in range(5000):
		world.advance(.02)
		if world.actors.codex.activity == "picking_up": break
	check(world.actors.codex.carry.is_empty(), "pickup windup has not transferred material")
	for i in range(5000):
		world.advance(.02)
		if world.actors.codex.activity == "putting_down": break
	check(int(world.actors.codex.carry.get("wood", 0)) == 3, "deposit windup still owns the bundle")
	for i in range(5000):
		world.advance(.1)
		if not world.work.jobs.has("codex") and not world.deliveries.active("codex"): break
	check(wood(world) == 3 and world.drops.is_empty() and world.actors.codex.carry.is_empty(), "animated full one-haul cycle conserves three wood")
	for phase in ["chop", "fall_wait", "pickup", "storage_delivery"]:
		var sample := World.new()
		sample.command("codex", {"intent": "chop", "target_id": "home.tree.01"})
		var reached := false
		for i in range(10000):
			sample.advance(.02)
			if sample.work.jobs.get("codex",{}).get("phase") == phase and not sample._routes.has("codex"):
				reached = true; break
		check(reached, "reached cancellation phase " + phase)
		var total := wood(sample)
		sample.command("codex", {"intent": "stop"})
		check(wood(sample) == total and sample.work.claims.is_empty(), "cancel conserves " + phase)
		check(Save.save_world(sample, directory), "save cancelled " + phase)
		var restored := World.new()
		check(Save.load_world(restored, directory).ok and wood(restored) == total and restored.work.jobs.is_empty(), "reload conserves " + phase)
	var partial := World.new()
	partial.command("codex", {"intent": "chop", "target_id": "home.tree.01"})
	for i in range(10000):
		partial.advance(.02)
		if int(partial.objects["home.tree.01"].get("health", 6)) == 5: break
	partial.command("codex", {"intent": "stop"})
	partial.command("codex", {"intent": "chop", "target_id": "home.tree.01"})
	for i in range(10000):
		partial.advance(.2)
		if not partial.work.jobs.has("codex"): break
	hits = 0
	for event in partial.work.visual_events:
		if event.kind == "hit": hits += 1
	check(hits == 6 and wood(partial) == 3, "resume partial health does not replay paid impacts")
	var library := Library.new(); library.configure(directory)
	var art: Dictionary = library.artworks["white-haired-girl"].duplicate(true)
	art.frames.erase("chop_up_1")
	art.frames.down_0[0].pixels[0] = 1
	check(library.publish(art, int(art.revision)).ok, "save customized older action set")
	var reloaded := Library.new(); reloaded.configure(directory)
	check(reloaded.artworks[art.id].frames.has("chop_up_1") and reloaded.artworks[art.id].frames.down_0[0].pixels[0] == 1, "new frames merge without replacing existing edits")
	check(reloaded.valid(reloaded.artworks[art.id]), "merged art stays valid")
	print("Motion and material transitions: %s checks, %s" % [checks, "FAIL" if failed else "PASS"])
	quit(1 if failed else 0)
