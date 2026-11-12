extends "res://tests/probe_first_real_ai.gd"
func fresh()->void:
	await super.fresh()
	await UI.click(self,game.dialogue_button)
	await UI.click(self,game.command_page.tabs.get_child(1))
	game._select_chat("companion-2")
	await text_input("帮我砍三棵树",true)
	await step_time(150)
	await scenario("@camp")
	await scenario("@forage")
	await scenario("@meal")
	# Finish the real circle through the host's explicit local stop.
	if OS.get_environment("HABITAT_KEEP_CIRCLE")!="1":
		if not game.chat.visible:await UI.click(self,game.dialogue_button)
		if game.command_page.commands_mode:await UI.click(self,game.command_page.tabs.get_child(1))
		game._select_chat("codex");await text_input("别干了",true)
	# Keep preparation facts through original save, without granting stock or history.
	preload("res://scripts/save_store.gd").save_world(game.world,OS.get_environment("HABITAT_DATA_DIR").path_join("prepared"))
	if OS.get_environment("HABITAT_PREPARE_AUTONOMY")=="1":
		if not game.chat.visible:await UI.click(self,game.dialogue_button)
		if game.command_page.commands_mode:await UI.click(self,game.command_page.tabs.get_child(1))
		game._select_chat("companion-2");await text_input("帮我种萝卜",true);await step_time(160);await step_time(1210)
	if OS.get_environment("HABITAT_PREPARE_CHESS")=="1":
		if not game.chat.visible:await UI.click(self,game.dialogue_button)
		if game.command_page.commands_mode:await UI.click(self,game.command_page.tabs.get_child(1))
		game._select_chat("codex");await text_input("别干了",true)
		game._select_chat("companion-2");await text_input("帮我砍九棵树",true)
		for tick in 4000:
			game._process(.1);game.local_host_commands._process(.1)
			if not game.world.work.jobs.has("companion-2"):break
			if tick%30==0:await process_frame
		await scenario("@meal")
		if not game.chat.visible:await UI.click(self,game.dialogue_button)
		if game.command_page.commands_mode:await UI.click(self,game.command_page.tabs.get_child(1))
		game._select_chat("codex");await text_input("别干了",true)
	game.chat.hide()
	print("PREPARATION real stock ",JSON.stringify(game.world.storage.saved()))
