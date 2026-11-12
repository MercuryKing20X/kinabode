class_name WorldReadEndpoint
extends Node
const LocalText=preload("res://scripts/localization.gd")
signal model_action_requested(actor_id: String)

var world: RefCounted
var library: RefCounted
var seen: Dictionary = {}
var directory := ""
var session := ""
var bindings: Dictionary = {}
var elapsed := 0.0
var heartbeat_at_msec := 0
var conversation_links: Dictionary = {}
var dialogue_links: Dictionary = {}
var resident_context:Callable

func configure(source: RefCounted, data_dir: String) -> void:
	world = source
	directory = data_dir.path_join("read-api")
	for folder in ["inbox", "outbox"]: DirAccess.make_dir_recursive_absolute(directory.path_join(folder))
	session = Crypto.new().generate_random_bytes(16).hex_encode()
	bindings = {}
	sync_bindings()
	_heartbeat()

func sync_bindings() -> void:
	# Keep unaffected connections stable. A switched-away resident loses its token.
	var connections: Dictionary={}
	for token in bindings.keys():
		if not world.director.model_controlled(bindings[token]):bindings.erase(token)
		else:connections[bindings[token]]=token
	for id in world.actors:
		if not world.director.model_controlled(id) or connections.has(id):continue
		var token:=Crypto.new().generate_random_bytes(24).hex_encode()
		bindings[token]=id;connections[id]=token
	_write(directory.path_join("connections.json"),connections)

func _heartbeat() -> void:
	_write(directory.path_join("heartbeat.json"), {"pid": OS.get_process_id(), "session": session, "updated": Time.get_unix_time_from_system(), "protocol_version": 1,"world_id":world.world_id})
	heartbeat_at_msec = Time.get_ticks_msec()

func _write(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify(value))
	file.close()
	DirAccess.rename_absolute(path + ".tmp", path)

func _process(delta: float) -> void:
	if world == null: return
	elapsed += delta
	# The client expires this lease using wall time. Engine delta can be clamped
	# after a slow frame (or scaled), so it cannot measure transport liveness.
	if Time.get_ticks_msec() - heartbeat_at_msec >= 1000:
		_heartbeat()
	if elapsed < 0.05: return
	elapsed = 0
	var count := 0
	for filename in DirAccess.get_files_at(directory.path_join("inbox")):
		if not filename.ends_with(".json"): continue
		var path := directory.path_join("inbox").path_join(filename)
		var file := FileAccess.open(path, FileAccess.READ)
		var response := {"ok": false, "error": "invalid_request"}
		if file != null and file.get_length() <= 131072:
			var request: Variant = JSON.parse_string(file.get_as_text())
			if request is Dictionary: response = handle(request)
		if file != null: file.close()
		DirAccess.remove_absolute(path)
		_write(directory.path_join("outbox").path_join(filename), response)
		count += 1
		if count >= 8: break
	# Expire abandoned responses; stale requests cannot accumulate indefinitely.
	for filename in DirAccess.get_files_at(directory.path_join("outbox")):
		var path := directory.path_join("outbox").path_join(filename)
		if Time.get_unix_time_from_system() - FileAccess.get_modified_time(path) > 30: DirAccess.remove_absolute(path)

func handle(request: Dictionary) -> Dictionary:
	if request.get("session") != session: return {"ok": false, "error": "stale_session"}
	var token: String = str(request.get("token", ""))
	if not bindings.has(token): return {"ok": false, "error": "unauthorized"}
	var expiry: Variant = request.get("expires")
	if not world.catalog._number(expiry) or float(expiry) < Time.get_unix_time_from_system(): return {"ok": false, "error": "expired"}
	if not request.get("query", {}) is Dictionary: return {"ok": false, "error": "invalid_query"}
	var operation := str(request.get("operation", ""))
	var query: Dictionary = request.get("query", {})
	var actor_id: String = bindings[token]
	if not world.director.model_controlled(actor_id):return {"ok":false,"error":"controller_changed"}
	if operation == "observe":
		var snapshot:Dictionary=world.observe(actor_id,query)
		if resident_context.is_valid():snapshot.merge(resident_context.call(actor_id),false)
		return snapshot
	if operation == "read_actions":
		var result: Dictionary=world.read_actions(actor_id,query)
		result["dialogue_context_required"]=dialogue_links.has(actor_id+":direct") or dialogue_links.has(actor_id+":group")
		return result
	if operation == "read_map": return world.read_map(actor_id, query)
	if operation == "read_memories": return world.read_memories(actor_id, query)
	if operation in ["dialogue_poll","dialogue_reply"]:
		var scope: String=str(query.get("scope","direct"))
		var connection: Node=dialogue_links.get(actor_id+":"+scope)
		if not is_instance_valid(connection) or connection.get_script()!=preload("res://scripts/external_dialogue_link.gd"):return {"ok":false,"error":"external_dialogue_not_connected"}
		var payload: Dictionary=query.duplicate()
		if operation=="dialogue_poll":payload.erase("scope");return connection.read_mailbox(payload)
		return connection.receive_reply(payload)
	if operation in ["read_conversation", "reply_conversation"]:
		var connection: Node = conversation_links.get(actor_id)
		if connection == null or not connection.has_method("read_mailbox"):
			return {"ok": false, "error": "existing_conversation_not_connected"}
		return connection.read_mailbox(query) if operation == "read_conversation" else connection.receive_reply(query)
	if operation in ["act", "edit_character", "edit_work"]:
		var request_id := str(request.get("request_id", ""))
		if request_id.is_empty(): return {"ok": false, "error": "missing_request_id"}
		if seen.has(request_id): return {"ok": false, "error": "duplicate_request"}
		if seen.size() >= 4096: return {"ok": false, "error": "session_limit"}
		seen[request_id] = true
	if operation == "act":
		if dialogue_links.has(actor_id+":direct") or dialogue_links.has(actor_id+":group"):return {"ok":false,"error":"dialogue_identity_required","message":LocalText.text("system.read_endpoint.read_the_current_turn_with_dialogue_poll_and")}
		model_action_requested.emit(actor_id)
		return world.command(actor_id, query)
	if library != null and operation in ["read_work", "edit_work"]:
		var id := str(query.get("artwork_id", ""))
		if not library.artworks.has(id) or library.artworks[id].get("kind","character") not in ["building","facility","plant"]: return {"ok": false, "error": "unknown_shared_work"}
		if operation == "read_work": return library.read_work(query)
		return library.patch(id, query)
	if library != null:
		var art_id: String = world.actors[actor_id].appearance_id
		if operation == "read_character": return library.read_frame(art_id, str(query.get("frame", "down_0")))
		if operation == "edit_character":
			if "spare" in library.artworks.get(art_id, {}).get("tags", []): return {"ok":false,"error":"shared_artwork_readonly"}
			return library.patch(art_id, query)
	return {"ok": false, "error": "unsupported_operation"}

func _exit_tree() -> void:
	if not directory.is_empty():
		DirAccess.remove_absolute(directory.path_join("heartbeat.json"))
		DirAccess.remove_absolute(directory.path_join("connections.json"))
