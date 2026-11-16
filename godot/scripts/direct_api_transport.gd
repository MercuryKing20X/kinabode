extends Node
## Only supplied game cards are sent. No tools, filesystem access or provider history.
## HTTPRequest checks connectivity; HTTPClient incrementally reads SSE (HTTPRequest
## buffers its entire response). Neither uses Python, a mailbox or a transcript file.
const Credentials=preload("res://scripts/api_credentials.gd")
signal event_received(event:Dictionary)
var directory:=""
var resident_id:="codex"
var scope:="direct"
var probe:HTTPRequest
var client:HTTPClient
var deadline:=0
var timeout_ms:=45000
var key:=""
var secret_guard:=""
var base:=""
var model:=""
var body:=""
var raw:=PackedByteArray()
var sse:=PackedByteArray()
var content:=""
var usage:Dictionary={}
var turn_key:=""
var started:=0
var first_ms:Variant=null
var streaming:=false
var posted:=false
var received_headers:=false
var done:=false
var partial:=""
var request_bytes:=0
func say(event:Dictionary)->void:
	event["turn_key"]=turn_key;event["scope"]=scope
	event_received.emit(scrub(event))
func fail(code:String)->void:
	# Fixed diagnostics only: servers may echo Authorization in arbitrary bodies.
	var messages={"missing_key":["缺少密钥；请填写本机密钥或环境变量。","Missing API key; set a local key or environment variable."],"invalid_endpoint":["地址无效；云端使用 HTTPS，本机可用 HTTP。","Invalid address; use HTTPS, or HTTP on loopback."],"auth":["密钥无效或无权访问。","Invalid key or access denied."],"timeout":["请求超时；本地生活继续。","Request timed out; local life continues."],"network":["连接失败；请检查地址和服务。","Connection failed; check the address and service."],"response":["回复格式无效或过大。","Invalid or oversized response."],"context":["游戏卡片过大，本次未发送。","Game card too large; request was not sent."]}
	var pair:Array=messages.get(code,messages.network)
	close()
	say({"kind":"error","code":"openai_auth" if code=="auth" else code,"message":pair[0] if TranslationServer.get_locale().begins_with("zh") else pair[1]})
func configure()->bool:
	var settings:=Credentials.read_settings(directory)
	base=Credentials.endpoint(OS.get_environment("HABITAT_OPENAI_BASE_URL") if not OS.get_environment("HABITAT_OPENAI_BASE_URL").is_empty() else str(settings.get_value("openai","base","https://api.openai.com/v1")))
	key=Credentials.key(directory)
	secret_guard=key
	if base.is_empty():fail("invalid_endpoint");return false
	if key.is_empty():fail("missing_key");return false
	if "\n" in key or "\r" in key:fail("missing_key");return false
	return true
func headers()->PackedStringArray:
	return PackedStringArray(["Authorization: Bearer "+key,"Content-Type: application/json","Accept: application/json, text/event-stream","User-Agent: Mozilla/5.0"])
func connect_api()->bool:
	close();turn_key=""
	if not configure():return false
	probe=HTTPRequest.new();add_child(probe);probe.timeout=15;probe.max_redirects=0;probe.body_size_limit=2097152
	probe.request_completed.connect(_probed)
	if probe.request(base+"/models",headers())!=OK:fail("network");return false
	return true
func _probed(result:int,status:int,_headers:PackedStringArray,_bytes:PackedByteArray)->void:
	if result!=HTTPRequest.RESULT_SUCCESS:fail("network");return
	if status in [401,403]:fail("auth");return
	if status<200 or status>=300:fail("network");return
	key=""
	say({"kind":"state","state":"ready","turnComplete":false})
