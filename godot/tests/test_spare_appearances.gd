extends SceneTree
const Library = preload("res://scripts/character_library.gd")
const World = preload("res://scripts/world_state.gd")
const Save = preload("res://scripts/save_store.gd")
const Motion = preload("res://scripts/actor_motion.gd")
const Endpoint = preload("res://scripts/read_endpoint.gd")
const IDS = ["ai-gpt", "ai-claude", "ai-gemini", "ai-grok", "ai-deepseek", "ai-glm", "ai-qwen", "ai-kimi"]
var checks := 0
var failed := false
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failed = true; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var directory := OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"): quit(1); return
	var library := Library.new(); library.configure(directory)
	for id in IDS:
		check(library.artworks.has(id) and library.valid(library.artworks[id]), id + " validates")
		if not library.artworks.has(id): continue
		var art: Dictionary = library.artworks[id]
		check(art.width == 96 and art.height == 128 and art.frames.size() == 51 and "spare" in art.tags, id + " has original 43 frames plus eight optional fire placeholders and independent spare metadata")
		var reference: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/characters/"+id+".provenance.json"))
		check(reference is Dictionary and art.frame_status.provenance.ends_with(id+".provenance.json"), id + " has recorded source")
		for direction in ["down","left","right","up"]:
			for prefix in ["pickup_", "carry_", "chop_"]:
				check(art.frames.has(prefix+direction+("_0" if prefix=="chop_" else "")), id + " has " + prefix + direction)
		var world := World.new(); world.library = library; world.director.set_all_enabled(false)
		world.actors.codex.appearance_id = id
		var result: Dictionary = world.command("codex", {"intent":"chop", "target_id":"home.tree.01"})
		check(result.ok, id + " accepts real chop")
		var motion := Motion.new(); var saw := {"walking":false,"chopping":false,"picking_up":false,"loaded":false}
		for tick in range(4000):
			world.advance(.1); motion.advance(.1,world.actors)
			var actor: Dictionary = world.actors.codex
			if saw.has(actor.activity): saw[actor.activity] = true
			if not actor.carry.is_empty(): saw.loaded = true
			if actor.activity in ["walking","chopping","picking_up"]:
				var pose: Dictionary = motion.pose(actor, world.work.jobs.get("codex",{}),world.actors)
				var frame: String = pose.frame if art.frames.has(pose.frame) else pose.fallback
				if not art.frames.has(frame): check(false,id+" missing actual frame "+frame); break
			if not world.work.jobs.has("codex") and not world._routes.has("codex"): break
		check(saw.values().all(func(value):return value), id + " really walked, chopped, picked up and carried")
	var game: Node = load("res://scenes/main_v3.tscn").instantiate(); game.world = World.new("res://content/home-v3/world.json"); root.add_child(game)
	game.save_enabled = false; game.set_process(false); game.view.sound_enabled = false
	await process_frame
	var actor: Dictionary = game.world.actors.codex
	var identity := {"name":actor.name,"controller":actor.controller,"role":actor.role}
	var original: String = actor.appearance_id
	game.island_hud.open_appearance("codex")
	check(game.island_hud.wardrobe.visible and game.island_hud.wardrobe.selected_actor=="codex", "resident card opens wardrobe bound to selected resident")
	game.island_hud.wardrobe.selected_work="ai-gpt";game.island_hud.wardrobe.refresh_preview()
	check(actor.appearance_id==original,"preview does not change the world")
	game.island_hud.wardrobe.apply_selection()
	check(actor.appearance_id=="ai-gpt" and actor.custom_appearance and actor.name==identity.name and actor.controller==identity.controller and actor.role==identity.role, "host applies spare without identity changes")
	check(Save.save_world(game.world,directory), "save host-selected appearance")
	actor.appearance_id = original; actor.custom_appearance=false
	check(Save.load_world(game.world,directory).ok and game.world.actors.codex.appearance_id=="ai-gpt" and game.world.actors.codex.custom_appearance, "reload keeps chosen appearance")
	game.island_hud.wardrobe.open_for("codex");game.island_hud.wardrobe.restore_default();game.island_hud.wardrobe.apply_selection()
	check(game.world.actors.codex.appearance_id==original,"host switches back to original")
	var world := World.new(); world.library = library
	check(world.add_companion("future-test","未来伙伴","companion","ai-gpt") and world.actors["future-test"].appearance_id=="ai-gpt", "host can provision future resident with selected spare")
	check(not world.add_companion("invalid-test","未来伙伴","companion","missing-work"), "unknown initial appearance is rejected")
	world.actors.codex.appearance_id="ai-gpt"
	check(not world.command("codex",{"intent":"set_appearance","appearance_id":"ai-claude"}).ok, "AI cannot change appearance")
	var endpoint := Endpoint.new(); endpoint.world=world;endpoint.library=library;endpoint.session="s";endpoint.bindings={"t":"codex"}
	var request := {"session":"s","token":"t","expires":Time.get_unix_time_from_system()+60,"request_id":"shared","operation":"edit_character","query":{"base_revision":1,"frame":"down_0","layer":0,"pixels":[{"x":0,"y":0,"color":"#ffffffff"}]}}
	var response: Dictionary=endpoint.handle(request)
	check(not response.ok and response.error=="shared_artwork_readonly", "AI cannot edit a shared spare artwork")
	endpoint.free();game.queue_free();await process_frame
	print("Spare appearances: %s checks, %s" % [checks, "FAIL" if failed else "PASS"])
	quit(1 if failed else 0)
