extends SceneTree
const Places=preload("res://scripts/map_locations.gd")
const World = preload("res://scripts/world_state.gd")
const Library = preload("res://scripts/character_library.gd")
const Save = preload("res://scripts/save_store.gd")
var world: RefCounted
var library: RefCounted
var directory := ""
var failed := false
var checks := 0
class BlockedWorld extends World:
	var block_trees := true
	func approach_route(actor_id: String, target: Dictionary) -> Array[Vector2]:
		if block_trees and target.get("kind") == "tree": return []
		return super.approach_route(actor_id, target)
func fresh() -> void:
	world = World.new(); world.library = library
func phase(actor_id: String, requested: String) -> bool:
	for tick in range(20000):
		world.advance(.1)
		if world.work.jobs.get(actor_id, {}).get("phase") == requested: return true
		if world.projects.plans.has(actor_id) and not world.projects.active(actor_id): break
	check(false, "never reached " + requested + str(world.projects.state(actor_id))); return false

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failed = true; push_error(label)
func job(actor_id: String, args: Dictionary) -> bool:
	var result: Dictionary = world.command(actor_id, args)
	check(result.ok, "accept " + str(args) + str(result))
	if not result.ok: return false
	for tick in range(20000):
		if not world.work.jobs.has(actor_id): return true
		world.advance(.2)
	check(false, "job timeout"); return false
func finish_project() -> void:
	for tick in range(60000):
		if not world.projects.active("codex"): return
		world.advance(.2)
	check(false, "project timeout " + str(world.projects.state("codex")))
func total_wood() -> int:
	var amount := 0
	for actor in world.actors.values(): amount += int(actor.carry.get("wood", 0))
	for chest in [{"id":"storage","items":world.storage.saved().items,"capacity":9007199254740991,"kind":"storage"}]: amount += int(chest.items.get("wood", 0))
	for drop in world.drops.values(): amount += int(drop.wood)
	for site in world.objects.values():
		if site.kind == "construction_site": amount += int(site.get("invested", 0)) + int(site.delivered.get("wood", 0))
	return amount
