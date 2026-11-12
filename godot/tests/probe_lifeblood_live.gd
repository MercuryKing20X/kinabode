extends "res://tests/probe_empowered_live.gd"
func run()->void:
	base=OS.get_environment("HABITAT_DATA_DIR")
	if OS.get_environment("HABITAT_LIVE_TEST")!="1" or not base.contains("habitat-live-test-youqi-"):quit(1);return
	OS.set_environment("HABITAT_OPENING","showcase")
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game);current_scene=game;game.save_enabled=false;game.set_process(false);game.memory_life.set_process(false)
	await ready_frames(10)
	game.world.director.set_controller("codex","model");game._ensure_link("codex");game.links.codex.event_received.connect(record_event)
	game.links.codex._start()
	var started:int=Time.get_ticks_msec()
	while game._connection_light("codex").state!="ready" and Time.get_ticks_msec()-started<60000:await create_timer(.1).timeout
	game.resident_connections.open("codex");await ready_frames()
	var panel:Node=game.resident_connections
	await UI.reveal(self,panel.tabs);await mouse_at(panel.tabs.global_position+panel.tabs.get_tab_rect(2).get_center());await ready_frames()
	await UI.click(self,panel.level_picker);await key_press(KEY_HOME)
	for step in range(5):await key_press(KEY_DOWN)
	await key_press(KEY_ENTER);await ready_frames()
	if not panel.life_dialog.visible:
		print("LIFE_UI_DIAG ",panel.level_picker.selected," ",panel.level_picker.disabled," ",panel.selected_id," ",panel.tabs.current_tab)
	check(panel.life_dialog.visible,"Lifeblood warning visible")
	check(panel.life_dialog.get_ok_button().disabled,"unchecked warning cannot confirm")
	await picture("lifeblood-warning")
	await UI.click(self,panel.life_ack);await UI.click(self,panel.life_dialog.get_ok_button());await ready_frames()
	check(panel.preferences.preference("codex").level=="lifeblood","real checked input enables Lifeblood")
	await picture("lifeblood-enabled");panel.close_panel();game.chat.hide();game.chat_input.release_focus()
	if failed:
		game.links.codex.shutdown();game.queue_free();await ready_frames();quit(1);return
	var initial:float=game.world.forest.clock
	for tick in range(600):
		game.autonomy.scheduler.input_received();game._process(1.0)
		await create_timer(.01).timeout
		started=Time.get_ticks_msec()
		while game.links.codex.is_busy() and Time.get_ticks_msec()-started<120000:await create_timer(.1).timeout
		if game.links.codex.is_busy():break
	var usage:Array=events.filter(func(e):return e.event.kind=="usage")
	game.memory_books.atomic(base.path_join("lifeblood-live.json"),{"checks":checks,"failed":failed,"game_seconds":game.world.forest.clock-initial,"events":events,"usage":usage,"records":game.autonomy.status("codex"),"history":game.intentions.history,"memory":game.memory_books.list_for("codex")})
	panel.open("codex");await ready_frames();await UI.click(self,panel.downgrade);check(panel.preferences.preference("codex").level=="ultra","one click downgrade")
	game.links.codex.shutdown();await create_timer(1).timeout;game.queue_free();await ready_frames();quit(1 if failed else 0)
