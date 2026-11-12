extends Node
## Session-only plans. World owns movement; existing systems own every resource commit.
const Text=preload("res://scripts/localization.gd")
var host:WeakRef
var game:Node:
	get:return host.get_ref()
var world:RefCounted:
	get:return game.world
var plans:Dictionary={}
var history:Array=[]
var last_failure:Dictionary={}
const ACTIONS=["assemble","fish","light","roast","invite","plant","harvest","water","chop","gather","build","chess","go_to","wander","sit","lounge","pool","swing","hold_cat","pet_cat","stars","home","follow","unfollow","hand_over","stop"]
func setup(source:Node)->void:
	host=weakref(source)
	for station_id in world.barbecues:
		var bound_station:String=station_id
		world.barbecues[station_id].fireside.steward_human_authority=func(id):
			return game.steward.active and id==game.steward.manager and game.steward.body_director.human_accepted() and game.steward.body_director.batch.get("step",{}).get("target_id","")==bound_station
		world.barbecues[station_id].fireside.host_authority=func(id):
			var plan:Dictionary=plans.get(id,{})
			return game.steward.active and plan.get("sponsor","")==game.steward.manager and plan.get("session_generation",-1)==world.session_generation and plan.get("station_id","")==bound_station and plan.get("current",{}).get("action","") in ["light","roast","invite"]
	world.activities.command_busy=func(id):return plans.has(id) or plans.values().any(func(plan):return id in plan.get("gather_guests",[]) or plan.get("escorts",{}).has(id))
func negated(text:String)->bool:
	var probe:String=text.to_lower()
	return ["token_12","token_13","token_14","token_15","token_16"].any(func(key):return probe.contains(game.local_host_commands.parser.grammar(key))) or ["don't","do not","never"].any(func(word):return probe.contains(word))
func chat_only(text:String)->bool:
	var terms:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/resident-intentions.json"))
	var probe:String=text.to_lower()
	return terms._chat_markers.any(func(word):return probe.contains(str(word))) and not terms._request_overrides.any(func(word):return probe.contains(str(word)))
func is_request(text:String)->bool:
	if negated(text) or chat_only(text):return false
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
	var p:Dictionary=plans.get(id,{})
	for who in p.get("escorts",{}):
		var owned:Dictionary=p.escorts[who]
		if world._routes.has(who) and owned.has("route") and is_same(world._routes[who],owned.route):world._routes.erase(who)
	plans.erase(id)
func submit(id:String,steps:Array,channel:String,adopt:Dictionary={},sponsor:String="",material_account:Dictionary={})->Dictionary:
	if id=="human" or (not world.director.model_controlled(id) and (sponsor.is_empty() or not game.steward.authorized(sponsor))):return world._error("model_required")
	if sponsor.is_empty() and (game.steward.authorized(id) or steps.any(func(step):return step is Dictionary and (step.has("actor_ids") or step.has("assignments")))):return game.steward.assign(id,steps,channel)
	if steps.is_empty() or steps.size()>5:return world._error("invalid_intent_count")
	for step in steps:
		if not step is Dictionary or step.keys().any(func(k):return k not in ["action","text","target_id","item_id","crop_id","x","y","region_id","guest_ids","replace"]):return world._error("invalid_intention")
		if not str(step.get("action","")) in ACTIONS:return world._error("unknown_intention")
		for field in ["text","target_id","item_id","crop_id","region_id"]:
			if step.has(field) and (not step[field] is String or step[field].length()>400):return world._error("invalid_intention")
		if step.action in ["plant","harvest","water","chop","gather","hand_over"] and step.has("text") and not str(step.text).is_empty():
			var parsed:Dictionary=game.local_host_commands.parser.parse_command(world,step.text,[id])
			if not parsed.get("ok",false) or (parsed.actor_ids!=[id] and sponsor.is_empty()):return world._error("own_actor_only")
		if step.has("guest_ids") and step.action not in ["roast","invite","pool","lounge","swing","stars","chess","go_to"]:return world._error("invalid_intention")
		if step.has("guest_ids") and (not step.guest_ids is Array or step.guest_ids.size()>world.actors.size()-1 or step.guest_ids.size()!=Array(step.guest_ids.reduce(func(dict,who):dict[who]=true;return dict,{}).keys()).size() or step.guest_ids.any(func(who):return who=="human" or not world.actors.has(who))):return world._error("invalid_participant")
	if plans.has(id):return world._error("plan_busy")
	if game.steward.meal_locked(id) and not steps.all(func(step):return step.action=="stop"):return world._error("meal_in_progress")
	if game.questions.has(id) or game.group_questions.has(id) or (world.activities.members.has(id) and not (steps[0].action=="assemble" and adopt.get("job_id","")==world.work.jobs.get(id,{}).get("id","missing") and world.work.jobs.get(id,{}).get("intent")=="gather_residents")):return world._error("waiting_for_answer")
	if world.hunger.rank(id)>=3 and not (game.steward.active and steps.all(func(step):return step.action in ["light","roast","invite"])):return world._error("very_hungry")
	last_failure.erase(id)
	plans[id]={"steps":steps.duplicate(true),"index":0,"channel":channel,"current":{},"elapsed":0.0,"started":false,"session_generation":world.session_generation,"adopt":adopt.duplicate(true),"sponsor":sponsor,"materials":material_account,"return_follow":world.activities.following.has(id)}
	_next(id)
	return {"ok":true,"status":"accepted"} if plans.has(id) else {"ok":false,"error":last_failure.get(id,"rejected")}
