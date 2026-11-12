extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
## Data-selected authored reactions to retained real facts. No new task/model lifecycle.
var _owner: WeakRef
var world: RefCounted:
	get:return _owner.get_ref()
var config: Dictionary={}
var reacted: Array=[]
var spoken: Dictionary={}
var observed: Dictionary={}
var next_check:=0.0
var daily_lines:Dictionary={}
var daily_day:=-1
func _init(source: RefCounted) -> void:
	_owner=weakref(source)
	var data: Variant=world.intelligence.personality_config()
	if not valid_config(data):world.error=LocalText.text("system.personality_system.the_personality_settings_are_invalid");return
	config=data
func valid_config(data: Variant) -> bool:
	if not data is Dictionary or data.get("version")!=1 or not data.get("traits") is Dictionary or data.traits.size()<4 or data.traits.size()>32 or not data.get("defaults") is Dictionary:return false
	for key in ["check_interval","fact_age","personal_gap","village_gap","repeat_window","repeat_limit"]:
		if not world.catalog._number(data.get(key)) or data[key]<1 or data[key]>86400:return false
	if data.repeat_limit!=2 or data.repeat_window!=3600:return false
	for profile in data.traits.values():
		if not profile is Dictionary or profile.get("action") not in ["watch","look","stretch"] or not profile.get("name") is String or profile.name.length()>12 or not profile.get("lines") is Dictionary:return false
		if not world.catalog._number(profile.get("idle_speech_scale",1)) or profile.get("idle_speech_scale",1)<.3 or profile.get("idle_speech_scale",1)>3:return false
		for key in ["weights","wish_weights","schedule_weights"]:
			if not profile.get(key) is Dictionary or not profile[key].values().all(func(value):return world.catalog._number(value) and value>=0 and value<=4):return false
		for context in ["ambient","calm","happy","quiet","tired","meal","giant","rain","fog","greet"]:
			if not profile.lines.get(context) is Array or profile.lines[context].size()<4 or profile.lines[context].size()>64 or not profile.lines[context].all(func(line):return line is String and not line.is_empty() and line.length()<=60):return false
	for style in ["calm","curious","lively"]:
		if not data.defaults.get(style) in data.traits:return false
	return true
func tag(id: String) -> String:
	if not world.intelligence.compatibility and not world.intelligence.preset(id).is_empty():return world.intelligence.tag(id)
	var prefs: Dictionary=world.residents.preferences_for(id)
	return str(prefs.personality) if prefs.get("personality","") in config.traits else str(config.defaults.get(prefs.get("fishing_style","calm"),"gentle"))
func profile(id: String) -> Dictionary:
	if not world.intelligence.compatibility and not world.intelligence.preset(id).is_empty():return world.intelligence.profile(id)
	return config.traits[tag(id)]
func pool(id: String,context: String="ambient") -> Array:
	var lines:Dictionary=profile(id).lines
	var result:Array=lines.get(context,lines.ambient).duplicate()
	if context=="ambient" and favorite_food_context(id):result.append_array(lines.get("favorite_aside",[]))
	return result
func speech_scale(id: String) -> float:return float(profile(id).get("idle_speech_scale",1))
func summary(id: String) -> Dictionary:return {"id":tag(id),"name":profile(id).name,"source":"local_rules"}
func weights(id: String,base: Dictionary) -> Dictionary:
	var result:=base.duplicate()
	for key in profile(id).weights:result[key]=float(result.get(key,0))*float(profile(id).weights[key])
	return result
func allowed_line(id: String,text: String) -> bool:
	if daily_day!=world.days.day():daily_lines.clear();daily_day=world.days.day()
	if daily_lines.get(id,{}).has(LocalText.content_keys.get(text,text)):return false
	var history: Dictionary=spoken.get(id,{})
	var times: Array=history.get(text,[]).filter(func(stamp):return world.director.time-float(stamp)<float(config.repeat_window))
	return times.size()<int(config.repeat_limit)
func note_line(id: String,text: String) -> void:
	if daily_day!=world.days.day():daily_lines.clear();daily_day=world.days.day()
	var today:Dictionary=daily_lines.get(id,{});today[LocalText.content_keys.get(text,text)]=true;daily_lines[id]=today
	var history: Dictionary=spoken.get(id,{})
	for line in history.keys():
		history[line]=history[line].filter(func(stamp):return world.director.time-float(stamp)<float(config.repeat_window))
		if history[line].is_empty():history.erase(line)
	var times: Array=history.get(text,[]);times.append(world.director.time);history[text]=times
	# At the village speech limit a resident cannot legitimately exceed this within one hour.
	if history.size()>256:history.erase(history.keys()[0])
	spoken[id]=history
