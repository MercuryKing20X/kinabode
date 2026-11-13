extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
## Lifecycle scenes observe actual seated/cooking/eating states. Taste pools require a real first chew. Director owns delivery.
var _fire:WeakRef
var fire:RefCounted:
	get:return _fire.get_ref()
var world:RefCounted:
	get:return fire.world
var pending:Array=[]
var reactions:Dictionary={}
var visible:Dictionary={}
var recent:Array=[]
var scene_deliveries:Dictionary={}
var scene_data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/barbecue-scenes.json"))
# Shared between stations, session-only; only delivered lines enter these sets.
static var delivered_days:Dictionary={}
static var delivered_meals:Dictionary={}
static var last_context:Dictionary={}
func speech_key()->String:return world.world_id+":"+str(world.days.day())
func meal_key()->String:return world.world_id+":"+str(fire.life.station.id)+":"+str(fire.state.get("id",""))
func fresh_line(id:String,line:String,context:String)->bool:
	return not delivered_days.get(speech_key(),{}).get(id,{}).has(line) and not delivered_meals.get(meal_key(),{}).has(line) and last_context.get(world.world_id+":"+id,"")!=context
func note_line(id:String,line:String,context:String)->void:
	for key in delivered_days.keys():
		if str(key).begins_with(world.world_id+":") and key!=speech_key():delivered_days.erase(key)
	if not delivered_days.has(speech_key()):delivered_days[speech_key()]={}
	if not delivered_days[speech_key()].has(id):delivered_days[speech_key()][id]={}
	delivered_days[speech_key()][id][line]=true
	if not delivered_meals.has(meal_key()):delivered_meals[meal_key()]={}
	delivered_meals[meal_key()][line]=true
	while delivered_meals.size()>8:delivered_meals.erase(delivered_meals.keys()[0])
	last_context[world.world_id+":"+id]=context
	while delivered_days.size()>32:delivered_days.erase(delivered_days.keys()[0])
	while last_context.size()>128:last_context.erase(last_context.keys()[0])

var next_bubble:=0.0
var last_speaker:=""
var mini_left:=0
var mini_topic:="phase"
var rng:=RandomNumberGenerator.new()
var rng_world:=""
var species_lines:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/fish-first-tastes.json"))
func _init(owner_fire:RefCounted)->void:_fire=weakref(owner_fire)
func trait_id(id:String)->String:return str(world.intelligence.tag(id))
func pool(id:String,context:String)->String:
	return "bbq-"+trait_id(id)+"-"+context.replace("_","-")
func selection(id:String,food:Dictionary,rank:int)->Dictionary:
	var foods:Array=world.intelligence.catalog.traits.get(trait_id(id),{}).get("favorite_foods",[])
	var favorite:bool=food.food_id in foods or food.category in foods or (not food.get("fish",{}).is_empty() and "fish" in foods) or trait_id(id) in world.recipes.metadata.get(food.food_id,{}).get("favorite_traits",[])
	var contexts:Array=["food_"+str(food.food_id).replace("-","_"),"category_"+food.category]
	var extras:Array=[]
	if favorite:extras.append("special_favorite")
	if food.get("first_time",false):extras.append("special_first")
	var fish:Dictionary=food.get("fish",{})
	if fish.get("size_id") in ["huge","giant"]:extras.append("special_giant")
	if not fish.is_empty() and world.fishing.rules.species.any(func(s):return s.id==fish.get("species_id") and float(s.weight)<=8):extras.append("special_rare")
	contexts.append_array(extras);contexts.append("hunger_"+["full","peckish","hungry","very_hungry"][clampi(rank,0,3)])
	var selected:=""
	for context in contexts:
		if world.intelligence.catalog.speech.has(pool(id,context)):selected=pool(id,context);break
	return {"pool":selected,"favorite":favorite,"first_time":bool(food.get("first_time",false)),"extra":extras.map(func(c):return pool(id,c)),"dish":food.category=="dish"}
