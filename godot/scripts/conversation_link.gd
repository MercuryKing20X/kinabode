class_name ConversationLink
extends Node
const LocalText=preload("res://scripts/localization.gd")
## Explicit existing-thread mailbox. This does not wake the desktop app or start a model.
signal event_received(event: Dictionary)

var resident_id := "codex"
var world_id := ""
var thread_id := ""
var _pid := -1 # Same lazy-link interface; this adapter never owns a model process.
var session := Crypto.new().generate_random_bytes(16).hex_encode()
var generation := 0
var pending: Dictionary = {}
var receipt: Dictionary = {}
var closed := false

static func valid_thread(value: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
	return pattern.search(value) != null

func is_busy() -> bool:
	return not pending.is_empty()

func send_message(text: String, snapshot: Dictionary) -> void:
	if closed or not valid_thread(thread_id):
		_error(LocalText.text("connection.conversation_link.the_original_conversation_binding_is_unavailable_no_independent_model"))
		return
	if is_busy():
		_error(LocalText.text("connection.conversation_link.the_previous_message_is_waiting_for_relay_reply_or"))
		return
	if text.strip_edges().is_empty(): return
	generation += 1
	pending = {
		"request_id": Crypto.new().generate_random_bytes(16).hex_encode(),
		"session": session, "generation": generation, "thread_id": thread_id,
		"resident_id": resident_id, "world_id": world_id, "text": text.left(4000),
		"created_at": Time.get_unix_time_from_system(),
		"context": {"selected_object_id": snapshot.get("selected_object_id", ""),
			"self_actor_id": resident_id, "snapshot_revision": snapshot.get("snapshot_revision", 0)}
	}
	receipt = {}
	event_received.emit({"kind": "state", "state": "waiting", "message": LocalText.text("connection.conversation_link.waiting_for_the_original_conversation_automatic_wakeup_is_not")})

func read_mailbox(query: Dictionary) -> Dictionary:
	if query.get("thread_id") != thread_id or closed:
		return {"ok": false, "error": "conversation_not_bound"}
	return {"ok": true, "transport": "manual_relay", "automatic_wakeup": false,
		"thread_id": thread_id, "resident_id": resident_id,
		"status": "awaiting_relay" if is_busy() else "idle",
		"request": pending.duplicate(true), "receipt": receipt.duplicate(true)}

func receive_reply(query: Dictionary) -> Dictionary:
	if closed or query.get("thread_id") != thread_id:
		return {"ok": false, "error": "conversation_not_bound"}
	if pending.is_empty(): return {"ok": false, "error": "no_pending_message"}
	for key in ["request_id", "session", "generation", "world_id", "resident_id"]:
		if query.get(key) != pending.get(key): return {"ok": false, "error": "stale_conversation_reply"}
	var text: Variant = query.get("text")
	if not text is String or text.strip_edges().is_empty() or text.length() > 8000:
		return {"ok": false, "error": "invalid_reply"}
	receipt = {"request_id": pending.request_id, "thread_id": thread_id,
		"status": "displayed", "text": text, "received_at": Time.get_unix_time_from_system()}
	pending.clear()
	event_received.emit({"kind": "assistant", "text": text, "source": "existing_conversation", "thread_id": thread_id})
	event_received.emit({"kind": "state", "state": "ready", "message": LocalText.text("connection.conversation_link.the_original_conversation_s_reply_has_arrived")})
	return {"ok": true, "receipt": receipt.duplicate(true)}

func copy_prompt() -> String:
	if pending.is_empty(): return ""
	return LocalText.text("connection.conversation_link.youqi_player_message_original_conversation_relay") + JSON.stringify(pending) + LocalText.text("connection.conversation_link.reply_to_the_player_in_this_bound_conversation_first")

func cancel_turn() -> void:
	generation += 1
	if not pending.is_empty(): receipt = {"request_id": pending.request_id, "status": "cancelled"}
	pending.clear()
	event_received.emit({"kind": "state", "state": "cancelled", "message": LocalText.text("connection.conversation_link.game_message_canceled_if_the_original_conversation_is_running")})

func answer(_id: String, _result: Variant) -> void:
	_error(LocalText.text("connection.conversation_link.reply_to_a_question_from_the_original_conversation_as"))

func reply(_id: String, _result: Dictionary) -> void:
	_error(LocalText.text("connection.conversation_link.the_original_conversation_uses_game_tools_it_does_not"))

func shutdown() -> void:
	closed = true
	pending.clear()

func _exit_tree() -> void:
	shutdown()

func _error(message: String) -> void:
	event_received.emit({"kind": "error", "message": message})
