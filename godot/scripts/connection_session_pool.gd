extends Node
const Text=preload("res://scripts/localization.gd")
const IDS=["codex","companion-2","npc.mira","npc.nora"]
signal releasing(id:String, scope:String)
signal changed
signal local_requested(id:String)
signal usage_notice(id:String)
signal quota_local_requested(id:String,first_notice:bool)
var quota_pending:Dictionary={}
var quota_elapsed:=0.0
var directory:=""
var links:Dictionary={}
var states:Dictionary={}
var settings:=ConfigFile.new()
var history:=ConfigFile.new()
var factory:Callable
var deadlines:Dictionary={}
var retries:Dictionary={}
var retry_due:Dictionary={}
var shared_preferences:RefCounted
var ledger_world:=""
var steward_requested:=""
var api_usage:=ConfigFile.new()
var initialized:=false
static func obtain(tree:SceneTree,base:String)->Node:
	var pool:Node=tree.root.get_node_or_null("ConnectionSessionPool")
	if pool==null and tree.root.has_meta("pending_connection_pool"):
		var pending:Variant=tree.root.get_meta("pending_connection_pool")
		if is_instance_valid(pending):pool=pending
	if pool==null:
		pool=load("res://scripts/connection_session_pool.gd").new();pool.name="ConnectionSessionPool";pool.directory=base;tree.root.set_meta("pending_connection_pool",pool)
		tree.root.add_child.call_deferred(pool)
		pool._ready()
	return pool
func _ready()->void:
	if initialized:return
	initialized=true
	api_usage.load(directory.path_join("openai-usage.cfg"))
	settings.load(directory.path_join("connection-mode.cfg"));history.load(directory.path_join("connection-overview.cfg"))
	# Retired player transports are ignored in memory; never rewrite on load.
	settings.set_value("connection","external_residents",{})
	settings.set_value("connection","shared_test",false)
	var save_path:=directory.path_join("island-v2.json")
	if FileAccess.file_exists(save_path):
		var saved:Variant=JSON.parse_string(FileAccess.get_file_as_string(save_path))
		if saved is Dictionary:ledger_world=str(saved.get("world_id",""))
	process_mode=Node.PROCESS_MODE_ALWAYS
func external(id:String)->bool:return settings.get_value("connection","external_residents",{}).get(id,false)
func stale(id:String)->bool:return external(id) and Time.get_unix_time_from_system()-float(history.get_value("external",id,0))>86400
func auto_enabled(id:String)->bool:return settings.get_value("auto",id,true)
func set_auto(id:String,enabled:bool)->void:settings.set_value("auto",id,enabled);persist()
func persist()->void:
	settings.save(directory.path_join("connection-mode.cfg"))
func management(id:String)->bool:return id in IDS and settings.get_value("management",id,false)
func set_management(id:String,on:bool)->void:
	if id not in IDS:return
	settings.set_value("management",id,on);persist();changed.emit()
func daily_limit(id:String)->int:return int(settings.get_value("daily_limit",id,0))
func set_daily_limit(id:String,value:int)->void:
	if id not in IDS or value<0 or value>100000000:return
	settings.set_value("daily_limit",id,value);persist();changed.emit()
func rows()->Dictionary:
	var result:Dictionary={}
	for id in IDS:
		var row:Dictionary=states.get(id,{"state":"unconnected" if external(id) else "local"}).duplicate(true)
		row.merge({"provider":Text.text("simple.external") if external(id) else Text.text("simple.builtin") if links.has(id) else Text.text("simple.local"),"last_connected":history.get_value("connected",id,0),"tokens":history.get_value("tokens",id+"/"+Time.get_date_string_from_system(),"?"),"stale":stale(id),"external":external(id),"auto":auto_enabled(id)},false)
		var prefs:=preload("res://scripts/resident_intelligence_preferences.gd").new();prefs.setup(directory,ledger_world)
		var account:Dictionary=prefs.accounting(id)
		var day:int=int(floor((Time.get_unix_time_from_system()+Time.get_time_zone_from_system().bias*60)/86400.0))
		if not account.is_empty():
			row.tokens=str(account.tokens) if int(account.day)==day else "0"
			if int(account.day)==day and (int(account.reserved)>0 or int(account.unknown_turns)>0):row.tokens+=" + ?"
		if settings.get_value("api",id,"codex")=="openai":row.provider="GPT API"
		var aggregate:Dictionary=quota_usage(id);row.tokens=str(aggregate.tokens)+(" + ?" if aggregate.reserved>0 or aggregate.unknown_turns>0 else "");row.daily_limit=daily_limit(id);row.quota_reserved=int(quota_usage(id).get("reserved",0));row.quota_unknown=int(quota_usage(id).get("unknown_turns",0))
		result[id]=row
	return result
func use_external(id:String)->void:
	disconnect_ai(id)
	var mode:Dictionary=settings.get_value("connection","external_residents",{});mode[id]=true;settings.set_value("connection","external_residents",mode);persist();changed.emit()
