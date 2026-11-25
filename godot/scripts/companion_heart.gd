extends RefCounted
## Six persistent feelings. Observation only; no routes, jobs, stock or relationship writes.
const RECONCILIATION_HURT:=30
var owner:WeakRef
var world:RefCounted:
	get:return owner.get_ref()
var config:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/heart.json"))
var profiles:Dictionary={}
var seen:Dictionary={}
var weather_seen:=""
var curves:Dictionary={}
var symbol_counts:Dictionary={}
var rendered_symbols:Dictionary={}
var reactions:Dictionary={}
var observe_left:=0.0
var next_sample:=0.0
func _init(w:RefCounted)->void:
	owner=weakref(w)
func profile(id:String)->Dictionary:
	if not profiles.has(id):profiles[id]={"mood":config.baseline.duplicate(true),"reason":"settled","last_contact":world.forest.clock,"extras":{}}
	return profiles[id]
func contact(id:String)->void:
	if id=="human" or not world.actors.has(id):return
	var before:float=float(profile(id).mood.hurt)
	profile(id).last_contact=world.forest.clock
	change(id,{"safe":2,"hurt":-2},"talk")
	if before>=RECONCILIATION_HURT and float(profile(id).mood.hurt)<before and world.actors[id].region_id==world.actors.human.region_id and world.point(world.actors[id]).distance_to(world.point(world.actors.human))<=12:
		world.memories.record_event("emotion_reconciled",id+":"+str(world.days.day()),["human",id],{"actor_id":id,"day":world.days.day(),"previous_hurt":before})
func mood(id:String)->Dictionary:
	return profile(id).mood.duplicate(true)
func change(id:String,delta:Dictionary,reason:String,ai:bool=false)->bool:
	if id=="human" or not world.actors.has(id) or delta.is_empty() or reason.length()>160:return false
	var limit:float=float(config.max_ai_delta if ai else config.max_event_delta)
	for axis in delta:
		var n:Variant=delta[axis]
		if axis not in config.axes or not (n is int or n is float) or not is_finite(n):return false
	var p:Dictionary=profile(id)
	for axis in delta:p.mood[axis]=clampf(float(p.mood[axis])+clampf(float(delta[axis]),-limit,limit),0,100)
	p.reason=reason;world.revision+=1
	var cue:String={"company_pat":"pat","company_comfort":"happy","company_praise":"shy","company_promise_kept":"happy","company_promise_missed":"hurt","meal_favorite":"happy","meal_mushroom":"wince","rejected":"hurt"}.get(reason,"")
	if not cue.is_empty():react(id,cue)
	return true
func react(id:String,cue:String)->void:
	reactions[id]={"cue":cue,"at":world.director.time}
func dominant(id:String)->String:
	var m:Dictionary=profile(id).mood
	var axis:="safe";var strength:=-INF
	for key in config.axes:
		# Hurt starts lower, so compare a rise from its own resting value.
		var value:float=float(m[key])-float(config.baseline[key])
		if value>strength:strength=value;axis=key
	return axis
func summary(id:String)->Dictionary:
	var p:Dictionary=profile(id);var axis:String=dominant(id)
	var en:int=1 if TranslationServer.get_locale().begins_with("en") else 0
	return {"axis":axis,"name":config.labels[axis][en],"reason":str(config.reasons.get(p.reason,[p.reason,p.reason])[en]),"mood":mood(id)}
func symbol(id:String,at:float)->String:
	var axis:String=dominant(id);var m:Dictionary=profile(id).mood
	if float(m[axis])-float(config.baseline[axis])<float(config.symbol_rise_threshold) or fposmod(at+float(abs(id.hash())%11),float(config.symbol_period))>=float(config.symbol_seconds):return ""
	return {"joy":"♪","tired":"z","missing":"♡","curious":"!?","hurt":"…","safe":"♥"}[axis]
func observe()->void:
	for event in world.memories.records:
		var key:String=str(event.id)
		if seen.has(key):continue
		seen[key]=true
		var kind:String=event.kind
		if kind=="story_chapter":
			for id in event.participants:
				if id!="human" and world.actors.has(id):react(id,"surprise")
			continue
		var delta:Dictionary=config.event_changes.get(kind,{})
		for id in event.participants:
			if id=="human" or not world.actors.has(id):continue
			if "human" in event.participants:profile(id).last_contact=world.forest.clock
			if not delta.is_empty():change(id,delta,"shared")
	for brain in world.director.brains.values():
		for receipt in brain.interactions.receipts.slice(-8):
			var key:String="receipt:"+str(brain.id)+":"+str(receipt.at)+":"+str(receipt.get("event",""))
			if seen.has(key):continue
			seen[key]=true
			if receipt.get("event")=="social_refusal":
				var listener:String=str(receipt.get("listener",""))
				if listener!="human" and world.actors.has(listener):change(listener,{"hurt":8},"rejected")
	while seen.size()>512:seen.erase(seen.keys()[0])
