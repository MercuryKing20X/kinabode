extends "res://tests/capture_workshop.gd"
func run() -> void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"): quit(1); return
	output = OS.get_environment("HABITAT_RUN_EVIDENCE")
	if output.is_empty(): quit(1); return
	root.size = Vector2i(1280, 800)
	game = load("res://scenes/main_v3.tscn").instantiate(); root.add_child(game)
	game.save_enabled = false; game.view.sound_enabled = false; game.world.director.set_all_enabled(false)
	game._toggle_workshop(); game.editor.open_art("human-starter")
	game.editor._create_outfit(); game.editor.outfit_toggle.pressed.emit()
	await shot("05-outfit-editor")
	game.editor._open_assembler(); await shot("06-assembler")
	game.editor._assemble_character(); await shot("07-assembled-work")
	quit()
