class_name SharedCompanionLink
extends "res://scripts/companion_link.gd"
## Bounded local FIFO; one actual model turn at a time, zero model idle polling.
const QUEUE_LIMIT := 3
var queued: Array[Dictionary] = []
var connection_state := "idle"
var thread_id := ""
var completed_responses := 0
var snapshot_provider: Callable

func _init() -> void:
	bridge_files = ["companion.py", "file_transport.py", "action_contract.py", "model_actions_mcp.py", "shared_companion.py", "codex_unix_websocket.py"]
	helper_filename = "shared_companion.py"
	runtime_namespace = "shared-runtime"
	data_namespace = "shared-companion"

func can_queue() -> bool:
	return not _cancelling and not _shutting_down and queued.size() < QUEUE_LIMIT

func _emit(event: Dictionary) -> void:
	if event.get("kind") == "assistant": completed_responses += 1
	if event.get("kind") == "state":
		connection_state = str(event.get("state", "idle"))
	if event.get("kind") == "error": connection_state = "error"
	if connection_state in ["error", "disconnected", "cancelled"] and not queued.is_empty():
		event = event.duplicate(true)
		event["message"] = str(event.get("message", "")) + LocalText.text("connection.shared_companion_link.s_unsent_messages_were_canceled") % queued.size()
		queued.clear()
	super._emit(event)

func send_message(text: String, snapshot: Dictionary) -> void:
	if text.strip_edges().is_empty(): return
	if not can_queue():
		_error(LocalText.text("connection.shared_companion_link.the_queue_is_full_or_stopping_your_input_is"))
		return
	if is_busy() or not queued.is_empty():
		queued.append({"text": text.left(4000), "snapshot": snapshot.duplicate(true)})
		_emit({"kind": "queue", "count": queued.size(), "message": LocalText.text("connection.shared_companion_link.queued_it_will_be_handled_after_the_earlier_response")})
		return
	connection_state = "connecting" if _pid <= 0 else "thinking"
	super.send_message(text, snapshot)

func _dispatch_next() -> void:
	if is_busy() or _cancelling or _shutting_down or queued.is_empty(): return
	var next: Dictionary = queued.pop_front()
	if snapshot_provider.is_valid():
		var fresh: Dictionary = snapshot_provider.call()
		if next.snapshot.has("selected_object_id"): fresh["selected_object_id"] = next.snapshot.selected_object_id
		if next.snapshot.has("dialogue"): fresh["dialogue"] = next.snapshot.dialogue
		next.snapshot = fresh
	connection_state = "thinking"
	super.send_message(next.text, next.snapshot)

func cancel_turn() -> void:
	queued.clear()
	connection_state = "cancelling"
	super.cancel_turn()

func shutdown() -> void:
	queued.clear()
	super.shutdown()

func _error(message: String) -> void:
	connection_state = "error"
	super._error(message)

func _accept_event(event: Dictionary) -> void:
	if _cancelling and event.get("kind") not in ["state"]: return
	if event.get("kind") == "state" and event.get("state") == "ready" and not event.get("turnComplete", false):
		if event.has("threadId"): thread_id = str(event.threadId)
		# Startup readiness is not completion of the user's first message.
		return
	if event.get("kind") == "state":
		connection_state = str(event.get("state", "idle"))
		if event.has("threadId"): thread_id = str(event.threadId)
	if event.get("kind") == "error":
		connection_state = "error"
	super._accept_event(event)
	if event.get("kind") == "state" and event.get("state") == "ready":
		call_deferred("_dispatch_next")

func connection_description() -> String:
	if _pid <= 0 and connection_state not in ["idle", "cancelled"]: connection_state = "disconnected"
	var label: String = {"idle":LocalText.text("connection.shared_companion_link.waiting_for_you"), "connecting":LocalText.text("connection.shared_companion_link.connecting"), "thinking":LocalText.text("connection.shared_companion_link.responding"), "acting":LocalText.text("connection.shared_companion_link.processing"), "waiting":LocalText.text("connection.shared_companion_link.waiting_for_your_answer"), "cancelling":LocalText.text("connection.shared_companion_link.stopping"), "cancelled":LocalText.text("connection.shared_companion_link.stopped"), "ready":LocalText.text("connection.shared_companion_link.waiting_for_you"), "error":LocalText.text("connection.shared_companion_link.connection_error"), "disconnected":LocalText.text("connection.shared_companion_link.disconnected")}.get(connection_state, LocalText.text("connection.shared_companion_link.waiting_for_you"))
	return LocalText.text("connection.shared_companion_link.test_companion") + label + (LocalText.text("connection.shared_companion_link.s_queued") % queued.size() if not queued.is_empty() else "")

func autonomy_capabilities() -> Dictionary:
	return {"supported":false,"reason":LocalText.text("connection.shared_companion_link.shared_test_connections_do_not_support_budgeted_autonomous_turns"),"levels":[]}
