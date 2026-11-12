class_name GomokuSystem
extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
const Rules=preload("res://scripts/gomoku_rules.gd")
const ACTIONS: Array=["gomoku_read","gomoku_join","gomoku_move","gomoku_leave","gomoku_resign"]
var _owner: WeakRef
var world: RefCounted:
	get:return _owner.get_ref()
var sessions: Dictionary={}
var memories: Array=[]
var config: Dictionary={}
var match_config: Dictionary={}
var companion: RefCounted
var rng:=RandomNumberGenerator.new()
func _init(source: RefCounted) -> void:
	_owner=weakref(source);rng.randomize()
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/gomoku.json"))
	if not data is Dictionary or data.get("version")!=1 or data.get("board_size")!=15:world.error=LocalText.text("ui.gomoku_system.the_gomoku_settings_are_invalid");return
	for key in ["arrival_timeout","search_ms","candidate_limit","root_limit","reply_limit"]:
		if not Rules.integer(data.get(key),1,300):world.error=LocalText.text("ui.gomoku_system.the_gomoku_settings_are_invalid");return
	if not data.get("think_seconds") is Array or data.think_seconds.size()!=2 or not world.catalog._number(data.think_seconds[0]) or not world.catalog._number(data.think_seconds[1]) or data.think_seconds[0]<.3 or data.think_seconds[1]<data.think_seconds[0] or data.think_seconds[1]>5:world.error=LocalText.text("ui.gomoku_system.the_gomoku_settings_are_invalid");return
	config=data
	companion=preload("res://scripts/gomoku_companion.gd").new(world)
	var limits: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/gomoku-match.json"))
	if not limits is Dictionary or limits.get("version")!=1:world.error=LocalText.text("ui.gomoku_system.the_match_budget_settings_are_invalid");return
	for key in ["max_steps","max_tokens","step_tokens","step_timeout","max_retries","tools_per_turn"]:
		if not Rules.integer(limits.get(key),1,2000000):world.error=LocalText.text("ui.gomoku_system.the_match_budget_settings_are_invalid");return
	if not limits.get("sources") is Dictionary or limits.sources.size()!=3 or not ["local_easy","local_normal","model"].all(func(key):return limits.sources.get(key) is String and limits.sources[key].length()<=20):world.error=LocalText.text("ui.gomoku_system.the_match_source_settings_are_invalid");return
	if limits.max_steps>225 or limits.max_retries!=1 or limits.tools_per_turn>6 or limits.step_timeout>300:world.error=LocalText.text("ui.gomoku_system.the_match_budget_settings_are_invalid");return
	match_config=limits
func table(id: String) -> Dictionary:
	var site: Dictionary=world.leisure.sites.get(id,{})
	return site if not site.is_empty() and world.leisure.art(site).get("recreation",{}).get("game")=="gomoku" else {}
func players(game: Dictionary) -> Array:return [game.black_id,game.white_id]
func active(id: String) -> bool:
	return sessions.values().any(func(game):return game.phase in ["arriving","playing"] and id in players(game))
func ai_active(id: String) -> bool:
	return sessions.values().any(func(g):return g.get("mode")=="ai" and g.phase in ["arriving","playing"] and id in players(g))
func _available(id: String) -> bool:
	if not world.actors.has(id) or not world.residents.supports(world.actors[id],"gomoku_join") or active(id):return false
	if world.loaded(id) or not world.fishing.held(id).is_empty() or world.projects.active(id) or world.farms.active(id) or world.shared_activity.holds(id) or world.activities.members.has(id):return false
	var job: Dictionary=world.work.jobs.get(id,{})
	var routine: RefCounted=world.director.routines.get(id)
	return (routine==null or not routine.held) and (job.is_empty() or job.get("source")=="local_rules") and (not world._routes.has(id) or (routine!=null and routine.owns_route) or (world.activities.following.has(id) and world.hunger.owned_routes.get(id,{}).has("route") and is_same(world.hunger.owned_routes[id].route,world._routes[id])))