func ate(id:String,food:Dictionary,previous_rank:int)->void:
	if id=="human":return
	pending.append({"actor_id":id,"scene":"first_bite","proof":fire.state.current.id,"expires":world.director.time+180})
	pending.append({"actor_id":id,"scene":"taste","proof":fire.state.current.id,"expires":world.director.time+180})
	var selected:=selection(id,food,previous_rank)
	var species:String=str(food.get("fish",{}).get("species_id",""))
	var special:Dictionary=world.recipes.metadata.get(food.food_id,{})
	if special.get("signature_trait","")==trait_id(id) and special.has("signature_line"):
		pending.append({"actor_id":id,"text":LocalText.content(special.signature_line),"proof":fire.state.current.id,"expires":world.director.time+180})
		reactions[id]={"until":world.director.time+8,"kind":"happy"}
	if food.get("first_time",false) and special.get("first_lines",{}).has(trait_id(id)):
		pending.append({"actor_id":id,"text":LocalText.content(special.first_lines[trait_id(id)]),"proof":fire.state.current.id,"expires":world.director.time+180})
	if food.get("first_species",false) and species_lines.has(species):pending.append({"actor_id":id,"text":species_lines[species],"proof":fire.state.current.id,"expires":world.director.time+180})
	if special.get("normal_lines",{}).has(trait_id(id)):
		pending.append({"actor_id":id,"text":LocalText.content(special.normal_lines[trait_id(id)]),"proof":fire.state.current.id,"expires":world.director.time+180})
	elif not selected.pool.is_empty():pending.append({"actor_id":id,"pool":selected.pool,"proof":fire.state.current.id,"expires":world.director.time+180})
	for extra in selected.extra:pending.append({"actor_id":id,"pool":extra,"proof":fire.state.current.id,"expires":world.director.time+180})
	if selected.dish:pending.append({"actor_id":id,"pool":pool(id,"category_dish"),"proof":fire.state.current.id,"expires":world.director.time+180})
	if pending.size()>32:pending=pending.slice(-32)
	if selected.favorite or selected.first_time or not food.get("fish",{}).is_empty() and food.fish.get("size_id")=="giant":reactions[id]={"until":world.director.time+(8 if special.get("signature_trait","")==trait_id(id) else 5),"kind":"happy"}
func clear()->void:
	pending.clear();visible.clear();reactions.clear();scene_deliveries.clear();mini_left=0
func facts(id:String,topic:String)->Dictionary:
	match topic:
		"food":
			var meals:Array=fire.state.get("ate",{}).get(id,[])
			return {"food":meals[-1].name} if not meals.is_empty() else {}
		"weather":return {"weather":world.weather.current().name}
		"phase":return {"phase":world.days.phase().name}
		"relationship":return {"stage":world.relationships.summary(id).name} if world.relationships.index(id)>0 else {}
		"moon":
			if world.days.phase().id!="night" or world.weather.current().id in ["rain","fog"]:return {}
			return {"moon":[LocalText.source("content.moon.new_moon"),LocalText.source("content.moon.waxing_crescent"),LocalText.source("content.moon.first_quarter"),LocalText.source("content.moon.waxing_gibbous"),LocalText.source("content.moon.full_moon"),LocalText.source("content.moon.waning_gibbous"),LocalText.source("content.moon.last_quarter"),LocalText.source("content.moon.waning_crescent")][posmod(world.days.day()-1,8)]}
		"catch":
			if world.fishing.memories.is_empty():return {}
			var m:Dictionary=world.fishing.memories[-1]
			var species:Array=world.fishing.rules.species.filter(func(s):return s.id==m.get("species_id",m.get("fish",{}).get("species_id","")))
			var catcher:String=str(m.get("actor_id",m.get("owner_id","")))
			if species.is_empty() or not world.actors.has(catcher):return {}
			return {"fish":species[0].name,"catcher":LocalText.source("content.moon.me") if catcher==id else world.actors[catcher].name}
		"emoji":return {"expression":true}
	return {}
func canonical_scene(pool_id:String)->String:
	if "-chat-" in pool_id:return "chat"
	if pool_id.ends_with("-special-first"):return "first_bite"
	return "taste"
func scene_key(id:String,scene:String)->String:return str(fire.state.current.get("id",""))+":"+id+":"+scene
func scene_done(id:String,scene:String)->bool:return scene_deliveries.has(scene_key(id,scene))
func delivered(id:String,line:String,context:String)->void:
	note_line(id,line,context)
	recent.append(line)
	if recent.size()>24:recent.pop_front()
	visible[id]=world.director.time+float(fire.config.bubble_seconds);last_speaker=id
	next_bubble=world.director.time+rng.randf_range(fire.config.bubble_interval[0],fire.config.bubble_interval[1]);mini_left-=1
