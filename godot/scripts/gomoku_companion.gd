extends RefCounted
var panel_tables:Dictionary={}
const LocalText=preload("res://scripts/localization.gd")
## Presentation facts derived from the single GomokuRules evaluator, never a second brain.
const Rules=preload("res://scripts/gomoku_rules.gd")
var _owner: WeakRef
var world: RefCounted:
	get:return _owner.get_ref()
var config: Dictionary={}
var observed_sites: Dictionary={}
var states: Dictionary={}
var rng:=RandomNumberGenerator.new()
func _init(w: RefCounted) -> void:
	_owner=weakref(w);rng.randomize()
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/gomoku-lines.json"))
	if not valid(data):world.error=LocalText.text("system.gomoku_companion.the_match_presentation_settings_are_invalid");return
	config=data
func valid(data: Variant) -> bool:
	if not data is Dictionary or data.get("version")!=1 or not data.get("traits") is Dictionary or not data.get("frames") is Dictionary or not data.get("presets") is Array or data.presets.size()!=3:return false
	for key in ["personal_gap","village_gap","bubble_seconds","pose_seconds","long_think","player_wait","advantage_ratio"]:
		if not world.catalog._number(data.get(key)) or data[key]<=0 or data[key]>3600:return false
	if data.traits.size()<4 or data.traits.size()>32 or not data.traits.has("gentle") or not data.presets.all(func(text):return text is String and not text.is_empty() and text.length()<=16):return false
	for pose_name in ["think","move","other_move","ahead","behind","win","lose","draw"]:
		if not data.frames.get(pose_name) is Array or data.frames[pose_name].is_empty() or data.frames[pose_name].size()>8 or not data.frames[pose_name].all(func(key):return key is String and not key.is_empty() and key.length()<=64):return false
	for profile in data.traits.values():
		if not profile is Dictionary or not profile.get("close_prefix") is String or profile.close_prefix.length()>20:return false
		for context in ["start","other_move","move","open_three","four","blocked","ahead","behind","win","lose","draw","long_think","player_wait","reply_praise","reply_think","reply_tease"]:
			if not profile.get("lines",{}).get(context) is Array or profile.lines[context].size()<4 or not profile.lines[context].all(func(t):return t is String and t.length()<=60):return false
	return true
func observe(site: String) -> void:observed_sites[site]=true
func state(game: Dictionary) -> Dictionary:
	if not states.has(game.id) and states.size()>=64:states.erase(states.keys()[0])
	if not states.has(game.id):states[game.id]={"hand":-1,"used":[],"bubbles":{},"poses":{},"changed":world.director.time,"facts":{},"revision":-1,"recent_speech":[]}
	return states[game.id]
func pool(id: String,context: String,human_listener: bool=true) -> Array:
	var tag: String=world.personality.tag(id);var entry: Dictionary=config.traits.get(tag,config.traits.gentle)
	var prefix: String=str(entry.close_prefix) if human_listener and world.relationships.index(id)>=2 else ""
	if not world.intelligence.compatibility:
		var authored:Array=world.intelligence.speech_pool(id,"gomoku_"+context)
		if not authored.is_empty():return authored.map(func(text):return prefix+str(text))
	return entry.lines.get(context,[]).map(func(text):return prefix+str(text))
func permitted(id: String,game: Dictionary) -> bool:
	if bool(panel_tables.get(str(game.get("site_id","")),false)):return false
	if id=="human" or id not in world.gomoku.players(game):return false
	var r: RefCounted=world.director.routines.get(id)
	return r!=null and r.enabled and r.chatter and not r.held and not world.activities.blocked(id) and not world.shared_activity.holds(id) and world.fishing.life.time>=float(world.fishing.life.quiet_until.get(id,0)) and game.phase in ["playing","finished"]
func say(id: String,game: Dictionary,context: String) -> bool:
	if not permitted(id,game) or world.gomoku.source_for(game,id)=="model":return false
	var s:=state(game)
	if s.hand==game.history.size():return false
	var lines:=pool(id,context,game.get("mode")!="ai").filter(func(text):return text not in s.used)
	lines=world.personality.selection(id,lines)
	if lines.is_empty():return false
	var text: String=lines[rng.randi_range(0,lines.size()-1)]
	var listener: String=(game.white_id if id==game.black_id else game.black_id) if game.get("mode")=="ai" else "human"
	if not world.director.say_local(id,text,"gomoku_"+context,float(config.personal_gap),float(config.village_gap),listener):return false
	remember_speech(game,id,text,"local_rules")
	s.hand=game.history.size();s.used.append(text);s.bubbles[id]={"text":text,"source":"local_rules","until":world.director.time+float(config.bubble_seconds)}
	return true
