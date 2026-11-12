extends RefCounted
signal completed(result: Dictionary)
signal panel_reaction(context: String)
const Rules=preload("res://scripts/jieqi_rules.gd")
const Player=preload("res://scripts/jieqi_player.gd")
const Text=preload("res://scripts/localization.gd")
var _owner: WeakRef
var world: RefCounted:
	get:return _owner.get_ref()
var game: Dictionary={}
var opponent:=""
var elapsed:=0.0
var reactions: Dictionary={}
var river_seen:=false
var last_spoken_hand:=-1
var last_line:=""
var last_line_key:=""
var phase:="paused"
var owned_jobs: Dictionary={}
var match_id:=""
var terminal_reason:=""
var pending_river_hand:=-1
var reaction_retry:=0.0
var pending_reaction:=""
var resuming:=false
var panel_speech:=false
var site_id:="play.gomoku"
var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/jieqi.json"))
func _init(source: RefCounted) -> void:_owner=weakref(source)
func start(id: String,seed_value: int=-1,mode: String="standard",requested_site: String="") -> Dictionary:
	if mode not in ["standard","chaos"]:return {"ok":false,"error":"invalid_mode"}
	var selected_site:=requested_site if not requested_site.is_empty() else site_id
	if id=="human" or not world.actors.has(id):return {"ok":false,"error":"invalid_opponent"}
	if world.hunger.rank(id)>=3:return {"ok":false,"error":"hungry"}
	var site: Dictionary=world.gomoku.table(selected_site)
	if site.is_empty() or not site.complete:return {"ok":false,"error":"unfinished_facility"}
	if world.actors.human.region_id!=site.region_id:return {"ok":false,"error":"different_region"}
	if not resuming and not game.is_empty() and phase not in ["finished"]:return {"ok":false,"error":"match_exists"}
	if world.gomoku.sessions.has(selected_site) and world.gomoku.sessions[selected_site].phase not in ["finished","abandoned"]:return {"ok":false,"error":"match_exists"}
	if not world.gomoku._available("human") or not world.gomoku._available(id):return {"ok":false,"error":"busy"}
	for slot in range(2):
		if world.work.claims.has(selected_site+".slot.%s"%slot):return {"ok":false,"error":"full"}
	site_id=selected_site
	pending_river_hand=-1;pending_reaction="";reaction_retry=0.0
	opponent=id;match_id="jieqi-"+str(Time.get_ticks_usec());phase="arriving"
	for slot in range(2):
		var who: String="human" if slot==0 else id
		world.director.command_received(who,"gomoku_join")
		world.work.serial+=1
		var job: Dictionary={"id":"job-%s"%world.work.serial,"intent":"jieqi","phase":"jieqi","target_id":site_id,"match_id":match_id,"slot":slot}
		world.work.jobs[who]=job;owned_jobs[who]=job.id;world.work.claims[site_id+".slot.%s"%slot]=who
	game=Rules.initial(seed_value if seed_value>=0 else randi(),mode);reactions.clear();river_seen=false;last_spoken_hand=-1;terminal_reason="";elapsed=0;world.revision+=1
	return {"ok":true}
func trait_key() -> String:
	var tag: String=world.personality.tag(opponent)
	var mapping: Dictionary={"curious":"playful","lively":"diligent"} if world.intelligence.compatibility else {"lively":"playful","laborious":"diligent"}
	return mapping.get(tag,tag)
func profile() -> Dictionary:
	var profiles: Dictionary=config.chaos_profiles if game.get("mode","standard")=="chaos" else config.profiles
	return profiles.get(trait_key(),profiles.gentle)
func play(a: int,b: int) -> bool:
	if game.is_empty() or game.turn!=1 or phase!="playing":return false
	return commit(a,b)
