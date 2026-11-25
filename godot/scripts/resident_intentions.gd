extends Node
## Session-only plans. World owns movement; existing systems own every resource commit.
const ACTIONS=["chop","roast","invite","go_to","build","sit","fish"]
const Text=preload("res://scripts/localization.gd")
var host:WeakRef
var game:Node:
	get:return host.get_ref()
var world:RefCounted:
	get:return game.world
var plans:Dictionary={}
var history:Array=[]
var last_failure:Dictionary={}
func setup(source:Node)->void:
	host=weakref(source)
func negated(text:String)->bool:
	var probe:String=text.to_lower()
	return ["token_12","token_13","token_14","token_15","token_16"].any(func(key):return probe.contains(game.local_host_commands.parser.grammar(key))) or ["don't","do not","never"].any(func(word):return probe.contains(word))
func chat_only(text:String)->bool:
	var terms:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/resident-intentions.json"))
	var probe:String=text.to_lower()
	return terms._chat_markers.any(func(word):return probe.contains(str(word))) and not terms._request_overrides.any(func(word):return probe.contains(str(word)))
func is_request(text:String)->bool:
	if negated(text) or chat_only(text):return false
	if ["摆花","摆个","摆字","送我花","换花","arrange flowers","place a rose","give me a rose","trade roses"].any(func(term):return text.to_lower().contains(term)):return true
	var terms:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/resident-intentions.json"))
	return terms.keys().filter(func(key):return not str(key).begins_with("_")).any(func(key):return terms[key].any(func(word):return game.local_host_commands.parser._contains_alias(text.to_lower(),str(word))))
func understand(text:String,id:String)->Array:
	if negated(text) or chat_only(text):return []
	var probe:String=text.to_lower()
	var terms:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/resident-intentions.json"))
	var wanted:Array=[];var positions:Dictionary={}
	for action in terms:
		if str(action).begins_with("_"):continue
		for word in terms[action]:
			var at:int=probe.find(str(word))
			if at>=0 and game.local_host_commands.parser._contains_alias(probe,str(word)):
				if action not in wanted:wanted.append(action)
				positions[action]=mini(int(positions.get(action,100000)),at)
	wanted.sort_custom(func(left,right):return positions[left]<positions[right])
	var steps:Array=[]
	for action in wanted:
		if action=="go_to" and wanted.size()>1:continue
		var step:Dictionary={"action":action}
		if action=="roast" and (probe.contains(Text.source("hud.mushroom")) or "mushroom" in probe):step.item_id="single:mushroom"
		if action=="go_to":
			var shores:Array=world.fishing.nearby_shores(id,1)
			if not shores.is_empty():step.merge({"region_id":shores[0].region_id,"x":shores[0].position[0],"y":shores[0].position[1]})
			else:continue
		if action in ["pool","lounge","swing","stars","chess"]:
			var guests:Array=[]
			for who in world.actors:
				if who in ["human",id]:continue
				if probe.contains(Text.resident(world,who).to_lower()):guests.append(who)
			if not guests.is_empty():step.guest_ids=guests
		steps.append(step)
		if action=="roast" and "invite" not in wanted:steps.append({"action":"invite"})
	return steps.slice(0,5)

func cancel(id:String)->void:
	if plans.erase(id) and world.director.brains.has(id):
		var brain:RefCounted=world.director.brains[id]
		if brain.current.get("origin")=="native":brain.finish("interrupted","cancelled")

