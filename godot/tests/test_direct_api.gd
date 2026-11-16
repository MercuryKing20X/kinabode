extends SceneTree
const Credentials=preload("res://scripts/api_credentials.gd")
var events:Array=[]
var failed:=0
var transport:Node
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("DIRECT_API ",label," ",ok)
	if not ok:failed+=1
func wait_kind(kind:String,seconds:float=5)->Dictionary:
	var until:=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<until:
		for event in events:
			if event.kind==kind:return event
		await process_frame
	return {}
func send(model:String="stream")->void:
	var cfg:=Credentials.read_settings(transport.directory);cfg.set_value("openai","chat",model);cfg.save(transport.directory.path_join("connection-mode.cfg"))
	events.clear()
	transport.send({"turn_key":"test-"+model,"text":"你好","world":{"intent_card":{"self":{"id":"codex"},"memory":{"about_you":[{"id":"quote-1","text":"我喜欢下雨"}]}}}},{"text":"小白，温柔。"})
func run()->void:
	for address in ["http://127.0.0.1:11434/v1","http://localhost:1234/v1","http://[::1]:11434/v1","https://api.example.org/v1/chat/completions"]:
		check(not Credentials.endpoint(address).is_empty(),"address "+address)
	for address in ["http://remote.example/v1","https://user:secret@example.org/v1","https://example.org/v1?key=secret"]:check(Credentials.endpoint(address).is_empty(),"reject unsafe address")
	transport=preload("res://scripts/direct_api_transport.gd").new();transport.directory=OS.get_environment("HABITAT_DATA_DIR");root.add_child(transport);transport.event_received.connect(func(event):events.append(event))
	var cfg:=ConfigFile.new();cfg.set_value("openai","base",OS.get_environment("HABITAT_STUB_BASE"));cfg.save(transport.directory.path_join("connection-mode.cfg"))
	check(Credentials.save_key(transport.directory,"stub-only-key"),"local key")
	check(transport.connect_api(),"probe started");check((await wait_kind("state")).get("state")=="ready","HTTP probe")
	send();var reply:Dictionary=await wait_kind("intent_result")
	check(reply.get("speech")=="你好呀，雨停了，我们去看看柚柚。","fragmented SSE utf8")
	check(events.any(func(e):return e.kind=="speech_partial"),"partial before final")
	check(events.any(func(e):return e.kind=="usage" and e.total_tokens==30),"usage")
	send("plain");check((await wait_kind("intent_result")).get("speech")=="我去看看。","nonstream compatibility")
	send("leak");check((await wait_kind("intent_result")).get("speech")=="[redacted]","valid reply cannot echo credential")
	send("auth");check((await wait_kind("error")).get("code")=="openai_auth","key error redacted")
	check(not JSON.stringify(events).contains("stub-only-key"),"no credential in events")
	send("disconnect");check((await wait_kind("error")).get("code")=="network","remote disconnect")
	transport.timeout_ms=100;send("timeout");check((await wait_kind("error")).get("code")=="timeout","timeout")
	transport.timeout_ms=45000;send("timeout");transport.cancel();await create_timer(.2).timeout
	check(not events.any(func(e):return e.kind=="intent_result"),"cancel rejects late output")
	events.clear();check(transport.connect_api(),"reconnect started");check((await wait_kind("state")).get("state")=="ready","reconnect ready")
	send("stream");check(not (await wait_kind("intent_result")).is_empty(),"reply after reconnect")
	transport.close();transport.queue_free()
	cfg=Credentials.read_settings(OS.get_environment("HABITAT_DATA_DIR"));cfg.set_value("api","codex","openai");cfg.set_value("openai","chat","stream");cfg.save(OS.get_environment("HABITAT_DATA_DIR").path_join("connection-mode.cfg"))
	OS.set_environment("HABITAT_PYTHON","/nonexistent/python")
	var link:=preload("res://scripts/companion_link.gd").new();root.add_child(link)
	link.event_received.connect(func(event):events.append(event));events.clear()
	check(link.probe_connection(),"native link probes without Python")
	await wait_kind("state")
	check(not link.is_busy() and link.handshake_ready,"native link handshake ready")
	events.clear();link.send_message("你好",{"intent_card":{"self":{"id":"codex"},"memory":{"about_you":[{"id":"quote-1","text":"我喜欢下雨"}]}}})
	check(not (await wait_kind("intent_result")).is_empty(),"CompanionLink native dispatch")
	check(link._pid==-1 and link._session_dir.is_empty(),"no process or file mailbox")
	link.shutdown();link.queue_free()
	Credentials.save_key(OS.get_environment("HABITAT_DATA_DIR"),"")
	var missing:=preload("res://scripts/direct_api_transport.gd").new();missing.directory=OS.get_environment("HABITAT_DATA_DIR");root.add_child(missing)
	events.clear();missing.event_received.connect(func(event):events.append(event))
	check(not missing.connect_api() and events[0].code=="missing_key","missing key never claims connected")
	missing.queue_free()
	var books:=preload("res://scripts/memory_books.gd").new();books.setup(OS.get_environment("HABITAT_DATA_DIR"))
	books.remember_chat("codex","world","before-ai","我喜欢下雨",1,"direct:codex")
	check(not books.card("codex").is_empty(),"offline words available before connection")
	books.offer_ai_quote("codex","world","real-turn","你说喜欢雨，我也记着今天的海风。","stub-provider",1,"direct:codex")
	check(books.keep_ai_quote("codex") and books.local_quotes("codex").size()==1,"player selected grounded quote")
	var reloaded:=preload("res://scripts/memory_books.gd").new();reloaded.setup(OS.get_environment("HABITAT_DATA_DIR"))
	check(reloaded.local_quotes("codex").size()==1,"quote survives reconnect and reload")
	var quote:Dictionary=reloaded.local_quotes("codex")[0];reloaded.remove(quote.id)
	check(reloaded.local_quotes("codex").is_empty(),"forget removes local quote")
	print("DIRECT_API failures=",failed);quit(1 if failed else 0)
