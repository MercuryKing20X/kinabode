extends "res://tests/probe_memory_live.gd"
func run()->void:
	var directory:String=OS.get_environment("HABITAT_DATA_DIR")
	if OS.get_environment("HABITAT_LIVE_TEST")!="1" or not directory.contains("habitat-live-test-youqi-"):quit(1);return
	await fresh();game.memory_life.set_process(false)
	game.world.director.set_controller("codex","model");game.resident_connections.preferences.choose("codex","ultra");game._ensure_link("codex");game.chat_actor="codex"
	game.links.codex.event_received.connect(func(e):
		if e.kind in ["usage","error","intent_result"]:receipts.append({"attempt":attempt,"event":e.duplicate(true)}))
	preload("res://tests/dialogue_ui_fixture.gd").open(game,"codex")
	for words in ["小白，早上好呀。","你喜欢晴天还是雨天？","今天想聊点什么？","一起看看海好吗？","有你在真好。"]:await ask(words)
	game.memory_books.atomic(directory.path_join("speed-live.json"),receipts)
	game.queue_free();await process_frame;quit(1 if failed else 0)