func commit(a: int,b: int) -> bool:
	var before:=game;var next:=Rules.move(game,a,b)
	if next.is_empty():return false
	game=next;elapsed=0;world.revision+=1
	if game.winner!=0 or game.draw:terminal_reason=game.get("terminal_reason","rules");finish()
	var kind: String=game.board[b].kind
	var context:="move"
	if game.get("terminal_reason","")=="chaos_selfcheck":context="chaos_selfcheck"
	elif game.winner!=0:context="win" if game.winner==2 else "lose"
	elif game.draw:context="draw"
	elif game.get("mode","standard")=="chaos" and before.board[b]!=null and before.board[b].hidden and before.board[b].get("true_side",before.board[b].side)==before.turn:context="chaos_own_capture"
	elif game.get("mode","standard")=="chaos" and before.board[a].hidden and game.board[b].side!=before.turn:context="chaos_opposite"
	elif not river_seen and kind in ["A","E"] and ((a/9<=4)!=(b/9<=4)):context="river";river_seen=true
	elif before.board[a].hidden and kind in ["R","H","C"]:context="big_self" if before.turn==2 else "big_you"
	elif before.board[b]!=null and before.board[b].hidden and before.board[b].kind in ["R","H","C"]:context="capture_hidden"
	elif before.board[b]!=null and before.board[b].kind in ["R","H","C"]:context="capture_big"
	elif before.board[b]!=null and kind=="S":context="soldier"
	elif Rules.checked(game.board,game.turn):context="check_self" if game.turn==2 else "check_you"
	react(context)
	if not panel_speech and context in ["river","chaos_opposite","chaos_own_capture","chaos_selfcheck"] and last_spoken_hand!=game.history.size() and int(reactions.get(context,0))<2:
		pending_river_hand=game.history.size();pending_reaction=context;reaction_retry=0.0
	return true
func advance(delta: float) -> void:
	if panel_speech:pending_river_hand=-1;pending_reaction=""
	if pending_river_hand>=0:
		if game.is_empty() or game.history.size()!=pending_river_hand or phase!="playing":pending_river_hand=-1;pending_reaction=""
		else:
			reaction_retry-=delta
			if reaction_retry<=0:
				react(pending_reaction);reaction_retry=1.0
				if last_spoken_hand==game.history.size():pending_river_hand=-1;pending_reaction=""
	if phase in ["arriving","playing"]:
		for who in ["human",opponent]:
			if world.work.jobs.get(who,{}).get("id","")!=owned_jobs.get(who,"") or (who!="human" and world.hunger.rank(who)>=3):
				pause();return
	if phase=="arriving":
		var site: Dictionary=world.gomoku.table(site_id)
		if site.is_empty():pause();return
		var layout: Dictionary=world.leisure.art(site).recreation
		var arrived:=true
		for slot in range(2):
			var who: String="human" if slot==0 else opponent
			var offset: Array=layout.slots[slot]
			if not world.interior._arrive(who,site.region_id,world.point(site)+Vector2(offset[0],offset[1])):arrived=false
			else:world.actors[who].activity="seated";world.work.face(world.actors[who],site)
		if arrived:phase="playing";react("start")
		return
	if phase!="playing":return
	if game.is_empty() or game.turn!=2 or game.winner!=0 or game.draw:return
	elapsed+=delta
	if elapsed<float(profile().delay):return
	var choice:=Player.choose(Rules.public_state(game),profile(),int(game.seed)+game.history.size()*7919)
	if not choice.is_empty():commit(choice[0],choice[1])
func react(context: String) -> void:
	if panel_speech:
		panel_reaction.emit(context)
		return
	if context=="move" or int(reactions.get(context,0))>=2 or last_spoken_hand==game.history.size():return
	var tag: String=trait_key()
	if tag not in config.profiles:tag="gentle"
	var line:=Text.text("jieqi.line."+tag+"."+context)
	if world.director.say_local(opponent,line,"jieqi_"+context,float(world.gomoku.companion.config.personal_gap),float(world.gomoku.companion.config.village_gap),"human"):
		reactions[context]=int(reactions.get(context,0))+1;last_line=line;last_line_key="jieqi.line."+tag+"."+context;last_spoken_hand=game.history.size()
func resign() -> void:
	if game.is_empty() or game.winner!=0 or game.draw:return
	game.winner=2;terminal_reason="resign";react("win");finish();world.revision+=1
func offer_draw() -> bool:
	if game.is_empty() or game.winner!=0 or game.draw:return false
	if (int(game.seed)+game.history.size())%({"gentle":2,"playful":4,"diligent":3,"quiet":3}.get(trait_key(),3))==0:game.draw=true;terminal_reason="agreement";react("draw");finish();world.revision+=1;return true
	return false
func saved() -> Dictionary:
	if game.is_empty():return {}
	return {"id":match_id,"opponent":opponent,"seed":game.seed,"mode":game.get("mode","standard"),"rules_version":2 if not game.get("legacy_chaos",false) else 1,"site_id":site_id,"history":game.history.duplicate(true),"winner":game.winner,"draw":game.draw,"reactions":reactions.duplicate(),"river_seen":river_seen,"last_spoken_hand":last_spoken_hand,"terminal_reason":terminal_reason}