func validate_begin(site_id: String,opponent: String,human_black: bool,mode: String,difficulty: String) -> Dictionary:
	var site:=table(site_id)
	if site.is_empty():return world._error("unknown_chess_table")
	if not site.complete:return world.work.fail("unfinished_facility",LocalText.text("ui.gomoku_system.build_the_table_with_real_wood_before_inviting"))
	if mode not in ["local","model"] or difficulty not in ["easy","normal"] or opponent=="human" or not _available("human") or not _available(opponent):return world.work.fail("chess_unavailable",LocalText.text("ui.gomoku_system.stop_work_and_put_your_items_away_before"))
	if mode=="model" and not world.director.model_controlled(opponent):return world.work.fail("model_required",LocalText.text("ui.gomoku_system.this_companion_is_not_model_controlled_choose_a"))
	if sessions.has(site_id) and sessions[site_id].phase not in ["finished","abandoned"]:return world.work.fail("match_exists",LocalText.text("ui.gomoku_system.the_previous_game_is_still_here_continue_or"))
	for slot in range(2):
		if world.work.claims.has(site_id+".slot.%s"%slot):return world._error("full")
	return {"ok":true}
func begin_host(site_id: String,opponent: String,human_black: bool,mode: String,difficulty: String) -> Dictionary:
	var checked:=validate_begin(site_id,opponent,human_black,mode,difficulty)
	if not checked.ok:return checked
	var game: Dictionary={"id":"match-"+Crypto.new().generate_random_bytes(12).hex_encode(),"site_id":site_id,"black_id":"human" if human_black else opponent,"white_id":opponent if human_black else "human","mode":mode,"difficulty":difficulty,"history":[],"revision":1,"phase":"paused","result":"","winner_id":"","resigned_id":"","at":0.0,"reason":LocalText.text("ui.gomoku_system.preparing_to_sit")}
	sessions[site_id]=game
	return _seat(game)
func begin_ai_host(site_id: String,black: String,white: String,sources: Dictionary) -> Dictionary:
	var site:=table(site_id)
	if site.is_empty() or not site.complete or black==white or "human" in [black,white] or sources.size()!=2:return world._error("invalid_ai_match")
	for id in [black,white]:
		if not _available(id) or sources.get(id) not in match_config.sources or (sources[id]=="model" and not world.director.model_controlled(id)):return world._error("chess_unavailable")
	if sessions.has(site_id) and sessions[site_id].phase not in ["finished","abandoned"]:return world._error("match_exists")
	for slot in range(2):
		if world.work.claims.has(site_id+".slot.%s"%slot):return world._error("full")
	var game: Dictionary={"id":"match-"+Crypto.new().generate_random_bytes(12).hex_encode(),"site_id":site_id,"black_id":black,"white_id":white,"mode":"ai","difficulty":"normal","history":[],"revision":1,"phase":"paused","result":"","winner_id":"","resigned_id":"","at":0.0,"reason":LocalText.text("ui.gomoku_system.waiting_for_seating_confirmation"),"ai":{"sources":sources.duplicate(),"step_limit":int(match_config.max_steps),"token_limit":int(match_config.max_tokens),"tokens":0,"unknown_tokens":0,"retries":0,"reserved_tokens":0}}
	sessions[site_id]=game;companion.observe(site_id)
	return _seat(game)
func resume_ai_host(site_id: String) -> Dictionary:
	var game: Dictionary=sessions.get(site_id,{})
	if game.get("mode")!="ai" or game.phase!="paused":return world._error("not_paused")
	game.ai.step_limit=mini(225,game.history.size()+int(match_config.max_steps))
	game.ai.token_limit=int(game.ai.tokens)+int(game.ai.unknown_tokens)+int(match_config.max_tokens);game.ai.retries=0
	return resume_host(site_id)
func abandon_host(site_id: String) -> Dictionary:
	var game: Dictionary=sessions.get(site_id,{})
	if game.get("mode")!="ai" or game.phase in ["finished","abandoned"]:return world._error("not_ai_match")
	pause(game,LocalText.text("ui.gomoku_system.you_ended_spectating_both_players_put_the_pieces"))
	game.phase="abandoned";game.reason=LocalText.text("ui.gomoku_system.ended_without_a_winner_no_completion_memory_is");game.revision+=1;world.revision+=1
	return {"ok":true}