func selection(id: String,pool_lines: Array,recent: Array=[]) -> Array:
	var available: Array=pool_lines.filter(func(line):return allowed_line(id,str(line)))
	var fresh: Array=available.filter(func(line):return line not in recent)
	return fresh if not fresh.is_empty() else available
func factual(id: String) -> Dictionary:
	var now: float=world.director.time
	for entry in world.memories.records.duplicate().slice(-32):
		var key: String=(id+":meal:"+entry.id).sha256_text()
		if entry.kind=="shared_barbecue" and entry.facts.get("version")==2 and id in entry.participants and "human" in entry.participants and now-float(observed.get("meal:"+entry.id,-INF))<=float(config.fact_age) and key not in reacted:return {"context":"meal","key":key}
		if entry.kind=="meal" and entry.facts.get("meal_type")=="cooked" and id in entry.facts.get("ate",[]) and "human" in entry.facts.get("ate",[]) and now-float(observed.get("meal:"+entry.id,-INF))<=float(config.fact_age) and key not in reacted:return {"context":"meal","key":key}
	for entry in world.fishing.memories:
		var key: String=(id+":giant:"+entry.id).sha256_text();var present: Array=entry.companions.duplicate();present.append(entry.actor_id)
		var fish: Dictionary=world.fishing.fish.get(entry.id,{})
		if world.memories.records.any(func(record):return record.kind=="fishing_catch" and record.source.id==entry.id) and id in present and "human" in present and fish.get("size_id") in ["huge","giant"] and now-float(observed.get("giant:"+entry.id,-INF))<=float(config.fact_age) and key not in reacted:return {"context":"giant","key":key}
	var weather: String=world.weather.current().id;var key: String=(id+":"+str(world.days.day())+":"+weather).sha256_text()
	if world.actors[id].region_id=="home" and weather in ["rain","fog"] and key not in reacted:return {"context":weather,"key":key}
	return {}
func try_event(id: String) -> bool:
	if not config.get("fact_events_enabled",true) or not world.relationships.available(id):return false
	if not world.director.can_say_local(id):return false
	var fact:=factual(id)
	if fact.is_empty():return false
	var r: RefCounted=world.director.routines[id];var lines:=selection(id,pool(id,fact.context),r.recent_lines)
	if lines.is_empty():return false
	var text: String=lines[r.rng.randi_range(0,lines.size()-1)]
	if not world.director.say_local(id,text,"personality_"+fact.context,float(config.personal_gap),float(config.village_gap)):return false
	reacted.append(fact.key)
	if reacted.size()>256:reacted.pop_front()
	r.recent_lines.append(text)
	if r.recent_lines.size()>6:r.recent_lines.pop_front()
	r.authored_reaction(str(profile(id).action));return true
func advance() -> void:
	if world.director.time<next_check:return
	next_check=world.director.time+float(config.check_interval)
	var retained: Dictionary={}
	for entry in world.memories.records:
		if entry.kind=="meal" or (entry.kind=="shared_barbecue" and entry.facts.get("version")==2):retained["meal:"+entry.id]=true
	for entry in world.fishing.memories:retained["giant:"+entry.id]=true
	for key in observed.keys():
		if not retained.has(key):observed.erase(key)
	for key in retained:
		if not observed.has(key):observed[key]=world.director.time
func reset() -> void:
	reacted.clear();spoken.clear();observed.clear();next_check=0
	daily_lines.clear();daily_day=-1
	if world.scene_speech!=null:world.scene_speech.reset()
	for entry in world.memories.records:observed["meal:"+entry.id]=-INF
	for entry in world.fishing.memories:observed["giant:"+entry.id]=-INF
	# On load do not replay prior meal/catch reactions; weather is a current visible state.
	for id in world.director.routines:
		for entry in world.memories.records:reacted.append((id+":meal:"+entry.id).sha256_text())
		for entry in world.fishing.memories:reacted.append((id+":giant:"+entry.id).sha256_text())
	if reacted.size()>256:reacted=reacted.slice(-256)

func favorite_food_context(id:String)->bool:
	if world.ingredients==null or world.recipes==null or not world.actors.has(id):return false
	var actor:Dictionary=world.actors[id]
	for recipe_id in world.recipes.recipe_catalog:
		if world.recipes.metadata.get(recipe_id,{}).get("signature_trait","")!=tag(id):continue
		for ingredient in world.recipes.recipe_catalog[recipe_id].ingredients:
			# These asides belong to the new island food content. Existing
			# unrelated meals never replace or perturb the original idle pool.
			if not world.ingredients.config.items.any(func(item):return item.id==ingredient and not str(item.id).begins_with("seed.")):continue
			if ingredient in world.ingredients.discovered:return true
			for source in world.ingredients.sources():
				if source.id==ingredient and source.region==actor.region_id and world.ingredients.visible(source) and world.point(actor).distance_to(Vector2(source.position[0],source.position[1]))<=12:return true
	return false