func _initialize() -> void: call_deferred("run")
func run() -> void:
	directory = OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"): quit(1); return
	library = Library.new(); library.configure(directory)
	world = World.new(); world.library = library
	var original_human: Array = world.actors.human.position.duplicate()
	check(world.command("codex", {"intent":"build_house", "target_id":"home.house.01"}).ok, "one project accepted from empty inventory")
	var id: String = world.projects.plans.codex.id
	check(not world.command("human", {"intent":"build_house", "target_id":"home.house.01"}).ok, "one persistent plan per site")
	check(not world.command("codex", {"intent":"move", "x":Places.point("p_51_44").x,"y":Places.point("p_51_44").y}).ok, "active plan cannot be silently replaced")
	check(not world.command("human", {"intent":"select_blueprint", "target_id":"home.house.01", "blueprint_id":"cottage-blue"}).ok, "project pins saved blueprint before material investment")
	finish_project()
	var plan: Dictionary = world.projects.state("codex")
	check(plan.status == "completed" and world.objects["home.house.01"].stage_index == 5, "one command completes all five stages")
	check(world.objects["home.house.01"].invested == 60 and total_wood() == 60, "real current-yield harvest conserves house investment and leftovers")
	check(world.actors.human.position == original_human and world.work.jobs.is_empty(), "model plan never controls human and stops on completion")
	check(plan.id == id and world.projects.memories.size() == 1, "one stable project and one factual completion memory")
	check(plan.contributors.codex.wood == 60 and plan.contributors.codex.stages == 5 and not plan.contributors.has("human"), "does not invent human contribution")
	for i in range(200): world.advance(.2)
	check(world.projects.memories.size() == 1 and total_wood() == 60, "completion is idempotent")
	check(Save.save_world(world, directory), "save completed project")
	var restored := World.new(); restored.library = library
	check(Save.load_world(restored, directory).ok, "reload completed plan and factual memory")
	check(restored.projects.memories.size() == 1 and restored.projects.plans.codex.status == "completed", "memory survives reload once")
	fresh()
	job("human", {"intent":"select_blueprint", "target_id":"home.house.01", "blueprint_id":"cottage-blue"})
	job("human", {"intent":"gather_wood", "tree_count":5, "zone_id":"home.forest"})
	job("human", {"intent":"build", "target_id":"home.house.01"})
	check(world.command("codex", {"intent":"build_house", "target_id":"home.house.01"}).ok, "continue a genuinely started blue house")
	finish_project()
	plan = world.projects.state("codex")
	check(plan.status == "completed" and plan.blueprint_id == "cottage-blue" and plan.started_stage == 1, "pinned blue appearance and prior stage retained")
	check(plan.contributors.human.wood == 14 and plan.contributors.human.stages == 1 and plan.contributors.codex.stages == 4, "completion records actual human and codex contributions")
	check(total_wood() == 60, "shared construction does not overharvest a second full set")
	# A real human delivery can arrive while the project owns construction.
	fresh()
	job("human", {"intent":"gather_wood", "tree_count":8, "zone_id":"home.forest"})
	job("human", {"intent":"take"})
	check(world.command("codex", {"intent":"build_house", "target_id":"home.house.01"}).ok, "start while human carries twenty")
	world.advance(.2)
	check(world.work.claims.get("home.house.01") == "codex", "project child owns current construction stage")
	job("human", {"intent":"deliver_wood", "target_id":"home.house.01"})
	check(world.objects["home.house.01"].contributions.human.wood > 0 and world.actors.human.carry.get("wood") == 20-world.objects["home.house.01"].contributions.human.wood, "human can deliver despite builder claim and keeps surplus")
	job("human", {"intent":"store"})
	finish_project(); check(total_wood() == 60 and world.projects.plans.codex.status == "completed", "concurrent delivery never overcharges or commits a stage twice")
	# Other residents can start a stage while the project waits; it observes completion.
	fresh(); job("human", {"intent":"gather_wood", "tree_count":5, "zone_id":"home.forest"})
	check(world.command("codex", {"intent":"build_house", "target_id":"home.house.01"}).ok, "start shared target before human construction")
	check(world.command("human", {"intent":"build", "target_id":"home.house.01"}).ok, "human takes actual stage")
	world.advance(.2)
	check(world.projects.state("codex").step == "waiting_partner" and not world.work.jobs.has("codex"), "project waits without claiming or idling model calls")
	finish_project(); check(world.objects["home.house.01"].contributions.human.stages == 1 and total_wood() == 60, "human stage counted once and remaining plan completes")
	# When the player supplies the shortage, abort an un-felled tree, not the material.
	fresh(); job("human", {"intent":"gather_wood", "tree_count":8, "zone_id":"home.forest"})
	job("human", {"intent":"build", "target_id":"home.house.01"})
	job("human", {"intent":"take"})
	check(world.command("codex", {"intent":"build_house", "target_id":"home.house.01"}).ok, "start with remaining stage supply held by human")
	if phase("codex", "chop"):
		var tree_id: String = world.work.jobs.codex.target_id
		job("human", {"intent":"store"})
		world.advance(.3)
		check(world.objects[tree_id].status == "mature" and total_wood() == 24, "fresh supplied wood prevents redundant tree felling")
		check(world.work.jobs.get("codex", {}).get("intent") != "gather_wood", "project replaces unneeded gathering with actual construction")
	finish_project(); check(world.projects.plans.codex.status == "completed" and total_wood() == 60, "adjusted plan still finishes correctly")
	# Stop during a live pickup; resume never duplicates resources or silently restarts.
	fresh(); world.command("codex", {"intent":"build_house", "target_id":"home.house.01"})
	for tick in range(20000):
		world.advance(.1)
		if int(world.actors.codex.carry.get("wood",0)) == 3: break
	id = world.projects.plans.codex.id
	check(total_wood() == 3, "eight carried before pause")
	check(world.command("codex", {"intent":"pause_project", "project_id":id}).ok, "pause entire plan")
	for i in range(50): world.advance(.2)
	check(world.projects.plans.codex.status == "paused" and world.work.jobs.is_empty() and world.work.claims.is_empty() and total_wood() == 3, "pause keeps carried and dropped wood and releases all claims")
	check(not world.command("human", {"intent":"resume_project", "project_id":id}).ok, "other identity cannot resume codex plan")
	check(not world.command("codex", {"intent":"resume_project", "project_id":"stale"}).ok, "stale project controls rejected")
	check(world.command("codex", {"intent":"resume_project", "project_id":id}).ok, "explicit resume")
	world.advance(.3)
	check(Save.save_world(world, directory.path_join("active")), "save running project and carried material")
	restored = World.new(); restored.library = library
	check(Save.load_world(restored, directory.path_join("active")).ok, "running project save validates")
	world = restored
	for i in range(100): world.advance(.2)
	check(world.projects.plans.codex.status == "paused" and world.work.jobs.is_empty() and total_wood() == 3, "restart preserves plan but never restarts work")
	check(world.command("codex", {"intent":"resume_project", "project_id":id}).ok, "continue after restart")
	finish_project(); check(world.projects.plans.codex.status == "completed" and total_wood() == 60, "resumed physical work remains conserved")
	fresh(); world.command("codex", {"intent":"build_house", "target_id":"home.house.01"})
	phase("codex", "chop"); id = world.projects.plans.codex.id
	check(world.command("codex", {"intent":"cancel_project", "project_id":id}).ok, "cancel project")
	for i in range(50): world.advance(.2)
	check(world.projects.plans.codex.status == "cancelled" and not world.projects.site_locked("home.house.01") and total_wood() == 0, "cancel before felling stops future work and unlocks unstarted plan")
	check(not world.command("codex", {"intent":"resume_project", "project_id":id}).ok, "cancelled plan cannot accidentally resume")
	job("human", {"intent":"select_blueprint", "target_id":"home.house.01", "blueprint_id":"cottage-blue"})
	check(Save.save_world(world,directory.path_join("cancelled")), "cancelled plans can save after changing unstarted blueprint")
	restored = World.new(); restored.library = library
	check(Save.load_world(restored,directory.path_join("cancelled")).ok, "cancelled plan history does not reject a newly selected blueprint")
	world = BlockedWorld.new(); world.library = library
	world.command("codex", {"intent":"build_house", "target_id":"home.house.01"}); finish_project()
	check(world.projects.plans.codex.status == "blocked" and world.projects.plans.codex.reason.contains("走不到") and world.work.jobs.is_empty(), "unreachable resources block once with real reason")
	var count: int = world.work.events.size()
	for i in range(100): world.advance(.2)
	check(world.work.events.size() == count and total_wood() == 0, "blocked project never retries or infers in a loop")
	world.block_trees = false
	check(world.command("codex", {"intent":"resume_project", "project_id":world.projects.plans.codex.id}).ok, "resume after route repaired")
	finish_project(); check(world.projects.plans.codex.status == "completed", "resolved blockage can continue same project")
	# Full storage containing actual mushrooms cannot silently disappear for wood.
	fresh()
	for chest in [{"id":"storage","items":world.storage.saved().items,"capacity":9007199254740991,"kind":"storage"}]: chest.capacity = 2
	job("human", {"intent":"forage", "target_id":world.life.patches.keys()[0]})
	world.command("codex", {"intent":"build_house", "target_id":"home.house.01"}); finish_project()
	check(world.projects.plans.codex.status == "completed" and total_wood() == 60, "unlimited warehouse permits real preparation and conserves actual construction wood")
	# Saved data corruption stays recoverable, and legacy files don't create plans.
	var base_path := directory.path_join("island-v2.json")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(base_path))
	data.projects.plans.codex.actor_id = "human"
	var bad_dir := directory.path_join("invalid"); DirAccess.make_dir_recursive_absolute(bad_dir)
	var bad_file := FileAccess.open(bad_dir.path_join("island-v2.json"), FileAccess.WRITE); bad_file.store_string(JSON.stringify(data)); bad_file.close()
	var bad_world := World.new(); var load_result: Dictionary = Save.load_world(bad_world, bad_dir)
	check(not load_result.ok and FileAccess.file_exists(load_result.backup), "forged project ownership is rejected with recovery copy")
	data = JSON.parse_string(FileAccess.get_file_as_string(base_path)); data.schema_version = 4; data.erase("projects")
	var legacy_dir := directory.path_join("legacy4"); DirAccess.make_dir_recursive_absolute(legacy_dir)
	var legacy_file := FileAccess.open(legacy_dir.path_join("island-v2.json"), FileAccess.WRITE); legacy_file.store_string(JSON.stringify(data)); legacy_file.close()
	var legacy := World.new()
	check(Save.load_world(legacy, legacy_dir).ok and legacy.projects.plans.is_empty() and legacy.objects["home.house.01"].stage_index == 5, "schema4 preserves actual house and creates no fictitious projects")
	# Game UI controls use the same bound project commands, not an alternate planner.
	var game: Node = load("res://scenes/main.tscn").instantiate(); root.add_child(game)
	game.save_enabled = false; game.set_process(false); game.view.sound_enabled = false; game.world.local_companion.set_enabled(false)
	game.project_panel.refresh()
	check(game.project_panel.enter_button.visible and game.project_panel.heading.text.contains("5 / 5"), "completed saved project offers real entry")
	check(game.world.command("codex", {"intent":"build_house", "target_id":"home.house.02"}).ok, "UI fixture starts new actual project")
	game.world.advance(.2); game.project_panel.refresh()
	game.project_panel.pause_button.pressed.emit()
	check(game.world.projects.plans.codex.status == "paused" and game.world.work.jobs.is_empty(), "pause button halts whole plan")
	game.project_panel.resume_button.pressed.emit()
	check(game.world.projects.active("codex"), "continue button resumes persistent plan")
	game.world.director.set_controller("codex","model");game._ensure_link("codex");game.command_page.selected=["codex"];game._select_chat("codex")
	if not game.world.projects.active("codex"):check(game.world.command("codex",{"intent":"resume_project","project_id":game.world.projects.plans.codex.id}).ok,"explicitly resume after fixture controller binding")
	game._companion_event({"kind":"question", "id":"qa-question", "text":"要继续这个方案吗？", "choices":["继续", "先暂停"]})
	check(game.world.projects.plans.codex.status == "paused" and game.pending_question == "qa-question", "in-game decision pauses active project")
	game._project_control({"intent":"resume_project", "project_id":game.world.projects.plans.codex.id})
	check(game.world.projects.plans.codex.status == "paused", "waiting for user answer does not authorize resume")
	game.project_panel.cancel_button.pressed.emit()
	check(game.world.projects.plans.codex.status == "cancelled" and game.pending_question.is_empty() and game.link._pid == -1, "cancel blocks stale answer without model inference")
	game.queue_free(); await process_frame
	print("Construction projects: %s checks, %s" % [checks,"FAIL" if failed else "PASS"])
	quit(1 if failed else 0)
