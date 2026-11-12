extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
## Bounded desires and proof observations. No automatic eating/crafting/taking or model messages.
var _owner: WeakRef
var world: RefCounted:
	get:return _owner.get_ref()
var config: Dictionary={}
var states: Dictionary={}
var next_check:=0.0
var statistics: Dictionary={"generated":{},"completed":{},"expired":{},"expiry_reasons":{},"outcomes":{}}
func _init(source: RefCounted) -> void:
	_owner=weakref(source)
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/wishes.json"))
	if not valid_config(data):world.error=LocalText.text("system.wish_system.the_wish_settings_are_invalid");return
	config=data
func valid_config(data: Variant) -> bool:
	if not data is Dictionary or data.get("version")!=1 or not data.get("templates") is Array or data.templates.is_empty() or data.templates.size()>32 or not data.get("interval_days") is Array or data.interval_days.size()!=2 or data.interval_days[0]!=2 or data.interval_days[1]!=3:return false
	for key in ["first_after","check_interval","expire_days","personal_gap","village_gap"]:
		if not world.catalog._number(data.get(key)) or data[key]<1 or data[key]>86400:return false
	if not data.get("hints") is Dictionary or not data.hints.values().all(func(text):return text is String and text.length()<=80) or not world.catalog._number(data.get("feasibility_margin")) or data.feasibility_margin<0 or data.feasibility_margin>600:return false
	if data.expire_days>14 or not data.get("complete_lines") is Array or data.complete_lines.size()<4:return false
	var unique: Dictionary={}
	for t in data.templates:
		if not t is Dictionary or not t.get("id") is String or t.id.is_empty() or t.id.length()>48 or unique.has(t.id) or t.get("kind") not in ["meal","fish","furniture","facility","homestead"] or not t.get("target") is String or not t.get("title") is String or t.title.length()>30 or not t.get("line") is String or t.line.length()>40 or not world.relationships.integer(t.get("min_stage"),4) or not t.get("styles") is Dictionary or not t.get("moods") is Array:return false
		unique[t.id]=true
	return data.complete_lines.all(func(line):return line is String and not line.is_empty() and line.length()<=60)
func template(key: String) -> Dictionary:
	for entry in config.templates:
		if entry.id==key:return entry
	return {}
func active(id: String) -> Dictionary:return states.get(id,{}).get("active",{})
func summary(id: String) -> Dictionary:
	var wish: Dictionary=active(id)
	if wish.is_empty():return {"source":"local_rules","active":false}
	var t:=template(wish.template_id)
	return {"source":"local_rules","active":true,"id":wish.id,"title":str(t.title),"text":str(t.line),"kind":t.kind,"target_id":wish.target_id,"match":t.get("match",{}).duplicate(),"hint":hint(t),"announced":wish.announced,"fulfilled":not wish.proof_id.is_empty()}
func target(t: Dictionary,id: String) -> String:
	match str(t.kind):
		"meal":return str(t.target) if meal_possible(str(t.target)) else ""
		"fish":
			var matches: Dictionary=t.get("match",{})
			for pair in [["species","species_id"],["colors","color_id"],["sizes","size_id"]]:
				if not world.fishing.rules[pair[0]].any(func(value):return value.id==matches.get(pair[1],"")):return ""
			return str(t.target) if world.fishing.nearby_shores("human").any(func(shore):return int(world.fishing.waters[shore.water_id].available)>0 and not world.find_route("human",Vector2(shore.position[0],shore.position[1])).is_empty()) else ""
		"homestead":return str(world.homestead.config.site.id) if not world.homestead.completed() and wood_possible(int(world.homestead.config.requirements.wood)) and crop_total()>=int(world.homestead.config.requirements.crops) else ""
		"furniture":
			for room in world.interior.rooms():
				if world.interior.RECIPES.has(t.target) and wood_possible(int(world.interior.RECIPES[t.target].wood)) and placement_possible(room,str(t.target)) and not world.interior.furniture.values().any(func(item):return world.interior.placed(item) and item.region_id==room and item.recipe_id==t.target):return room
		"facility":
			for site in world.leisure.sites.values():
				var art: Dictionary=world.leisure.art(site)
				if site.complete and not art.get("recreation",{}).has("game") and art.get("recreation",{}).get("behavior")==t.target and art.recreation.slots.size()>=2:return site.id
	return ""
