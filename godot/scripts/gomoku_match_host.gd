extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
## Explicit host-authorized chess rounds. Reuses native turn leases and the existing daily ledger.
var _owner: WeakRef
var game: Node:
	get:return _owner.get_ref()
var pending: Dictionary={}
var retired: Array=[]
var serial:=0
var queued_chat: Array=[]
func setup(owner_node: Node) -> void:_owner=weakref(owner_node)
func scheduler() -> RefCounted:return game.autonomy.scheduler
func config() -> Dictionary:return game.world.gomoku.match_config
func connected(id: String) -> bool:
	return game.world.director.model_controlled(id) and game._valid_link(game.links,id) and game.connection_ui_states.get(id+":direct")=="ready" and game.links[id].has_method("send_autonomy") and game.links[id].has_method("autonomy_capabilities") and game.links[id].autonomy_capabilities().supported and game.resident_connections.preferences.preference(id).level in game.links[id].autonomy_capabilities().get("levels",[]) and not game._resident_chat_busy(id)
func policy(id: String) -> Dictionary:return scheduler().config.levels[game.resident_connections.preferences.preference(id).level]
func reserve_size(id: String) -> int:return mini(int(config().step_tokens),int(policy(id).turn_tokens))
func budget_ok(id: String,g: Dictionary) -> bool:
	var ledger: Dictionary=scheduler().usage(id);var reserve:=reserve_size(id);var p:=policy(id)
	return reserve>0 and int(ledger.calls)<int(p.daily) and int(ledger.tokens)+int(ledger.reserved)+reserve<=int(p.daily_tokens) and int(g.ai.tokens)+int(g.ai.unknown_tokens)+int(g.ai.get("reserved_tokens",0))+reserve<=int(g.ai.token_limit)
func begin(site: String,black: String,white: String,sources: Dictionary) -> Dictionary:
	if pending.values().any(func(round_state):return round_state.site==site):return {"ok":false,"error":"previous_chess_turn_pending","message":LocalText.text("ui.gomoku_match_host.wait_for_the_previous_turn_to_confirm_it")}
	for id in [black,white]:
		if id=="human" or not game.world.actors.has(id):return {"ok":false,"error":"invalid_ai_match"}
		if game._resident_chat_busy(id):return {"ok":false,"error":"resident_busy"}
		if sources.get(id)=="model" and not connected(id):return {"ok":false,"error":"model_not_connected","message":LocalText.text("ui.gomoku_match_host.enable_the_players_model_connections_before_starting_the")}
	for id in [black,white]:
		if sources.get(id)=="model" and not budget_ok(id,{"ai":{"tokens":0,"unknown_tokens":0,"token_limit":int(config().max_tokens)}}):return {"ok":false,"error":"chess_budget","message":LocalText.text("ui.gomoku_match_host.not_enough_daily_autonomy_allowance_or_low_mode")}
	return game.world.gomoku.begin_ai_host(site,black,white,sources)
func resume(site: String) -> Dictionary:
	var g: Dictionary=game.world.gomoku.sessions.get(site,{})
	if g.get("mode")!="ai" or g.phase!="paused":return {"ok":false,"error":"not_paused"}
	for id in game.world.gomoku.players(g):
		if pending.has(id) or game._resident_chat_busy(id) or (game.world.gomoku.source_for(g,id)=="model" and not connected(id)):return {"ok":false,"error":"resident_busy"}
	var proposal: Dictionary=g.duplicate(true);proposal.ai.token_limit=int(g.ai.tokens)+int(g.ai.unknown_tokens)+int(config().max_tokens)
	for id in game.world.gomoku.players(g):
		if game.world.gomoku.source_for(g,id)=="model" and not budget_ok(id,proposal):return {"ok":false,"error":"daily_chess_budget"}
	return game.world.gomoku.resume_ai_host(site)
func end(site: String) -> Dictionary:
	var result: Dictionary=game.world.gomoku.abandon_host(site)
	tick(.01);return result
func context(id: String,g: Dictionary) -> Dictionary:
	var memories: Array=[]
	for entry in game.world.memories.records:
		if id in entry.participants:memories.append(str(game.world.memories._describe(entry).get("summary","")).left(60))
	return {"source":"host_authorized_gomoku_match","world_id":game.world.world_id,"resident_id":id,"self":{"id":id,"name":game.world.actors[id].name,"controller":"model"},"event":LocalText.text("ui.gomoku_match_host.game_event_not_a_player_message_the_player"),"chess":game.world.gomoku.read(g.site_id,id).match,"own_memories":memories.slice(-3),"match_dialogue":game.world.gomoku.companion.state(g).get("recent_speech",[]).slice(-3).duplicate(true)}