func _seat(game: Dictionary) -> Dictionary:
	for who in players(game):
		if source_for(game,who)=="model" and not world.director.model_controlled(who):return world._error("model_required")
	var opponent: String=game.white_id if game.black_id=="human" else game.black_id
	if game.mode=="model" and not world.director.model_controlled(opponent):return world.work.fail("model_required",LocalText.text("ui.gomoku_system.an_original_player_switched_to_local_control_restore"))
	for id in players(game):
		if not _available(id):return world.work.fail("chess_unavailable",LocalText.text("ui.gomoku_system.a_player_is_busy_the_board_is_kept"))
	for slot in range(2):
		if world.work.claims.has(game.site_id+".slot.%s"%slot):return world._error("full")
	game.phase="arriving";game.reason=LocalText.text("ui.gomoku_system.walking_to_the_table_together_play_begins_once");game.revision+=1;game["jobs"]={};game["timer"]=0.0;game["think"]=0.0
	for index in range(2):
		var id: String=players(game)[index]
		world.activities.pause_follow(id)
		world.director.command_received(id,"gomoku_join")
		world.work.serial+=1
		var job_id: String="job-%s"%world.work.serial
		world.work.jobs[id]={"id":job_id,"intent":"play_gomoku","phase":"gomoku_work","target_id":game.site_id,"match_id":game.id,"slot":index,"step":"entry"}
		world.work.claims[game.site_id+".slot.%s"%index]=id;game.jobs[id]=job_id
	world.revision+=1
	return {"ok":true,"status":"accepted","match_id":game.id,"message":game.reason}
func resume_host(site_id: String) -> Dictionary:
	if not sessions.has(site_id) or sessions[site_id].phase!="paused" or table(site_id).is_empty() or not table(site_id).complete:return world._error("not_paused")
	return _seat(sessions[site_id])
func pause_actor(id: String,reason: String=LocalText.text("ui.gomoku_system.paused_first_the_board_stays_here")) -> void:
	for game in sessions.values():
		if id in players(game) and game.phase in ["arriving","playing"]:pause(game,reason)
func pause(game: Dictionary,reason: String) -> void:
	if game.phase not in ["arriving","playing"]:return
	game.phase="paused";game.reason=reason;game.revision+=1;game["think"]=0.0;_release(game);world.revision+=1
func _release(game: Dictionary) -> void:
	for id in players(game):
		var owned: String=str(game.get("jobs",{}).get(id,""))
		if not owned.is_empty() and world.work.jobs.get(id,{}).get("id")==owned:
			# A paused shared game releases exact owned jobs with an honest receipt;
			# do not silently erase the other participant's accepted real task.
			if game.phase=="paused" and not world.work.events.any(func(event):return event.get("job_id")==owned):
				world.work.record_event(id,world.work.jobs[id],"blocked",str(game.get("reason",LocalText.text("ui.gomoku_system.game_paused_the_board_is_kept"))))
			world.work.stop(id,false)
	game["jobs"]={}
func tick(id: String,job: Dictionary,_delta: float) -> void:
	var game: Dictionary=sessions.get(job.target_id,{})
	if game.is_empty() or game.id!=job.match_id or game.phase not in ["arriving","playing"]:world.work.stop(id,false);return
	var site:=table(game.site_id)
	if site.is_empty():pause(game,LocalText.text("ui.gomoku_system.the_table_settings_are_unavailable_the_board_is"));return
	var layout: Dictionary=world.leisure.art(site).recreation
	var entry: Vector2=world.point(site)+Vector2(layout.entry[0],layout.entry[1])
	if job.step=="entry":
		if not world.interior._arrive(id,"home",entry):return
		job.step="seat"
	var p: Array=layout.slots[int(job.slot)]
	if not world.interior._arrive(id,"home",world.point(site)+Vector2(p[0],p[1])):return
	job.step="using";world.actors[id].activity="seated";world.work.face(world.actors[id],site)
func source_for(game: Dictionary,id: String) -> String:
	return "human" if id=="human" else game.get("ai",{}).get("sources",{}).get(id,game.mode)