func submit(id:String,steps:Array,_channel:String,_adopt:Dictionary={})->Dictionary:
	if not world.director.model_controlled(id) or not world.director.brains.has(id) or steps.is_empty() or steps.size()>6 or plans.has(id):
		return world._error("resident_unavailable")
	if game.questions.has(id) or game.group_questions.has(id):return world._error("waiting_for_answer")
	var translated:Array=[]
	var original_indices:Array=[]
	for index in steps.size():
		var step:Variant=steps[index]
		if not step is Dictionary:return world._error("invalid_step")
		var target:Variant=step.get("target_id","")
		match step.get("action"):
			"chop":translated.append({"action":"chop_and_haul","target":target})
			"light":translated.append({"action":"native_light","target":target})
			"roast","invite":
				var guests:Variant=step.get("guest_ids",world.director.routines.keys().filter(func(who):return who!=id))
				if step.action=="roast" and not step.has("guest_ids"):
					for later in steps.slice(index+1):
						if later is Dictionary and later.get("action")=="invite" and later.has("guest_ids"):
							guests=later.guest_ids;break
				var meal:Dictionary={"action":"native_"+step.action,"target":target,"guests":guests}
				if step.action=="roast":meal.item=step.get("item_id","")
				translated.append(meal)
			"go_to":translated.append({"action":"go_to","target":target})
			"build":translated.append({"action":"build","target":target})
			"sit":translated.append({"action":"use","target":target})
			"fish":translated.append({"action":"fish"})
			"wander":translated.append({"action":"native_wander"})
			"home","follow","unfollow","stop","gather","hand_over","pet_cat","hold_cat","chess","stars":
				translated.append({"action":"native_own","operation":step.action,"target":target})
			"plant","water","harvest":
				translated.append({"action":"native_field","operation":step.action,"target":target,"crop":step.get("crop_id","")})
			"arrange_flowers","gift_flower":
				translated.append({"action":"native_flower","operation":step.action,"color":step.get("color","red"),"text":step.get("text",""),"pattern":step.get("pattern","")})
			"pool","lounge","swing":
				last_failure[id]="unknown_resort_activity"
				return world._error("unknown_resort_activity")
			_:return world._error("unsupported_step")
		original_indices.append(index)
	if translated.is_empty():return world._error("invalid_step")
	var basic:RefCounted=world.director.brains[id].intention.basic
	var key:=str(Time.get_ticks_usec())
	if not basic.accept({"reason":"Resident plan","steps":translated},"native",key):return world._error("resident_busy")
	last_failure.erase(id)
	plans[id]={"id":key,"steps":steps.duplicate(true),"index":0,"mapped":original_indices,"generation":world.session_generation,"current":steps[0].duplicate(true)}
	if translated[0].action=="fish":basic.start_native_fishing()
	return {"ok":true,"status":"accepted"}

func advance(_delta:float)->void:
	for id in plans.keys():
		var plan:Dictionary=plans[id]
		if plan.generation!=world.session_generation:
			plans.erase(id)
			continue
		var brain:RefCounted=world.director.brains[id]
		var result:Dictionary=brain.intention.basic.result
		var running:bool=brain.current.get("action_id")==plan.id
		var matched:bool=result.get("id")==plan.id
		var completed:int=int(brain.current.index) if running else int(result.get("steps",result.get("step",0))) if matched else 0
		while plan.index<completed and plan.index<plan.mapped.size():
			var step:Dictionary=plan.steps[plan.mapped[plan.index]]
			_record(id,plan,str(step.action),"completed")
			plan.index+=1
		plan.current=plan.steps[plan.index].duplicate(true) if plan.index<plan.steps.size() else {}
		plan.station_id=str(brain.current.get("meal_station","")) if running else plan.get("station_id","")
		if running:continue
		if not matched or result.get("status")!="completed":
			last_failure[id]=str(result.get("error","interrupted")) if matched else "interrupted"
			if plan.index<plan.mapped.size():_record(id,plan,str(plan.steps[plan.mapped[plan.index]].action),last_failure[id])
		plans.erase(id)

func _record(id:String,plan:Dictionary,action:String,result:String)->void:
	history.append({"actor_id":id,"action":action,"result":result,"at":world.forest.clock,"life_turn_key":plan.get("life_turn_key","")})
	if history.size()>64:history.pop_front()
