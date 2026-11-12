extends SceneTree
const Talk=preload("res://tests/dialogue_ui_fixture.gd")
var checks := 0
var failed := false
class FakeShared extends "res://scripts/shared_companion_link.gd":
	var submitted: Array[Dictionary] = []
	func _start() -> bool: return true
	func _send(message: Dictionary) -> bool:
		submitted.append(message.duplicate(true)); return true
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failed = true; push_error(label)
func run() -> void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"): quit(1); return
	var game: Node = load("res://scenes/main.tscn").instantiate()
	game.shared_test = true; root.add_child(game); game.save_enabled = false; game.set_process(false); game.view.sound_enabled = false
	await process_frame
	Talk.open(game,"codex")
	check(game.links.codex.has_method("can_queue") and game.links.codex._pid == -1, "shared mode never starts inference on opening")
	check(game.controller_picker.get_item_text(0) == "共享测试 · 自动" and not game.relay_button.visible, "test identity and automatic transport explicit")
	check(not game.links["companion-2"].has_method("can_queue"), "only selected test resident uses new connection")
	game.links.codex.queue_free()
	var link := FakeShared.new(); game.add_child(link); game.links.codex = link; game.link = link
	link.event_received.connect(game._bound_companion_event.bind("codex"))
	Talk.send(game,"第一条")
	Talk.send(game,"第二条")
	link.queued[0].snapshot["dialogue"] = {"channel_id":"direct:codex", "message_id":"second"}
	Talk.send(game,"第三条")
	Talk.send(game,"第四条")
	check(link.submitted.size() == 1 and link.queued.size() == 3, "one active inference and bounded FIFO")
	link._accept_event({"kind":"state","state":"ready","threadId":"test-thread","turnComplete":false}); await process_frame
	check(link.submitted.size() == 1 and link.is_busy(), "initial connection ready never advances the pending FIFO")
	game.chat_input.text = "第五条草稿"; Talk.send(game,game.chat_input.text)
	check(game.chat_input.text == "第五条草稿" and not game.chat_log.get_parsed_text().contains("你 → 小白：第五条"), "full queue preserves draft without fake acceptance")
	link.snapshot_provider = func(): return {"snapshot_revision":999,"self":{"job":{}}}
	link._accept_event({"kind":"assistant","text":"第一条的真实来源在测试中用替身验证界面。"})
	check(link.completed_responses == 1, "one displayed assistant event increments response count exactly once")
	link._accept_event({"kind":"state","state":"ready","turnComplete":true}); await process_frame
	check(link.submitted.size() == 2 and link.submitted[1].text == "第二条" and link.queued.size() == 2, "completion sends precisely next queued message")
	check(link.submitted[1].world.snapshot_revision == 999, "queued turn reads fresh world state when actually dispatched")
	check(link.submitted[1].world.dialogue.message_id == "second", "fresh snapshot keeps the queued message's original channel identity")
	check(link._generation == 2 and game.view.speech_actor == "codex", "each queued turn has fresh generation and own bubble")
	game._stop_companion()
	check(link.queued.is_empty() and not link.is_busy(), "stop clears all pending messages")
	link._accept_event({"kind":"state","state":"ready","turnComplete":true}); await process_frame
	check(link.submitted.size() == 2, "late ready cannot resurrect cancelled FIFO")
	Talk.send(game,"新的消息"); Talk.send(game,"等待中的消息")
	link._emit({"kind":"state","state":"disconnected"})
	check(link.queued.is_empty(), "transport loss clears waiting queue without auto replay")
	link._busy = false
	Talk.send(game,"又一条"); Talk.send(game,"不能迟到")
	link._error("测试断线")
	check(link.queued.is_empty(), "error drops deferred work")
	link._busy = true; link._pid = 999999
	link.cancel_turn()
	var before := link.completed_responses
	link._accept_event({"kind":"assistant","text":"late cancelled response"})
	check(link.completed_responses == before and not game.chat_log.get_parsed_text().contains("late cancelled response"), "cancel barrier blocks late text")
	link._accept_event({"kind":"state","state":"cancelled"})
	check(not link.is_busy(), "acknowledged cancellation releases input")
	link._pid = -1
	game._toggle_shared_test()
	check(not game.shared_test and not game.links.codex.has_method("can_queue"), "can explicitly return to original connection")
	game._toggle_shared_test()
	check(game.shared_test and game.links.codex._pid == -1, "switch back stays lazy")
	game.queue_free(); await process_frame
	print("Shared dialogue: %s checks" % checks)
	quit(1 if failed else 0)
