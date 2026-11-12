extends "res://tests/test_intelligence_core_input.gd"
var receipts:Array=[]
var attempt:=0
func wait_reply(connection:Node)->void:
	var began:int=Time.get_ticks_msec()
	while connection.is_busy() and Time.get_ticks_msec()-began<90000:await create_timer(.1).timeout
	if connection.is_busy():connection.cancel_turn();await create_timer(1).timeout
func ask(words:String)->void:
	attempt+=1
	if not game.chat.visible:await UI.click(self,game.dialogue_button)
	if game.command_page.commands_mode:await UI.click(self,game.command_page.tabs.get_child(1))
	await text_input(words)
	await wait_reply(game.links.codex)
func run()->void:
	var directory:String=OS.get_environment("HABITAT_DATA_DIR")
	if OS.get_environment("HABITAT_LIVE_TEST")!="1" or not directory.contains("habitat-live-test-"):quit(1);return
	await fresh();game.memory_life.set_process(false)
	var w:RefCounted=game.world
	# Only this isolated game-owned Xiaobai link may call the model.
	w.director.set_controller("codex","model");game._ensure_link("codex");game.chat_actor="codex"
	game.links.codex.event_received.connect(func(e):
		if e.kind in ["usage","error","intent_result"]:receipts.append({"attempt":attempt,"event":e.duplicate(true)}))
	preload("res://tests/dialogue_ui_fixture.gd").open(game,"codex")
	if game.command_page.commands_mode:await UI.click(self,game.command_page.tabs.get_child(1))
	await ask("我喜欢下雨。请把这句话记在关于我的笔记里，引用我这条原话的ID。")
	await picture("live-note")
	# Real gameplay, no stock grants: host builds available facilities using original UI.
	game.chat.hide();game.house_panel.open_site("home.house.01");await process_frame
	check(await UI.click(self,game.house_panel.build_all_button),"native host prerequisite")
	game.house_panel.hide()
	game._refresh_conversation_holds()
	check(preload("res://tests/barbecue_fixture.gd").meal(w,"single:mushroom",["human","codex"]),"real shared meal")
	w.memories.sync();game.memory_life._process(1.1)
	for i in 120:
		await process_frame;game.memory_life._process(1.1)
		if not game.memory_life.photo_busy and game.memory_life.photo_queue.is_empty():break
	var meal_day:int=w.days.day()
	# Request the single daily composition using real day sources (letter + portrait).
	while w.days.day()==meal_day:w.advance(10)
	game.memory_life.attempts.codex={"day":meal_day,"pending":true}
	attempt+=1;check(game.memory_life.request_daily("codex"),"daily memory composition dispatched")
	await wait_reply(game.links.codex)
	game.book_panel.open();game.book_panel.tabs.select(2);game.book_panel.refresh();await picture("live-letter-photo")
	game.book_panel.tabs.select(4);game.book_panel.refresh();await picture("live-portrait");game.book_panel.hide()
	# Disconnect and reattach original owned session through normal source controls.
	game.links.codex.shutdown();await create_timer(1).timeout;game.links.codex.queue_free();game.links.erase("codex");game._ensure_link("codex")
	game.links.codex.event_received.connect(func(e):
		if e.kind in ["usage","error","intent_result"]:receipts.append({"attempt":attempt,"event":e.duplicate(true)}))
	await ask("重新接上了。你还记得我喜欢什么吗？")
	await picture("live-reconnect")
	game.memory_books.export_html(directory.path_join("album.html"))
	game.memory_books.atomic(directory.path_join("live-memory-results.json"),{"attempts":attempt,"events":receipts,"letters":game.memory_books.list_for("codex","letters"),"portrait":game.memory_books.list_for("codex","about_you").filter(func(e):return e.params.get("kind","")=="portrait"),"checks":checks,"failed":failed})
	print("LIVE_MEMORY_RESULT ",directory," attempts=",attempt)
	game.queue_free();await process_frame;quit(1 if failed else 0)
