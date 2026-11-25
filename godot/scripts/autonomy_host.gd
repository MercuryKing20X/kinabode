extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
## Main's session integration. Scheduler remains provider-neutral and read-only.
var _owner: WeakRef
var game: Node:
	get:return _owner.get_ref()
var scheduler: RefCounted
var pending: Array=[]
var manual_usage: Dictionary={}
var complete_usage: Dictionary={}
var quiet_until: Dictionary={}
var meetings:RefCounted
var notice_until:=0.0
func setup(owner_node: Node,prefs: RefCounted) -> void:
	_owner=weakref(owner_node)
	meetings=preload("res://scripts/heart_meetings.gd").new(owner_node)
	scheduler=preload("res://scripts/autonomy_scheduler.gd").new()
	refresh_support()
	scheduler.setup(game.world,prefs,dispatch,can_send,recent)
	scheduler.company_fireside=func(id):return game.company!=null and game.company.fireside_model_ready(id)
	scheduler.company_ready=func(id):return game.company!=null and game.company.model_ready(id)
	scheduler.company_progress=func(id,reason):game.company.scheduler_state(id,"waiting",reason)
	scheduler.codex_high=func(id):return game._valid_link(game.links,id) and game.links[id].get_script()==preload("res://scripts/companion_link.gd")
	prefs.preference_changed.connect(changed)
	scheduler.ultra_notice.connect(show_notice)
func recent(id: String) -> Array:
	return game.dialogue.histories.get("direct:"+id,[]).filter(func(entry):return entry.kind in ["message","answer","autonomy"]).duplicate(true)
func context(id: String) -> Dictionary:return game.world.autonomy_context(id,scheduler.queues.get(id,[]),recent(id))
func refresh_support() -> void:
	for id in game.world.director.routines:
		var connection:Variant=game.links.get(id)
		var supported: bool=is_instance_valid(connection) and connection.has_method("autonomy_capabilities") and connection.autonomy_capabilities().supported and game.world.director.model_controlled(id) and not game.resident_connections.preferences.failure_state(id).get("unavailable",false)
		game.resident_connections.preferences.runtime_supported[id]=supported
func can_send(id: String) -> bool:
	if meetings.reserved_guest(id):return false
	if native_heart(id) and meetings.incoming(id).is_empty() and not game.world.director.brains[id].intention.due() and (game.company==null or not game.company.model_ready(id)):return false
	if not pending.is_empty() or game.next_chat.has(id):return false
	# Input focus suppresses fresh autonomous inference independently of body/follow holds.
	if game.chat.visible and game.chat_input.has_focus() and (game.group_chat or game.chat_actor==id):return false
	return (game.intentions==null or not game.intentions.plans.has(id)) and bool(game.resident_connections.preferences.runtime_supported.get(id,false)) and game._valid_link(game.links,id) and not game.links[id].is_busy() and not game.questions.has(id) and not game.group_questions.has(id) and not (game._valid_link(game.group_links,id) and game.group_links[id].is_busy()) and scheduler.now()>=float(quiet_until.get(id,0))
func dispatch(id: String,data: Dictionary,policy: Dictionary,key: String) -> bool:
	if not can_send(id):return false
	if native_heart(id) or (game.links[id].has_method("uses_intents") and game.links[id].uses_intents()):
		game.links[id].helper_filename="intent_companion.py"
		game.immediate_turns[id]={"turn_key":key,"command":true,"text":"","result":{},"memory_sources":[],"memory_request":{},"autonomy":true}
	var context:Dictionary=data.duplicate(true)
	if native_heart(id):
		var fireside:bool=game.company!=null and game.company.fireside_model_ready(id)
		var invite:Dictionary={} if fireside or (game.company!=null and game.company.model_ready(id)) else meetings.prompt(id,key)
		var company:Dictionary=game.company.model_card(id,key) if invite.is_empty() and game.company!=null else {}
		if fireside and company.is_empty():return false
		var card:Dictionary={"company_request":company} if not company.is_empty() else heart_card(id) if invite.is_empty() else {"peer_request":invite}
		context["heart_card"]=card
		game.immediate_turns[id]["heart"]=true
		if not company.is_empty():game.immediate_turns[id]["company"]=true
		elif invite.is_empty():game.world.director.brains[id].intention.requested()
		else:game.immediate_turns[id]["peer_invitation"]=invite.id
	elif scheduler.preferences.preference(id).level=="lifeblood":
		if game.life_archive!=null:game.life_archive.observe_context(id,key)
		var card:Dictionary=game._intent_card(id,{"dialogue":{"channel_id":"direct:"+id,"recipient_ids":[id]}},"direct:"+id)
		context["lifeblood_memory"]=card
		game.immediate_turns[id].memory_sources=card.memory_sources.map(func(e):return e.id)
	var sent:bool=game.links[id].send_autonomy(context,scheduler.preferences.preference(id).level,{"tools":int(policy.tools),"turn_tokens":int(game.connection_pool.turn_limit(id))},key)
	if game.immediate_turns.get(id,{}).get("company",false):
		if sent:game.company.scheduler_state(id,"sent")
		else:game.company.model_failed(id,"transport_rejected")
	if not sent and game.life_archive!=null:game.life_archive.reject_before_inference(id,key)
	return sent