func configuration(id:String)->Dictionary:
	var world_id:=""
	var path:=directory.path_join("island-v2.json")
	if FileAccess.file_exists(path):
		var save:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
		if save is Dictionary:world_id=str(save.get("world_id",""))
	var python:String=OS.get_environment("HABITAT_PYTHON")
	if python.is_empty():python="/usr/bin/python3"
	var args:Array=[ProjectSettings.globalize_path("res://").path_join("../scripts/habitat_godot.py").simplify_path(),"--data-dir",directory,"--resident",id]
	if not world_id.is_empty():args.append_array(["--world",world_id])
	args.append("mcp")
	return {"mcpServers":{"youqi":{"command":python,"args":args}}}
func use_builtin(id:String)->void:
	var mode:Dictionary=settings.get_value("connection","external_residents",{});mode[id]=false;settings.set_value("connection","external_residents",mode);persist();changed.emit()
func acquire(id:String,scope:String,creator:Callable)->Node:
	var key:=id if scope=="direct" else id+":"+scope
	if valid(key):return links[key]
	var connection:Node=creator.call()
	links[key]=connection
	if connection.get_parent()==null:add_child(connection)
	return connection
func valid(key:String)->bool:
	return links.has(key) and is_instance_valid(links[key]) and not links[key].is_queued_for_deletion()
func release(id:String,scope:String="direct")->void:
	var key:=id if scope=="direct" else id+":"+scope
	var connection:Variant=links.get(key)
	links.erase(key)
	releasing.emit(id,scope)
	if not is_instance_valid(connection):return
	for entry in connection.event_received.get_connections():
		connection.event_received.disconnect(entry.callable)
	connection.shutdown()
	connection.queue_free()
func connect_ai(id:String,world_id:String="")->Node:
	if quota_reached(id):return null
	if settings.get_value("api",id,"codex")=="openai" and int(settings.get_value("openai","limit",10000000))>0 and api_tokens()>=int(settings.get_value("openai","limit",10000000)):return null
	use_builtin(id)
	settings.set_value("enabled",id,true);settings.set_value("selection",id,settings.get_value("api",id,"codex"));persist()
	if valid(id) and states.get(id,{}).get("state","") in ["ready","connecting"]:return links[id]
	var connection:Node=links[id] if valid(id) else factory.call(id) if factory.is_valid() else preload("res://scripts/companion_link.gd").new()
	connection.resident_id=id;connection.world_id=world_id if not world_id.is_empty() else "island-resident";connection.helper_filename="intent_companion.py"
	if connection.get_parent()==null:add_child(connection)
	links[id]=connection;states[id]={"state":"connecting"};deadlines[id]=Time.get_ticks_msec()+30000
	if not connection.has_meta("pool_observed"):
		connection.set_meta("pool_observed",true)
		connection.event_received.connect(func(event):receive(id,event))
	connection.probe_connection();changed.emit();return connection
func schedule_retry(id:String)->void:
	if not settings.get_value("enabled",id,false):return
	if retry_due.has(id):return
	var attempt:int=int(retries.get(id,0))
	retries[id]=attempt+1
	retry_due[id]=Time.get_ticks_msec()+[2000,5000,15000,60000,120000][mini(attempt,4)]
func receive(id:String,event:Dictionary)->void:
	if event.get("code")=="openai_auth":
		_api_error.call_deferred(id,str(event.get("message","")))
		return
	if event.get("kind")=="usage" and event.get("complete",false) and event.has("model") and _valid_api_receipt(event):
		var day:=Time.get_date_string_from_system()
		var key:String=str(event.get("turn_key",""))
		var receipts:Dictionary=api_usage.get_value(day,"receipts",{})
		var receipt:String=id+":"+str(event.get("scope","direct"))+":"+key
		if key.is_empty():
			api_usage.set_value(day,"unscoped_usage_unknown",true);api_usage.save(directory.path_join("openai-usage.cfg"))
			if int(settings.get_value("openai","limit",10000000))>0:stop_all_ai.call_deferred()
		elif not receipts.has(receipt):
			receipts[receipt]=true;api_usage.set_value(day,"receipts",receipts)
			api_usage.set_value(day,"tokens",int(api_usage.get_value(day,"tokens",0))+int(event.get("total_tokens",0)))
			if event.get("estimated_usd")!=null:api_usage.set_value(day,"usd",float(api_usage.get_value(day,"usd",0.0))+float(event.estimated_usd))
			else:api_usage.set_value(day,"unknown_price",true)
			api_usage.save(directory.path_join("openai-usage.cfg"))
			var cap:int=int(settings.get_value("openai","limit",10000000))
			if cap>0 and api_tokens()>=cap:
				stop_all_ai.call_deferred()
			elif cap>0 and api_tokens()>=int(cap*.9) and not api_usage.get_value(day,"warned",false):
				api_usage.set_value(day,"warned",true);api_usage.save(directory.path_join("openai-usage.cfg"))
				states[id]={"state":"ready","greeting":Text.text("gpt.warning")}
				usage_notice.emit(id)
	if event.get("kind")=="error":states[id]={"state":"error","error":explain(str(event.get("message","")))};deadlines.erase(id)
	elif event.get("kind")=="state":
		var state:String=str(event.get("state",""))
		if state=="ready":
			var hello:String=Text.text("reliable.reconnected") if retries.has(id) else Text.text("simple.hello."+id)
			retry_due.erase(id);retries.erase(id)
			states[id]={"state":"ready","greeting":hello};deadlines.erase(id)
			history.set_value("connected",id,Time.get_unix_time_from_system());history.save(directory.path_join("connection-overview.cfg"))
		elif state in ["error","disconnected"]:
			if states.get(id,{}).get("state")!="error":states[id]={"state":state}
	if event.get("state","") in ["error","disconnected"] or event.get("kind")=="error":schedule_retry(id)
	changed.emit()
