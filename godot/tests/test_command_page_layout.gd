extends "res://tests/test_intelligence_core_input.gd"
func run()->void:
	await fresh()
	check(await UI.click(self,game.journey.map_button),"map click")
	game.journey._process(0);await process_frame;await picture("final-navigation")
	check(await UI.click(self,game.journey.shortcuts.get_child(0)),"map entry click")
	check(game.atlas.visible,"actual atlas visible")
	await picture("final-atlas");game._toggle_atlas(false)
	check(await UI.click(self,game.dialogue_button),"commands click")
	game.command_page.category=2;game.command_page.rebuild();await picture("final-zh")
	TranslationServer.set_locale("en");preload("res://scripts/localization.gd").events.changed.emit()
	game.command_page.show_mode(true);game.command_page.rebuild_targets();game.command_page.rebuild()
	await picture("final-en")
	root.size=Vector2i(960,640);await process_frame;game.command_page.show_mode(true);await picture("final-960")
	game.queue_free();await process_frame
	print("COMMAND_LAYOUT ",checks," failed=",failed);quit(1 if failed else 0)