func player_input() -> void:
	if scheduler!=null and not scheduler.config.is_empty():scheduler.input_received()
func changed(id: String,_preference: Dictionary) -> void:
	# Lowering/closing also cancels an in-flight turn; never carries over an old policy.
	cancel(id)
	var connection:Variant=game.links.get(id)
	if is_instance_valid(connection) and connection.has_method("autonomy_capabilities") and "low" in connection.autonomy_capabilities().get("levels",[]):connection.capability_error=""
	refresh_support()
	game._refresh_control_ui()
func owns_turn(id: String) -> bool:
	return scheduler.active.has(id) and game._valid_link(game.links,id) and game.links[id].turn_kind=="autonomy_event" and game.links[id].turn_key==scheduler.active[id].id
func cancel(id: String) -> void:
	if owns_turn(id) and not game.links[id]._cancelling:game.links[id].cancel_turn()
func interrupted(id: String) -> void:
	pending=pending.filter(func(entry):return id not in entry.targets)
	quiet_until[id]=scheduler.now()+120
	scheduler.queues.erase(id)
func tick(delta: float) -> void:
	refresh_support()
	if delta>0:meetings.tick()
	if game.autonomy_notice!=null:game.autonomy_notice.visible=scheduler.now()<notice_until
	for id in scheduler.active.keys():
		if not owns_turn(id):
			scheduler.finish(id,false);continue
		var bound_night:bool=game.company!=null and game.company.fireside_model_bound(id,str(scheduler.active[id].id))
		var offered:Dictionary=game.company.model_pending.get(id,{}) if game.company!=null else {}
		var lost_night:bool=offered.get("turn","")==scheduler.active[id].id and offered.get("kind","") in ["story","question"] and not bound_night
		if not scheduler.enabled(id) or game.world.activities.members.has(id) or game.world.activities.gathering.get("failures",{}).has(id) or (game.world.shared_activity.holds(id) and not bound_night) or lost_night or game.questions.has(id) or game.group_questions.has(id):cancel(id)
	for id in game.world.director.brains:
		var brain:RefCounted=game.world.director.brains[id]
		brain.intention.settled=func(row):remember_intention(id,row)
		brain.intention.outings.meetings=meetings
		if not scheduler.enabled(id) or scheduler.active.has(id) or not can_send(id):continue
		if not native_heart(id):continue
		var invite:Dictionary=meetings.incoming(id)
		if not invite.is_empty():scheduler.enqueue(id,"heart-peer:"+str(invite.id),"reflection","A companion invited you. Answer this invitation only.")
		elif brain.intention.due():scheduler.enqueue(id,"heart:"+str(brain.intention.revision),"reflection","Choose a current intention from the host list.")
	scheduler.advance(delta,game.world.activities.held)
func defer_chat(text: String,scope: String,id: String) -> bool:
	var targets: Array=game._group_recipients() if scope=="group" else [id]
	var waiting: bool=targets.any(func(who):return owns_turn(who))
	if not waiting:return false
	if pending.size()>=3:game.status.text=LocalText.text("system.autonomy_host.the_queue_waiting_for_stop_is_full_your_input");return true
	for who in targets:game._instant_busy_reply(who,text)
	pending.append({"text":text,"scope":scope,"targets":targets.duplicate()})
	game.chat_input.clear();game.status.text=LocalText.text("content.overnight.text.72a9bad2f4d003") if TranslationServer.get_locale().begins_with("zh") else "Your message is queued and will go first after the current reply."
	# Preserve the active generation; player messages flush first on completion.
	return true
