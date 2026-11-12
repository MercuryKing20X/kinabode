extends SceneTree
var events: Array[Dictionary] = []
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var directory := OS.get_environment("HABITAT_DATA_DIR")
	if OS.get_environment("HABITAT_LIVE_TEST") != "1" or not directory.contains("habitat-live-test-"):
		push_error("Live shared dialogue needs explicit opt-in and disposable data."); quit(1); return
	var marker := "海风" + Crypto.new().generate_random_bytes(3).hex_encode()
	var garden := "星光小院" + Crypto.new().generate_random_bytes(2).hex_encode()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	game.shared_test = true; root.add_child(game); game.save_enabled = false; game.view.sound_enabled = false
	await process_frame
	var link: Node = game.links.codex
	link.event_received.connect(func(event): events.append(event.duplicate(true)))
	game._select_chat("codex")
	game._send("我们做三轮聊天测试。请记住口令“" + marker + "”，只用一句简短中文确认，不用任何工具。")
	game._send("给咱们的小院取名“" + garden + "”。请记住这个名字，只用一句话确认，不用工具。")
	game._send("第三轮：我们刚才的口令和小院名字分别是什么？请准确说出两者，用一句话回答，不用工具。")
	print("LIVE_SHARED_THREE_MESSAGES_ACCEPTED")
	var deadline := Time.get_ticks_msec() + 240000
	while Time.get_ticks_msec() < deadline:
		if events.any(func(event): return event.kind == "error"): break
		if events.filter(func(event): return event.kind == "assistant").size() >= 3 and not link.is_busy() and link.queued.is_empty(): break
		await create_timer(.2).timeout
	var replies: Array = events.filter(func(event): return event.kind == "assistant").map(func(event): return event.text)
	var errors: Array = events.filter(func(event): return event.kind == "error")
	var result := {"ok":false,"marker":marker,"garden":garden,"thread_id":link.thread_id,
		"replies":replies,"errors":errors,"queued":link.queued.size(),"busy":link.is_busy(),
		"rendered_chat":game.chat_log.get_parsed_text(),"automatic_transport":true,
		"same_as_developer_conversation":link.thread_id == OS.get_environment("CODEX_THREAD_ID")}
	var status_path: String = directory.path_join("shared-companion/codex").path_join(game.world.world_id).path_join("shared-status.json")
	var first_status: Variant = JSON.parse_string(FileAccess.get_file_as_string(status_path)) if FileAccess.file_exists(status_path) else {}
	if replies.size() >= 3 and errors.is_empty() and not link.is_busy():
		var last: String = replies[-1]
		result.ok = last.contains(marker) and last.contains(garden) and not result.same_as_developer_conversation and game.view.speech_actor == "codex"
		await create_timer(2).timeout
		var idle_status: Variant = JSON.parse_string(FileAccess.get_file_as_string(status_path))
		result["idle_did_not_infer"] = first_status.get("messages_submitted") == idle_status.get("messages_submitted") and idle_status.get("messages_submitted") == 3
		result["service"] = idle_status
		result.ok = result.ok and result.idle_did_not_infer
	await process_frame; await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(directory.path_join("shared-dialogue.png"))
	var file := FileAccess.open(directory.path_join("shared-dialogue-result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "));file.close()
	print("LIVE_SHARED_RESULT ", JSON.stringify(result))
	game.queue_free(); await process_frame
	quit(0 if result.ok else 1)
