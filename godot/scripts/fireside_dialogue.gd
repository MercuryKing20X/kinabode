extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
## Pools are selected only after the first chew of an actual reserved cooked portion. Director owns speech delivery.
var _fire:WeakRef
var fire:RefCounted:
	get:return _fire.get_ref()
var world:RefCounted:
	get:return fire.world
var pending:Array=[]
var reactions:Dictionary={}
var visible:Dictionary={}
var recent:Array=[]
# Shared between stations, session-only; only delivered lines enter these sets.
static var delivered_days:Dictionary={}
static var delivered_meals:Dictionary={}
static var last_context:Dictionary={}
func speech_key()->String:return world.world_id+":"+str(world.days.day())
func meal_key()->String:return world.world_id+":"+str(fire.life.station.id)+":"+str(fire.state.current.get("id",""))
func fresh_line(id:String,line:String,context:String)->bool:
	return not delivered_days.get(speech_key(),{}).get(id,{}).has(line) and not delivered_meals.get(meal_key(),{}).has(line) and last_context.get(world.world_id+":"+id,"")!=context
func note_line(id:String,line:String,context:String)->void:
	for key in delivered_days.keys():
		if key!=speech_key():delivered_days.erase(key)
	if not delivered_days.has(speech_key()):delivered_days[speech_key()]={}
	if not delivered_days[speech_key()].has(id):delivered_days[speech_key()][id]={}
	delivered_days[speech_key()][id][line]=true
	if not delivered_meals.has(meal_key()):delivered_meals[meal_key()]={}
	delivered_meals[meal_key()][line]=true
	while delivered_meals.size()>8:delivered_meals.erase(delivered_meals.keys()[0])
	last_context[world.world_id+":"+id]=context

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
	pending.clear();visible.clear();reactions.clear();mini_left=0
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
func deliver(id:String,pool_id:String,values:Dictionary)->bool:
	var lines:Array=world.intelligence.catalog.speech.get(pool_id,{}).get("lines",[])
	var start:int=rng.randi_range(0,maxi(0,lines.size()-1))
	for offset in range(lines.size()):
		var template:String=lines[(offset+start)%lines.size()]
		var line:String=template
		for key in values:line=line.replace("{"+key+"}",str(values[key]))
		if "{" in line or recent.has(line) or not fresh_line(id,line,pool_id):continue
		if not world.director.say_fireside(id,line,"fireside_"+pool_id,fire.life.station.id):continue
		preload("res://scripts/localization.gd").remember_speech(id,line,template,values,pool_id)
		note_line(id,line,pool_id)
		recent.append(line)
		if recent.size()>24:recent.pop_front()
		visible[id]=world.director.time+float(fire.config.bubble_seconds);last_speaker=id
		next_bubble=world.director.time+rng.randf_range(fire.config.bubble_interval[0],fire.config.bubble_interval[1]);mini_left-=1
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
	pending=pending.filter(func(p):return p.expires>now)
	if now<next_bubble or visible.size()>=int(fire.config.bubble_limit):return
	if mini_left<=0:mini_left=rng.randi_range(2,3);mini_topic=["food","weather","phase","catch","moon","relationship","emoji"][rng.randi_range(0,6)]
	var actors:Array=fire.jobs.keys().filter(func(id):return id!="human" and id in fire.state.attended)
	if last_speaker in actors:actors.erase(last_speaker);actors.append(last_speaker)
	for id in actors:
		for p in pending:
			if p.actor_id==id and p.has("text"):
				if fresh_line(id,p.text,"first_taste") and world.director.say_fireside(id,p.text,"fireside_fish_first",fire.life.station.id):
					note_line(id,p.text,"first_taste")
					visible[id]=now+float(fire.config.bubble_seconds);last_speaker=id;next_bubble=now+rng.randf_range(fire.config.bubble_interval[0],fire.config.bubble_interval[1]);mini_left-=1;pending.erase(p);return
				continue
			if p.actor_id==id and deliver(id,p.pool,{}):pending.erase(p);return
		if world.work.jobs.get(id,{}).get("phase","")=="fire_sit" and world.scene_speech!=null:
			var tag:String=world.personality.tag(id)
			for row in world.scene_speech.data.scenes.meal_close.get(tag,[]):
				var line:String=row.en if TranslationServer.get_locale().begins_with("en") else row.zh
				if not fresh_line(id,line,"meal_close"):continue
				if not world.director.say_fireside(id,line,"fireside_scene_meal_close",fire.life.station.id):continue
				note_line(id,line,"meal_close")
				visible[id]=now+float(fire.config.bubble_seconds);last_speaker=id;next_bubble=now+rng.randf_range(fire.config.bubble_interval[0],fire.config.bubble_interval[1]);mini_left-=1;world.scene_speech.note(id,"meal_close",row.id);return
		var topics:Array=[mini_topic,"food","weather","phase","emoji"]
		for n in range(topics.size()):
			var topic:String=topics[n];var proof:=facts(id,topic)
			if not proof.is_empty() and deliver(id,pool(id,"chat_"+topic),proof):return
