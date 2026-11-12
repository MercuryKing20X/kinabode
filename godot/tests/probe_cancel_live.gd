extends "res://tests/probe_memory_live.gd"
func run()->void:
	var base:String=OS.get_environment("HABITAT_DATA_DIR")
	if OS.get_environment("HABITAT_LIVE_TEST")!="1" or not base.contains("habitat-live-test-youqi-"):quit(1);return
	await fresh();game.memory_life.set_process(false)
	game.world.director.set_controller("codex","model");game._ensure_link("codex");game.chat_actor="codex"
	game.connection_ui_states["codex:direct"]="ready"
	game.steward.pool.set_management("codex",true)
	game.steward.pool.settings.set_value("steward_prompt","codex",true)
	game.steward.start("codex");game.steward.reasons.clear()
	game.links.codex.event_received.connect(func(e):
		if e.kind in ["state","usage","error","intent_result"]:receipts.append({"attempt":attempt,"event":e.duplicate(true)}))
	for level in ["ultra","lifeblood"]:
		game.resident_connections.preferences.choose("codex",level)
		for words in ["去砍树","你在干嘛","跟我走","今天天气不错","我们来玩丢手绢"]:
			attempt+=1
			preload("res://tests/dialogue_ui_fixture.gd").open(game,"codex")
			await text_input(words,true)
			await wait_reply(game.links.codex)
			game.memory_books.atomic(base.path_join("cancel-live.json"),{"receipts":receipts,"history":game.intentions.history,"jobs":game.world.work.jobs,"play":game.playground.kind,"usage":game.autonomy.scheduler.usage("codex"),"checks":checks,"failed":failed})
		game.playground.stop()
	game.queue_free();await process_frame;quit(1 if failed else 0)