func _note(id:String,action:String,result:String,channel_override:String="")->void:
	var row:Dictionary={"actor_id":id,"action":action,"result":result,"at":world.forest.clock}
	if plans.has(id) and plans[id].has("life_turn_key"):row.life_turn_key=plans[id].life_turn_key
	history.append(row)
	if history.size()>128:history.pop_front()
	var channel:String=plans.get(id,{}).get("channel",game.Channels.direct(id))
	if not channel_override.is_empty():channel=channel_override
	var label:String=Text.text("intent.action."+action) if Text.entries.has("intent.action."+action) else action
	var outcome:String=Text.text("intent.started")%label if result=="accepted" else Text.text("intent.completed")%label if result=="completed" else result
	if action=="fish" and result=="completed" and not world.fishing.held(id).is_empty():outcome=Text.text("intent.caught")%Text.content(str(world.fishing.describe(world.fishing.held(id)).species_name))
	game.call_deferred("_record_chat",channel,"",Text.resident(world,id)+" "+outcome,"execution")
func _fail(id:String,reason:String)->void:
	if game.steward.active:game.steward.body_director.failure(game,id,reason,plans.get(id,{}))
	last_failure[id]=reason
	var p:Dictionary=plans.get(id,{})
	if world.farms.active(id) and not str(p.get("farm_order_id","")).is_empty() and world.farms.orders.get(id,{}).get("host_order_id","")==p.farm_order_id:world.farms.pause(id)
	if not str(p.get("job_id","")).is_empty() and world.work.jobs.get(id,{}).get("id")==p.job_id:
		if world.farms.active(id):world.farms.pause(id)
		world.command(id,{"intent":"stop"})
	_note(id,str(plans.get(id,{}).get("current",{}).get("action","")),reason)
	var line:String=Text.text("intent.blocked")%reason
	game.local_host_commands.speech_queue.append({"actor_id":id,"line":line,"channel_id":plans.get(id,{}).get("channel",game.Channels.direct(id)),"expires":world.director.time+180})
	plans.erase(id)
func _free(id:String)->bool:
	return not world.work.jobs.has(id) and not world.farms.active(id) and not world.projects.active(id) and not world.homestead.active(id) and not world.activities.members.has(id)
func _prepare(id:String)->void:
	world.activities.pause_follow(id)
	world.director.routines[id].interrupt(0)
