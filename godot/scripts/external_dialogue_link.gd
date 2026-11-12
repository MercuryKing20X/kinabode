class_name ExternalDialogueLink
extends "res://scripts/companion_link.gd"
## Provider-neutral mailbox. External inference belongs to the client, never faked here.
var packet: Dictionary={}
var results: Dictionary={}
var seen: Dictionary={}
func _start() -> bool:
	if _session.is_empty():_session=_new_token()
	return true
func _send(message: Dictionary) -> bool:
	if message.get("kind")=="chat":
		packet={"world_id":world_id,"resident_id":resident_id,"scope":conversation_scope,"session":_session,"generation":_generation,"request_id":_new_token(),"text":message.text,"world":message.world.duplicate(true)}
		results.clear();seen.clear();_emit({"kind":"state","state":"waiting","message":LocalText.text("connection.external_dialogue_link.the_message_is_ready_waiting_for_the_external_ai")})
	elif message.get("kind")=="tool_result":
		results[message.id]=message.result.duplicate(true)
		if results.size()>32:results.erase(results.keys()[0])
	return true
func read_mailbox(query: Dictionary={}) -> Dictionary:
	if not query.is_empty():return {"ok":false,"error":"invalid_dialogue_query"}
	return {"ok":true,"adapter":"external_mcp","world_id":world_id,"self_actor_id":resident_id,"scope":conversation_scope,"pending":packet.duplicate(true),"results":results.duplicate(true)}
func receive_reply(query: Dictionary) -> Dictionary:
	if packet.is_empty() or not _busy:return {"ok":false,"error":"no_pending_dialogue"}
	for key in ["world_id","resident_id","scope","session","generation","request_id"]:
		if query.get(key)!=packet.get(key):return {"ok":false,"error":"stale_dialogue"}
	if query.keys().any(func(key):return key not in ["world_id","resident_id","scope","session","generation","request_id","event_id","event"]):return {"ok":false,"error":"invalid_dialogue_reply"}
	var id: Variant=query.get("event_id");var event: Variant=query.get("event")
	if not id is String or id.is_empty() or id.length()>64 or seen.has(id) or seen.size()>=64 or not event is Dictionary:return {"ok":false,"error":"invalid_dialogue_event"}
	var kind: Variant=event.get("kind")
	if kind not in ["assistant","question","action","complete"]:return {"ok":false,"error":"unsupported_dialogue_event"}
	if kind in ["assistant","question"] and (not event.get("text") is String or event.text.is_empty() or event.text.length()>4000):return {"ok":false,"error":"invalid_dialogue_text"}
	if kind=="question" and (not event.get("choices",[]) is Array or event.get("choices",[]).size()>5 or not event.get("choices",[]).all(func(choice):return choice is String and choice.length()<=50)):return {"ok":false,"error":"invalid_question_choices"}
	if kind=="action" and not _pending_ids.is_empty():return {"ok":false,"error":"waiting_for_answer"}
	if kind=="action" and not event.get("command") is Dictionary:return {"ok":false,"error":"invalid_dialogue_action"}
	if kind=="complete" and not _pending_ids.is_empty():return {"ok":false,"error":"question_unanswered"}
	var planning:bool=packet.get("world",{}).get("intent_card",{}).has("steward_request")
	if planning and kind in ["action","question"]:return {"ok":false,"error":"planning_only"}
	if planning and kind=="assistant":
		var reply:Variant=JSON.parse_string(event.text)
		if not reply is Dictionary or not reply.get("speech") is String or not reply.get("planning") is Array:return {"ok":false,"error":"invalid_plan_reply"}
		event={"kind":"intent_result","speech":reply.speech,"intents":[],"planning":reply.planning}
	seen[id]=true
	if kind=="complete":packet.clear();_accept_event({"kind":"state","state":"ready","turnComplete":true});return {"ok":true}
	var routed: Dictionary=event.duplicate(true);routed["id"]=id
	_accept_event(routed)
	return {"ok":true,"result":results.get(id,{}).duplicate(true)}
func cancel_turn() -> void:
	_generation+=1;packet.clear();_pending_ids.clear();results.clear();_busy=false
	_emit({"kind":"state","state":"cancelled","message":LocalText.text("connection.external_dialogue_link.the_game_isolated_the_old_reply_stop_the_external")})
func shutdown() -> void:cancel_turn()

func autonomy_capabilities() -> Dictionary:
	return {"supported":false,"reason":LocalText.text("connection.external_dialogue_link.the_external_ai_adapter_has_not_declared_budget_cancellation"),"levels":[]}
