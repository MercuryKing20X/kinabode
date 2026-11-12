extends SceneTree
const Talk=preload("res://tests/dialogue_ui_fixture.gd")
var checks := 0
var failed := false
const Channels = preload("res://scripts/dialogue_channels.gd")
class FakeAdapter extends "res://scripts/companion_link.gd":
	var sent: Array[Dictionary] = []
	func _start() -> bool: return true
	func _send(message: Dictionary) -> bool:
		sent.append(message.duplicate(true)); return true
	func complete(text := "") -> void:
		if not text.is_empty(): _accept_event({"kind":"assistant", "text":text})
		_accept_event({"kind":"state", "state":"ready", "turnComplete":true})
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failed = true; push_error(label)
func run() -> void:
	var directory := OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"): quit(1); return
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game); game.save_enabled = false; game.set_process(false); game.view.sound_enabled = false
	await process_frame
	Talk.open(game,"codex")
	game.world.director.set_all_enabled(false)
	game.dialogue_adapter_factory = func(_id, _scope): return FakeAdapter.new()
	for connection in game.links.values(): connection.queue_free()
	game.links.clear(); game._ensure_link("codex"); game._ensure_link("companion-2"); game.link = game.links.codex
	var white: FakeAdapter = game.links.codex
	var blue: FakeAdapter = game.links["companion-2"]
	check(game.group_links.is_empty() and game.chat_picker.item_count == game.world.actors.size(), "all is an extra recipient, no model starts from opening")
	Talk.send(game,"私聊口令：白色贝壳")
	check(white.sent.size() == 1 and blue.sent.is_empty(), "direct message reaches only its selected adapter")
	white._accept_event({"kind":"state", "state":"ready", "turnComplete":false})
	check(white.is_busy(), "bootstrap ready cannot open another channel while a turn is active")
	game.chat_input.text = "我的私聊草稿"; game._select_chat(Channels.ALL)
	check(game.group_chat and game.chat_log.get_parsed_text().is_empty() and not game.daily_controls.visible, "all opens a separate group record without single-resident controls")
	Talk.send(game,"先发给空闲的伙伴")
	check(not game.group_links.has("codex") and game.group_links["companion-2"].sent.size() == 1, "busy direct recipient skipped without blocking other group recipients")
	check(game.chat_log.get_parsed_text().contains("未发送：小白"), "partial delivery is explicit")
	white.complete("私聊回复")
	check(not game.chat_log.get_parsed_text().contains("私聊回复") and game.dialogue.unread.has(Channels.direct("codex")), "late direct reply stays in direct channel and marks unread")
	game.group_links["companion-2"].complete()
	Talk.send(game,"大家好，今天一起逛逛吧")
	var group_white: FakeAdapter = game.group_links.codex
	var group_blue: FakeAdapter = game.group_links["companion-2"]
	check(group_white.sent.size() == 1 and group_blue.sent.size() == 2, "one group turn fans out once to every available model")
	check(group_white.sent[0].world.self.id == "codex" and group_blue.sent[-1].world.self.id == "companion-2", "same group message retains independent actor authority")
	check(group_white.sent[0].world.dialogue.message_id == group_blue.sent[-1].world.dialogue.message_id and group_white.sent[0].world.dialogue.recipient_ids.size() == 2, "same immutable group message identity and audience")
	check(not JSON.stringify(group_white.sent).contains("白色贝壳"), "private context never enters group envelope")
	check(group_white.session_data_directory(directory) != white.session_data_directory(directory), "model histories use separate direct and group storage")
	game.chat_input.text = "群聊草稿"; game._select_chat("codex")
	check(game.chat_input.text == "我的私聊草稿" and game.chat_log.get_parsed_text().contains("私聊回复") and not game.chat_log.get_parsed_text().contains("大家好"), "switch restores correct direct draft and history")
	Talk.send(game,"暂时不能双重控制")
	# B — DIRECTION 2026-11-09: “她在想时你又说话就排队/合并”；仍禁止并行控制同一居民。
	check(white.sent.size() == 1 and game.chat_input.text.is_empty() and game.next_chat.get("codex",[])==["暂时不能双重控制"], "group inference queues direct input without simultaneous control of same resident")
	group_blue.complete("小蓝的群聊回复")
	group_white.complete("小白的群聊回复")
	check(not game.chat_log.get_parsed_text().contains("群聊回复"), "group completion cannot leak into currently viewed direct chat")
	game._select_chat(Channels.ALL)
	check(game.chat_input.text == "群聊草稿" and game.chat_log.get_parsed_text().contains("小蓝的群聊回复") and game.chat_log.get_parsed_text().contains("小白的群聊回复"), "group restores draft and asynchronously ordered named replies")
	check(group_white.sent.size() == 1 and group_blue.sent.size() == 2, "model replies never trigger more inference")
	group_white._accept_event({"kind":"question", "id":"white-q", "text":"先去海边吗？", "choices":["去海边"]})
	group_blue._accept_event({"kind":"question", "id":"blue-q", "text":"带上花篮吗？", "choices":["带上"]})
	check(game.group_questions.size() == 2 and game.questions.is_empty() and game.question_picker.item_count == 3, "group questions each expose a distinct answer target")
	game._answer_group("codex", "wrong-id", "去")
	check(group_white.sent.size() == 1, "stale or mismatched question cannot be answered")
	for index in range(1, game.question_picker.item_count):
		if game.question_picker.get_item_metadata(index).actor_id == "companion-2": game.question_picker.select(index)
	Talk.send(game,"带上花篮")
	check(group_blue.sent[-1].kind == "tool_result" and group_blue.sent[-1].id == "blue-q" and group_white.sent.size() == 1, "free-form group answer reaches only selected asker")
	check(game.group_questions.has("codex") and not game.group_questions.has("companion-2"), "answering one group question preserves the other")
	game._answer_group("codex", "white-q", "去海边")
	check(group_white.sent[-1].id == "white-q" and game.group_questions.is_empty(), "choice answers maintain exact question identity")
	group_white.complete(); group_blue.complete()
	game._select_chat("codex"); Talk.send(game,"继续私聊")
	# The accepted direct messages share the real debounce window, then start once.
	while Time.get_ticks_msec()<int(game.next_chat_due.get("codex",0)):await create_timer(.05).timeout
	game._process(0)
	check(white.sent[-1].text=="暂时不能双重控制\n继续私聊","queued direct messages retain arrival order after group completion")
	game._select_chat(Channels.ALL); game._stop_companion()
	check(white.is_busy(), "stop group does not cancel an unrelated direct turn")
	white.complete()
	game.world.director.set_controller("npc.mira", "model")
	Talk.send(game,"新伙伴也来吧")
	check(game.group_links.has("npc.mira") and game.group_links["npc.mira"].sent.size() == 1, "newly connected NPC automatically joins recipients without name branches")
	for connection in game.group_links.values(): connection.complete()
	game._select_chat("npc.mira"); game._change_controller(1)
	game._bound_companion_event({"kind":"assistant", "text":"旧连接不应再说话"}, "npc.mira", "group")
	game._select_chat(Channels.ALL)
	check(not game.chat_log.get_parsed_text().contains("旧连接不应再说话"), "local takeover rejects stale group events")
	for i in range(3, 9): check(game.world.add_companion("companion-%s" % i, "测试伙伴%s" % i), "host can provision beyond five model residents")
	game._refresh_resident_names(); Talk.send(game,"扩展接口测试")
	check(game._group_recipients().size() == 8 and game.group_links["companion-8"].sent.size() == 1, "group routing is independent of the two default test actors")
	check(game.chat_picker.item_count == game.world.actors.size(), "recipient menu refreshes when host adds residents")
	for connection in game.group_links.values(): connection.complete()
	check(game.Save.save_world(game.world, directory), "expanded roster saves")
	var restored := preload("res://scripts/world_state.gd").new()
	check(game.Save.load_world(restored, directory).ok and restored.actors.has("companion-8"), "expanded roster survives reload without whitelist of five IDs")
	game._select_chat("npc.nora"); game._change_controller(0)
	game.world.residents.rename(game.world, "npc.nora", "新的名字"); game._refresh_resident_names()
	check(game.chat_picker.get_item_text(game.chat_picker.selected) == "新的名字", "recipient menu preserves identity when renamed")
	game._select_chat(Channels.ALL); game._refresh_control_status(); game.chat.show()
	if not OS.get_environment("HABITAT_DIALOGUE_CAPTURE").is_empty():
		await process_frame; await process_frame; await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("HABITAT_DIALOGUE_CAPTURE"))
	game.queue_free(); await process_frame
	print("Dialogue channels: %s checks, %s" % [checks, "FAIL" if failed else "PASS"])
	quit(1 if failed else 0)