func _next(id:String)->void:
	if not plans.has(id):return
	var p:Dictionary=plans[id]
	if p.index>=p.steps.size():
		if not game.steward.active and not str(p.get("sponsor","")).is_empty() and p.steps.any(func(step):return step.action in ["chop","gather","plant","harvest","water","build"]) and not p.get("returning",false):
			p.returning=true;p.steps.append({"action":"go_to","target_id":"human"})
		else:
			if p.get("returning",false) and world.actors[id].region_id==world.actors.human.region_id and world.point(world.actors[id]).distance_to(world.point(world.actors.human))<=3:
				var line:String=Text.resident(world,id)+Text.text("steward.returned")
				game.steward.speak(str(p.sponsor),line,"",true,"work_returned")
				_note(id,"return","completed")
			if p.get("return_follow",false) and not game.steward.active and not world.work.jobs.has(id):world.activities.following[id]=true
			if not str(p.get("sponsor","")).is_empty() and p.steps.any(func(step):return step.action=="fish"):
				var held_fish:Dictionary=world.fishing.held(id)
				if not held_fish.is_empty():world.fishing.host_stock_nearest(str(held_fish.id))
			plans.erase(id);return
	if game.steward.meal_locked(id) and p.steps[p.index].action not in ["invite","stop"]:p.waiting_meal=true;return
	p.waiting_meal=false
	p.current=p.steps[p.index];p.index+=1;p.elapsed=0.0;p.started=false;p.job_id=""
	if p.current.action=="roast":p.erase("gather_fire")
	if p.index==1 and not p.adopt.is_empty():
		if world.work.jobs.get(id,{}).get("id","")!=p.adopt.get("job_id","") and world.farms.orders.get(id,{}).get("host_order_id","")!=p.adopt.get("farm_order_id",""):_fail(id,"stale_job");return
		p.job_id=str(p.adopt.get("job_id",""));p.position=world.point(world.actors[id]);p.activity=world.actors[id].activity;p.started=true;return
	if not p.sponsor.is_empty() and world.director.routines[id].owns_job():world.director.routines[id].interrupt(0)
	if p.current.action!="stop" and not _free(id):_fail(id,"busy");return
	_prepare(id)
	var step:Dictionary=p.current;var action:String=step.action
	if action=="roast" and step.get("item_id","")=="single:fish":step.item_id="fish"
	if action not in ["hold_cat","pet_cat"] and world.cat.carrier==id:world.cat.interact(id,"release")
	var held_fish:Dictionary=world.fishing.held(id)
	var needs_placement:bool=action not in ["light","invite","fish","go_to","wander","follow","unfollow","home","stop","roast"] or (action=="roast" and str(step.get("item_id","")).begins_with("single:"))
	if not held_fish.is_empty() and needs_placement:
		var stocked:=false
		for pen in world.fishing.pens:
			if world.fishing.command(id,{"intent":"stock_fish","fish_id":held_fish.id,"pen_id":pen}).get("ok",false):stocked=true;break
		if not stocked:_fail(id,"pending_fish");return
	var result:Dictionary={"ok":true}
	if action=="fish":
		var held:Variant=world.activities.held.get(id,false);world.activities.held.erase(id)
		result=world.fishing.invite_from_host_text([id],false)
		world.activities.held[id]=held
	elif action in ["light","roast","invite"]:
		var station_id:String=str(step.get("target_id",""))
		if station_id.is_empty():
			var distance:float=INF
			for key in world.barbecues:
				var station:Dictionary=world.barbecues[key].station
				var d:float=world.point(station).distance_squared_to(world.point(world.actors[id]))
				if station.region_id==world.actors[id].region_id and world.standard.ready(key) and d<distance:station_id=key;distance=d
		if not world.barbecues.has(station_id):_fail(id,"unbuilt_camp");return
		p.station_id=station_id
		var life:RefCounted=world.barbecues[station_id]
		var upcoming_roasts:Array=p.steps.slice(p.index).filter(func(next):return next.action=="roast")
		if action=="roast" or (action=="light" and not upcoming_roasts.is_empty()):
			var gathering_step:Dictionary=step if action=="roast" else upcoming_roasts[0]
			var future_roster:Array=p.steps.slice(p.index).filter(func(next):return next.action=="invite" and next.has("guest_ids"))
			var roster:Array=future_roster[0].guest_ids if not future_roster.is_empty() else world.actors.keys().filter(func(who):return who not in ["human",id])
			var guests:Array=gathering_step.get("guest_ids",roster).duplicate()
			p.gather_guests=[];p.gather_targets={}
			var seats:Array=life.seats()
			if seats.size()==8:seats=[seats[0],seats[4],seats[2],seats[6],seats[1],seats[5],seats[3],seats[7]]
			var seat_index:int=1
			for who in guests:
				if who==id or (world.hunger.rank(who)>=3 and not game.steward.active) or game.questions.has(who) or game.group_questions.has(who) or not life.fireside.can_invite([who]).ok:continue
				world.activities.pause_follow(who)
				world.director.routines[who].interrupt(0)
				var at:Vector2=world.point(seats[mini(seat_index,seats.size()-1)])
				seat_index+=1
				# Reserve this eligible guest before routing so the host's real plan pauses explicit follow.
				p.gather_guests.append(who)
				var arrival:Dictionary={"ok":true} if game.steward.active else world.command(who,{"intent":"move","region_id":life.station.region_id,"x":at.x,"y":at.y})
				if arrival.get("ok",false):p.gather_targets[who]={"at":at,"region":life.station.region_id}
				else:p.gather_guests.erase(who)
		if not life.fireside.near(id,5):
			result={"ok":false,"error":"unreachable"}
			for offset in [Vector2(0,3),Vector2(3,0),Vector2(-3,0),Vector2(0,-3)]:
				var at:Vector2=world.point(life.station)+offset
				if world.walkable(life.station.region_id,at) and world.command(id,{"intent":"move","region_id":life.station.region_id,"x":at.x,"y":at.y}).get("ok",false):result={"ok":true};break
	elif action in ["assemble","plant","harvest","water","chop","gather","hand_over"]:
		if world.resort.vacation(id):
			var plaza:Array=world.map_anchor("plaza.center")
			var at:=Vector2(plaza[0],plaza[1])+Vector2(0,3)
			result=world.command(id,{"intent":"move","region_id":"home","x":at.x,"y":at.y});p.labor_approach=true
		else:result=_labor(id,step,p.channel)

	elif action in ["go_to","home","wander","hold_cat","pet_cat","pool","lounge","swing","stars","sit"]:
		var at:Vector2=world.point(world.actors[id]);var region:String=world.actors[id].region_id
		if action in ["hold_cat","pet_cat"]:at=world.cat.position+Vector2(1,0);region=world.cat.region
		elif action in ["pool","lounge","swing","stars"]:
			var target:String=str(step.get("target_id",world.resort.nearest(action)))
			if not world.resort.activities.has(target):_fail(id,"unknown_resort_activity");return
			p.activity_id=target;at=world.point(world.resort.activities[target]);region="home"
			p.escorts={}
			for who in step.get("guest_ids",[]):
				if not _free(who) or world.hunger.rank(who)>=3 or game.questions.has(who) or game.group_questions.has(who) or world.activities.held.get(who,false):continue
				if world._routes.has(who) and not world.activities.following.has(who) and not world.director.routines[who].owns_route:continue
				world.activities.pause_follow(who);world.director.routines[who].interrupt(0)
				p.escorts[who]={}
				var followed:Dictionary=world.command(who,{"intent":"move","region_id":region,"x":at.x+2,"y":at.y})
				if followed.get("ok",false):p.escorts[who]={"route":world._routes.get(who,[])}
				else:p.escorts.erase(who)
		elif action=="home":
			for object in world.objects.values():
				if object.get("owner_id")==id and object.kind=="construction_site" and object.get("stage_index",0)==5:at=world.interior.outside("room."+object.id);region=object.region_id;break
		elif action=="wander":
			for offset in [Vector2(5,0),Vector2(0,5),Vector2(-5,0),Vector2(0,-5)]:
				if world.walkable(region,at+offset):at+=offset;break
		elif action=="sit":
			for site in world.leisure.sites.values():
				if (not step.has("target_id") or step.target_id==site.id) and site.complete and world.leisure.art(site).recreation.behavior=="sit":result=world.leisure.command(id,{"intent":"use_facility","target_id":site.id});p.job_id=result.get("job_id","");break
			if not p.has("job_id"):_fail(id,"unfinished_facility");return
		else:
			if step.has("target_id"):
				var target:Dictionary=world.actors.get(str(step.target_id),world.object_by_id(str(step.target_id)))
				if target.is_empty():_fail(id,"unknown_target");return
				at=world.point(target)+Vector2(0,2);region=target.get("region_id","home")
			elif step.has("x") and step.has("y"):
				if not world.catalog._number(step.x) or not world.catalog._number(step.y):_fail(id,"invalid_position");return
				at=Vector2(step.x,step.y);region=str(step.get("region_id",region))
			else:_fail(id,"missing_target");return
		if action=="go_to" and step.has("guest_ids"):
			p.escorts={}
			for who in step.guest_ids:
				if who==id or not _free(who) or world.hunger.rank(who)>=3 or game.questions.has(who) or game.group_questions.has(who) or world.activities.held.get(who,false):continue
				if world._routes.has(who) and not world.activities.following.has(who) and not world.director.routines[who].owns_route:continue
				world.activities.pause_follow(who);world.director.routines[who].interrupt(0)
				var destination:Vector2=at+Vector2(2,0)
				p.escorts[who]={}
				var moved:Dictionary=world.command(who,{"intent":"move","region_id":region,"x":destination.x,"y":destination.y})
				if moved.get("ok",false):p.escorts[who]={"route":world._routes.get(who,[]),"destination":destination,"region_id":region}
				else:p.escorts.erase(who)
		if action!="sit":result=world.command(id,{"intent":"move","region_id":region,"x":at.x,"y":at.y})
	elif action in ["follow","unfollow","stop"]:
		result=world.command(id,{"intent":action})
	elif action=="build":
		var template:String=str(step.get("target_id",game.steward.missing_facility()))
		if not game.steward.reserve_materials(p.materials,id,game.steward.material_cost(id,step),[p.current]+p.steps.slice(p.index),p.channel):_fail(id,"confirmation_required");return
		if world.leisure.sites.has(template):
			result=world.command(id,{"intent":"build_facility","target_id":template})
		else:
			if template not in world.their_island.config.templates:_fail(id,"unknown_template");return
			var anchor:=Vector2.ZERO
			for territory in world.home_island.config.their_island.territories:
				if territory.owner_id==id:anchor=Vector2(territory.anchor[0],territory.anchor[1])
			result={"ok":false,"error":"no_available_project_site"}
			var offsets:Array=[Vector2(0,-30),Vector2(0,-12),Vector2(0,12),Vector2(0,-24),Vector2(0,24),Vector2(6,0),Vector2(-6,0)]
			for y in range(178,251,3):
				for x in range(int(anchor.x)-8,int(anchor.x)+9,3):offsets.append(Vector2(x,y)-anchor)
			for offset in offsets:
				var at:Vector2=anchor+offset
				result=world.their_island.propose(id,{"template_id":template,"x":at.x,"y":at.y,"name":Text.resident(world,id)+" · "+template,"reason":Text.text("intent.build_reason")},true,true)
				if result.get("ok",false):break
			if result.get("ok",false):result=world.their_island.decide(id,result.proposal_id,"accept",true)
	elif action=="chess":
		var site:Dictionary=world.gomoku.table(str(step.get("target_id","play.gomoku")))
		if site.is_empty() or not site.complete:_fail(id,"unfinished_facility");return
		var entry:Array=world.leisure.art(site).recreation.entry
		var at:Vector2=world.point(site)+Vector2(entry[0],entry[1])
		result=world.command(id,{"intent":"move","region_id":"home","x":at.x,"y":at.y});p.chess_pending=true
	if not result.get("ok",false):_fail(id,str(result.get("message",result.get("error","rejected"))));return
	p.job_id=str(world.work.jobs.get(id,{}).get("id",""))
	p.position=world.point(world.actors[id]);p.activity=world.actors[id].activity
	_note(id,action,"accepted")
