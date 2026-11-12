extends SceneTree
## Explicit opt-in: the assistant in the existing thread must read and reply.
## No app-server is created. The automatic desktop wake-up remains unimplemented.
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var directory := OS.get_environment("HABITAT_DATA_DIR")
	var thread_id := OS.get_environment("CODEX_THREAD_ID")
	if OS.get_environment("HABITAT_LIVE_CONVERSATION_TEST") != "1" or not directory.contains("habitat-live-test-"):
		push_error("Live conversation test needs explicit opt-in and disposable data."); quit(1); return
	var game: Node = load("res://scenes/main.tscn").instantiate()
	game.conversation_thread = thread_id
	root.add_child(game); game.save_enabled = false; game.view.sound_enabled = false
	await process_frame
	game._select_chat("codex")
	game._send("【原会话转接验证】这是有栖游戏发出的测试消息。请用一句话回复，确认你记得我们要和 AI 一起生活的目标。")
	var link: Node = game.links.codex
	var request_id: String = link.pending.get("request_id", "")
	print("LIVE_CONVERSATION_REQUEST ", request_id)
	var deadline := Time.get_ticks_msec() + 300000
	while Time.get_ticks_msec() < deadline and link.receipt.get("status") != "displayed":
		await create_timer(0.2).timeout
	if link.receipt.get("status") != "displayed": push_error("No real reply received."); quit(1); return
	if not game.chat_log.get_parsed_text().contains(link.receipt.text) or game.view.speech_actor != "codex":
		push_error("Reply did not reach actual native UI."); quit(1); return
	await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(directory.path_join("conversation-reply.png"))
	var result := {"ok": true, "request_id": request_id, "thread_id": thread_id,
		"receipt": link.receipt, "rendered_chat": game.chat_log.get_parsed_text(),
		"automatic_wakeup": false, "separate_model_started": link._pid > 0}
	var file := FileAccess.open(directory.path_join("conversation-result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  ")); file.close()
	print("LIVE_CONVERSATION_REPLY_DISPLAYED")
	game.queue_free(); await process_frame; quit()
