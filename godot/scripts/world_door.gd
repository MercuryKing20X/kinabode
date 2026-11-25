extends Node
## A loopback-only, bounded HTTP/1.1 transport. POST replies use JSON; no SSE.
const PORT := 17642
const MAX_BODY := 16384
const MAX_HEADER := 4096
const LEASE_MS := 300000
const ADDRESS := "127.0.0.1"
const VERSION := "2025-11-25"
const VERSIONS := ["2024-11-05","2025-03-26","2025-06-18",VERSION]
const TOOLS := {
	"claim": ["Claim an unbound resident. Returns the lease, persona and memory.", {"resident":"string","client":"string"}, ["resident","client"]],
	"release": ["Release this lease and return its resident to local life.", {"lease":"string"}, ["lease"]],
	"look": ["Views: surroundings (concise local coordinates), self (step shapes), nearby (full state), map, memories, warehouse, creations.", {"lease":"string","view":"string"}, ["lease","view"]],
	"act": ["Submit 1–6 flat step objects. For example: {\"action\":\"place_piece\",\"item\":\"sign\",\"position\":[X,Y]}, then {\"action\":\"name_place\",\"position\":[X,Y],\"label\":\"\u4f60\u597d\"}. Replace X,Y with nearby integer tile coordinates. Fence uses place_piece with item fence. Wait for action_finished before another plan.", {"lease":"string","steps":"array","reason":"string"}, ["lease","steps"]],
	"ask_help": ["Ask an unclaimed local resident to perform one documented basic step.", {"lease":"string","resident":"string","steps":"array","reason":"string"}, ["lease","resident","steps"]],
	"say": ["Speak to a nearby resident or yourself. Shared speech limits apply.", {"lease":"string","target":"string","text":"string"}, ["lease","target","text"]],
	"events": ["Wait up to 20 seconds for events after the supplied sequence number.", {"lease":"string","after":"integer"}, ["lease"]]
}
var world: RefCounted
var directory := ""
var token := ""
var server := TCPServer.new()
var connections: Array[Dictionary] = []
var leases: Dictionary = {}
var owners: Dictionary = {}
var background:Dictionary={}
var request_times: Array[int] = []
var serial := 0
var world_generation := 0
var enabled := false
var knocks: Array[Dictionary] = []
var helpers:Dictionary={}
var greeted_clients:Dictionary={}
var greeting_path: String:
	get: return directory.path_join("world-door-greetings.cfg")
signal spoken(actor: String, target: String, line: String)
signal changed
signal claimed(actor: String)

func setup(source: RefCounted, path: String) -> void:
	# Reply to already queued local requests before the frame's simulation.
	process_priority=-1
	world = source
	directory = path
	world_generation=world.session_generation
	world.flower_creation.creations.removed.connect(func(id:String,row:Dictionary):publish(id,"piece_removed",row))
	set_process(false)
	var preferences:=ConfigFile.new()
	if preferences.load(directory.path_join("world-door.cfg"))==OK:
		enabled=bool(preferences.get_value("door","enabled",false))
	var greetings:=ConfigFile.new()
	if greetings.load(greeting_path)==OK:
		for identity in greetings.get_value("door","greeted",PackedStringArray()):
			if identity is String and valid_secret(identity) and greeted_clients.size()<1024:
				greeted_clients[identity]=true
	if enabled:open()

func set_enabled(value:bool)->bool:
	if value and not open():return false
	if not value:close()
	enabled=value
	var preferences:=ConfigFile.new()
	preferences.set_value("door","enabled",enabled)
	return preferences.save(directory.path_join("world-door.cfg"))==OK

func knock(result:String,client:String="",actor:String="")->void:
	knocks.push_front({"at":Time.get_time_string_from_system(),"result":result,"client":client,"actor":actor})
	if knocks.size()>12:knocks.pop_back()
	changed.emit()

func rotate()->bool:
	var fresh:=secret()
	if not write_key(fresh):return false
	var listening:=server.is_listening()
	close()
	token=fresh
	return not listening or open()

func write_key(fresh:String)->bool:
	var path:=directory.path_join("world-door-token")
	var file:=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null:return false
	file.store_string(fresh);file.close()
	var secured:=OS.get_name()=="Windows" or FileAccess.set_unix_permissions(path+".tmp",FileAccess.UNIX_READ_OWNER|FileAccess.UNIX_WRITE_OWNER)==OK
	if secured and DirAccess.rename_absolute(path+".tmp",path)==OK:return true
	DirAccess.remove_absolute(path+".tmp")
	return false