func explain(raw:String)->String:
	var lower:=raw.to_lower()
	if Text.source("content.connection.match.missing") in raw or "not found" in lower:return Text.text("simple.missing")
	if Text.source("content.connection.match.login") in raw or "auth" in lower or "login" in lower:return Text.text("simple.login")
	if "quota" in lower or "usage limit" in lower or Text.source("content.connection.match.quota") in raw:return Text.text("simple.quota")
	if Text.source("content.connection.match.timeout") in raw or "timeout" in lower or "timed out" in lower:return Text.text("simple.timeout")
	return raw
func disconnect_ai(id:String,explicit:bool=true)->void:
	retries.erase(id);retry_due.erase(id)
	release(id,"group")
	release(id)
	deadlines.erase(id);states[id]={"state":"local"}
	if explicit:settings.set_value("enabled",id,false);settings.set_value("selection",id,"local");persist()
	changed.emit()
func start_saved()->void:
	for id in IDS:
		if settings.get_value("selection",id,"")=="local" and not settings.get_value("enabled",id,false):continue
		var previous:Dictionary=history.get_value("residents",id,{})
		if settings.get_value("enabled",id,false) or previous.get("state","") in ["disconnected","error"]:
			settings.set_value("enabled",id,true);connect_ai(id)
func _process(_delta:float)->void:
	quota_elapsed+=_delta
	if quota_elapsed>=.25:
		quota_elapsed=0
		for actor_id in IDS:
			if settings.get_value("enabled",actor_id,false) and quota_reached(actor_id) and not quota_pending.has(actor_id):
				quota_pending[actor_id]=true;_quota_local.call_deferred(actor_id)
	for id in retry_due.keys():
		if Time.get_ticks_msec()<int(retry_due[id]):continue
		retry_due.erase(id)
		if valid(id):
			links[id].shutdown()
			links[id].probe_connection()
			states[id]={"state":"connecting"};deadlines[id]=Time.get_ticks_msec()+60000
		else:connect_ai(id)

	for id in deadlines.keys():
		if Time.get_ticks_msec()>deadlines[id]:
			deadlines.erase(id);states[id]={"state":"error","error":Text.text("simple.timeout")};schedule_retry(id);changed.emit()

func turn_limit(id:String)->int:return int(settings.get_value("turn_limit",id,0))
func set_turn_limit(id:String,value:int)->void:
	if id not in IDS or value<0 or value>100000000:return
	settings.set_value("turn_limit",id,value);persist();changed.emit()

func api_tokens()->int:return int(api_usage.get_value(Time.get_date_string_from_system(),"tokens",0))
func api_cost()->float:return float(api_usage.get_value(Time.get_date_string_from_system(),"usd",0.0))
func stop_all_ai()->void:
	for id in IDS:
		disconnect_ai(id);local_requested.emit(id)
func set_api(id:String,value:String)->void:
	if settings.get_value("api",id,"codex")==value:return
	disconnect_ai(id,false);local_requested.emit(id);settings.set_value("api",id,value);settings.set_value("selection",id,value);persist()

func _api_error(id:String,message:String)->void:
	states[id]={"state":"error","error":message}
	deadlines.erase(id);schedule_retry(id)
	changed.emit()

func quota_usage(id:String)->Dictionary:
	return preload("res://scripts/ai_quota.gd").usage(directory,id)
func quota_reached(id:String)->bool:
	return preload("res://scripts/ai_quota.gd").reached(directory,id,daily_limit(id))
func _quota_local(id:String)->void:
	quota_pending.erase(id)
	if not quota_reached(id) or not settings.get_value("enabled",id,false):return
	var day:String=Time.get_date_string_from_system()
	var first_notice:bool=history.get_value("quota_notice",id,"")!=day
	disconnect_ai(id)
	quota_local_requested.emit(id,first_notice)
	if first_notice:
		history.set_value("quota_notice",id,day);history.save(directory.path_join("connection-overview.cfg"))
		states[id]={"state":"local","greeting":Text.text("quota.exhausted")};changed.emit()

func _valid_api_receipt(event:Dictionary)->bool:
	for field in ["total_tokens","input_tokens","output_tokens"]:
		var amount:Variant=event.get(field)
		if not (amount is int or amount is float) or not is_finite(amount) or amount<0 or amount!=floor(amount):return false
	return int(event.total_tokens)>=int(event.input_tokens)+int(event.output_tokens)