func _labor(id:String,step:Dictionary,channel:String)->Dictionary:
	var action:String=step.action
	if action in ["plant","harvest"] and not plans.get(id,{}).get("sponsor","").is_empty():
		var mode:String="plant" if action=="plant" else "ready"
		var preview:Dictionary=world.farms.preview_host_orders([id],mode,str(step.get("target_id","")),str(step.get("crop_id","mixed")))
		var result:Dictionary=world.farms.confirm_host_orders(preview,[id])
		var accepted:Array=result.get("rows",[]).filter(func(row):return row.get("ok",false))
		if not accepted.is_empty():plans[id].farm_order_id=str(world.farms.orders.get(id,{}).get("host_order_id",""))
		return {"ok":true} if not accepted.is_empty() else world._error("farm_unavailable")
	var text:String=str(step.get("text",""))
	if text.is_empty():text={"assemble":Text.source("content.steward.command.assemble"),"plant":preload("res://scripts/localization.gd").source("content.v06.text.3e0da8855fa512")+(" "+str(step.crop_id) if step.get("crop_id","mixed")!="mixed" else ""),"harvest":preload("res://scripts/localization.gd").source("content.v06.text.6567f52a152abf"),"water":preload("res://scripts/localization.gd").source("content.v06.text.22f8fe6abe8667"),"chop":"chop 1 tree","gather":"forage","hand_over":"hand over"}[action]
	if action in ["plant","harvest","water"] and step.has("target_id"):
		if not world.farms.farms.has(step.target_id):return world._error("unknown_farm")
		text+=" "+str(world.farms.farms[step.target_id].name)
	var parsed:Dictionary=game.local_host_commands.parser.parse_command(world,text,[id])
	if not parsed.get("ok",false) or (parsed.actor_ids!=[id] and plans.get(id,{}).get("sponsor","").is_empty()):return world._error("own_actor_only")
	if not plans.get(id,{}).get("sponsor","").is_empty() and not str(parsed.get("next_text","")).is_empty():return world._error("use_structured_steps")
	var held:Variant=world.activities.held.get(id,false);world.activities.held.erase(id)
	game.local_host_commands.submit(text,[id],channel,[id],[id] if not plans.get(id,{}).get("sponsor","").is_empty() else [],plans.get(id,{}).get("materials",{}),{id:str(step.target_id)} if action in ["chop","gather"] and step.has("target_id") else {})
	world.activities.held[id]=held
	var result:Dictionary=game.local_host_commands.last_execution.duplicate(true)
	if result.get("ok",false) and action=="water":plans[id].farm_order_id=str(world.farms.orders.get(id,{}).get("host_order_id",""))
	return result if not result.is_empty() else {"ok":false,"error":"confirmation_required"}
