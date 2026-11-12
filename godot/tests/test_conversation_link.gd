extends SceneTree
const Talk=preload("res://tests/dialogue_ui_fixture.gd")
var checks := 0
var failed := false
const THREAD := "01a15cad-a6ec-7da2-8810-f64c34a67cbd"
const OTHER := "11111111-1111-1111-1111-111111111111"
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failed = true; push_error(label)

func request(game: Node, actor_id: String, operation: String, query: Dictionary) -> Dictionary:
	var token := ""
	for candidate in game.endpoint.bindings:
		if game.endpoint.bindings[candidate] == actor_id: token = candidate
	return game.endpoint.handle({"session": game.endpoint.session, "token": token,
		"expires": Time.get_unix_time_from_system()+5, "operation": operation, "query": query})

func run() -> void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"): quit(1); return
	var game: Node = load("res://scenes/main.tscn").instantiate()
	game.conversation_thread = THREAD
	root.add_child(game)
	game.save_enabled = false; game.set_process(false); game.view.sound_enabled = false
	await process_frame
	Talk.open(game,"codex")
	var link: Node = game.links.codex
	check(link.has_method("read_mailbox") and link._pid == -1, "original thread has a mailbox, never a new model process")
	check(not game.links["companion-2"].has_method("read_mailbox") and game.links["companion-2"]._pid == -1, "second resident stays independent and idle")
	check(game.controller_picker.get_item_text(0) == "原会话 · 手动转接" and game.relay_button.visible, "UI describes actual manual transport")
	check(request(game, "codex", "read_conversation", {"thread_id": OTHER}).error == "conversation_not_bound", "wrong thread cannot read pending message")
	Talk.send(game,"今晚一起烧烤好吗？")
	var inbox: Dictionary = request(game, "codex", "read_conversation", {"thread_id": THREAD})
	check(inbox.ok and inbox.status == "awaiting_relay" and not inbox.automatic_wakeup, "acceptance is waiting for relay, not delivered or inferred")
	check(inbox.request.text == "今晚一起烧烤好吗？" and inbox.request.world_id == game.world.world_id, "native input carries original text and live world identity")
	check(not inbox.request.context.has("objects"), "no whole-world snapshot or private history in the prompt")
	game.chat_input.text = "第二条先留着"
	Talk.send(game,game.chat_input.text)
	check(game.chat_input.text == "第二条先留着" and not game.chat_log.get_parsed_text().contains("你 → 小白：第二条"), "busy send preserves draft and does not pretend accepted")
	check(request(game, "companion-2", "read_conversation", {"thread_id": THREAD}).error == "existing_conversation_not_connected", "another resident cannot read Codex mailbox")
	var payload: Dictionary = inbox.request.duplicate(true); payload.text = "好呀，我们在火边聊一会儿。"
	var wrong: Dictionary = payload.duplicate(true); wrong.thread_id = OTHER
	check(not request(game, "codex", "reply_conversation", wrong).ok, "wrong conversation cannot reply")
	for key in ["session", "world_id", "resident_id", "request_id"]:
		wrong = payload.duplicate(true); wrong[key] = "wrong"
		check(not request(game, "codex", "reply_conversation", wrong).ok, "mismatched " + key + " rejected")
	wrong = payload.duplicate(true); wrong.generation = int(payload.generation) + 1
	check(not request(game, "codex", "reply_conversation", wrong).ok, "stale generation rejected")
	wrong = payload.duplicate(true); wrong.text = "a".repeat(8001)
	check(not request(game, "codex", "reply_conversation", wrong).ok, "oversized reply rejected")
	var delivered: Dictionary = request(game, "codex", "reply_conversation", payload)
	check(delivered.ok and delivered.receipt.status == "displayed" and not link.is_busy(), "receipt only after the native UI consumes a reply")
	check(game.chat_log.get_parsed_text().contains(payload.text) and game.view.speech_actor == "codex", "same reply reaches chat and bound resident bubble")
	var log_before: String = game.chat_log.get_parsed_text()
	check(not request(game, "codex", "reply_conversation", payload).ok and game.chat_log.get_parsed_text() == log_before, "replayed response cannot display twice")
	check(request(game, "codex", "read_conversation", {"thread_id": THREAD}).receipt.text == payload.text, "uncertain timeout can inspect actual receipt")
	Talk.send(game,"可以换个话题吗？")
	var cancelled: Dictionary = link.pending.duplicate(true); cancelled.text = "过期回复"
	game._stop_companion()
	check(not link.is_busy() and not request(game, "codex", "reply_conversation", cancelled).ok, "cancel detaches pending message and rejects stale reply")
	Talk.send(game,"重新聊聊")
	check(not request(game, "codex", "reply_conversation", cancelled).ok and link.is_busy(), "old reply cannot attach to a later message")
	check(link.copy_prompt().contains(link.pending.request_id) and link.copy_prompt().contains(THREAD), "manual forward includes exact destination and request")
	game._change_controller(1)
	check(not request(game, "codex", "read_conversation", {"thread_id": THREAD}).ok, "local takeover revokes mailbox access")
	check(not link.is_busy(), "takeover drops pending relay without killing desktop conversation")
	game.queue_free(); await process_frame
	print("Conversation link: %s checks" % checks)
	quit(1 if failed else 0)