func open() -> bool:
	if server.is_listening(): return true
	if server.listen(PORT, ADDRESS) != OK: return false
	var path := directory.path_join("world-door-token")
	if not token.is_empty():pass
	elif FileAccess.file_exists(path):
		var existing := FileAccess.open(path, FileAccess.READ)
		if existing != null and existing.get_length() == 64:
			var value := existing.get_as_text()
			if valid_secret(value): token = value
	else:
		var fresh := secret()
		if write_key(fresh):token=fresh
	if not valid_secret(token):
		server.stop()
		return false
	set_process(true)
	changed.emit()
	return true

func secret() -> String:
	return Crypto.new().generate_random_bytes(32).hex_encode()

func first_claim(actor:String, client:String)->bool:
	var identity:=(actor+"\n"+client).sha256_text()
	if greeted_clients.has(identity):return false
	greeted_clients[identity]=true
	if greeted_clients.size()>1024:greeted_clients.erase(greeted_clients.keys()[0])
	var greetings:=ConfigFile.new()
	greetings.set_value("door","greeted",PackedStringArray(greeted_clients.keys()))
	greetings.save(greeting_path)
	return true

func valid_secret(value: String) -> bool:
	return value.length() == 64 and value.is_valid_hex_number(false)

func authenticated(value: String) -> bool:
	if value.length() != 71 or not value.begins_with("Bearer "): return false
	var a := value.substr(7).to_utf8_buffer()
	var b := token.to_utf8_buffer()
	if a.size() != b.size(): return false
	var difference := 0
	for i in b.size(): difference |= a[i] ^ b[i]
	return difference == 0

func close() -> void:
	server.stop()
	for peer in connections: peer.socket.disconnect_from_host()
	connections.clear()
	for lease in leases.keys(): release(lease)
	helpers.clear()
	request_times.clear()
	set_process(false)
	changed.emit()

func _exit_tree() -> void:
	close()

func release(lease: String) -> void:
	if not leases.has(lease): return
	var id: String = leases[lease].actor
	leases.erase(lease)
	owners.erase(id)
	if not world.actors.has(id): return
	world.actors[id].erase("world_door_client")
	var brain: RefCounted = world.director.brains[id]
	if brain.current.get("origin") == "world_door": brain.finish("interrupted", "lease_released")
	changed.emit()

func publish(id: String, kind: String, data: Dictionary) -> bool:
	if background.has(id):
		var thinker:Node=background[id].get_ref()
		if is_instance_valid(thinker):return thinker.notify(id,kind,data)
	if not owners.has(id): return false
	var events: Array = leases[owners[id]].events
	serial += 1
	events.append({"sequence":serial,"type":kind,"data":data.duplicate(true)})
	if events.size() > 64: events.pop_front()
	return true

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if world_generation!=world.session_generation:
		close()
		world_generation=world.session_generation
		if enabled:open()
		return
	for key in leases.keys():
		var lease: Dictionary = leases[key]
		var id: String = lease.actor
		if now >= int(lease.expires) or not world.actors.has(id) or world.director.model_controlled(id):
			release(key)
			continue
		var near: bool = world.actors[id].region_id == world.actors.human.region_id and world.point(world.actors[id]).distance_to(world.point(world.actors.human)) <= 5
		if near and not lease.near: publish(id, "player_nearby", {})
		lease.near = near
		var plan_id: String = lease.get("plan", "")
		if not plan_id.is_empty():
			var plan: RefCounted = world.director.brains[id].intention.basic
			if plan.result.get("id") == plan_id:
				lease.last_action = plan.result.duplicate(true)
				changed.emit()
				publish(id, "action_finished", plan.result)
				lease.erase("plan")
	for _i in range(8):
		if not server.is_connection_available(): break
		var socket := server.take_connection()
		if socket == null: break
		socket.set_no_delay(true)
		if connections.size() >= 24:
			socket.disconnect_from_host()
		else:
			connections.append({"socket":socket,"buffer":PackedByteArray(),"deadline":now+2000})
	for i in range(connections.size()-1, -1, -1):
		var peer: Dictionary = connections[i]
		var socket: StreamPeerTCP = peer.socket
		socket.poll()
		if socket.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			connections.remove_at(i)
			continue
		if peer.has("reply"):
			if peer.sent>=peer.reply.size():
				socket.disconnect_from_host()
				connections.remove_at(i)
				continue
			var written: Array = socket.put_partial_data(peer.reply.slice(peer.sent))
			if written[0] != OK or now >= peer.deadline:
				socket.disconnect_from_host()
				connections.remove_at(i)
			else:
				peer.sent += int(written[1])
				if peer.sent >= peer.reply.size():
					socket.disconnect_from_host()
					connections.remove_at(i)
			continue
		if peer.has("wait"):
			var waiting: Dictionary = peer.wait
			var result := event_result(waiting.lease, waiting.after)
			if not result.ok or not result.events.is_empty() or now >= peer.deadline: respond(peer, 200, tool_reply(waiting.rpc, waiting.id, result))
			continue
		if now >= peer.deadline:
			respond(peer, 408)
			continue
		var available := socket.get_available_bytes()
		if available <= 0: continue
		if peer.buffer.size() + available > MAX_BODY + MAX_HEADER:
			respond(peer, 413)
			continue
		var chunk: Array = socket.get_partial_data(available)
		if chunk[0] != OK: continue
		peer.buffer.append_array(chunk[1])
		parse(peer, now)

