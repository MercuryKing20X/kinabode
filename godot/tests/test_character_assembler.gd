extends SceneTree
const Library = preload("res://scripts/character_library.gd")
const Assembler = preload("res://scripts/character_assembler.gd")
var checks := 0
var failed := false
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failed = true; push_error(message)
func _initialize() -> void:
	var dir := OS.get_environment("HABITAT_DATA_DIR")
	if not dir.contains("youqi-test-"): quit(1); return
	var library := Library.new(); library.configure(dir)
	var snapshots := {}
	for id in ["human-starter", "white-haired-girl", "blue-haired-girl", "orange-haired-girl", "black-scarf-girl"]:
		snapshots[id] = library.artworks[id].duplicate(true)
	var outputs := []
	for name in Assembler.PRESETS:
		var result: Dictionary = Assembler.assemble(library, Assembler.PRESETS[name], name)
		check(result.ok, name + " assembled")
		if result.ok:
			var art: Dictionary = library.artworks[result.id]
			check(art.frames.size() >= 40 and library.valid(art), name + " has valid existing frames")
			check(result.id not in snapshots, name + " is independent")
			outputs.append(library.render(art, "down_0").get_data())
	check(outputs.size() == 4 and outputs[0] != outputs[1] and outputs[1] != outputs[2] and outputs[2] != outputs[3], "four compositions have distinct pixels")
	for id in snapshots: check(library.artworks[id] == snapshots[id], "original remains unchanged: " + id)
	print("Character assembler: %s checks, %s" % [checks, "FAIL" if failed else "PASS"])
	quit(1 if failed else 0)
