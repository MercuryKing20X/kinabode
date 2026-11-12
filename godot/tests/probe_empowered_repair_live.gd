extends "res://tests/probe_empowered_live.gd"
func finished(index:int)->bool:
	if index==8:
		return not game.intentions.plans.has("codex") and game.world.barbecues.values().any(func(life):return life.fireside.state.get("roast_by")=="codex" and not life.fireside.state.current.is_empty() and life.fireside.state.current.food_id=="fish" and life.fireside.state.current.eaten==life.fireside.state.current.total)
	return true
func run()->void:
	base=OS.get_environment("HABITAT_DATA_DIR")
	if OS.get_environment("HABITAT_LIVE_TEST")!="1" or not base.contains("habitat-live-test-") or not base.contains("youqi-"):quit(1);return
	OS.set_environment("HABITAT_OPENING","showcase")
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game);current_scene=game;game.save_enabled=false;game.set_process(false);game.memory_life.set_process(false)
	await ready_frames(10)
	game.resident_connections.open("codex");await ready_frames()
	check(await UI.click(self,game.resident_connections.connect_button),"explicit repair handshake")
	var began:=Time.get_ticks_msec()
	while game.links.codex.is_busy() and Time.get_ticks_msec()-began<45000:await create_timer(.1).timeout
	check(game._connection_light("codex").state=="ready","repair connection ready")
	if failed:quit(1);return
	game.resident_connections.close_panel();game.links.codex.event_received.connect(record_event)
	preload("res://tests/dialogue_ui_fixture.gd").open(game,"codex")
	await one("先逛逛，再去钓鱼，回来烤鱼",8)
	if game._connection_light("codex").state=="ready":await one("我想写个整理文件的小工具，应该从哪里开始？",9)
	game.memory_books.atomic(base.path_join("empowered-live-results.json"),{"attempts":turns.size(),"turn_numbers":[8,9],"seen_turn_keys":seen_keys.keys(),"turns":turns,"events":events,"checks":checks,"failed":failed,"note":"Only the two failed acceptance details are retried. Original attempts remain retained."})
	game.links.codex.shutdown();game.queue_free();await ready_frames()
	print("EMPOWERED_REPAIR_LIVE_DONE ",base);quit(1 if failed else 0)