func _say(game: Dictionary,context: String) -> void:
	var old: Array=companion.config.get("legacy_lines",{}).get(context,[])
	if not old.is_empty():
		var text: String=old[rng.randi_range(0,old.size()-1)]
		# Legacy host/engine calls with no opened board retain their original speech cadence.
		if not companion.observed_sites.has(game.site_id):
			world.director.say_local(companion.opponent(game),text,"gomoku_"+context,18,4);return
	companion.event(game,context)
func _turn(game: Dictionary) -> String:return game.black_id if game.history.size()%2==0 else game.white_id
func advance(delta: float) -> void:
	for game in sessions.values():
		if game.phase not in ["arriving","playing"]:continue
		var valid:=true
		for id in players(game):
			if world.work.jobs.get(id,{}).get("id")!=game.jobs.get(id):valid=false
		if not valid:pause(game,LocalText.text("ui.gomoku_system.someone_left_their_seat_you_can_continue_after"));continue
		if game.phase=="arriving":
			game.timer+=delta
			if game.timer>float(config.arrival_timeout):pause(game,LocalText.text("ui.gomoku_system.the_players_cannot_arrive_together_right_now_the"));continue
			if players(game).all(func(id):return world.work.jobs[id].get("step")=="using"):
				game.phase="playing";game.reason="";game.revision+=1;game.think=rng.randf_range(config.think_seconds[0],config.think_seconds[1]);_say(game,"start");world.revision+=1
			continue
		companion.advance(game)
		var id:=_turn(game)
		if game.mode=="ai" and game.history.size()>=int(game.ai.step_limit):pause(game,LocalText.text("ui.gomoku_system.this_confirmed_move_limit_is_reached_confirm_a"));continue
		if id=="human" or source_for(game,id)=="model":continue
		game.think-=delta
		if game.think>0:continue
		var state:=Rules.replay(game.history)
		var p:=Rules.choose(state.board,1+game.history.size()%2,("easy" if source_for(game,id)=="local_easy" else "normal") if game.mode=="ai" else game.difficulty,config,rng)
		if p.x>=0:_place(id,game,p)
func _place(id: String,game: Dictionary,p: Vector2i) -> Dictionary:
	if game.phase!="playing" or _turn(game)!=id:return world._error("not_your_turn")
	if not Rules.inside(p):return world._error("invalid_intersection")
	var state:=Rules.replay(game.history)
	if Rules.cell(state.board,p)!=0:return world._error("occupied_intersection")
	game.history.append([p.x,p.y]);game.revision+=1;game.think=rng.randf_range(config.think_seconds[0],config.think_seconds[1]);world.revision+=1
	var site:=table(game.site_id)
	world.work.visual_event("gomoku_stone",site,id)
	state=Rules.replay(game.history)
	if state.winner!=0 or state.draw:
		_finish(game,"five" if state.winner!=0 else "draw",game.black_id if state.winner==1 else game.white_id if state.winner==2 else "")
	else:
		if game.mode=="ai":companion.event(game,"move",id)
		elif id!="human":_say(game,"move")
		elif companion.observed_sites.has(game.site_id):companion.event(game,"other_move",id)
		companion.state(game).poses[id]={"state":"move","until":world.director.time+float(companion.config.pose_seconds)}
	return {"ok":true,"status":"completed","match_id":game.id,"revision":game.revision,"phase":game.phase}
func _finish(game: Dictionary,result: String,winner: String,resigned: String="") -> void:
	game.phase="finished";game.result=result;game.winner_id=winner;game.resigned_id=resigned;game.at=Time.get_unix_time_from_system();game.reason=LocalText.text("ui.gomoku_system.this_game_is_over_you_can_play_another");game.revision+=1;_release(game)
	var record: Dictionary=_saved_game(game);memories.append(record)
	if memories.size()>32:memories.pop_front()
	world.memories.sync();world.revision+=1
	if game.mode=="ai":companion.event(game,"draw" if result=="draw" else "win",winner)
	else:_say(game,"draw" if result=="draw" else "lose" if winner=="human" else "win")
