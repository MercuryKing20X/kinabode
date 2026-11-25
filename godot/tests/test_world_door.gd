extends SceneTree

const Door=preload("res://scripts/world_door.gd")
const Save=preload("res://scripts/save_store.gd")
var door: Node
var game: Node
var failures:=0
var checks:=0
var latency:Array[int]=[]
var ordinary_latency:Array[int]=[]
var measuring_ordinary:=false
var slow_samples:Array[Dictionary]=[]
var last_frame_usec:=0
var frame_gap_usec:=0

class Fake extends "res://scripts/companion_link.gd":
	func _start()->bool:return true
	func _send(_payload:Dictionary)->bool:return true

func _initialize()->void:run.call_deferred()

func track_frame()->void:
	var now:=Time.get_ticks_usec()
	if last_frame_usec>0:frame_gap_usec=maxi(frame_gap_usec,now-last_frame_usec)
	last_frame_usec=now

func check(condition:bool,label:String)->void:
	checks+=1
	if not condition:
		failures+=1
		push_error(label)

func post(path:String, body:Dictionary, auth:String, headers:PackedStringArray=[]) -> Array:
	var request:=HTTPRequest.new()
	request.use_threads=true
	request.timeout=23
	root.add_child(request)
	var began:=Time.get_ticks_msec()
	frame_gap_usec=0
	var lines:=PackedStringArray(["Content-Type: application/json","Accept: application/json, text/event-stream"])
	lines.append_array(headers)
	if not auth.is_empty():lines.append("Authorization: Bearer "+auth)
	var err:=request.request("http://127.0.0.1:"+str(Door.PORT)+path,lines,HTTPClient.METHOD_POST,JSON.stringify(body))
	if err!=OK:
		request.queue_free()
		return [0,{}]
	var reply:Array=await request.request_completed
	request.queue_free()
	if not (body.get("command")=="events" or body.get("params",{}).get("name")=="events"):
		var took:=Time.get_ticks_msec()-began
		latency.append(took)
		if measuring_ordinary:ordinary_latency.append(took)
		if took>100:
			var params:Dictionary=body.get("params",{})
			var label:String=str(body.get("command",params.get("name",body.get("method","invalid"))))
			slow_samples.append({"sample":latency.size(),"command":label,"ms":took,"max_frame_ms":float(frame_gap_usec)/1000.0})
	var parsed:Variant=JSON.parse_string(reply[3].get_string_from_utf8()) if not reply[3].is_empty() else {}
	return [reply[1],parsed if parsed is Dictionary else {}]

func rpc(method:String,params:Dictionary={}) -> Array:
	return await post("/mcp",{"jsonrpc":"2.0","id":1,"method":method,"params":params},door.token)

func command(name:String,args:Dictionary,mcp:bool=false) -> Dictionary:
	var response:Array
	if mcp:
		response=await rpc("tools/call",{"name":name,"arguments":args})
		var data:Variant=JSON.parse_string(response[1].get("result",{}).get("content",[{"text":"{}"}])[0].text)
		return data if data is Dictionary else {}
	response=await post("/world",{"command":name,"arguments":args},door.token)
	return response[1]

func piece_action(lease:String,step:Dictionary,mcp:bool)->bool:
	var accepted:=await command("act",{"lease":lease,"steps":[step]},mcp)
	if not accepted.get("ok",false):return false
	var cursor:=0
	for i in 3:
		var response:=await command("events",{"lease":lease,"after":cursor},mcp)
		for event in response.get("events",[]):
			cursor=maxi(cursor,int(event.sequence))
			if event.type=="action_finished" and event.data.id==accepted.action_id:return event.data.status=="completed"
	return false