func defer_direct(id: String,text: String) -> bool:
	if not pending.has(id) or not game._valid_link(game.links,id) or not game.world.director.model_controlled(id):return false
	pause_target(id)
	if not game.links[id].is_busy():return false
	if queued_chat.size()>=3:game.status.text=LocalText.text("ui.gomoku_match_host.the_waiting_match_message_queue_is_full_your");return true
	queued_chat.append({"id":id,"text":text});game.chat_input.clear();game.status.text=LocalText.text("ui.gomoku_match_host.stopping_the_match_turn_the_message_will_be");return true
func discard_chat(id: String) -> void:queued_chat=queued_chat.filter(func(entry):return entry.id!=id)
func pause_site(site: String) -> void:
	var g: Dictionary=game.world.gomoku.sessions.get(site,{})
	if g.get("mode")!="ai":return
	game.world.gomoku.pause(g,LocalText.text("ui.gomoku_match_host.the_player_paused_the_match_the_board_and"))
	for id in game.world.gomoku.players(g):
		if pending.has(id) and game._valid_link(game.links,id):game.links[id].cancel_turn()
func pause_target(id: String,reason: String=LocalText.text("ui.gomoku_match_host.the_player_wants_to_chat_with_a_player")) -> void:
	for g in game.world.gomoku.sessions.values():
		if g.get("mode")=="ai" and id in game.world.gomoku.players(g):
			game.world.gomoku.pause(g,reason)
			for who in game.world.gomoku.players(g):
				if pending.has(who) and game._valid_link(game.links,who):game.links[who].cancel_turn()
	if pending.has(id) and game._valid_link(game.links,id):game.links[id].cancel_turn()
func external_hold(id: String) -> bool:
	return game.questions.has(id) or game.group_questions.has(id) or game.world.activities.members.has(id) or game.world.shared_activity.holds(id) or (game._valid_link(game.group_links,id) and game.group_links[id].is_busy()) or (game.editor!=null and game.editor.visible) or (game.chat.visible and game.chat_input.has_focus() and (game.group_chat or game.chat_actor==id))
func prepare(delta: float) -> void:
	if delta<=0:return
	for g in game.world.gomoku.sessions.values():
		if g.get("mode")=="ai" and g.phase in ["arriving","playing"] and game.world.gomoku.players(g).any(func(id):return external_hold(id) or (game.world.gomoku.source_for(g,id)=="model" and not game.world.director.model_controlled(id))):pause_site(g.site_id)
func tick(delta: float) -> void:
	if delta<=0:return
	for id in pending.keys():
		var p: Dictionary=pending[id];var g: Dictionary=p.record
		if not game._valid_link(game.links,id):
			game.world.gomoku.pause(g,LocalText.text("ui.gomoku_match_host.connection_removed_unknown_usage_stays_reserved"))
			finish(id,g);continue
		if game.world.gomoku.sessions.get(p.site,{}).get("id")!=p.match_id or (g.get("phase")!="playing" and not (g.get("phase")=="finished" and p.moved)) or scheduler().now()>float(p.deadline) or not game.world.director.model_controlled(id):
			if g.get("phase")=="playing":game.world.gomoku.pause(g,LocalText.text("ui.gomoku_match_host.the_model_move_timed_out_or_was_interrupted"))
			if game._valid_link(game.links,id) and not game.links[id]._cancelling:game.links[id].cancel_turn()
	for g in game.world.gomoku.sessions.values():
		if g.get("mode")!="ai" or g.phase!="playing":continue
		var id: String=game.world.gomoku._turn(g)
		if game.world.gomoku.source_for(g,id)!="model" or pending.has(id) or game.world.gomoku.players(g).any(func(who):return pending.has(who)):continue
		if g.history.size()>=int(g.ai.step_limit):game.world.gomoku.pause(g,LocalText.text("ui.gomoku_match_host.this_confirmed_move_limit_is_reached_confirm_again"));continue
		if game.questions.has(id) or game.group_questions.has(id) or game.world.activities.blocked(id):game.world.gomoku.pause(g,LocalText.text("ui.gomoku_match_host.a_player_needs_to_handle_something_else_the"));continue
		if not connected(id):game.world.gomoku.pause(g,LocalText.text("ui.gomoku_match_host.the_model_is_disconnected_or_busy_local_play"));continue
		if not budget_ok(id,g):game.world.gomoku.pause(g,LocalText.text("ui.gomoku_match_host.not_enough_match_or_daily_autonomy_budget_confirm"));continue
		dispatch(id,g)
	if not queued_chat.is_empty():
		var entry: Dictionary=queued_chat[0]
		if not game._valid_link(game.links,entry.id) or not game.world.director.model_controlled(entry.id):
			queued_chat.pop_front();game.status.text=LocalText.text("ui.gomoku_match_host.connection_changed_unsent_match_messages_are_canceled")
		elif not pending.has(entry.id) and not game._resident_chat_busy(entry.id):
			queued_chat.pop_front()
			if game.world.director.model_controlled(entry.id):game._send_direct(entry.id,entry.text)