func stock(item: String) -> int:
	var amount:=int(world.available_items("human").get(item,0))
	return amount
func crop_total() -> int:
	var total:=0
	for item in world.farms.crops:
		if item!="daisy":total+=crop_potential(item)
	return total
func crop_potential(item: String) -> int:
	var amount:=stock(item)
	var counted_seeds:Dictionary={}
	if not world.farms.crops.has(item):return amount
	var horizon: float=float(config.expire_days)*world.days.day_seconds-float(config.get("feasibility_margin",120))
	for plot in world.farms.plots.values():
		if not world.farms.allowed("human",plot.farm_id):continue
		if plot.crop_id==item and (world.farms.remaining(plot) if plot.watered else float(world.farms.crops[item].seconds))<=horizon:amount+=int(world.farms.crops[item].yield)
	for farm in world.farms.farms.values():
		if item not in farm.crop_ids or not world.farms.allowed("human",farm.id) or float(world.farms.crops[item].seconds)>horizon:continue
		var chest_id:String="storage"
		var seeds: int=maxi(0,int(world.available_items("human").get("seed."+item,0))-int(counted_seeds.get(chest_id,0)))
		var empty: int=world.farms.farm_plots(farm.id).filter(func(plot):return plot.crop_id.is_empty()).size()
		var usable:int=mini(seeds,empty);counted_seeds[chest_id]=int(counted_seeds.get(chest_id,0))+usable
		amount+=usable*int(world.farms.crops[item].yield)
	return amount
func meal_possible(recipe_id: String) -> bool:
	if not world.recipes.recipes.has(recipe_id):return false
	var recipe: Dictionary=world.recipes.recipes[recipe_id]
	if recipe.fish and not world.fishing.fish.values().any(func(fish):return fish.owner_id=="human" and fish.location!="cooking"):return false
	for item in recipe.ingredients:
		if crop_potential(item)<int(recipe.ingredients[item]):return false
	return true
func wood_possible(required: int) -> bool:
	var amount:=stock("wood")
	for tree in world.objects.values():
		if tree.kind=="tree" and tree.get("status")=="mature" and not world.approach_route("human",tree).is_empty():amount+=8
		if amount>=required:return true
	return amount>=required
func placement_possible(room: String,recipe: String) -> bool:
	for x in range(2,24):
		for y in range(2,8):
			if world.interior.placement(room,{"id":"wish-preview","recipe_id":recipe,"position":[x,y],"facing":"down"}):return true
	return false
func hint(t: Dictionary,localized:bool=false) -> String:
	if t.kind=="meal" and world.recipes.recipes.has(t.target):
		for item in world.recipes.recipes[t.target].ingredients:
			if stock(item)>=int(world.recipes.recipes[t.target].ingredients[item]) or not world.farms.crops.has(item):continue
			var growing: bool=world.farms.plots.values().any(func(plot):return plot.crop_id==item)
			var pattern:String=str(config.hints.growing if growing else config.hints.plant)
			var crop:String=str(world.farms.crops[item].name)
			return (LocalText.content(pattern)%LocalText.content(crop)) if localized else pattern%crop
	return LocalText.content(str(config.hints.get(t.kind,""))) if localized else str(config.hints.get(t.kind,""))
func expire(id: String,wish: Dictionary) -> void:
	var reason: String="conditions_unavailable_at_expiry" if target(template(wish.template_id),id).is_empty() else "player_did_not_complete"
	statistics.expiry_reasons[reason]=int(statistics.expiry_reasons.get(reason,0))+1
	statistics.outcomes[wish.id]=reason
	# Diagnostics are bounded memory, never new historical memories or save progress.
	if statistics.outcomes.size()>128:statistics.outcomes.erase(statistics.outcomes.keys()[0])
	states[id].active={};count("expired",id);world.revision+=1