func parse(peer: Dictionary, now: int) -> void:
	var bytes: PackedByteArray = peer.buffer
	var end := -1
	for i in range(mini(MAX_HEADER, bytes.size()-3)):
		if bytes[i] == 13 and bytes[i+1] == 10 and bytes[i+2] == 13 and bytes[i+3] == 10:
			end = i
			break
	if end < 0:
		if bytes.size() >= MAX_HEADER: respond(peer, 413)
		return
	var lines := bytes.slice(0,end).get_string_from_ascii().split("\r\n")
	var request := lines[0].split(" ")
	if request.size() != 3 or request[2] != "HTTP/1.1":
		respond(peer,400);return
	var h := {}
	for index in range(1, lines.size()):
		var line: String = lines[index]
		var colon := line.find(":")
		var name := line.left(colon).to_lower()
		if colon <= 0 or name.strip_edges() != name or h.has(name):
			respond(peer,400);return
		h[name] = line.substr(colon+1).strip_edges()
	var hosts:=[ADDRESS+":"+str(PORT),"localhost:"+str(PORT)]
	if h.get("host") not in hosts or (h.has("origin") and h.origin not in ["http://"+hosts[0],"http://"+hosts[1]]):
		knock("origin")
		respond(peer,403);return
	if not authenticated(h.get("authorization","")):
		knock("key")
		respond(peer,401);return
	if request[1] not in ["/world","/mcp"]:
		respond(peer,404);return
	if request[0] != "POST":
		respond(peer,405);return
	if request[1]=="/mcp" and h.has("mcp-protocol-version") and h["mcp-protocol-version"] not in VERSIONS:
		respond(peer,400);return
	var size_text: String = h.get("content-length","")
	if h.has("transfer-encoding") or not size_text.is_valid_int() or not str(h.get("content-type","")).to_lower().split(";")[0].strip_edges() == "application/json":
		respond(peer,400);return
	var size := int(size_text)
	if size < 0 or size > MAX_BODY:
		respond(peer,413);return
	if bytes.size() < end+4+size: return
	if bytes.size() != end+4+size:
		respond(peer,400);return
	while not request_times.is_empty() and request_times[0] <= now-1000: request_times.pop_front()
	if request_times.size() >= 32:
		respond(peer,429);return
	request_times.append(now)
	var body: Variant = JSON.parse_string(bytes.slice(end+4).get_string_from_utf8())
	if not body is Dictionary:
		respond(peer,400);return
	dispatch(peer, request[1] == "/mcp", body, now)

func tool_schema() -> Array:
	var rows := []
	for name in TOOLS:
		var row: Array = TOOLS[name]
		var fields := {}
		for key in row[1]:
			fields[key] = {"type":row[1][key]}
			if row[1][key] == "array": fields[key]["items"] = {"type":"object"}
		rows.append({"name":name,"description":row[0],"inputSchema":{"type":"object","properties":fields,"additionalProperties":false,"required":row[2]}})
	return rows

