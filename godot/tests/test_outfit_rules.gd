extends SceneTree

const Library = preload("res://scripts/character_library.gd")
var checks := 0
var failed := false

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var directory := OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"): quit(1); return
	var library := Library.new()
	library.configure(directory)
	for id in ["human-starter", "white-haired-girl", "blue-haired-girl", "orange-haired-girl", "black-scarf-girl"]:
		var legacy: Dictionary = library.artworks[id]
		var optional: Dictionary = legacy.duplicate(true)
		optional.outfit = {}
		for frame in ["down_0", "up_0", "chop_left_1", "carry_right_1"]:
			check(library.render(legacy, frame).get_data() == library.render(optional, frame).get_data(), id + ": legacy pixels unchanged for " + frame)
	var original: Dictionary = library.artworks["white-haired-girl"].duplicate(true)
	var art: Dictionary = original.duplicate(true)
	var pixels: Array = art.frames.down_0[0].pixels
	var index := -1
	for i in range(pixels.size()):
		if int(pixels[i]) > 0:
			index = i
			break
	var source := int(pixels[index])
	var target := 1 if source != 1 else 2
	art.outfit = {"top": {"enabled": false, "colors": {str(source): target}, "masks": {"down_0": [index]}}}
	check(library.valid(art), "valid optional outfit")
	check(library.render(art, "down_0").get_data() == library.render(original, "down_0").get_data(), "disabled outfit preserves original pixels")
	art.outfit.top.enabled = true
	check(library.render(art, "down_0").get_data() != library.render(original, "down_0").get_data(), "enabled mask changes selected pixel")
	check(art.frames == original.frames, "outfit does not modify authored frames")
	art.outfit.top.inherit = {"down_1": "down_0"}
	check(library.valid(art), "new frame can explicitly inherit an existing mask")
	check(preload("res://scripts/outfit_rules.gd").colors_for_frame(art, "down_1").has(index), "inherited mask is used by renderer")
	art.outfit.top.inherit.down_1 = "missing"
	check(not library.valid(art), "missing inherited mask is rejected")
	art.outfit.top.inherit.down_1 = "down_0"
	var published: Dictionary = library.patch("white-haired-girl", {"base_revision": original.revision, "outfit": art.outfit})
	check(published.ok and library.artworks["white-haired-girl"].frames == original.frames, "outfit patch publishes without changing source frames")
	check(not library.patch("white-haired-girl", {"base_revision": original.revision, "outfit": art.outfit}).ok, "stale outfit patch cannot overwrite another revision")
	var restored := Library.new()
	restored.configure(directory)
	var saved: Dictionary = restored.artworks["white-haired-girl"].outfit.top
	check(saved.enabled and int(saved.colors[str(source)]) == target and int(saved.masks.down_0[0]) == index, "optional outfit survives reload")
	art.outfit.top.masks.down_0 = [-1]
	check(not library.valid(art), "negative mask is rejected")
	art.outfit.top.masks.down_0 = [index, index]
	check(not library.valid(art), "duplicate mask is rejected")
	art.outfit.top.masks.down_0 = [index]
	art.outfit.top.colors[str(source)] = art.palette.size()
	check(not library.valid(art), "colors outside existing palette are rejected")
	art.outfit.top.colors[str(source)] = target
	art.outfit.top.masks["nonexistent"] = [index]
	check(not library.valid(art), "unknown frame mask is rejected")
	print("Outfit foundation: %s checks, %s" % [checks, "FAIL" if failed else "PASS"])
	quit(1 if failed else 0)