func facts(game: Dictionary) -> Dictionary:
	var s:=state(game)
	if s.revision==game.revision:return s.facts
	var result: Dictionary={"open_three":false,"four":false,"blocked":false,"ahead_id":""}
	var replay:=Rules.replay(game.history)
	if not game.history.is_empty():
		var last: Array=game.history[-1];var p:=Vector2i(last[0],last[1]);var color: int=1+(game.history.size()-1)%2
		var patterns:=Rules.patterns(replay.board,p,color)
		result.open_three=patterns.any(func(v):return v.count==3 and v.open==2)
		result.four=patterns.any(func(v):return v.count==4 and v.open>=1)
		var before:=Rules.replay(game.history.slice(0,-1))
		result.blocked=Rules.value(before.board,p,3-color)>=6000
	var black:=Rules.ranked(replay.board,1);var white:=Rules.ranked(replay.board,2)
	if not black.is_empty() and not white.is_empty():
		var a: float=black[0].attack;var b: float=white[0].attack
		if maxf(a,b)>=2200 and maxf(a,b)>maxf(1,minf(a,b))*float(config.advantage_ratio):result.ahead_id=game.black_id if a>b else game.white_id
	s.revision=game.revision;s.facts=result
	return result
func context(game: Dictionary,id: String,base: String) -> String:
	var f:=facts(game)
	if f.four:return "four"
	if f.open_three:return "open_three"
	if f.blocked:return "blocked"
	if not f.ahead_id.is_empty():return "ahead" if f.ahead_id==id else "behind"
	return base
func opponent(game: Dictionary) -> String:return game.white_id if game.black_id=="human" else game.black_id
func event(game: Dictionary,base: String,mover: String="") -> void:
	var s:=state(game);s.changed=world.director.time
	if not mover.is_empty():
		s.poses[mover]={"state":"move","until":world.director.time+float(config.pose_seconds)}
		for id in world.gomoku.players(game):
			if id!=mover:s.poses[id]={"state":"other_move","until":world.director.time+float(config.pose_seconds)}
	var id:=opponent(game)
	if "human" not in world.gomoku.players(game):id=mover if not mover.is_empty() else game.black_id
	if id!="human":say(id,game,context(game,id,base) if base in ["move","other_move"] else base)
func advance(game: Dictionary) -> void:
	if game.phase!="playing" or not observed_sites.has(game.site_id):return
	var elapsed: float=world.director.time-float(state(game).changed)
	var id:=opponent(game)
	if world.gomoku._turn(game)=="human":
		if elapsed>=float(config.player_wait):say(id,game,"player_wait")
	elif elapsed>=float(config.long_think):say(world.gomoku._turn(game),game,"long_think")
func preset(game: Dictionary,index: int) -> bool:
	if index<0 or index>=3 or "human" not in world.gomoku.players(game):return false
	return say(opponent(game),game,["reply_praise","reply_think","reply_tease"][index])
func pose(game: Dictionary,id: String) -> String:
	if game.phase=="abandoned":return "other_move"
	if game.phase=="finished":return "draw" if game.result=="draw" else "win" if game.winner_id==id else "lose"
	var p: Dictionary=state(game).poses.get(id,{})
	if world.director.time<float(p.get("until",0)):return p.state
	var f:=facts(game)
	if not f.ahead_id.is_empty():return "ahead" if f.ahead_id==id else "behind"
	return "think" if world.gomoku._turn(game)==id else "other_move"
func frame(art: Dictionary,pose_name: String) -> String:
	for key in config.frames.get(pose_name,config.frames.think):
		if art.frames.has(key):return key
	return str(art.frames.keys()[0]) if not art.frames.is_empty() else ""
func bubble(game: Dictionary,id: String) -> Dictionary:
	var b: Dictionary=state(game).bubbles.get(id,{})
	if b.get("source")=="local_rules" and not permitted(id,game):return {}
	return b.duplicate() if world.director.time<float(b.get("until",0)) else {}
func remember_speech(game: Dictionary,id: String,text: String,source: String) -> void:
	var s:=state(game)
	s.recent_speech.append({"actor_id":id,"text":text,"source":source,"hand":game.history.size()})
	if s.recent_speech.size()>12:s.recent_speech.pop_front()
func model_speech(game: Dictionary,id: String,text: String) -> bool:
	if id=="human" or id not in world.gomoku.players(game) or text.is_empty() or text.length()>30:return false
	remember_speech(game,id,text,"model")
	state(game).bubbles[id]={"text":text,"source":"model","until":world.director.time+float(config.bubble_seconds)}
	return true
func clear() -> void:states.clear();observed_sites.clear()