func send(message:Dictionary,persona:Dictionary)->bool:
	close();turn_key=str(message.turn_key)
	if not configure():return false
	var settings:=Credentials.read_settings(directory)
	var world:Dictionary=message.get("world",{})
	var card:Dictionary=world.get("lifeblood_memory",world.get("intent_card",world)).duplicate(true)
	var deep:bool=message.get("kind")=="autonomy_event" or world.get("source")=="host_memory_maintenance" or card.has("memory_request")
	model=str(settings.get_value("openai","thinking" if deep else "chat","gpt-6.1-terra"))
	var instructions:=FileAccess.get_file_as_string("res://content/connection-instructions.txt")
	var messages:Array=[{"role":"system","content":instructions+"\nFixed resident persona:\n"+str(persona.get("text",""))},{"role":"user","content":JSON.stringify({"card":card,"chat":str(message.get("text",""))})}]
	# Keep the same identity and memory for every provider, never silently drop them.
	if JSON.stringify(messages).to_utf8_buffer().size()>100000:fail("context");return false
	var payload:Dictionary={"model":model,"messages":messages,"stream":true,"stream_options":{"include_usage":true},"max_tokens":1600}
	if model.begins_with("gpt-") or model.begins_with("o3") or model.begins_with("o4"):
		payload["reasoning_effort"]={"low":"low","medium":"medium","high":"high","ultra":"high","lifeblood":"high"}.get(str(message.get("level","low")),"low") if deep else "low"
	body=JSON.stringify(payload);request_bytes=body.to_utf8_buffer().size()
	client=HTTPClient.new();client.read_chunk_size=4096
	var split:=base.split("://");var address:String=split[1].split("/")[0]
	var host:=address;var port:=443 if split[0]=="https" else 80
	if address.begins_with("["):
		host=address.get_slice("]",0)+"]"
		if "]:" in address:port=int(address.get_slice("]:",1))
	elif ":" in address:host=address.get_slice(":",0);port=int(address.get_slice(":",1))
	if client.connect_to_host(host,port,TLSOptions.client() if split[0]=="https" else null)!=OK:fail("network");return false
	started=Time.get_ticks_msec();deadline=started+timeout_ms;set_process(true)
	say({"kind":"state","state":"thinking"})
	return true
func close()->void:
	if is_instance_valid(probe):probe.cancel_request();probe.queue_free();probe=null
	if client!=null:client.close();client=null
	key="";secret_guard="";body="";raw.clear();sse.clear();content="";usage={};partial="";first_ms=null
	posted=false;received_headers=false;streaming=false;done=false;set_process(false)
func cancel()->void:
	close();say({"kind":"state","state":"cancelled"})
func _process(_delta:float)->void:
	if client==null:return
	if Time.get_ticks_msec()>deadline:fail("timeout");return
	if client.poll()!=OK:fail("network");return
	var state:=client.get_status()
	if state==HTTPClient.STATUS_CONNECTED and not posted:
		var path:String="/"+base.split("://")[1].split("/",true,1)[1]+"/chat/completions"
		if client.request(HTTPClient.METHOD_POST,path,headers(),body)!=OK:fail("network");return
		posted=true;body="";key=""
	if client.has_response() and not received_headers:
		received_headers=true
		var status:=client.get_response_code()
		if status in [401,403]:fail("auth");return
		if status<200 or status>=300:fail("network");return
		for header in client.get_response_headers():
			if header.to_lower().begins_with("content-type:") and "text/event-stream" in header.to_lower():streaming=true
	if state==HTTPClient.STATUS_BODY:
		var chunk:=client.read_response_body_chunk()
		if streaming:
			sse.append_array(chunk)
			if sse.size()>2097152:fail("response");return
			while sse.find(10)>=0:
				var at:=sse.find(10);var line:=sse.slice(0,at).get_string_from_utf8().strip_edges();sse=sse.slice(at+1)
				if line.begins_with("data:"):_sse_line(line.substr(5).strip_edges())
				if client==null:return
		else:raw.append_array(chunk)
		if raw.size()>2097152 or content.to_utf8_buffer().size()>2097152:fail("response");return
	elif posted and received_headers and state in [HTTPClient.STATUS_CONNECTED,HTTPClient.STATUS_DISCONNECTED]:
		if streaming:
			if not done:fail("response");return
		else:
			var value:Variant=decode(raw.get_string_from_utf8())
			if not value is Dictionary:fail("response");return
			usage=value.get("usage",{}) if value.get("usage") is Dictionary else {}
			var choices:Variant=value.get("choices",[])
			if not choices is Array or choices.is_empty() or not choices[0] is Dictionary:fail("response");return
			content=str(choices[0].get("message",{}).get("content",""))
		finish()
	elif state in [HTTPClient.STATUS_CANT_CONNECT,HTTPClient.STATUS_CANT_RESOLVE,HTTPClient.STATUS_CONNECTION_ERROR,HTTPClient.STATUS_TLS_HANDSHAKE_ERROR]:fail("network")