func flush_pending() -> void:
	if pending.is_empty():return
	var entry: Dictionary=pending[0]
	if entry.targets.any(func(id):return scheduler.active.has(id) or (game._valid_link(game.links,id) and game.links[id].is_busy()) or (game._valid_link(game.group_links,id) and game.group_links[id].is_busy())):return
	pending.pop_front()
	if entry.scope=="group":game._send_group(entry.text,entry.targets)
	elif game.world.director.model_controlled(entry.targets[0]):game._send_direct(entry.targets[0],entry.text)
	if not pending.is_empty():game.call_deferred("_flush_autonomy_messages")
func event(value: Dictionary,id: String,scope: String) -> void:
	var key: String=str(value.get("turn_key",""))
	if value.get("kind")=="usage" and not key.is_empty():
		var total: int=int(value.get("total_tokens",-1));var input: int=int(value.get("input_tokens",-1));var output: int=int(value.get("output_tokens",-1))
		if total<0 or input<0 or output<0 or total<input+output:return
		if value.get("autonomy",false) and scheduler.active.get(id,{}).get("id")==key:scheduler.record_usage(id,total,input,output)
		else:
			var receipt: String=id+":"+scope+":"+key
			var before: Dictionary=manual_usage.get(receipt,{"total":0,"input":0,"output":0})
			if total<int(before.total) or input<int(before.input) or output<int(before.output):return
			var ledger: Dictionary=scheduler.usage(id)
			ledger.tokens+=total-int(before.total);ledger.input_tokens+=input-int(before.input);ledger.output_tokens+=output-int(before.output)
			scheduler.update_turn(ledger,key,scope,total,input,output,"complete" if value.get("complete",false) else "reported_partial")
			if scheduler.preferences.save_accounting(id,ledger):manual_usage[receipt]={"total":total,"input":input,"output":output}
			if manual_usage.size()>128:manual_usage.erase(manual_usage.keys()[0])
		if value.get("complete",false):complete_usage[key]=true
	if value.get("kind")=="state" and value.get("state") in ["ready","cancelled","error","disconnected"] and value.get("turnComplete",true):
		if game.company!=null and game.company.model_pending.get(id,{}).get("turn","")==key and not key.is_empty():
			game.company.model_failed(id,"no_valid_reply" if value.state=="ready" else str(value.state))
		if not key.is_empty() and scheduler.active.get(id,{}).get("id")==key:
			scheduler.finish(id,complete_usage.has(key))
		elif value.get("state")=="ready" and not value.get("autonomy",false):scheduler.dialogue_finished(id)
		complete_usage.erase(key)
		game.call_deferred("_flush_autonomy_messages")
	if value.get("kind")=="error" and value.get("code")=="autonomy_unsupported" and scheduler.active.has(id):
		cancel(id)
		scheduler.reject(id,"autonomy_unsupported")
		if not scheduler.preferences.failure_state(id).get("unavailable",false):game.links[id].capability_error=""
		cancel(id);return
	if value.get("kind")=="error" and scheduler.active.has(id):
		if native_heart(id):game.world.director.brains[id].intention.feedback("","reply_invalid")
		# Keep the generation barrier up even if the helper reports an error first.
		cancel(id)
func status(id: String) -> Dictionary:
	refresh_support()
	var connection:Variant=game.links.get(id)
	var supported: bool=bool(game.resident_connections.preferences.runtime_supported.get(id,false))
	var failure: Dictionary=scheduler.preferences.failure_state(id)
	var reason: String=connection.autonomy_capabilities().reason if is_instance_valid(connection) and connection.has_method("autonomy_capabilities") else LocalText.text("system.autonomy_host.no_connection_exists_yet_send_a_message_first_to")
	if failure.get("unavailable",false):reason=LocalText.text("system.autonomy_host.after_d_consecutive_failures_autonomy_was_disabled_s_turn")%[int(failure.count),failure.reason]
	return {"usage_reference":preload("res://scripts/autonomy_estimate.gd").usage_reference(scheduler.config),"supported":supported,"retryable":bool(failure.get("unavailable",false)) and is_instance_valid(connection) and connection.has_method("autonomy_capabilities") and "low" in connection.autonomy_capabilities().get("levels",[]),"reason":reason,"records":scheduler.records.read(id),"gate_labels":scheduler.config.get("gate_labels",{}),"estimated_tokens_per_turn":preload("res://scripts/autonomy_estimate.gd").tokens(scheduler.config,context(id)),"estimated_tokens_per_hour":preload("res://scripts/autonomy_estimate.gd").tokens(scheduler.config,context(id))*int(scheduler.config.levels.ultra.hourly),"usage":scheduler.usage(id),"active":scheduler.active.has(id),"policy":scheduler.policy_for(id) if not scheduler.config.is_empty() else {}}

