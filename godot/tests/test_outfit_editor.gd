extends SceneTree
const Library = preload("res://scripts/character_library.gd")
const Editor = preload("res://scripts/character_editor.gd")
const World = preload("res://scripts/world_state.gd")
const Endpoint = preload("res://scripts/read_endpoint.gd")
var checks := 0
var failed := false
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failed = true; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var dir := OS.get_environment("HABITAT_DATA_DIR")
	if not dir.contains("youqi-test-"): quit(1); return
	var library := Library.new(); library.configure(dir)
	var editor := Editor.new(); root.add_child(editor); editor.setup(library); editor.open_art("human-starter")
	check(not editor.canvas.art.has("outfit"), "old artwork starts without outfit")
	var original: Dictionary = editor.canvas.art.frames.duplicate(true)
	editor._create_outfit()
	check(editor.canvas.art.has("outfit") and editor.dirty, "explicit creation produces draft")
	check(editor.canvas.art.frames == original and not library.artworks["human-starter"].has("outfit"), "source frames and live artwork unchanged")
	editor._toggle_outfit("head", true)
	check(editor.canvas.art.outfit.head.enabled, "part can be enabled")
	editor.canvas.undo(); check(not editor.canvas.art.outfit.head.enabled, "outfit undo restores previous state")
	editor.canvas.redo(); check(editor.canvas.art.outfit.head.enabled, "outfit redo restores enabled state")
	editor.outfit_palette.select(2); editor._recolor_outfit("head")
	check(not editor.canvas.art.outfit.head.colors.is_empty(), "selected existing palette color remaps the part")
	check(library.valid(editor.canvas.art) and editor.canvas.art.frames == original, "recolor validates without changing original frames")
	var duplicate: Dictionary = library.create_work(library.artworks["human-starter"])
	check(duplicate.ok, "compatible destination created")
	editor._refresh_outfit()
	for index in range(editor.outfit_target.item_count):
		if editor.outfit_target.get_item_metadata(index) == duplicate.id: editor.outfit_target.select(index)
	editor._copy_outfit()
	check(editor.character_id == duplicate.id and editor.canvas.art.has("outfit") and editor.dirty, "copy goes to compatible destination draft")
	check(not library.artworks[duplicate.id].has("outfit"), "copy does not silently publish")
	var world := World.new()
	var endpoint := Endpoint.new(); endpoint.world = world; endpoint.library = library; endpoint.session = "test"; endpoint.bindings = {"token":"codex"}
	var own: String = world.actors.codex.appearance_id
	var sample := {"head":{"enabled":false,"colors":{},"masks":{}}}
	var request := {"session":"test", "token":"token", "expires":Time.get_unix_time_from_system()+60, "request_id":"own-outfit", "operation":"edit_character", "query":{"artwork_id":"human-starter", "base_revision":library.artworks[own].revision, "outfit":sample}}
	check(endpoint.handle(request).ok and library.artworks[own].has("outfit"), "bound AI edits only its own character")
	check(not library.artworks["human-starter"].has("outfit"), "AI artwork_id cannot select the human")
	request.request_id = "other-outfit"; request.operation = "edit_work"
	check(not endpoint.handle(request).ok, "shared work endpoint rejects character outfit edits")
	endpoint.free()
	editor.queue_free(); await process_frame
	print("Outfit editor: %s checks, %s" % [checks, "FAIL" if failed else "PASS"])
	quit(1 if failed else 0)
