class_name CompanionLink
extends Node
const LocalText=preload("res://scripts/localization.gd")
## 非阻塞文件队列。玩家消息或显式开启的预算自主事件启动一轮。

signal event_received(event: Dictionary)

const FILES: Array[String] = ["intent_companion.py", "companion.py", "file_transport.py", "action_contract.py", "model_actions_mcp.py", "codex_high_budget.json"]
var bridge_files: Array[String] = FILES.duplicate()
var helper_filename := "companion.py"
var runtime_namespace := "runtime"
var data_namespace := "companion"
var conversation_scope := "direct"
const BUSY_STATES: Array[String] = ["connecting", "thinking", "acting", "waiting", "cancelling"]
const MAX_EVENT_BYTES: int = 2097152

var resident_id := "codex"
var world_id := ""
var persona_card:Dictionary={}
var handshake_ready:=false
var _pid: int = -1
var _session: String = ""
var _session_dir: String = ""
var _data_dir: String = ""
var _generation: int = 0
var _sequence: int = 0
var _busy: bool = false
var _cancelling: bool = false
var _pending_ids: Dictionary = {}
var _poll_elapsed: float = 0.0
var _heartbeat_elapsed: float = 0.0
var _started_at: int = 0
var _shutting_down: bool = false
var turn_kind := "chat"
var turn_key := ""
var capability_error := ""
var direct_api:Node
func _is_direct_api()->bool:
	var base:=OS.get_environment("HABITAT_DATA_DIR")
	if base.is_empty():base=ProjectSettings.globalize_path("user://")
	return preload("res://scripts/api_credentials.gd").read_settings(base).get_value("api",resident_id,"codex")=="openai"
func _direct()->Node:
	if not is_instance_valid(direct_api):
		direct_api=preload("res://scripts/direct_api_transport.gd").new();add_child(direct_api)
		direct_api.event_received.connect(_accept_event)
	_data_dir=OS.get_environment("HABITAT_DATA_DIR")
	if _data_dir.is_empty():_data_dir=ProjectSettings.globalize_path("user://")
	direct_api.directory=_data_dir;direct_api.resident_id=resident_id;direct_api.scope=conversation_scope
	set_meta("memory_provider","OpenAI-compatible")
	persona_card=preload("res://scripts/persona_cards.gd").card(resident_id,"",_data_dir)
	return direct_api
var autonomy_tool_limit := 0
var autonomy_tool_calls := 0

func autonomy_capabilities() -> Dictionary:
	return {"supported":capability_error.is_empty(),"reason":capability_error,"levels":["low","medium","high","ultra","lifeblood"]}

func send_autonomy(context: Dictionary,level: String,limits: Dictionary,key: String) -> bool:
	if is_busy() or level not in ["medium","high","ultra","lifeblood"] or not autonomy_capabilities().supported:return false
	var bounded:Dictionary=context.duplicate(true);bounded.erase("lifeblood_memory")
	if JSON.stringify(bounded).to_utf8_buffer().size()>4096:return false
	if context.has("lifeblood_memory") and (level!="lifeblood" or JSON.stringify(context.lifeblood_memory).to_utf8_buffer().size()>80000):return false
	if _daily_quota_reached():return false
	if _is_direct_api():
		turn_kind="autonomy_event";turn_key=key;_generation+=1;_busy=true
		var accepted:bool=_direct().send({"kind":"autonomy_event","world":context.duplicate(true),"level":level,"limits":limits,"turn_key":key},persona_card)
		if not accepted:_busy=false
		return accepted
	if not _start():return false
	turn_kind="autonomy_event";turn_key=key;autonomy_tool_limit=int(limits.get("tools",0));autonomy_tool_calls=0;_generation+=1;_busy=true;_pending_ids.clear()
	var accepted: bool=_send({"kind":"autonomy_event","world":context.duplicate(true),"level":level,"limits":limits.duplicate(),"turn_key":key})
	if not accepted:_busy=false
	return accepted


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)

func is_busy() -> bool:
	return _busy or _cancelling or (_shutting_down and _pid>0 and OS.is_process_running(_pid))

func _new_token() -> String:
	return Crypto.new().generate_random_bytes(20).hex_encode()

func _emit(event: Dictionary) -> void:
	event_received.emit(event)

func _error(message: String) -> void:
	_emit({"kind": "error", "message": message})