func proofs(wish: Dictionary) -> Array:
	var t:=template(wish.template_id);var found: Array=[];var id: String=wish.resident_id
	match str(t.kind):
		"meal":
			for entry in world.memories.records:
				if entry.kind=="meal" and entry.facts.get("recipe_id")==wish.target_id and id in entry.facts.get("ate",[]) and "human" in entry.facts.get("ate",[]):found.append("memory:"+entry.id)
				if entry.kind=="shared_barbecue" and entry.facts.get("version")==2:
					var foods:Dictionary=entry.facts.get("foods",{})
					if foods.get(id,[]).any(func(food):return food.food_id==wish.target_id and food.category=="dish") and foods.get("human",[]).any(func(food):return food.food_id==wish.target_id and food.category=="dish"):found.append("memory:"+entry.id)
		"fish":
			for entry in world.fishing.memories:
				var present: Array=entry.companions.duplicate();present.append(entry.actor_id)
				var fish: Dictionary=world.fishing.fish.get(entry.id,{})
				if id in present and "human" in present and not fish.is_empty() and t.match.keys().all(func(key):return fish.get(key)==t.match[key]):found.append("fish:"+entry.id)
		"furniture":
			for item in world.interior.furniture.values():
				if world.interior.placed(item) and item.region_id==wish.target_id and item.recipe_id==t.target:found.append("furniture:"+str(item.id))
		"homestead":
			var completion: Dictionary=world.homestead.site.get("completion",{})
			var completion_id: String=str(completion.get("id",""))
			if world.homestead.completed() and not world.homestead.site.has("host_completion_source") and not world.homestead.site.has("preset_origin") and not completion_id.is_empty():found.append("homestead:"+completion_id)
		"facility":
			var one: Dictionary=world.work.jobs.get(id,{});var human: Dictionary=world.work.jobs.get("human",{})
			if one.get("intent")=="use_facility" and human.get("intent")=="use_facility" and one.get("target_id")==wish.target_id and human.get("target_id")==wish.target_id and one.get("step")=="using" and human.get("step")=="using":found.append("facility:"+(str(one.id)+str(human.id)).sha256_text())
	return found
func count(kind: String,id: String) -> void:statistics[kind][id]=int(statistics[kind].get(id,0))+1
func generate(id: String) -> bool:
	var routine: RefCounted=world.director.routines[id]
	var day: int=world.days.day();var previous: Dictionary=states.get(id,{})
	if not routine.enabled or routine.time<float(config.first_after) or not active(id).is_empty() or day<int(previous.get("next_day",1)):return false
	var candidates: Array=[];var prefs: Dictionary=world.intelligence.preferences_for(id)
	var used: Array=states.values().filter(func(state):return not state.active.is_empty()).map(func(state):return state.active.template_id)
	var mood: String=world.director.moods.summary(id).id
	for t in config.templates:
		var resolved:=target(t,id)
		if resolved.is_empty() or world.relationships.index(id)<int(t.min_stage):continue
		var weight: float=float(t.styles.get(prefs.get("fishing_style","calm"),1))+(2 if mood in t.moods else 0)
		if t.kind=="facility":weight+=float(prefs.facilities.get(t.target,0))
		weight*=float(world.personality.profile(id).wish_weights.get(t.kind,1))
		if t.id in used:weight*=.05
		if t.id in previous.get("history",[]):weight*=.25
		candidates.append({"template":t,"target":resolved,"weight":weight})
	if candidates.is_empty():return false
	var distinct: Array=candidates.filter(func(option):return option.template.id not in used)
	if not distinct.is_empty():candidates=distinct
	var rng:=RandomNumberGenerator.new();rng.seed=abs((world.world_id+id+str(day)).hash())
	var total: float=candidates.reduce(func(sum,value):return sum+float(value.weight),0.0);var roll:=rng.randf()*total
	var selected: Dictionary=candidates[-1]
	for option in candidates:
		roll-=float(option.weight)
		if roll<=0:selected=option;break
	var wish: Dictionary={"id":"wish-"+Crypto.new().generate_random_bytes(12).hex_encode(),"resident_id":id,"template_id":selected.template.id,"target_id":selected.target,"created_day":day,"expires_day":day+int(config.expire_days),"announced":false,"baseline":[],"proof_id":""}
	wish.baseline=proofs(wish)
	var history: Array=previous.get("history",[]).duplicate();history.append(wish.template_id)
	if history.size()>2:history.pop_front()
	states[id]={"active":wish,"last_created_day":day,"next_day":day+rng.randi_range(int(config.interval_days[0]),int(config.interval_days[1])),"history":history}
	count("generated",id);world.revision+=1;return true