func advance(delta:float)->void:
	if delta<=0:return
	for id in plans.keys():
		var p:Dictionary=plans[id];var action:String=str(p.current.action)
		p.elapsed+=delta
		if game.questions.has(id) or game.group_questions.has(id) or (world.activities.members.has(id) and action!="assemble"):_note(id,action,"interrupted");cancel(id);continue
		if p.session_generation!=world.session_generation or (not p.sponsor.is_empty() and not game.steward.authorized(p.sponsor)) or (p.sponsor.is_empty() and not world.director.model_controlled(id)):plans.erase(id);continue
		if world.hunger.rank(id)>=3 and not (game.steward.active and action in ["light","roast","invite"]):_fail(id,"very_hungry");continue
		if p.get("waiting_meal",false):_next(id);continue
		if p.get("labor_approach",false) and not world._routes.has(id):
			p.labor_approach=false
			var result:Dictionary=_labor(id,p.current,p.channel)
			if not result.get("ok",false):_fail(id,str(result.get("error","rejected")));continue
			p.job_id=str(world.work.jobs.get(id,{}).get("id",""))
		var moving:bool=world.point(world.actors[id])!=p.position
		var doing:bool=world.actors[id].activity!=p.activity or float(world.work.jobs.get(id,{}).get("time",0))>0
		if (moving or doing) and not p.started:
			p.started=true
			history.append({"actor_id":id,"action":action,"result":"started","delay":p.elapsed,"at":world.forest.clock})
			if history.size()>128:history.pop_front()
		if action in ["light","roast","invite"] and not world._routes.has(id):
			var fire:RefCounted=world.barbecues[p.station_id].fireside
			if not fire.near(id,5):_fail(id,"unreachable");continue
			var future:Array=[p.current]+p.steps.slice(p.index)
			var priced:Dictionary=p.current.duplicate(true);priced.target_id=p.station_id
			if not game.steward.reserve_materials(p.materials,id,game.steward.material_cost(id,priced,p.steps.slice(p.index)),future,p.channel):_fail(id,"confirmation_required");continue
			var result:Dictionary={"ok":true}
			if action=="light":result=fire.light_host(true,id)
			else:
				var future_invites:Array=p.steps.slice(p.index).filter(func(step):return step.action=="invite" and step.has("guest_ids"))
				var default_guests:Array=future_invites[0].guest_ids if not future_invites.is_empty() else world.actors.keys().filter(func(who):return who!="human")
				var guests:Array=p.current.get("guest_ids",default_guests).duplicate()
				if id not in guests:guests.push_front(id)
				guests=guests.filter(func(who):return (world.hunger.rank(who)<3 or game.steward.active) and not game.questions.has(who) and not game.group_questions.has(who))
				if action=="roast":
					var fish:Dictionary=world.fishing.held(id)
					var food:String=str(p.current.get("item_id",""))
					if food.begins_with("fish:"):fish=world.fishing.fish.get(food.trim_prefix("fish:"),{})
					elif food=="fish" and fish.is_empty():
						var owned:Array=world.fishing.fish.values().filter(func(entry):return entry.owner_id==id and (entry.location=="storage" or world.fishing.pens.has(entry.location)))
						if not owned.is_empty():fish=owned[0]
					var direct:bool=not fish.is_empty() and not food.begins_with("single:") and not food.begins_with("recipe:")
					if direct:
						if not fire.direct_fish_available(fish,id) or not fire.valid_fish(fish,true,id):_fail(id,"fish_not_owned");continue
					elif fire.menu(id).filter(func(row):return row.id==str(p.current.get("item_id","single:mushroom")) and int(row.maximum)>0).is_empty():
						_fail(id,"missing_food");continue
					# Freeze the eligible roster selected before approaching; workers are never recruited later.
					guests=p.get("gather_guests",[]).duplicate()
					if id not in guests:guests.push_front(id)
					if not p.has("gather_fire"):
						var accepted:Array=guests.filter(func(who):return fire.can_invite([who]).ok or (direct and who==id))
						p.gather_fire={"at":world.forest.clock,"guests":accepted}
						# Approaching a new meal never reopens the completed meal's timer/circle.
						# The real grill commit owns its new invitation and seat jobs.
						if not game.steward.active:game.steward.speak(id,Text.text("content.overnight.text.d0a3c372b12813") if TranslationServer.get_locale().begins_with("zh") else "Come sit by the fire. I'll wait for everyone before grilling.")
					var missing:Array=[] if game.steward.active else p.gather_fire.guests.filter(func(who):return who!=id and (world._routes.has(who) or not p.gather_targets.has(who) or world.actors[who].region_id!=p.gather_targets[who].region or world.point(world.actors[who]).distance_to(p.gather_targets[who].at)>1.5))
					if not missing.is_empty() and world.forest.clock-float(p.gather_fire.at)<60:continue
					if not missing.is_empty():
						for who in missing:
							game.steward.speak(id,(Text.text("content.overnight.text.572176c7810b0c") if TranslationServer.get_locale().begins_with("zh") else "%s couldn't arrive in time; we'll start with those seated.")%Text.resident(world,who))
							fire.interrupt(who)
					guests=p.gather_fire.guests.filter(func(who):return who not in missing)
					if direct:result=fire.direct_grill(fish.id,id)
					else:
						var menu_id:String=str(p.current.get("item_id","single:mushroom"))
						var offered:Array=fire.menu(id).filter(func(row):return row.id==menu_id and int(row.maximum)>0)
						if offered.is_empty():result={"ok":false,"error":"missing_food"}
						elif not fire.burning():result=fire.light_host(true,id)
						if result.ok:
							fire.selected_guests=[]
							for who in guests:
								if fire.can_invite([who]).ok:fire.selected_guests.append(who)
							result=fire.roast_host(str(p.current.get("item_id","single:mushroom")),id)
				if action=="invite" and p.has("roast_meal"):
					if str(fire.state.current.get("id",""))!=p.roast_meal.id:result={"ok":false,"error":"meal_changed"}
					elif not p.current.has("guest_ids"):guests=guests.filter(func(who):return who in p.roast_meal.guests)
				if action=="invite" and (not fire.active() or fire.state.current.is_empty() or int(fire.state.current.eaten)+int(fire.state.current.wasted)>=int(fire.state.current.total)):result={"ok":false,"error":"no_waiting_food"}
				if action=="invite" and result.ok and not fire.waiting_meal() and guests.any(func(who):return who not in fire.state.invited):result={"ok":false,"error":"invitation_not_committed"}
				if result.ok and fire.waiting_meal():
					var accepted:Array=guests.filter(func(who):return fire.can_invite([who]).ok)
					result=fire.invite_direct(accepted)
			if action=="roast" and result.ok:
				p.roast_meal={"id":str(fire.state.current.get("id","")),"guests":fire.state.invited.duplicate()}
			if not result.ok:_fail(id,str(result.get("message",result.get("error","rejected"))));continue
			p.started=true;_note(id,action,"completed");_next(id);continue
		if action in ["hold_cat","pet_cat"] and not world._routes.has(id):
			if world.cat.interact(id,"hold" if action=="hold_cat" else "pet"):_note(id,action,"completed");_next(id)
			elif p.elapsed>=3 and not game._resident_chat_busy(id):_fail(id,"cat_unavailable")
			continue
		if action in ["pool","lounge","swing","stars"]:
			if (world._routes.has(id) or p.get("escorts",{}).keys().any(func(who):return world._routes.has(who))) and p.elapsed<60:continue
			for who in p.get("escorts",{}):
				if not world._routes.has(who) and _free(who) and not p.escorts[who].get("arrived",false):
					var joined:Dictionary=world.resort.begin(p.activity_id,[who])
					p.escorts[who].arrived=true
					_note(who,action,"accepted" if joined.ok else "unavailable",p.channel)
		if action in ["pool","lounge","swing","stars"] and not world._routes.has(id) and not world.work.jobs.has(id):
			var result:Dictionary=world.resort.begin(p.activity_id,[id])
			if not result.ok:_fail(id,str(result.get("rejected",{})));continue
			p.job_id=str(world.work.jobs[id].id);p.started=true
		if action in ["pool","lounge","swing","stars"] and not world.resort.using(id).is_empty() and p.get("escorts",{}).keys().all(func(who):return not world.resort.using(who).is_empty()):
			_note(id,action,"completed")
			if p.index<p.steps.size():world.work.stop(id,false);_next(id)
			else:plans.erase(id)
			continue
		if action=="chess":
			if game._resident_chat_busy(id) or world._routes.has(id) or world.director.routines[id].held:continue
			var table:String=str(p.current.get("target_id","play.gomoku"))
			var peers:Array=p.current.get("guest_ids",world.actors.keys().filter(func(who):return who not in ["human",id] and _free(who)))
			if peers.is_empty():_fail(id,"chess_unavailable");continue
			var peer:String=str(peers[0])
			var sources:Dictionary={};sources[id]=game.steward.body_director.chess_source(game,id) if game.steward.active else "model" if world.director.model_controlled(id) else "local";sources[peer]=game.steward.body_director.chess_source(game,peer) if game.steward.active else "model" if world.director.model_controlled(peer) else "local"
			var result:Dictionary=game.gomoku_match_host.begin(table,id,peer,sources)
			if not result.ok:_fail(id,str(result.get("error","chess_unavailable")));continue
			p.started=true;_note(id,action,"accepted");plans.erase(id);continue
		if p.elapsed>=3 and not p.started and action not in ["follow","unfollow","stop","invite"]:_fail(id,"not_started");continue
		var done:bool=false
		if action=="fish":done=not world.fishing.held(id).is_empty()
		elif action=="build":done=not world.their_island.running.has(id) and not world.work.jobs.has(id)
		elif action in ["plant","harvest"]:done=not world.farms.active(id)
		elif action in ["assemble","water","chop","gather","hand_over"]:done=not p.get("labor_approach",false) and not game.local_host_commands.tracked.any(func(row):return id in row.actors and id not in row.finished and id not in row.canceled and id not in row.returning)
		else:done=not world._routes.has(id) and not world.work.jobs.has(id)
		if done and action=="go_to":done=p.get("escorts",{}).keys().all(func(who):return not world._routes.has(who) and world.actors[who].region_id==p.escorts[who].region_id and world.point(world.actors[who]).distance_to(p.escorts[who].destination)<=1)
		if done and action in ["plant","harvest"] and world.farms.orders.get(id,{}).get("status")!="completed":_fail(id,"work_interrupted");continue
		if done and action in ["chop","gather","build","water"] and not str(p.job_id).is_empty():
			var receipts:Array=world.work.events.filter(func(event):return event.get("actor_id")==id and event.get("job_id")==p.job_id)
			if receipts.is_empty() or receipts.back().get("status")!="completed":_fail(id,"work_interrupted");continue
		if done:_note(id,action,"completed");_next(id)
