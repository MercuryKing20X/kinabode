extends "res://tests/probe_empowered_live.gd"
func run()->void:
	base=OS.get_environment("HABITAT_DATA_DIR")
	if OS.get_environment("HABITAT_LIVE_TEST")!="1" or not base.contains("habitat-live-test-youqi-"):quit(1);return
	root.size=Vector2i(1280,800);OS.set_environment("HABITAT_OPENING","showcase")
	var title:Node=load("res://scenes/title.tscn").instantiate();root.add_child(title);current_scene=title;await ready_frames(10)
	await UI.click(self,title.menu.get_node("connections"));await UI.click(self,title.connection_panel.buttons.codex)
	var pool:Node=title.connection_panel.pool
	var begin:int=Time.get_ticks_msec()
	while pool.states.get("codex",{}).get("state")!="ready" and Time.get_ticks_msec()-begin<45000:await create_timer(.1).timeout
	if pool.states.get("codex",{}).get("state")!="ready":print("LIVE_CONNECT_FAILED");quit(1);return
	title.queue_free();await ready_frames()
	game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game);current_scene=game;game.save_enabled=false;game.set_process(false);game.memory_life.set_process(false);await ready_frames(10)
	game.links.codex.event_received.connect(record_event)
	game.steward.pool.set_management("codex",true)
	game.chat.hide();game.chat_input.release_focus()
	check(game.steward.start("codex"),"explicit single manager")
	begin=Time.get_ticks_msec()
	while Time.get_ticks_msec()-begin<75000:
		game._process(.1)
		if events.any(func(e):return e.event.kind=="intent_result"):break
		await create_timer(.1).timeout
	game.memory_books.atomic(base.path_join("human-live.json"),{"events":events,"timeline":game.steward.timeline,"usage":game.autonomy.scheduler.usage("codex")})
	game.steward.stop();game.links.codex.shutdown();game.queue_free();await ready_frames();print("SINGLE_LIVE_DONE ",base);quit()