func advance(delta:float)->void:
	if delta<=0 or not is_finite(delta):return
	observe_left-=delta
	if observe_left<=0:observe();observe_left=1.0
	var weather:String=str(world.weather.current().id)
	var changed:bool=not weather_seen.is_empty() and weather_seen!=weather
	weather_seen=weather
	for id in world.director.routines:
		var p:Dictionary=profile(id);var actor:Dictionary=world.actors[id]
		for axis in config.axes:p.mood[axis]=move_toward(float(p.mood[axis]),float(config.baseline[axis]),delta*float(config.decay_per_second))
		var near:bool=actor.region_id==world.actors.human.region_id and world.point(actor).distance_to(world.point(world.actors.human))<=float(config.near_distance)
		p.mood.missing=clampf(float(p.mood.missing)+delta*float(config.missing_near_per_second if near else config.missing_far_per_second),0,100)
		if near:p.mood.safe=clampf(float(p.mood.safe)+delta*float(config.safe_near_per_second),0,100)
		var working:bool=world.director.moods.laboring(id)
		var resting:bool=actor.activity in ["resting","local_rest","sitting","local_sit","play_lie"] or world.director.brains[id].current.get("action","") in ["rest","night_rest"]
		if working:p.mood.tired=minf(100,float(p.mood.tired)+delta*float(config.work_tired_per_second));p.reason="work"
		elif resting:p.mood.tired=maxf(0,float(p.mood.tired)+delta*float(config.rest_tired_per_second));p.reason="rest"
		if world.forest.clock-float(p.last_contact)>float(config.neglect_seconds):p.mood.hurt=minf(100,float(p.mood.hurt)+delta*float(config.neglect_hurt_per_second));p.reason="neglect"
		if changed:change(id,config.weather_changes.get(weather,{"curious":2}),"weather")
	if world.forest.clock>=next_sample:
		next_sample=world.forest.clock+30
		for id in world.director.routines:
			if not curves.has(id):curves[id]=[]
			curves[id].append({"at":world.forest.clock,"mood":mood(id)})
			if curves[id].size()>64:curves[id].pop_front()
func note_symbol(id:String,at:float)->void:
	var bucket:int=int((at+float(abs(id.hash())%11))/float(config.symbol_period))
	if rendered_symbols.get(id,-1)!=bucket:
		rendered_symbols[id]=bucket;symbol_counts[id]=int(symbol_counts.get(id,0))+1
func choice_score(id:String,action:String,_need:String="")->float:
	var m:Dictionary=profile(id).mood;var c:Dictionary=config.choice
	var joy:float=maxf(0,float(m.joy)-float(config.baseline.joy))/50.0
	var hurt:float=maxf(0,float(m.hurt)-float(config.baseline.hurt))/90.0
	var tired:float=maxf(0,float(m.tired)-float(config.baseline.tired))/80.0
	var curious:float=maxf(0,float(m.curious)-float(config.baseline.curious))/50.0
	var score:=0.0
	if action in c.near_actions:score+=joy*float(c.joy_near)+hurt*float(c.hurt_near)
	if action in c.solitude_actions:score+=hurt*float(c.hurt_solitude)
	if action in c.rest_actions:score+=tired*float(c.tired_rest)
	if action in c.explore_actions:score+=curious*float(c.curious_explore)
	return score
func saved()->Dictionary:return {"version":1,"profiles":profiles.duplicate(true)}
func valid(value:Variant,actors:Dictionary)->bool:
	if not value is Dictionary or value.get("version")!=1 or not value.get("profiles") is Dictionary or value.profiles.size()>actors.size():return false
	for id in value.profiles:
		if id=="human" or not actors.has(id):return false
		var p:Variant=value.profiles[id]
		if not p is Dictionary or not p.get("mood") is Dictionary or p.mood.size()!=6 or not p.get("reason") is String or p.reason.length()>160:return false
		for axis in config.axes:
			var n:Variant=p.mood.get(axis)
			if not (n is int or n is float) or not is_finite(n) or n<0 or n>100:return false
		var time:Variant=p.get("last_contact")
		if not (time is int or time is float) or not is_finite(time) or time<0:return false
		if not p.get("extras") is Dictionary or p.extras.keys().any(func(key):return key!="mushrooms"):return false
		if p.extras.has("mushrooms"):
			var extra:Variant=p.extras.mushrooms
			if not extra is Dictionary or extra.size()!=2:return false
			for key in ["day","count"]:
				var n:Variant=extra.get(key)
				if not (n is int or n is float) or not is_finite(n) or n!=floor(n) or n<0 or n>1000000:return false
	return true
func restore(value:Dictionary)->void:
	reactions.clear()
	profiles=value.get("profiles",{}).duplicate(true);seen.clear();curves.clear();weather_seen="";next_sample=0
	# Old retained facts are a baseline, never newly experienced feelings.
	for event in world.memories.records:seen[str(event.id)]=true