func dispatch(id: String,g: Dictionary) -> void:
	var data:=context(id,g)
	if JSON.stringify(data).to_utf8_buffer().size()>4096:game.world.gomoku.pause(g,LocalText.text("ui.gomoku_match_host.the_real_match_context_exceeds_4_kb_no"));return
	serial+=1;var key: String="gomoku-"+Crypto.new().generate_random_bytes(12).hex_encode()
	var ledger: Dictionary=scheduler().usage(id);var before:=ledger.duplicate(true);var cap:=reserve_size(id)
	ledger.calls+=1;ledger.reserved+=cap;ledger.last_at=scheduler().now();ledger.times.append(ledger.last_at)
	if not scheduler().preferences.save_accounting(id,ledger):game.world.gomoku.pause(g,LocalText.text("ui.gomoku_match_host.usage_ledger_could_not_be_saved_no_model"));return
	g.ai.reserved_tokens=int(g.ai.get("reserved_tokens",0))+cap;game.world.revision+=1
	pending[id]={"record":g,"key":key,"site":g.site_id,"match_id":g.id,"revision":g.revision,"generation":-1,"deadline":scheduler().now()+float(config().step_timeout),"reserve":cap,"total":0,"input":0,"output":0,"complete":false,"moved":false,"failed":false,"day":scheduler().day_key()}
	var estimate: int=preload("res://scripts/autonomy_estimate.gd").tokens(scheduler().config,data)
	scheduler().records.start(id,key,[{"kind":LocalText.text("ui.gomoku_match_host.match")}],scheduler().now(),estimate)
	var level: String=game.resident_connections.preferences.preference(id).level
	if not game.links[id].send_autonomy(data,level,{"tools":int(config().tools_per_turn),"turn_tokens":cap},key):
		g.ai.reserved_tokens=maxi(0,int(g.ai.get("reserved_tokens",0))-cap);game.world.revision+=1
		scheduler().preferences.save_accounting(id,before);scheduler().records.update(id,key,0,"rejected_before_inference");retire(id);game.world.gomoku.pause(g,LocalText.text("ui.gomoku_match_host.model_send_failed_this_allowance_was_not_charged"));return
	if pending.has(id):pending[id].generation=game.links[id]._generation
func retire(id: String) -> void:
	if not pending.has(id):return
	retired.append(pending[id].key);pending.erase(id)
	if retired.size()>128:retired.pop_front()
func usage(id: String,event: Dictionary,g: Dictionary) -> void:
	var p: Dictionary=pending[id]
	var total: int=int(event.get("total_tokens",-1));var input: int=int(event.get("input_tokens",-1));var output: int=int(event.get("output_tokens",-1))
	if total<int(p.total) or input<int(p.input) or output<int(p.output) or total<input+output:return
	var ledger: Dictionary=scheduler().usage(id);var delta: int=total-int(p.total);var freed: int=mini(int(p.reserve),delta) if p.day==scheduler().day_key() else 0
	ledger.tokens+=delta;ledger.input_tokens+=input-int(p.input);ledger.output_tokens+=output-int(p.output);ledger.reserved=maxi(0,int(ledger.reserved)-freed)
	scheduler().update_turn(ledger,p.key,"gomoku_match",total,input,output,"complete" if event.get("complete",false) else "reported_partial")
	if not scheduler().preferences.save_accounting(id,ledger):game.world.gomoku.pause(g,LocalText.text("ui.gomoku_match_host.usage_ledger_could_not_be_saved_pausing"));return
	g.ai.reserved_tokens=maxi(0,int(g.ai.get("reserved_tokens",0))-mini(int(p.reserve),delta))
	game.world.revision+=1
	p.reserve-=mini(int(p.reserve),delta);p.total=total;p.input=input;p.output=output;p.complete=bool(event.get("complete",false));g.ai.tokens+=delta
	scheduler().records.update(id,p.key,total,"complete" if p.complete else "reported_partial")
	if total>reserve_size(id) or int(g.ai.tokens)+int(g.ai.unknown_tokens)>int(g.ai.token_limit):game.world.gomoku.pause(g,LocalText.text("ui.gomoku_match_host.reported_model_usage_exceeds_the_budget_pausing_immediately"));game.links[id].cancel_turn()
