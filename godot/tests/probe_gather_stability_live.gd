extends "res://tests/probe_empowered_live.gd"
func run()->void:
	base=OS.get_environment("HABITAT_DATA_DIR")
	if OS.get_environment("HABITAT_LIVE_TEST")!="1" or not base.contains("habitat-live-test-youqi-"):quit(1);return
	OS.set_environment("HABITAT_OPENING","showcase")
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	var title:Node=load("res://scenes/title.tscn").instantiate();root.add_child(title);current_scene=title;await ready_frames(10)
	await UI.click(self,title.menu.get_node("connections"));await UI.click(self,title.connection_panel.buttons.codex)
	var pool:Node=title.connection_panel.pool
	var began:int=Time.get_ticks_msec()
	while pool.states.get("codex",{}).get("state")!="ready" and Time.get_ticks_msec()-began<45000:await create_timer(.1).timeout
	if pool.states.get("codex",{}).get("state")!="ready":print("LIVE_HANDSHAKE_FAILED");quit(1);return
	title.queue_free();await ready_frames()
	game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game);current_scene=game;game.save_enabled=false;game.set_process(false);game.memory_life.set_process(false);await ready_frames(10)
	game.links.codex.event_received.connect(record_event)
	preload("res://tests/dialogue_ui_fixture.gd").open(game,"codex")
	game.autonomy.scheduler.preferences.choose("codex","ultra");game.autonomy.scheduler.preferences.enable_autonomy("codex",true)
	game.steward.pool.set_management("codex",true);game.steward.start("codex")
	for words in ["你好呀","今天风景真好","你喜欢下雨吗","过来陪我","你在想什么","去营火烤蘑菇叫大家来吃","慢慢来","你喜欢什么","我们一起看星星吧","谢谢你"]:
		number+=1
		await text_input(words)
		var start:int=Time.get_ticks_msec()
		while game.links.codex.is_busy() and Time.get_ticks_msec()-start<60000:
			game._process(.1);await create_timer(.1).timeout
		turns.append({"human":words,"elapsed_ms":Time.get_ticks_msec()-start,"busy":game.links.codex.is_busy()})
		if game.links.codex.is_busy():break
	var target:float=game.world.forest.clock+1800
	while game.world.forest.clock<target:
		game._process(.5)
		if int(game.world.forest.clock)%20==0:await process_frame
	await picture("stable-live-end")
	game.memory_books.atomic(base.path_join("stability-live.json"),{"events":events,"turns":turns,"clock":game.world.forest.clock})
	game.links.codex.shutdown();game.queue_free();await ready_frames();quit()