func dispose() -> void:
	if scheduler==null:return
	if scheduler.preferences.preference_changed.is_connected(changed):scheduler.preferences.preference_changed.disconnect(changed)
	scheduler.dispatch=Callable();scheduler.available=Callable();scheduler.histories=Callable();scheduler.codex_high=Callable()
	scheduler.company_fireside=Callable()
	scheduler.company_ready=Callable();scheduler.company_progress=Callable()
	if scheduler.ultra_notice.is_connected(show_notice):scheduler.ultra_notice.disconnect(show_notice)
	if game.world.promises.execution_started.is_connected(scheduler.note_model_action):game.world.promises.execution_started.disconnect(scheduler.note_model_action)
	if game.world.promises.settled.is_connected(scheduler.dialogue_finished):game.world.promises.settled.disconnect(scheduler.dialogue_finished)

func retire(id: String) -> void:
	# The host has revoked/replaced this source. It will never accept its late events.
	interrupted(id);scheduler.finish(id,false)

func show_notice(id: String,estimate: int) -> void:
	if game.autonomy_notice==null:return
	var reference: String=preload("res://scripts/autonomy_estimate.gd").usage_reference(scheduler.config)
	game.autonomy_notice.text=LocalText.resident(game.world,id)+LocalText.text("system.autonomy_host.today_s_first_ultra_autonomous_turn")+(reference if not reference.is_empty() else LocalText.text("system.autonomy_host.up_to_about_d_tokens_hour_estimate")%estimate)+LocalText.text("system.autonomy_host.no_unit_price_is_configured_you_can_turn_this")
	notice_until=scheduler.now()+float(scheduler.config.get("notice_seconds",10));game.autonomy_notice.show()

func heart_card(id:String)->Dictionary:
	var brain:RefCounted=game.world.director.brains[id]
	var card:Dictionary={"heart_request":brain.intention.card(),"memory":game.memory_books.card(id,"","direct:"+id,scheduler.preferences.preference(id).level)}
	card.heart_request["basic_plan"]=brain.intention.basic.card()
	var facts:Array=game.memory_books.list_for(id,"facts").filter(func(entry):return entry.world_id==game.world.world_id and entry.source=="game")
	card.heart_request.situation["new_shared_facts"]=facts.slice(-3).map(func(entry):return {"summary":game.memory_books.render(entry).left(120),"kind":str(entry.params.get("legacy",{}).get("kind","fact"))})
	card.heart_request.situation["no_new_fact"]=facts.is_empty()
	card.heart_request.situation["player_can_approach"]=brain.distance()<=20
	# Keep complete identity in the separate fixed persona; bound only memory summaries.
	if JSON.stringify(card).to_utf8_buffer().size()>int(brain.config.ai_intention.card_bytes):
		var compact:Dictionary={"abridged":true}
		for section in card.memory:
			if not card.memory[section] is Array:continue
			compact[section]=card.memory[section].slice(0,2).map(func(entry):return {"id":entry.id,"text":str(entry.text).left(120)})
		card.memory=compact
	if JSON.stringify(card).to_utf8_buffer().size()>int(brain.config.ai_intention.card_bytes):card.memory={"abridged":true}
	return card
func remember_intention(id:String,row:Dictionary)->void:
	var en:bool=TranslationServer.get_locale().begins_with("en")
	var brain:RefCounted=game.world.director.brains[id]
	var line:String=("My intention: " if en else "我的打算：")+brain.action_name(row.activity)+(". Outcome: " if en else "。结局：")+brain.text(row.outcome)+(". " if en else "。")+str(row.detail)
	game.memory_books.add(id,str(row.get("world_id",game.world.world_id)),"intention:"+str(row.get("id",id+":"+str(row.at))),"feelings",line,{"kind":"intention_outcome","activity":row.activity,"outcome":row.outcome},int(row.get("day",game.world.days.day())),"game",[id],float(row.at))

func native_heart(id:String)->bool:
	return game._valid_link(game.links,id) and is_instance_valid(game.links[id].get("direct_api"))