func dispatch(peer: Dictionary, rpc: bool, body: Dictionary, now: int) -> void:
	var method: Variant = body.get("command")
	var args: Variant = body.get("arguments",{})
	var id: Variant = body.get("id")
	if rpc:
		if id is float and is_finite(id) and absf(id)<=9007199254740991.0 and id==floorf(id):id=int(id)
		if body.get("jsonrpc") != "2.0" or not body.get("method") is String or (body.has("id") and not (id is String or id is int)):
			respond(peer,200,{"jsonrpc":"2.0","id":null,"error":{"code":-32600,"message":"Invalid Request"}});return
		var rpc_method: String = body.method
		if not body.has("id"):
			respond(peer,202);return
		var result := {}
		match rpc_method:
			"initialize":
				var params:Variant=body.get("params",{})
				if not params is Dictionary:params={}
				var client:Variant=params.get("clientInfo",{})
				var client_name:String=str(client.get("name","")) if client is Dictionary else ""
				var clean:=RegEx.new()
				clean.compile("[^a-zA-Z0-9 _./-]")
				client_name=clean.sub(client_name.left(48),"",true)
				if client_name==token:client_name=""
				knock("connected",client_name)
				var requested:Variant=params.get("protocolVersion",VERSION)
				result = {"protocolVersion":requested if requested in VERSIONS else VERSION,"capabilities":{"tools":{}},"serverInfo":{"name":"kinabode-world","version":"0.8"}}
			"ping": pass
			"tools/list": result = {"tools":tool_schema()}
			"tools/call":
				var p: Variant = body.get("params")
				if p is Dictionary:
					method = p.get("name")
					args = p.get("arguments",{})
			_:
				respond(peer,200,{"jsonrpc":"2.0","id":id,"error":{"code":-32601,"message":"Method not found"}});return
		if rpc_method != "tools/call":
			respond(peer,200,{"jsonrpc":"2.0","id":id,"result":result});return
	var result := command(method,args,now)
	if result.has("poll"):
		peer.wait = {"lease":args.lease,"after":int(args.get("after",0)),"rpc":rpc,"id":id}
		peer.deadline = now+20000
	else: respond(peer,200,tool_reply(rpc,id,result))

func tool_reply(rpc: bool, id: Variant, result: Dictionary) -> Dictionary:
	if not rpc: return result
	return {"jsonrpc":"2.0","id":id,"result":{"content":[{"type":"text","text":JSON.stringify(result)}],"isError":not result.ok}}

func respond(peer: Dictionary, status: int, body: Dictionary = {}) -> void:
	var payload := (JSON.stringify(body) if not body.is_empty() else "").to_utf8_buffer()
	var reason: String = {200:"OK",202:"Accepted",400:"Bad Request",401:"Unauthorized",403:"Forbidden",404:"Not Found",405:"Method Not Allowed",408:"Request Timeout",413:"Content Too Large",429:"Too Many Requests"}[status]
	var headers := "HTTP/1.1 %d %s\r\nConnection: close\r\nCache-Control: no-store\r\nContent-Type: application/json\r\nContent-Length: %d\r\n" % [status,reason,payload.size()]
	if status == 405: headers += "Allow: POST\r\n"
	if status == 401: headers += "WWW-Authenticate: Bearer\r\n"
	peer.reply = (headers+"\r\n").to_utf8_buffer()
	peer.reply.append_array(payload)
	peer.sent = 0
	peer.deadline = Time.get_ticks_msec()+2000
	peer.erase("wait")
	peer.erase("buffer")
	var socket:StreamPeerTCP=peer.socket
	var written:Array=socket.put_partial_data(peer.reply)
	if written[0]==OK:peer.sent=int(written[1])

func error(code: String) -> Dictionary:
	return {"ok":false,"error":code}

func event_result(key: String, after: int) -> Dictionary:
	if not leases.has(key): return error("invalid_lease")
	var events: Array = leases[key].events
	return {"ok":true,"events":events.filter(func(row):return row.sequence > after),"oldest":events[0].sequence if not events.is_empty() else 0}