func finish(id: String,g: Dictionary) -> void:
	var p: Dictionary=pending[id];var ledger: Dictionary=scheduler().usage(id)
	g.ai.reserved_tokens=maxi(0,int(g.ai.get("reserved_tokens",0))-int(p.reserve))
	if p.complete and p.day==scheduler().day_key():ledger.reserved=maxi(0,int(ledger.reserved)-int(p.reserve))
	elif not p.complete:
		ledger.unknown_turns+=1;g.ai.unknown_tokens+=int(p.reserve)
		if p.day!=scheduler().day_key():ledger.reserved+=int(p.reserve)
	scheduler().update_turn(ledger,p.key,"gomoku_match",int(p.total),int(p.input),int(p.output),"complete" if p.complete else "unknown")
	if not scheduler().preferences.save_accounting(id,ledger):game.world.gomoku.pause(g,LocalText.text("ui.gomoku_match_host.usage_ledger_could_not_be_saved_pausing"))
	scheduler().records.update(id,p.key,int(p.total),"complete" if p.complete else "unknown")
	game.world.revision+=1
	var failed: bool=not p.moved or p.failed
	retire(id)
	if failed and g.phase=="playing":
		if int(g.ai.retries)<int(config().max_retries):g.ai.retries+=1
		else:game.world.gomoku.pause(g,LocalText.text("ui.gomoku_match_host.one_model_move_failed_and_was_retried_once"))
	elif not failed:g.ai.retries=0
func read_board(id: String,g: Dictionary) -> Dictionary:
	var result: Dictionary=game.world.gomoku.read(g.site_id,id)
	var actions: Dictionary=game.world.read_actions(id)
	actions.actions=actions.actions.filter(func(action):return action.id in ["gomoku_read","gomoku_move"])
	result.actions=actions
	return result
func event(id: String,event: Dictionary,scope: String) -> bool:
	var key: String=str(event.get("turn_key",""))
	if key in retired:
		if event.get("kind") in ["action","observe","read_work","edit_work","question"] and game._valid_link(game.links,id):game.links[id].reply(str(event.get("id","")),{"ok":false,"error":"stale_chess_match_round"})
		return true
	if scope!="direct" or not pending.has(id) or key!=pending[id].key:return false
	var p: Dictionary=pending[id];var g: Dictionary=p.record
	if g.get("id")!=p.match_id:return true
	var kind: String=str(event.get("kind",""))
	if kind=="usage":usage(id,event,g);return true
	if kind=="state":
		game.connection_ui_states[id+":direct"]=str(event.get("state","idle"))
		if event.get("state")=="cancelled" and p.failed and g.phase=="playing":game.connection_ui_states[id+":direct"]="ready"
		if event.get("state") in ["ready","cancelled","error","disconnected"] and event.get("turnComplete",true):finish(id,g)
		return true
	if kind=="assistant":return true # Only the accepted step's speech is game dialogue; never a new round.
	if kind=="error":
		p.failed=true;game.world.gomoku.pause(g,LocalText.text("ui.gomoku_match_host.the_model_connection_returned_an_error_the_board"));game.links[id].cancel_turn();return true
	if kind in ["observe","read_work","edit_work","action","question"]:
		var valid: bool=not external_hold(id) and game.world.gomoku.sessions.get(p.site,{}).get("id")==p.match_id and game.world.director.model_controlled(id) and not game.links[id]._cancelling and game.links[id]._generation==p.generation and g.phase=="playing" and scheduler().now()<=float(p.deadline)
		var result: Dictionary={"ok":false,"error":"chess_round_restricted"}
		if kind=="observe" and valid:result=read_board(id,g)
		elif kind=="action" and valid and not p.failed and not p.moved:
			var args: Dictionary=event.get("command",{})
			if args.get("intent")=="gomoku_read":result=read_board(id,g)
			elif args.get("intent")=="gomoku_move" and args.get("site_id")==g.site_id and args.get("match_id")==g.id and args.get("revision")==p.revision:
				result=game.world.command(id,args)
				if result.get("ok",false):
					p.moved=true;scheduler().note_model_action(id)
					if not str(args.get("speech","")).is_empty():game.view.say(args.speech,"model",id);game._record_chat("direct:"+id,id,args.speech,"message")
				else:p.failed=true
			scheduler().records.action(id,p.key,args,result)
		game.links[id].reply(str(event.get("id","")),result)
		if kind=="question":game.world.gomoku.pause(g,LocalText.text("ui.gomoku_match_host.a_player_asked_a_question_pause_the_match"));game.links[id].cancel_turn()
		elif p.failed:game.links[id].cancel_turn()
		return true
	return true