func _start() -> bool:
	if _is_direct_api():
		_busy=true;return _direct().connect_api()
	if _pid > 0 and OS.is_process_running(_pid):
		if _shutting_down:
			_error(LocalText.text("connection.companion_link.the_previous_connection_is_closing_send_again_in_a"))
			return false
		return true
	_data_dir = OS.get_environment("HABITAT_DATA_DIR")
	if _data_dir.is_empty():
		_data_dir = ProjectSettings.globalize_path("user://")
	_data_dir = ProjectSettings.globalize_path(_data_dir)
	var runtime_dir: String = _data_dir.path_join(runtime_namespace).path_join(resident_id)
	if DirAccess.make_dir_recursive_absolute(runtime_dir) != OK:
		_error(LocalText.text("connection.companion_link.cannot_create_the_game_dialogue_directory"))
		return false
	for filename in bridge_files:
		var source: FileAccess = FileAccess.open("res://bridge/" + filename, FileAccess.READ)
		if source == null:
			_error(LocalText.text("connection.companion_link.dialogue_components_are_missing_use_the_complete_game_installation"))
			return false
		var bytes: PackedByteArray = source.get_buffer(source.get_length())
		source.close()
		var target: FileAccess = FileAccess.open(runtime_dir.path_join(filename + ".tmp"), FileAccess.WRITE)
		if target == null:
			_error(LocalText.text("connection.companion_link.cannot_prepare_the_game_dialogue_components"))
			return false
		target.store_buffer(bytes)
		target.close()
		if DirAccess.rename_absolute(runtime_dir.path_join(filename + ".tmp"), runtime_dir.path_join(filename)) != OK:
			_error(LocalText.text("connection.companion_link.cannot_update_the_game_dialogue_components"))
			return false
	_session = _new_token()
	_session_dir = _data_dir.path_join("bridge-sessions").path_join(_session)
	for folder in ["inbox", "processing", "outbox"]:
		if DirAccess.make_dir_recursive_absolute(_session_dir.path_join(folder)) != OK:
			_error(LocalText.text("connection.companion_link.cannot_create_the_dialogue_message_queue"))
			return false
	_generation = 0
	_sequence = 0
	_pending_ids.clear()
	_cancelling = false
	_shutting_down = false
	var python: String = OS.get_environment("HABITAT_PYTHON")
	if python.is_empty():
		python = "/usr/bin/python3"
	if not FileAccess.file_exists(python):
		_error(LocalText.text("connection.companion_link.python_3_was_not_found_companion_connections_are_unavailable"))
		return false
	var conversation_dir := session_data_directory(_data_dir)
	DirAccess.make_dir_recursive_absolute(conversation_dir)
	persona_card=preload("res://scripts/persona_cards.gd").card(resident_id,"",_data_dir)
	_write_atomic(conversation_dir.path_join("persona.json"),persona_card)
	var args := PackedStringArray([
		"-u", runtime_dir.path_join("file_transport.py"),
		"--session-dir", _session_dir, "--data-dir", conversation_dir,
		"--nonce", _session, "--parent-pid", str(OS.get_process_id())
	])
	args.append_array(PackedStringArray(["--helper", runtime_dir.path_join(helper_filename)]))
	var codex: String = OS.get_environment("HABITAT_CODEX")
	if not codex.is_empty():
		args.append_array(PackedStringArray(["--codex", codex]))
	_write_heartbeat()
	_pid = OS.create_process(python, args, false)
	if _pid <= 0:
		_error(LocalText.text("connection.companion_link.cannot_start_the_codex_connection_check_local_python_and"))
		return false
	_busy = true
	_started_at = Time.get_ticks_msec()
	set_process(true)
	_emit({"kind": "state", "state": "connecting", "message": LocalText.text("connection.companion_link.connecting_to_your_companion")})
	return true

func session_data_directory(base: String) -> String:
	var directory := base.path_join(data_namespace).path_join(resident_id).path_join(world_id if not world_id.is_empty() else "default")
	# Preserve existing direct sessions; group history has its own model thread.
	return directory.path_join("group-all") if conversation_scope == "group" else directory

func send_message(text: String, world: Dictionary) -> void:
	if is_busy():
		_error(LocalText.text("connection.companion_link.wait_for_this_reply_answer_the_question_or_stop"))
		return
	if text.strip_edges().is_empty():
		return
	if _daily_quota_reached():
		_error(LocalText.text("steward.limit"));return
	if _is_direct_api():
		_generation+=1;turn_kind="chat";turn_key=_new_token();_busy=true
		if not _direct().send({"kind":"chat","text":text.left(4000),"world":world.duplicate(true),"level":world.get("intelligence_level","low"),"turn_key":turn_key},persona_card):_busy=false
		return
	if not _start():
		return
	_generation += 1
	turn_kind="chat";turn_key=_new_token()
	_busy = true
	_pending_ids.clear()
	var payload:Dictionary={"intent_card":world.intent_card} if helper_filename in ["intent_companion.py","openai_companion.py"] and world.has("intent_card") else world
	if world.get("source")=="host_memory_maintenance":payload["source"]="host_memory_maintenance"
	var caps:=ConfigFile.new();caps.load(_data_dir.path_join("connection-mode.cfg"))
	if not _send({"limits":{"turn_tokens":int(caps.get_value("turn_limit",resident_id,0))},"kind": "chat", "text": text.left(4000), "world": payload,"level":world.get("intelligence_level","low"),"turn_key":turn_key}):
		_busy = false