func command(method: Variant, args: Variant, now: int) -> Dictionary:
	if not method is String or not TOOLS.has(method) or not args is Dictionary: return error("unknown_command")
	# Authenticated clients still must not put the door key into public world data.
	if not token.is_empty() and JSON.stringify(args).contains(token):return error("invalid_argument")
	var spec: Array = TOOLS[method]
	for key in spec[2]:
		if not args.has(key): return error("missing_argument")
	for key in args:
		if not spec[1].has(key):return error("invalid_argument")
		var value: Variant = args[key]
		match spec[1][key]:
			"string":
				if not value is String or value.is_empty() or value.length() > 160: return error("invalid_argument")
			"array":
				if not value is Array: return error("invalid_argument")
			"integer":
				if not world._integer(value) or value < 0 or value > serial: return error("invalid_cursor")
	if method == "claim":
		var id: String = args.resident
		var name: String = args.client
		if not world.director.brains.has(id) or id == "human" or world.director.model_controlled(id) or owners.has(id) or background.has(id):return error("resident_unavailable")
		var brain: RefCounted = world.director.brains[id]
		var own_idle_plan:bool=brain.current.get("origin")=="local" and brain.current.has("basic_plan") and world.work.jobs.get(id,{}).get("id","")==brain.current.get("job_id","")
		if not brain.active() or (brain.busy() and not own_idle_plan) or world.director.routines[id].held: return error("resident_busy")
		if name.length() > 32 or name != name.strip_edges() or "\r" in name or "\n" in name or "\t" in name: return error("invalid_client")
		brain.finish("interrupted","external_claim")
		world.director.routines[id].interrupt(0)
		var key := secret()
		if not valid_secret(key):return error("lease_unavailable")
		owners[id] = key
		leases[key] = {"actor":id,"expires":now+LEASE_MS,"near":false,"events":[]}
		world.actors[id]["world_door_client"] = name
		knock("claimed",name,id)
		claimed.emit(id)
		var persona:Dictionary={"personality":brain.tag()}
		if id in ["codex","companion-2","npc.mira","npc.nora"]:
			persona=preload("res://scripts/persona_cards.gd").card(id,"en")
		var receipt:Dictionary={"ok":true,"lease":key,"self":world._resident(id),"persona":persona,"memories":world.read_memories(id),"guide":"You are this island resident. The player is a newcomer. Only act as yourself. Travel and work take game time, and materials are real. See look for available basic steps. A plan is accepted before it runs; wait for its outcome."}
		if first_claim(id,name):
			receipt.suggestion={"zh":"先在居民旁边立一块写着「你好」的牌子。木材不够就先去砍树，搬回仓库。","en":"Leave a sign beside your resident that reads \u4f60\u597d. If you're short on wood, chop a tree and haul the wood back first."}
		return receipt
	var key: String = args.lease
	if not leases.has(key): return error("invalid_lease")
	var lease: Dictionary = leases[key]
	var actor: String = lease.actor
	if now >= int(lease.expires):
		release(key);return error("invalid_lease")
	var timestamps:Array=lease.get("requests",[])
	while not timestamps.is_empty() and int(timestamps[0])<=now-1000:timestamps.pop_front()
	if timestamps.size()>=8:return error("rate_limited")
	timestamps.append(now)
	lease.requests=timestamps
	lease.expires = now+LEASE_MS
	match method:
		"release":
			release(key);return {"ok":true}
		"look":
			return look(actor,args.view)
		"act":
			if lease.has("plan"): return error("action_in_progress")
			var result:=act(actor,args,"world_door")
			if result.ok:lease.plan=result.action_id
			return result
		"ask_help":
			return ask_help(actor,args,key)
		"say":
			var target: String = args.target
			if not world.actors.has(target) or world.actors[actor].region_id != world.actors[target].region_id or world.point(world.actors[actor]).distance_to(world.point(world.actors[target])) > 8: return error("listener_unavailable")
			if not world.director.say_command(actor,target,args.text):return error("speech_unavailable")
			spoken.emit(actor,target,args.text)
			return {"ok":true}
		"events":
			var result := event_result(key,int(args.get("after",0)))
			return {"ok":true,"poll":true} if result.events.is_empty() else result
	return error("unknown_command")

func look(actor:String, view:String)->Dictionary:
	match view:
		"self":return {"ok":true,"self":world._resident(actor),"actions":world.director.brains[actor].intention.basic.card(),"project":world.flower_creation.creations.projects.get(actor,"")}
		"nearby":return world.observe(actor,{"limit":24})
		"surroundings":return surroundings(actor)
		"map":return world.read_map(actor)
		"memories":return world.read_memories(actor)
		"warehouse":return {"ok":true,"storage":world.storage.saved()}
		"creations":
			var creations:RefCounted=world.flower_creation.creations
			return {"ok":true,"catalog":creations.catalog(),"pieces":creations.pieces.duplicate(true),"changes":creations.changes.slice(-32).duplicate(true)}
	return error("invalid_view")