func advance(delta: float) -> void:
	if delta<=0 or world.director.time<next_check:return
	next_check=world.director.time+float(config.check_interval)
	for id in world.director.routines:
		var wish: Dictionary=active(id)
		if not wish.is_empty():
			if world.days.day()>=int(wish.expires_day):expire(id,wish);continue
			var actual: Array=proofs(wish).filter(func(key):return key not in wish.baseline)
			var proof: String=str(actual[0]) if not actual.is_empty() else ""
			if wish.proof_id!=proof:wish.proof_id=proof;world.revision+=1
		else:generate(id)
func try_event(id: String) -> bool:
	var wish: Dictionary=active(id)
	if wish.is_empty() or not world.relationships.available(id):return false
	if not world.director.can_say_local(id):return false
	var t:=template(wish.template_id);var ready: bool=not wish.proof_id.is_empty()
	if not ready and wish.announced:return false
	var text: String=config.complete_lines[world.director.routines[id].rng.randi_range(0,config.complete_lines.size()-1)] if ready else str(t.line)
	if not world.director.say_local(id,text,"wish_completed" if ready else "wish",float(config.personal_gap),float(config.village_gap)):return false
	world.director.routines[id].authored_reaction("watch")
	if ready:
		world.memories.record_event("wish_completed",wish.id,["human",id],{"wish_id":wish.id,"resident_id":id,"template_id":t.id,"title":t.title,"kind":t.kind,"target_id":wish.target_id,"proof_id":wish.proof_id})
		states[id].active={};count("completed",id)
	else:wish.announced=true
	world.revision+=1;return true
func saved() -> Dictionary:return {"version":1,"states":states.duplicate(true)}
func valid_saved(data: Variant,actors: Dictionary) -> bool:
	if not data is Dictionary or data.get("version")!=1 or not data.get("states") is Dictionary or data.states.size()>actors.size():return false
	for id in data.states:
		var state: Variant=data.states[id]
		if id=="human" or not actors.has(id) or not state is Dictionary or state.size()!=4 or not state.get("active") is Dictionary or not state.get("history") is Array or state.history.size()>2 or not state.history.all(func(key):return not template(str(key)).is_empty()):return false
		if not world.relationships.integer(state.get("last_created_day"),1000000) or state.last_created_day<1 or not world.relationships.integer(state.get("next_day"),1000003) or (state.next_day-state.last_created_day!=2 and state.next_day-state.last_created_day!=3):return false
		var wish: Dictionary=state.active
		if wish.is_empty():continue
		if wish.size()!=9 or not wish.get("id") is String or not wish.id.begins_with("wish-") or wish.id.length()!=29 or not wish.id.substr(5).is_valid_hex_number(false) or wish.get("resident_id")!=id or template(str(wish.get("template_id",""))).is_empty() or not wish.get("target_id") is String or wish.target_id.length()<1 or wish.target_id.length()>128:return false
		if not world.relationships.integer(wish.get("created_day"),1000000) or wish.created_day!=state.last_created_day or not world.relationships.integer(wish.get("expires_day"),1000014) or wish.expires_day-wish.created_day<1 or wish.expires_day-wish.created_day>14 or not wish.get("announced") is bool or not wish.get("baseline") is Array or wish.baseline.size()>512 or not wish.baseline.all(func(key):return key is String and key.length()<=128) or not wish.get("proof_id") is String or wish.proof_id.length()>128:return false
	return true
func restore(data: Dictionary) -> void:
	states=data.get("states",{}).duplicate(true);next_check=world.director.time+float(config.first_after)
	for state in states.values():
		if not state.active.is_empty():
			if world.days.day()>=int(state.active.expires_day):state.active={}
			else:state.active.proof_id=""