func run()->void:
	var directory:=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.begins_with("/tmp/") and not directory.begins_with("/var/folders/"):
		quit(1);return
	set_meta("title_opening","showcase")
	game=load("res://scenes/main_v3.tscn").instantiate()
	game.dialogue_adapter_factory=func(_id,_scope):return Fake.new()
	root.add_child(game)
	await process_frame
	process_frame.connect(track_frame)
	door=game.world_door
	check(door!=null and not door.server.is_listening(),"world door initially closed")
	if door==null or not door.open():
		push_error("could not open test loopback port")
		quit(1);return
	check((await post("/world",{},""))[0]==401,"missing token forbidden")
	check((await post("/world",{},"0".repeat(64)))[0]==401,"incorrect token forbidden")
	check((await post("/world",{},door.token,["Origin: https://example.invalid"]))[0]==403,"untrusted origin forbidden")
	var start:Array=await rpc("initialize",{"protocolVersion":Door.VERSION,"capabilities":{},"clientInfo":{"name":"test","version":"1"}})
	check(start[1].get("result",{}).get("protocolVersion")==Door.VERSION,"MCP initialization")
	var listed: Array=await rpc("tools/list")
	check(listed[1].get("result",{}).get("tools",[]).size()==Door.TOOLS.size(),"MCP tool definitions")
	var human:Dictionary=await command("claim",{"resident":"human","client":"test"})
	check(human.get("error")=="resident_unavailable","cannot claim player")
	var white:Dictionary=await command("claim",{"resident":"codex","client":"MCP test"},true)
	var black:Dictionary=await command("claim",{"resident":"npc.nora","client":"HTTP test"})
	check(white.get("ok",false) and black.get("ok",false),"both clients claim distinct residents")
	check(white.get("suggestion",{}).get("en","").contains("wood") and black.get("suggestion",{}).get("zh","").contains("你好"),"first claim suggests a real greeting sign in both languages")
	var nearby:Dictionary=await command("look",{"lease":white.lease,"view":"surroundings"},true)
	check(nearby.get("resident")=="codex" and nearby.get("position") is Array and JSON.stringify(nearby).to_utf8_buffer().size()<4096,"compact local observation works through MCP")
	if not white.has("lease") or not black.has("lease"):quit(1);return
	check((await command("claim",{"resident":"codex","client":"second"})).get("error")=="resident_unavailable","exclusive ownership")
	check((await command("say",{"lease":white.lease,"target":"codex","text":"A private value: "+door.token},true)).get("error")=="invalid_argument","door key cannot enter public speech")
	for client in [white,black]:
		var mcp:bool=client==white
		var key:String=client.lease
		check((await command("look",{"lease":key,"view":"self"},mcp)).get("ok",false),"look at owned resident")
		check((await command("say",{"lease":key,"target":client.self.id,"text":"The tide is quiet."},mcp)).get("ok",false),"explicit speech accepted by both transports")
		await process_frame
		await process_frame
		check(game.view.speech_by_actor.get(client.self.id,{}).get("text")=="The tide is quiet.","explicit speech reaches the world bubble")
		var wrong:Dictionary=await command("act",{"lease":key,"steps":[{"action":"wait","seconds":0}]},mcp)
		check(wrong.get("error")=="plan_rejected","invalid plan rejected")
		var plan:Dictionary=await command("act",{"lease":key,"steps":[{"action":"wait","seconds":1}]},mcp)
		check(plan.has("action_id"),"asynchronous action accepted")
		var after:=0
		for i in range(3):
			var received:Dictionary=await command("events",{"lease":key,"after":after},mcp)
			var done:=false
			for event in received.get("events",[]):
				after=maxi(after,int(event.sequence))
				if event.type=="action_finished":
					done=event.data.id==plan.get("action_id") and event.data.status=="completed"
			if done:
				check(true,"action receipt delivered")
				break
			if i==2:check(false,"missing action receipt")
		check((await command("release",{"lease":key},mcp)).get("ok",false),"release returns resident")
		check(not game.world.actors[client.self.id].has("world_door_client"),"owner label removed")
	# Sample ordinary reads over both transports without overrunning a lease.
	var sample_clients:Array=[
		await command("claim",{"resident":"codex","client":"MCP latency"},true),
		await command("claim",{"resident":"npc.nora","client":"HTTP latency"})
	]
	check(sample_clients.all(func(row):return row.has("lease")),"both latency clients have live leases")
	if sample_clients.all(func(row):return row.has("lease")):
		var views:=["self","nearby","warehouse","map","memories","creations"]
		measuring_ordinary=true
		for i in range(100):
			var transport:=i%2
			var sampled:Dictionary=await command("look",{"lease":sample_clients[transport].lease,"view":views[(i/2)%views.size()]},transport==0)
			check(sampled.get("ok",false),"ordinary read succeeded at sample "+str(i+1))
			await create_timer(.07).timeout
		measuring_ordinary=false
		await command("release",{"lease":sample_clients[0].lease},true)
		await command("release",{"lease":sample_clients[1].lease})
	var display_client:Dictionary=await command("claim",{"resident":"codex","client":"MCP builder"},true)
	check(display_client.get("ok",false),"builder claims a resident")
	if display_client.has("lease"):
		var explorer:Dictionary=await command("look",{"lease":display_client.lease,"view":"creations"},true)
		check(explorer.get("catalog",{}).has("path"),"read authored placements")
		var position:Vector2=game.world.point(game.world.actors.codex).round()
		var cells:Array=[]
		for offset in [Vector2.UP,Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT,Vector2.ZERO]:
			var cell:Vector2=position+offset
			if game.world.catalog.on_land(game.world.catalog.regions.home,cell) and game.world.walkable("home",cell):
				cells.append([cell.x,cell.y])
		if not cells.is_empty():
			var tile:Array=cells[0]
			var steps:Array=[{"action":"place_piece","item":"sign","position":tile},{"action":"name_place","position":tile,"label":"Quiet coast"},{"action":"write_diary","label":"I put a sign near the coast."}]
			var work:Dictionary=await command("act",{"lease":display_client.lease,"steps":steps,"reason":"A name for this shore."},true)
			var seq:=0
			var finished:=false
			for _i in range(3):
				var updates:Dictionary=await command("events",{"lease":display_client.lease,"after":seq},true)
				for event in updates.get("events",[]):
					seq=maxi(seq,int(event.sequence))
					if event.type=="action_finished" and event.data.id==work.get("action_id") and event.data.status=="completed":finished=true
				if finished:break
			check(finished,"actual MCP placement, naming and diary finish through World")
			check(game.world.flower_creation.creations.changes.size()==3,"three actual changes logged")
			if finished:
				check(game.world.flower_creation.creations.commit("codex","remove_piece",{"position":tile},"")=="","test cell released")
			await command("release",{"lease":display_client.lease},true)
		else:check(false,"no valid cell for placement")
	var world:RefCounted=game.world
	var layer:RefCounted=world.flower_creation.creations
	var actor:Dictionary=world.actors.human
	var spot:Vector2=world.point(actor).round()
	for offset in [Vector2.ZERO,Vector2.UP,Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT]:
		var candidate:Vector2=world.point(actor).round()+offset
		if world.catalog.on_land(world.catalog.regions.home,candidate) and world.walkable("home",candidate):
			spot=candidate;break
	var step:Dictionary={"item":"sign","position":[spot.x,spot.y],"label":"The quiet coast"}
	var wood:int=world.storage.count("wood")
	check(layer.commit("human","remove_piece",step,"")=="protected_or_missing","existing world protected")
	check(layer.commit("human","place_piece",step,"")=="","place existing sprite at a legal grid cell")
	check(layer.commit("human","place_piece",step,"")=="occupied_or_blocked","occupied grid cell refused")
	check(world.storage.count("wood")==wood-2,"exact material debit")
	check(layer.commit("human","name_place",step,"")=="","persist sign name")
	var save_path:=directory.path_join("island-v2.json")
	check(Save.save_world(game.world,directory),"new save writes")
	var old:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(save_path))
	old.erase("world_creations")
	var file:=FileAccess.open(save_path,FileAccess.WRITE)
	var encoded:=JSON.stringify(old)
	file.store_string(encoded)
	file.close()
	var prefs:=FileAccess.open(directory.path_join("local-life.cfg"),FileAccess.WRITE)
	prefs.store_string("[interface]\nshow_hunger=true\n")
	prefs.close()
	check(Save.load_world(game.world,directory).get("loaded",false),"old save loads")
	check(FileAccess.get_file_as_string(directory.path_join("island-v2.before-world.json"))==encoded,"old save backed up byte for byte")
	check(FileAccess.get_file_as_string(directory.path_join("before-world-files/local-life.cfg"))=="[interface]\nshow_hunger=true\n","sidecar backed up before migration")
	check(layer.changes.is_empty(),"missing optional world creations restores empty")
	file=FileAccess.open(save_path,FileAccess.WRITE)
	old["world_creations"]={"pieces":{},"changes":[],"summaries":{},"sequence":0,"seen":0}
	file.store_string(JSON.stringify(old))
	file.close()
	check(layer.commit("human","place_piece",step,"")=="","place after loading")
	check(Save.save_world(world,directory),"placement save")
	check(Save.load_world(world,directory).get("loaded",false) and layer.pieces.size()==1,"placed piece survives reload")
	check(FileAccess.get_file_as_string(directory.path_join("island-v2.before-world.json"))==encoded,"repeat load preserves first backup")
	check(layer.commit("human","remove_piece",step,"")=="" and layer.pieces.is_empty(),"removing placed piece frees cell")
	check(world.storage.count("wood")==wood-3,"half-cost removal refund")
	await process_frame
	await process_frame
	check(door.open(),"reopen door after reload invalidated the old session")
	for mcp in [true,false]:
		var claimed:Dictionary=await command("claim",{"resident":"codex","client":"Placement check"},mcp)
		check(claimed.has("lease"),"place/remove client claims "+str(mcp)+" "+str(claimed.get("error","")))
		if not claimed.has("lease"):continue
		var list:Dictionary=await command("look",{"lease":claimed.lease,"view":"creations"},mcp)
		check(list.get("catalog",{}).size()>=10 and not list.catalog.fence.walkable,"shared blocking catalog "+str(mcp))
		var origin:Vector2=world.point(world.actors.codex).round()
		var tile:Array=[]
		for offset in [Vector2(3,0),Vector2(0,3),Vector2(-3,0),Vector2(0,-3),Vector2(3,3)]:
			var p:Vector2=origin+offset
			var args:Dictionary={"item":"fence","position":[p.x,p.y]}
			if layer.check("codex","place_piece",args).is_empty() and not layer.approach("codex",p).is_empty():
				tile=args.position;break
		check(not tile.is_empty(),"routable blocking piece spot "+str(mcp))
		if not tile.is_empty():
			var k:String=world.flower_creation.key("home",Vector2(tile[0],tile[1]))
			check(await piece_action(claimed.lease,{"action":"place_piece","item":"fence","position":tile},mcp) and layer.pieces.get(k,{}).get("owner")=="codex","transport placed blocking piece "+str(mcp))
			check(await piece_action(claimed.lease,{"action":"remove_piece","position":tile},mcp) and not layer.pieces.has(k),"transport removed blocking piece "+str(mcp))
			check(await piece_action(claimed.lease,{"action":"place_piece","item":"sign","position":tile},mcp) and layer.pieces.get(k,{}).get("item")=="sign","transport placed a real sign "+str(mcp))
			check(await piece_action(claimed.lease,{"action":"name_place","position":tile,"label":"你好"},mcp) and layer.pieces.get(k,{}).get("label")=="你好","transport named the sign "+str(mcp))
			check(layer.pieces.get(k,{}).get("author")=="Placement check","sign records the visiting client as author")
			check(await piece_action(claimed.lease,{"action":"remove_piece","position":tile},mcp) and not layer.pieces.has(k),"transport removed sign for the next client "+str(mcp))
		check(claimed.has("suggestion")==mcp,"same named client sees the suggestion on its first claim only")
		await command("release",{"lease":claimed.lease},mcp)
	door.close()
	latency.sort()
	ordinary_latency.sort()
	if ordinary_latency.size()==100:
		print("WORLD_DOOR_ORDINARY samples=100 p50_ms=",ordinary_latency[49]," p95_ms=",ordinary_latency[94]," max_ms=",ordinary_latency[-1])
	print("WORLD_DOOR_SLOW ",JSON.stringify(slow_samples))
	print("WORLD_DOOR checks=",checks," failures=",failures," samples=",latency.size()," p50_ms=",latency[ceili(latency.size()*.5)-1]," p95_ms=",latency[ceili(latency.size()*.95)-1]," max_ms=",latency[-1])
	game.queue_free()
	await process_frame
	quit(1 if failures>0 else 0)