func _sse_line(line:String)->void:
	if line=="[DONE]":done=true;return
	if line.is_empty():return
	var event:Variant=decode(line)
	if not event is Dictionary:fail("response");return
	if event.get("usage") is Dictionary:usage=event.usage
	for choice in event.get("choices",[]):
		if choice is Dictionary and choice.get("delta") is Dictionary and choice.delta.get("content") is String:content+=choice.delta.content
	var regex:=RegEx.new();regex.compile('"speech"\\s*:\\s*"')
	var match:=regex.search(content)
	if match!=null:
		var suffix:=content.substr(match.get_end())
		for length in range(suffix.length(),-1,-1):
			var parser:=JSON.new()
			if parser.parse('"'+suffix.left(length)+'"')==OK and parser.data is String:
				var text:String=parser.data.left(1000)
				if not text.is_empty() and text!=partial:
					partial=text
					if first_ms==null:first_ms=Time.get_ticks_msec()-started
					say({"kind":"speech_partial","text":text})
				break
func finish()->void:
	# Charge valid usage even when the final intent JSON is malformed. Missing usage
	# stays unknown in the existing reservation ledger; never invent free tokens.
	var valid_usage:=true
	for field in ["prompt_tokens","completion_tokens","total_tokens"]:
		var n:Variant=usage.get(field)
		if not (n is int or n is float) or not is_finite(n) or n<0 or n!=floor(n):valid_usage=false
	if valid_usage and int(usage.total_tokens)>=int(usage.prompt_tokens)+int(usage.completion_tokens):
		say({"kind":"usage","input_tokens":int(usage.prompt_tokens),"output_tokens":int(usage.completion_tokens),"total_tokens":int(usage.total_tokens),"complete":true,"model":model,"estimated_usd":null,"first_token_ms":first_ms,"ai_reply_ms":Time.get_ticks_msec()-started,"request_bytes":request_bytes})
	var value:Variant=decode(content)
	if not value is Dictionary or not value.get("speech") is String:fail("response");return
	for field in ["intents","memory","planning"]:
		if not value.get(field,[]) is Array or value.get(field,[]).size()>(5 if field=="intents" else 6) or value.get(field,[]).any(func(item):return not item is Dictionary):fail("response");return
	value["kind"]="intent_result";value.speech=value.speech.left(1000)
	for field in ["observe","want","reflect"]:
		if value.has(field) and (not value[field] is String or value[field].length()>1200):fail("response");return
	if value.has("feel"):
		var feeling:Variant=value.feel
		if not feeling is Dictionary or not feeling.get("text") is String or feeling.text.length()>1200 or not feeling.get("source_ids") is Array or feeling.source_ids.size()>30 or feeling.source_ids.any(func(id):return not id is String):fail("response");return
	if value.has("act") and value.act!=value.get("intents",[]):fail("response");return
	if value.has("life_wishes") and (not value.life_wishes is Array or value.life_wishes.size()>3):fail("response");return
	if value.has("life_day") and (not value.life_day is Dictionary or value.life_day.values().any(func(v):return not v is String or v.length()>1200)):fail("response");return
	# Host independently validates life fields, memories and every intention.
	var accepted:Dictionary={}
	for field in ["speech","intents","memory","planning","preference","reason","observe","feel","want","act","reflect","life_wishes","life_day"]:
		if value.has(field):accepted[field]=value[field]
	accepted["kind"]="intent_result"
	accepted=scrub(accepted)
	close();say(accepted);say({"kind":"state","state":"ready","turnComplete":true})

func decode(text:String)->Variant:
	var parser:=JSON.new()
	return parser.data if parser.parse(text)==OK else null

func scrub(value:Variant)->Variant:
	if value is String:return value.replace(secret_guard,"[redacted]") if not secret_guard.is_empty() else value
	if value is Array:return value.map(func(item):return scrub(item))
	if value is Dictionary:
		var clean:Dictionary={}
		for field in value:clean[field]=scrub(value[field])
		return clean
	return value