func command(id: String,args: Dictionary) -> Dictionary:
	var action: String=str(args.get("intent",""))
	var keys: Array=["intent","site_id"] if action=="gomoku_read" else ["intent","site_id","match_id","revision","x","y","speech"] if action=="gomoku_move" else ["intent","site_id","match_id","revision"]
	if args.keys().any(func(key):return key not in keys) or not args.get("site_id") is String or table(args.site_id).is_empty():return world._error("invalid_chess_command")
	if action=="gomoku_read":return read(args.site_id,id)
	var game: Dictionary=sessions.get(args.site_id,{})
	if game.is_empty() or id not in players(game):return world._error("not_a_player")
	if args.get("match_id")!=game.id or not Rules.integer(args.get("revision"),1,1000000) or args.revision!=game.revision:return world._error("stale_chess_turn")
	if game.phase=="abandoned":return world._error("match_finished")
	if action=="gomoku_join":return {"ok":true,"status":"already_joined"} if game.phase in ["playing","arriving"] else world._error("host_resume_required")
	if action=="gomoku_leave":pause(game,LocalText.text("ui.gomoku_system.someone_left_their_seat_the_board_is_kept"));return {"ok":true,"status":"paused"}
	if action=="gomoku_resign":
		if game.phase=="finished":return world._error("match_finished")
		_finish(game,"resign",game.white_id if id==game.black_id else game.black_id,id);return {"ok":true,"status":"completed"}
	if action!="gomoku_move" or not Rules.integer(args.get("x"),0,14) or not Rules.integer(args.get("y"),0,14):return world._error("invalid_intersection")
	if id!="human" and source_for(game,id)!="model":return world._error("local_chess_control")
	if args.has("speech") and (not args.speech is String or args.speech.length()>30 or args.speech.contains("\n") or args.speech.contains("\r")):return world._error("invalid_chess_speech")
	var result:=_place(id,game,Vector2i(args.x,args.y))
	if result.ok and id!="human" and source_for(game,id)=="model" and not str(args.get("speech","")).is_empty():companion.model_speech(game,id,args.speech)
	return result
func read(site_id: String,id: String) -> Dictionary:
	var game: Dictionary=sessions.get(site_id,{})
	var result: Dictionary={"ok":true,"site_id":site_id,"self_actor_id":id,"rules":{"size":15,"black_first":true,"overline_wins":true,"forbidden_moves":false},"match":{}}
	if not game.is_empty():
		result.match=_saved_game(game);var state:=Rules.replay(game.history)
		result.match["board"]=state.board;result.match["winning_line"]=state.line;result.match["turn_actor_id"]=_turn(game) if game.phase not in ["finished","abandoned"] else ""
	return result
func snapshot(id: String) -> Dictionary:
	var tables: Array=[];var games: Array=[]
	for site in world.leisure.sites.values():
		if table(site.id).is_empty():continue
		tables.append({"site_id":site.id,"name":site.name,"position":site.position.duplicate(),"complete":site.complete,"phase":sessions.get(site.id,{}).get("phase","empty")})
		if sessions.has(site.id) and id in players(sessions[site.id]):games.append(read(site.id,id).match)
	return {"tables":tables,"own_matches":games,"default_brain":"local_rules","model_auto_wakeup":false}
func _saved_game(game: Dictionary) -> Dictionary:
	var result:=game.duplicate(true)
	for key in ["jobs","timer","think"]:result.erase(key)
	return result
func saved() -> Dictionary:
	var games: Dictionary={}
	for id in sessions:games[id]=_saved_game(sessions[id])
	return {"version":1,"sessions":games,"memories":memories.duplicate(true)}
func restore(data: Dictionary) -> void:
	companion.clear()
	sessions=data.get("sessions",{}).duplicate(true);memories=data.get("memories",[]).duplicate(true)
	for game in sessions.values()+memories:
		game.history=game.history.map(func(p):return [int(p[0]),int(p[1])]);game.revision=int(game.revision)
	for game in sessions.values():
		if game.get("mode")=="ai":
			game.ai.unknown_tokens+=int(game.ai.get("reserved_tokens",0));game.ai.reserved_tokens=0
		if game.phase not in ["finished","abandoned"]:game.phase="paused";game.reason=LocalText.text("ui.gomoku_system.the_earlier_board_remains_continue_explicitly_before_taking");game.revision+=1
