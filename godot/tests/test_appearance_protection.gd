extends SceneTree
const World = preload("res://scripts/world_state.gd")
const Library = preload("res://scripts/character_library.gd")
const Save = preload("res://scripts/save_store.gd")
var checks := 0
func check(value: bool, reason: String) -> void:
	checks += 1
	if not value: push_error(reason); quit(1); assert(value, reason)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var directory := OS.get_environment("HABITAT_DATA_DIR")
	assert(directory.contains("youqi-test-"))
	var world := World.new()
	var library := Library.new(); library.configure(directory); world.library = library; library.resident_world = world
	check(not world.assign_appearance("human", "ai-gpt"), "human assignment requires confirmation")
	check(not world.assign_appearance("human", "ai-gpt", true), "human assignment requires both flags")
	check(world.assign_appearance("human", "ai-gpt", true, true), "confirmed human assignment")
	check(world.assign_appearance("codex", "ai-claude"), "partner assignment")
	check(Save.save_world(world, directory), "save explicit assignments")
	var restored := World.new(); restored.library = library
	check(Save.load_world(restored, directory).ok, "load saved assignments")
	check(restored.actors.human.appearance_id == "ai-gpt" and restored.actors.human.custom_appearance, "human appearance persists")
	check(restored.actors.codex.appearance_id == "ai-claude" and restored.actors.codex.custom_appearance, "partner appearance persists")
	var before: Dictionary = restored.actors.human.duplicate(true)
	var result: Dictionary = Save.restore_human_appearance(restored, directory)
	check(result.ok and FileAccess.file_exists(result.get("backup", "")), "recovery requires a backup")
	before.appearance_id = restored.residents.appearance_for("human"); before.custom_appearance = false
	check(restored.actors.human == before, "recovery changes only appearance fields")
	var saved := World.new(); saved.library = library
	check(Save.load_world(saved, directory).ok and saved.actors.human.appearance_id == "ai-gpt", "backup happens before restoration save")
	check(Save.save_world(restored, directory), "save restored appearance")
	print("Appearance protection: ", checks, " checks, PASS")
	quit()