func answer(request_id: String, result: Variant) -> void:
	if _cancelling or not _pending_ids.has(request_id):
		_error(LocalText.text("connection.companion_link.this_question_or_request_has_ended_the_reply_was"))
		return
	var payload: Dictionary
	if result is String:
		payload = {"answer": result}
	elif result is Dictionary:
		payload = result
	else:
		_error(LocalText.text("connection.companion_link.the_reply_format_is_invalid"))
		return
	_pending_ids.erase(request_id)
	_emit({"kind":"tool_receipt","result":payload.duplicate(true)})
	_send({"kind": "tool_result", "id": request_id, "result": payload})

func reply(request_id: String, result: Dictionary) -> void:
	answer(request_id, result)

func cancel_turn() -> void:
	if is_instance_valid(direct_api):
		_generation+=1;direct_api.cancel();return
	if not _busy and _pending_ids.is_empty():return
	if _pid <= 0:
		_busy = false
		_generation+=1;_pending_ids.clear()
		_accept_event({"kind":"state","state":"cancelled","message":LocalText.text("connection.companion_link.response_stopped")})
		return
	if _cancelling:
		return
	# 立即屏蔽已排队旧消息；不能等 Python 往返之后才开始隔离。
	_generation += 1
	_cancelling = true
	_busy = true
	_pending_ids.clear()
	_emit({"kind": "state", "state": "cancelling", "message": LocalText.text("connection.companion_link.stopping_the_response")})
	_send({"kind": "cancel"})

func shutdown() -> void:
	if is_instance_valid(direct_api):
		direct_api.close();_generation+=1;_busy=false;handshake_ready=false;turn_key="";return
	if _pid <= 0 or _shutting_down:
		return
	_shutting_down = true
	_generation += 1
	_cancelling = true
	_pending_ids.clear()
	_send({"kind": "shutdown"})
	# 不阻塞渲染线程；传输进程负责退出 helper 和它的 app-server。
	set_process(false)

func _exit_tree() -> void:
	shutdown()

func _send(message: Dictionary) -> bool:
	_sequence += 1
	var envelope := {"session": _session, "generation": _generation, "id": _new_token(), "message": message}
	var filename: String = "%010d.json" % _sequence
	var pending: String = _session_dir.path_join("inbox").path_join(filename)
	return _write_atomic(pending, envelope)

func _write_atomic(path: String, value: Dictionary) -> bool:
	var temporary: String = path + ".tmp"
	var stream: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if stream == null:
		_error(LocalText.text("connection.companion_link.cannot_write_to_the_game_dialogue_queue"))
		return false
	stream.store_string(JSON.stringify(value))
	stream.flush()
	stream.close()
	if DirAccess.rename_absolute(temporary, path) != OK:
		DirAccess.remove_absolute(temporary)
		_error(LocalText.text("connection.companion_link.cannot_submit_the_game_dialogue_message"))
		return false
	return true

func _write_heartbeat() -> void:
	_write_atomic(_session_dir.path_join("client-heartbeat.json"), {"pid": OS.get_process_id(), "session": _session, "updated": Time.get_unix_time_from_system()})

func _process(delta: float) -> void:
	_poll_elapsed += delta
	_heartbeat_elapsed += delta
	if _heartbeat_elapsed >= 1.0:
		_heartbeat_elapsed = 0.0
		_write_heartbeat()
	if _poll_elapsed < 0.05:
		return
	_poll_elapsed = 0.0
	_drain_events()
	if _pid > 0 and not OS.is_process_running(_pid):
		_drain_events()
		_pid = -1
		_busy = false
		_cancelling = false
		_pending_ids.clear()
		set_process(false)
		_accept_event({"kind": "state", "state": "disconnected", "message": LocalText.text("connection.companion_link.the_companion_connection_closed_you_can_send_again")})
	elif not _shutting_down and Time.get_ticks_msec() - _started_at > 60000:
		var heartbeat_path: String = _session_dir.path_join("bridge-heartbeat.json")
		if not FileAccess.file_exists(heartbeat_path) or Time.get_unix_time_from_system() - FileAccess.get_modified_time(heartbeat_path) > 60:
			_error(LocalText.text("connection.companion_link.the_companion_connection_stopped_responding_and_was_closed"))
			shutdown()
			_busy = false
			_cancelling = false
			_accept_event({"kind":"state","state":"disconnected","message":LocalText.text("connection.companion_link.connection_heartbeat_timed_out_the_old_turn_is_isolated")})
			set_process(true)