func valid_saved(value: Variant,saved_actors:Dictionary={}) -> bool:
	if not value is Dictionary:return false
	if value.is_empty():return true
	if not (world.actors if saved_actors.is_empty() else saved_actors).has(value.get("opponent","")) or value.opponent=="human":return false
	if value.keys().any(func(k):return k not in ["id","opponent","seed","mode","rules_version","site_id","history","winner","draw","reactions","river_seen","last_spoken_hand","terminal_reason"]):return false
	if not Rules.integer(value.get("rules_version",1),1,2):return false
	if value.get("mode","standard") not in ["standard","chaos"]:return false
	if not value.get("site_id","play.gomoku") is String or str(value.get("site_id","play.gomoku")).length()>128:return false
	var seed_value: Variant=value.get("seed")
	if not (seed_value is int or seed_value is float) or not is_finite(seed_value) or seed_value!=floor(seed_value) or seed_value<0 or seed_value>4294967295:return false
	if not Rules.integer(value.get("winner"),0,2) or not value.get("draw") is bool:return false
	if value.get("id","") is not String or str(value.get("id","")).length()>96:return false
	if not value.get("reactions",{}) is Dictionary or value.get("reactions",{}).size()>16:return false
	for k in value.get("reactions",{}):
		if k not in ["start","win","lose","draw","big_self","big_you","river","capture_hidden","capture_big","soldier","check_self","check_you","chaos_opposite","chaos_own_capture","chaos_selfcheck"]:return false
		if not Rules.integer(value.reactions[k],0,2):return false
	if not value.get("river_seen",false) is bool:return false
	if not Rules.integer(value.get("last_spoken_hand",-1),-1,4096):return false
	var replayed:=Rules.replay(int(seed_value),value.get("history"),value.get("mode","standard"),value.get("rules_version",1)==1)
	if replayed.is_empty():return false
	var reason: String=str(value.get("terminal_reason",""))
	if reason not in ["","rules","resign","agreement","chaos_selfcheck"]:return false
	if reason=="chaos_selfcheck" and (replayed.get("terminal_reason","")!=reason or value.winner!=replayed.winner or value.draw):return false
	if reason=="rules" and (value.winner!=replayed.winner or value.draw!=replayed.draw):return false
	if reason=="resign" and (value.winner!=2 or value.draw or replayed.winner!=0 or replayed.draw):return false
	if reason=="agreement" and (not value.draw or value.winner!=0 or replayed.winner!=0 or replayed.draw):return false
	if reason=="" and (value.winner!=0 or value.draw):return false
	# A non-rule terminal result can only be resignation or an agreed draw.
	if replayed.winner!=0 and replayed.winner!=value.winner:return false
	if replayed.draw and not value.draw:return false
	if value.winner!=0 and value.draw:return false
	return true
func restore(value: Dictionary) -> void:
	game={};opponent="";pending_river_hand=-1;reaction_retry=0.0
	if value.is_empty() or not valid_saved(value):return
	terminal_reason=str(value.get("terminal_reason",""))
	match_id=str(value.get("id","jieqi-"+str(value.seed)));phase="paused";reactions=value.get("reactions",{}).duplicate();river_seen=value.get("river_seen",false);last_spoken_hand=int(value.get("last_spoken_hand",-1))
	site_id=value.get("site_id","play.gomoku");opponent=value.opponent
	game=Rules.initial(int(value.seed),value.get("mode","standard"))
	for entry in value.history:
		game=Rules.move(game,int(entry[0]),int(entry[1]))
		if game.get("terminal_reason","")=="chaos_selfcheck":terminal_reason="chaos_selfcheck";break
	if terminal_reason!="chaos_selfcheck":game.winner=value.winner;game.draw=value.draw
	if game.winner!=0 or game.draw:phase="finished"

func pause() -> void:
	phase="paused";pending_river_hand=-1
	for who in owned_jobs:
		if world.work.jobs.get(who,{}).get("id")==owned_jobs[who]:world.work.stop(who,false)
	owned_jobs.clear()
func finish() -> void:
	pause();phase="finished"
	completed.emit({"id":match_id,"opponent_id":opponent,"winner":"human" if game.winner==1 else "opponent" if game.winner==2 else "draw","seed":game.seed,"moves":game.history.size()})
func resume() -> Dictionary:
	if game.is_empty() or phase!="paused" or game.winner!=0 or game.draw:return {"ok":false}
	var retained: Dictionary=game.duplicate(true)
	var old_id:=match_id;var old_reactions:=reactions.duplicate();var old_river:=river_seen;var old_hand:=last_spoken_hand
	resuming=true
	var result:=start(opponent,int(game.seed),game.get("mode","standard"),site_id)
	resuming=false
	if result.ok:game=retained;match_id=old_id;reactions=old_reactions;river_seen=old_river;last_spoken_hand=old_hand
	return result

func display_line()->String:
	return Text.text(last_line_key) if not last_line_key.is_empty() else ""
