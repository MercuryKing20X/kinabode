extends "res://tests/test_one_line_cloud_stub.gd"
func fresh()->void:
	await super.fresh()
	check(await UI.click(self,game.dialogue_button),"open actual chat")
	check(game.chat_input.visible and not game.command_page.tabs.visible,"unified dialogue is directly available")
	game._select_chat("companion-2")