func deliver_scene(id:String,scene:String)->bool:
	var tag:String=trait_id(id)
	# Legacy compatibility tags describe speech, never identity or permissions.
	if tag=="curious":tag="lively"
	var lines:Array=scene_data.scenes.get(tag,{}).get(scene,[]).duplicate()
	if scene=="satisfied" and world.scene_speech!=null:
		lines.append_array(world.scene_speech.data.scenes.meal_close.get(world.personality.tag(id),[]))
	if lines.is_empty():return false
	var start:int=rng.randi_range(0,lines.size()-1)
	for offset in range(lines.size()):
		var row:Dictionary=lines[(start+offset)%lines.size()]
		var line:String=LocalText.content(row.zh)
		if recent.has(line) or not fresh_line(id,line,scene):continue
		if not world.director.say_fireside(id,line,"fireside_scene_"+scene,fire.life.station.id):continue
		delivered(id,line,scene);scene_deliveries[scene_key(id,scene)]=true
		if row.has("id") and world.scene_speech!=null:world.scene_speech.note(id,"meal_close",row.id)
		return true
	return false
func lifecycle_scene(id:String)->String:
	var job:Dictionary=world.work.jobs.get(id,{})
	if job.get("phase","")=="fire_travel":return ""
	var eaten:bool=id in fire.state.current.get("eaters",[])
	if eaten:
		if float(fire.state.current.get("meal_remaining",INF))<=8:return "depart"
		if not scene_done(id,"satisfied"):return "satisfied"
		return "chat"
	if not fire.state.current.get("ready",false):
		# Cooking is shorter than the unchanged personal speech gap. Choose among
		# the three truthful arrival scenes, so waiting/aroma need no extra turn.
		var arrival:Array=["seat","wait","smell"]
		var start:int=posmod(world.days.day()+fire.state.attended.find(id),arrival.size())
		for offset in range(arrival.size()):
			var context:String=arrival[(start+offset)%arrival.size()]
			if last_context.get(world.world_id+":"+id,"")!=context:return context
	if not scene_done(id,"seat"):return "seat"
	return ""
func deliver(id:String,pool_id:String,values:Dictionary)->bool:
	var lines:Array=world.intelligence.catalog.speech.get(pool_id,{}).get("lines",[])
	var start:int=rng.randi_range(0,maxi(0,lines.size()-1))
	for offset in range(lines.size()):
		var template:String=lines[(offset+start)%lines.size()]
		var line:String=template
		for key in values:line=line.replace("{"+key+"}",str(values[key]))
		if "{" in line or recent.has(line) or not fresh_line(id,line,canonical_scene(pool_id)):continue
		if not world.director.say_fireside(id,line,"fireside_"+pool_id,fire.life.station.id):continue
		preload("res://scripts/localization.gd").remember_speech(id,line,template,values,pool_id)
		delivered(id,line,canonical_scene(pool_id))
		return true
	return false
func tick()->void:
	# Independent local presentation RNG: reproducible for a retained world and camp.
	if rng_world!=world.world_id:
		rng_world=world.world_id
		rng.seed=hash(world.world_id+":"+str(fire.life.station.id)+":fireside-v4")
	var now:float=world.director.time
	for id in visible.keys():
		if visible[id]<=now:visible.erase(id)
	for id in reactions.keys():
		if reactions[id].until<=now:reactions.erase(id)
	pending=pending.filter(func(p):return p.expires>now and p.proof==fire.state.current.get("id",""))
	if now<next_bubble or visible.size()>=int(fire.config.bubble_limit):return
	if mini_left<=0:mini_left=rng.randi_range(2,3);mini_topic=["food","weather","phase","catch","moon","relationship","emoji"][rng.randi_range(0,6)]
	var actors:Array=fire.jobs.keys().filter(func(id):return id!="human" and id in fire.state.attended)
	if last_speaker in actors:actors.erase(last_speaker);actors.append(last_speaker)
	for id in actors:
		var scene:String=lifecycle_scene(id)
		if scene in ["seat","wait","smell","depart"] and deliver_scene(id,scene):return
		if scene=="satisfied" and scene_done(id,"first_bite") and deliver_scene(id,scene):return
		for p in pending:
			if p.actor_id==id and p.has("scene"):
				if deliver_scene(id,p.scene):pending.erase(p);return
				continue
			if p.actor_id==id and p.has("text"):
				if fresh_line(id,p.text,"taste") and world.director.say_fireside(id,p.text,"fireside_fish_first",fire.life.station.id):
					delivered(id,p.text,"taste");pending.erase(p);return
				continue
			if p.actor_id==id and deliver(id,p.pool,{}):pending.erase(p);return
		if scene in ["satisfied","chat"] and deliver_scene(id,scene):return
		var topics:Array=[mini_topic,"food","weather","phase","emoji"]
		for n in range(topics.size()):
			var topic:String=topics[n];var proof:=facts(id,topic)
			if not proof.is_empty() and deliver(id,pool(id,"chat_"+topic),proof):return
