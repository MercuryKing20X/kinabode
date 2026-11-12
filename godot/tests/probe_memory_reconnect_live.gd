extends "res://tests/probe_memory_live.gd"
func run()->void:
	var directory:String=OS.get_environment("HABITAT_DATA_DIR")
	if OS.get_environment("HABITAT_LIVE_TEST")!="1" or not directory.contains("habitat-live-test-"):quit(1);return
	await fresh();game.memory_life.set_process(false)
	var w:RefCounted=game.world
	w.director.set_controller("codex","model");game._ensure_link("codex");game.chat_actor="codex"
	game.links.codex.event_received.connect(func(e):
		if e.kind in ["usage","error","intent_result"]:receipts.append({"attempt":4,"event":e.duplicate(true)}))
	preload("res://tests/dialogue_ui_fixture.gd").open(game,"codex")
	await ask("重新接上了。你还记得我喜欢什么吗？")
	await picture("live-reconnect-verified")
	game.memory_books.atomic(directory.path_join("live-reconnect-results.json"),receipts)
	game.queue_free();await process_frame;quit(1 if failed else 0)