func surroundings(actor:String)->Dictionary:
	var self_actor:Dictionary=world.actors[actor]
	var origin:Vector2=world.point(self_actor)
	var people:Array=[]
	var pieces:Array=[]
	for id in world.actors:
		var other:Dictionary=world.actors[id]
		if id!=actor and other.region_id==self_actor.region_id and origin.distance_to(world.point(other))<=16:
			people.append({"id":id,"position":other.position.duplicate()})
	for piece in world.flower_creation.creations.pieces.values():
		if piece.region==self_actor.region_id and origin.distance_to(world.point(piece))<=12:
			pieces.append({"item":piece.item,"position":piece.position.duplicate(),"owner":piece.get("owner","")})
	var sites:Dictionary={}
	if self_actor.region_id=="home":
		var center:=origin.round()
		var creations:RefCounted=world.flower_creation.creations
		var points:Array[Vector2]=[]
		for offset in [Vector2(3,0),Vector2(0,3),Vector2(-3,0),Vector2(0,-3),Vector2(4,2),Vector2(-4,2),Vector2(2,-4),Vector2(-2,-4)]:
			points.append(center+offset)
		for item in ["sign","fence"]:
			for at in points:
				var position:=[roundi(at.x),roundi(at.y)]
				if position==sites.get("sign",[]) or not creations.check(actor,"place_piece",{"item":item,"position":position}).is_empty():continue
				if creations.approach(actor,at).is_empty():continue
				sites[item]=position
				break
	return {"ok":true,"resident":actor,"region":self_actor.region_id,"position":self_actor.position.duplicate(),"people":people,"pieces":pieces.slice(0,16),"warehouse_wood":world.storage.count("wood"),"suggested_sites":sites}

func act(actor:String,args:Dictionary,source:String)->Dictionary:
	if actor=="human" or not world.director.brains.has(actor):return error("resident_unavailable")
	if source=="island_ai" and (not background.has(actor) or owners.has(actor) or (not token.is_empty() and JSON.stringify(args).contains(token))):return error("resident_unavailable")
	var basic:RefCounted=world.director.brains[actor].intention.basic
	var action_id:="world-%d"%(serial+1)
	if not basic.accept({"reason":args.get("reason","Island work"),"steps":args.get("steps")},source,action_id):return error("plan_rejected")
	serial+=1
	return {"ok":true,"action_id":action_id}

const HELP_LINES={
	"gentle":[["我想先吃点东西，好吗？","Could I have a bite first?"],["等我忙完手里这件，好吗？","Can it wait until I've finished this?"],["今天我想慢一点。","I'd like to take things a little slower today."]],
	"lively":[["肚子都叫啦，先让我吃口饭！","My stomach's making a racket. Food first!"],["等一下，我手头还没忙完呢！","Hang on! I'm still in the middle of something."],["这回先算啦，我有别的点子！","I'll sit this one out. I've got another idea!"]],
	"quiet":[["先吃饭。","A bite first."],["我在忙。","I'm in the middle of something."],["这件我先不接。","I'll pass this time."]],
	"laborious":[["先垫垫肚子，才有劲儿干活。","Let me get a bite in me before I start."],["这单先做完，再说下一单。","One job at a time. This one comes first."],["这个活儿我今天不接。","I won't take that job today."]]
}

func ask_help(actor:String,args:Dictionary,key:String)->Dictionary:
	var id:String=args.resident
	if id==actor or not world.director.brains.has(id) or owners.has(id) or background.has(id) or world.director.model_controlled(id):return error("resident_unavailable")
	if args.steps.size()!=1:return error("invalid_argument")
	var brain:RefCounted=world.director.brains[id]
	var index:=2
	if world.hunger.rank(id)>=2:index=0
	elif helpers.has(id) or brain.busy() or not brain.current.is_empty() or not brain.eligible(true):index=1
	elif brain.tag()!="quiet" or args.steps[0] is Dictionary and args.steps[0].get("action") in ["wait","go_to","place_piece"]:
		var result:=act(id,args,"requested_help")
		if result.ok:
			helpers[id]={"id":result.action_id,"requester":actor,"lease":key}
			var self_ref:WeakRef=weakref(self)
			brain.intention.basic.completed=func(outcome:Dictionary):
				var door:Node=self_ref.get_ref()
				if is_instance_valid(door):door.helper_finished(id,outcome)
			return result
	var pair:Array=HELP_LINES.get(brain.tag(),HELP_LINES.gentle)[index]
	return {"ok":false,"error":"help_declined","message":preload("res://scripts/world_creations.gd").phrase(pair[0],pair[1])}

func helper_finished(id:String,outcome:Dictionary)->void:
	var help:Dictionary=helpers.get(id,{})
	if help.get("id")!=outcome.get("id"):return
	helpers.erase(id)
	if owners.get(help.requester)==help.lease:
		publish(help.requester,"help_finished",{"resident":id,"result":outcome})