func _drain_events() -> void:
	var outbox: String = _session_dir.path_join("outbox")
	var filenames: PackedStringArray = DirAccess.get_files_at(outbox)
	filenames.sort()
	var consumed: int = 0
	for filename in filenames:
		if not filename.ends_with(".json"):
			continue
		var path: String = outbox.path_join(filename)
		var stream: FileAccess = FileAccess.open(path, FileAccess.READ)
		if stream == null:
			continue
		if stream.get_length() > MAX_EVENT_BYTES:
			stream.close()
			DirAccess.remove_absolute(path)
			_error(LocalText.text("connection.companion_link.the_companion_response_was_too_large_and_was_ignored"))
			continue
		var envelope: Variant = JSON.parse_string(stream.get_as_text())
		stream.close()
		DirAccess.remove_absolute(path)
		consumed += 1
		if envelope is Dictionary and envelope.get("session", "") == _session and int(envelope.get("generation", -1)) == _generation:
			var event: Variant = envelope.get("event", {})
			if event is Dictionary:
				_accept_event(event)
		if consumed >= 32:
			break

func _accept_event(event: Dictionary) -> void:
	if event.get("code")=="autonomy_unsupported":capability_error=str(event.get("message",LocalText.text("connection.companion_link.unsupported_autonomy_level")))
	if event.has("turn_key") and not str(event.turn_key).is_empty() and event.turn_key!=turn_key:return
	if is_instance_valid(direct_api) and event.get("kind")=="usage" and event.get("model") is String:set_meta("memory_provider","API · "+str(event.model))
	event=event.duplicate(true);event["autonomy"]=turn_kind=="autonomy_event";event["turn_key"]=turn_key
	var kind: String = str(event.get("kind", ""))
	if _cancelling:
		if kind == "state" and str(event.get("state", "")) in ["cancelled", "disconnected", "error"]:
			_cancelling = false
			_busy = false
		elif kind!="usage":
			return
	if kind == "state":
		var state: String = str(event.get("state", ""))
		if state == "ready" and event.has("turnComplete") and not event.turnComplete:
			handshake_ready=true
			if not turn_key.is_empty():return
		_busy = state in BUSY_STATES
		if state in ["ready", "cancelled", "disconnected", "error"]:
			_pending_ids.clear()
	elif kind in ["question", "action", "observe", "read_work", "edit_work"]:
		var request_id: String = str(event.get("id", ""))
		if request_id.is_empty():
			return
		_pending_ids[request_id] = true
		if turn_kind=="autonomy_event":
			autonomy_tool_calls+=1
			if autonomy_tool_calls>autonomy_tool_limit:
				reply(request_id,{"ok":false,"error":"autonomy_tool_budget"});cancel_turn();return
			if kind=="question":
				reply(request_id,{"ok":false,"error":"autonomy_cannot_open_question"});return
		_busy = true
	elif kind == "error":
		_busy = false
		_pending_ids.clear()
	_emit(event)
	if kind=="state" and event.get("state") in ["ready","cancelled","disconnected","error"] and turn_key==event.get("turn_key"):
		turn_key="";turn_kind="chat"

func codex_high_policy() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://bridge/codex_high_budget.json"))

func uses_intents()->bool:
	return helper_filename=="intent_companion.py" or get_script().resource_path=="res://scripts/companion_link.gd"

# Starts the owned transport handshake only. No user message or model turn.
func probe_connection()->bool:
	if is_busy():return false
	return _start()

func _daily_quota_reached()->bool:
	var base:String=_data_dir
	if base.is_empty():base=OS.get_environment("HABITAT_DATA_DIR")
	if base.is_empty():base=ProjectSettings.globalize_path("user://")
	var caps:=ConfigFile.new();caps.load(base.path_join("connection-mode.cfg"))
	var maximum:int=int(caps.get_value("daily_limit",resident_id,0))
	if maximum<=0:return false
	return preload("res://scripts/ai_quota.gd").reached(base,resident_id,maximum)