func valid_game(game: Variant,actors: Dictionary,sites: Dictionary) -> bool:
	if not game is Dictionary or game.size()!=(15 if game.has("ai") else 14) or not game.get("id") is String or game.id.length()!=30 or not game.id.begins_with("match-") or not game.id.substr(6).is_valid_hex_number(false):return false
	if game.keys().any(func(key):return key not in ["id","site_id","black_id","white_id","mode","difficulty","history","revision","phase","result","winner_id","resigned_id","at","reason","ai"]):return false
	if not sites.has(game.get("site_id","")) or not actors.has(game.get("black_id","")) or not actors.has(game.get("white_id","")) or game.black_id==game.white_id or (game.get("mode")!="ai" and "human" not in players(game)):return false
	if not sites[game.site_id].get("complete",false) or sites[game.site_id].get("artwork",{}).get("recreation",{}).get("game")!="gomoku":return false
	if game.get("mode") not in ["local","model","ai"] or game.get("difficulty") not in ["easy","normal"] or game.get("phase") not in ["arriving","playing","paused","finished","abandoned"] or not Rules.integer(game.get("revision"),1,1000000):return false
	if not game.get("reason") is String or game.reason.length()>200 or not world.catalog._number(game.get("at")) or game.at<0 or game.at>253402300799:return false
	if game.mode=="ai":
		if "human" in players(game) or not game.get("ai") is Dictionary or game.ai.size() not in [6,7] or not game.ai.get("sources") is Dictionary or game.ai.sources.size()!=2:return false
		for who in players(game):
			if game.ai.sources.get(who) not in match_config.sources:return false
		for key in ["step_limit","token_limit","tokens","unknown_tokens","retries"]:
			if not Rules.integer(game.ai.get(key),0,2000000000):return false
		if game.ai.has("reserved_tokens") and not Rules.integer(game.ai.reserved_tokens,0,2000000000):return false
		if game.ai.keys().any(func(key):return key not in ["sources","step_limit","token_limit","tokens","unknown_tokens","retries","reserved_tokens"]):return false
		if int(game.ai.tokens)+int(game.ai.unknown_tokens)+int(game.ai.get("reserved_tokens",0))>2000000000:return false
		if game.ai.step_limit<1 or game.ai.step_limit>225 or game.ai.token_limit<1 or game.ai.retries>1:return false
	elif game.has("ai") or game.phase=="abandoned":return false
	var state:=Rules.replay(game.get("history"))
	if state.is_empty():return false
	if game.phase!="finished":return game.result=="" and game.winner_id=="" and game.resigned_id=="" and game.at==0 and state.winner==0 and not state.draw
	if game.at<=0:return false
	if game.result=="draw":return state.draw and game.winner_id=="" and game.resigned_id==""
	if game.result=="five":return state.winner!=0 and game.winner_id==(game.black_id if state.winner==1 else game.white_id) and game.resigned_id==""
	return game.result=="resign" and state.winner==0 and not state.draw and game.resigned_id in players(game) and game.winner_id in players(game) and game.winner_id!=game.resigned_id
func valid_saved(data: Variant,actors: Dictionary,sites: Dictionary) -> bool:
	if not data is Dictionary or data.get("version")!=1 or not data.get("sessions") is Dictionary or data.sessions.size()>64 or not data.get("memories") is Array or data.memories.size()>32:return false
	var seen: Dictionary={};var active_players: Dictionary={}
	for key in data.sessions:
		var game: Variant=data.sessions[key]
		if not valid_game(game,actors,sites) or key!=game.site_id or seen.has(game.id):return false
		seen[game.id]=true
		if game.phase in ["arriving","playing"]:
			for id in players(game):
				if active_players.has(id):return false
				active_players[id]=true
	seen.clear()
	for game in data.memories:
		if not valid_game(game,actors,sites) or game.phase!="finished" or seen.has(game.id):return false
		seen[game.id]=true
	return true
