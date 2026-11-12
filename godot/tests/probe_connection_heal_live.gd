extends "res://tests/probe_empowered_live.gd"
func run()->void:
	base=OS.get_environment("HABITAT_DATA_DIR")
	if OS.get_environment("HABITAT_LIVE_TEST")!="1" or not base.contains("habitat-live-test-youqi-"):quit(1);return
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	OS.set_environment("HABITAT_OPENING","showcase")
	var title:Node=load("res://scenes/title.tscn").instantiate();root.add_child(title);await ready_frames(10)
	await UI.click(self,title.menu.get_node("connections"));await UI.click(self,title.connection_panel.buttons.codex)
	var pool:Node=title.connection_panel.pool
	var start:int=Time.get_ticks_msec()
	while pool.states.get("codex",{}).get("state")!="ready" and Time.get_ticks_msec()-start<45000:await create_timer(.1).timeout
	check(pool.states.get("codex",{}).get("state")=="ready","live handshake")
	if failed:quit(1);return
	var owned_pid:int=pool.links.codex._pid
	if owned_pid>0:OS.kill(owned_pid)
	start=Time.get_ticks_msec()
	while Time.get_ticks_msec()-start<45000:
		await create_timer(.1).timeout
		if pool.states.get("codex",{}).get("state")=="ready" and pool.links.codex._pid!=owned_pid:break
	check(pool.links.codex._pid!=owned_pid and pool.states.codex.state=="ready","owned process death healed")
	title.queue_free();await ready_frames()
	game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false);game.memory_life.set_process(false);await ready_frames(10)
	game.links.codex.event_received.connect(record_event)
	preload("res://tests/dialogue_ui_fixture.gd").open(game,"codex")
	if OS.get_environment("HABITAT_LIVE_PLAN_ONLY")!="1":
		await one("小白，你回来啦？",8)
		await one("现在岛上有什么好玩的？",9)
	game.steward.pool.set_management("codex",true);game.steward.start("codex")
	game.chat.hide();game.chat_input.release_focus();game.steward.queue.clear();game.steward.reasons=["host_requested_planning"];game.steward.request_plan()
	start=Time.get_ticks_msec()
	while Time.get_ticks_msec()-start<90000:
		game._process(.1);await create_timer(.1).timeout
		if seen_keys.size()>=(1 if OS.get_environment("HABITAT_LIVE_PLAN_ONLY")=="1" else 3) and not game.links.codex.is_busy():break
	game.memory_books.atomic(base.path_join("heal-live.json"),{"checks":checks,"failed":failed,"events":events,"turns":turns,"planning":game.steward.timeline})
	game.steward.stop();pool.disconnect_ai("codex");game.queue_free();await ready_frames();quit(1 if failed else 0)
