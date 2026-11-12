extends RefCounted
## One session director. All body commands use World or the original intention executor.
var tasks:Dictionary={}
var batch:Dictionary={}
var issuing:=false
var next_check:=0.0
var next_question:=0.0
var question_until:=0.0
var card:PanelContainer
var invitation_card:PanelContainer
var selected:=""
var faults:Array=[]
var failures:Dictionary={}
var questions:=0
var answers:=0
var reports:=0
var invitations:=0
var ai_ignored:=0
var ai_used:=0
var rest_until:=0.0
var paused:Dictionary={}
var history:Array=[]
var receipts:Array=[]
var preferences:Dictionary={}
var ai_choice:=""
var question_options:Array=[]
var invitation_for:=""
var invitation_answer:=false
var invitation_deadline:=0.0
var invited:Dictionary={}
var serial:=0
var spoken:Dictionary={}
var audit_seen:=0
var reported_goals:Dictionary={}
var owner_visit:=false
var closing:=false
var formation_center:=Vector2.INF
var formation_slots:Dictionary={}
func reset()->void:
	closing=false;formation_center=Vector2.INF;formation_slots.clear()
	reported_goals.clear();tasks.clear();batch.clear();paused.clear();preferences.clear();failures.clear();faults.clear();history.clear();receipts.clear();invited.clear();spoken.clear()
	invitation_for="";invitation_deadline=0;owner_visit=false;next_check=0;next_question=0;question_until=0;rest_until=0;questions=0;answers=0;reports=0;invitations=0;ai_ignored=0;ai_used=0;serial=0;audit_seen=0
	if is_instance_valid(card):card.queue_free()
	if is_instance_valid(invitation_card):invitation_card.queue_free()
func begin(g:Node)->void:
	g.world.deliveries.party=g.steward.Pool.IDS.duplicate()
	next_question=g.world.forest.clock+float(g.steward.trace_config.owner_question_seconds)
	for goal in g.world.standard.goals.rows(g.world):
		if goal.done:reported_goals[goal.id]=true
	for id in g.steward.Pool.IDS:
		g.world.hunger.clear_follow(id)
		g.world.activities.suspended_follow[id]=true
		g.world.director.routines[id].interrupt(0)
		if g.world.work.jobs.has(id) or g.world.farms.active(id):paused[id]=g.world.forest.clock
func end(g:Node)->void:
	g.world.deliveries.party.clear()
	if not batch.is_empty() and batch.step.action=="play" and not g.playground.kind.is_empty():g.playground.stop()
	for id in tasks.keys():
		if tasks[id].get("source")==preload("res://scripts/localization.gd").source("content.v06.text.b70a891cbab1ea"):continue
		if tasks[id].has("owned_job") and g.world.work.jobs.get(id,{}).get("id")==tasks[id].owned_job:g.world.work.stop(id,false)
		release(g,id,"host_stop")
	if is_instance_valid(card):card.queue_free()
	if is_instance_valid(invitation_card):invitation_card.queue_free()
	invitation_for="";invitation_deadline=0;owner_visit=false
	for id in g.steward.Pool.IDS:g.world.activities.suspended_follow.erase(id)
	question_until=0;batch.clear();tasks.clear()
func note(g:Node,kind:String,details:Dictionary)->void:
	var row:Dictionary=details.duplicate(true);row.kind=kind;row.clock=g.world.forest.clock;row.day=g.world.days.day()
	history.append(row)
	if history.size()>4096:history.pop_front()
	g.steward.trace(kind,details)
func say(g:Node,kind:String,arg:String="")->void:
	var id:String=g.steward.manager
	var tag:String=g.world.intelligence.tag(id)
	var language:String="en" if TranslationServer.get_locale().begins_with("en") else "zh"
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/steward-director-speech.json"))
	var lines:Array=data.get(tag,data.gentle).get(kind,data.gentle.report)[language]
	for template in lines:
		var line:String=str(template).replace("{choice}",arg)
		var key:String=str(g.world.days.day())+":"+id+":"+kind+":"+line
		if spoken.has(key):continue
		spoken[key]=true;g.steward.speak(id,line,"",true,"steward_local");return
func idle(g:Node,id:String)->bool:
	var w:RefCounted=g.world
	return id not in g.playground.members and not paused.has(id) and not g.intentions.plans.has(id) and not g.intentions.plans.values().any(func(plan):return plan.get("escorts",{}).has(id) or id in plan.get("gather_guests",[])) and not w.work.jobs.has(id) and not w.farms.active(id) and not w.deliveries.active(id) and not w.projects.active(id) and not w.activities.members.has(id) and not w.activities.held.get(id,false) and not g.questions.has(id) and not g.group_questions.has(id) and (not g._resident_chat_busy(id) or g.steward.pending.get("id","")==id) and not g.steward.meal_locked(id)
func task(g:Node,id:String,action:String,source:String="")->Dictionary:
	if source.is_empty():source=preload("res://scripts/localization.gd").source("content.v06.text.0f98f12cf3aa27")
	serial+=1
	var row:Dictionary={"id":serial,"action":action,"source":source,"start":g.world.forest.clock,"last_move":g.world.forest.clock,"position":g.world.point(g.world.actors[id]),"points":[],"goal":batch.get("goal",{}).get("id",""),"traveling":false}
	if not batch.is_empty():batch.last_progress=g.world.forest.clock
	tasks[id]=row;note(g,"task_start",row.merged({"actor":id}));return row
func release(g:Node,id:String,reason:String)->void:
	var w:RefCounted=g.world
	if g.intentions.plans.get(id,{}).get("sponsor","")==g.steward.manager:
		g.intentions._fail(id,reason)
	elif tasks.get(id,{}).get("route")!=null and is_same(tasks[id].route,w._routes.get(id,[])):
		w._routes.erase(id);w.actors[id].activity="idle"
	if tasks.has(id):note(g,"task_end",{"actor":id,"task":tasks[id],"result":reason})
	tasks.erase(id)
func failure(g:Node,id:String,reason:String,plan:Dictionary)->void:
	var job_id:String=str(plan.get("job_id",""))
	var events:Array=g.world.work.events.filter(func(e):return e.get("job_id")==job_id and e.get("actor_id")==id)
	var stops:Array=g.world.work.stop_audit.filter(func(e):return e.job_id==job_id and e.actor==id)
	var row:Dictionary={"actor":id,"action":plan.get("current",{}),"reason":reason,"receipts":events,"stops":stops,"goal":batch.get("goal",{}).get("id","")}
	note(g,"intention_failed",row);receipts.append(row)
	if not batch.is_empty():batch.failed=reason
func player_order(g:Node,ids:Array)->void:
	if ids.any(func(id):return id in g.playground.members):g.playground.stop()
	for id in ids:
		if id=="human" or id not in g.steward.Pool.IDS:continue
		release(g,id,"player_command")
		if g.world.gomoku.active(id):g.world.gomoku.pause_actor(id)
		paused[id]=g.world.forest.clock;task(g,id,"player_command",preload("res://scripts/localization.gd").source("content.v06.text.b70a891cbab1ea"))
	if not batch.is_empty():batch.failed="player_command"
func safe(g:Node,at:Vector2,region:String="home",radius:int=12)->Vector2:
	if g.world.walkable(region,at):return at
	for r in range(1,radius+1):
		for i in 16:
			var point:Vector2=at+Vector2.from_angle(TAU*i/16)*r
			if g.world.walkable(region,point):return point
	return Vector2.INF
func move(g:Node,id:String,at:Vector2,action:String="regroup",region:String="home")->bool:
	if not idle(g,id):return false
	var target:Vector2=safe(g,at,region)
	if not target.is_finite():return false
	var old:Dictionary=tasks.get(id,{})
	if g.world._routes.has(id) and old.get("route")!=null and is_same(old.route,g.world._routes[id]):return true
	g.world.activities.pause_follow(id)
	g.world.activities.suspended_follow[id]=true
	var result:Dictionary=g.world.command(id,{"intent":"move","region_id":region,"x":target.x,"y":target.y})
	if not result.get("ok",false):
		note(g,"route_rejected",{"actor":id,"error":result,"target":target})
		if not batch.is_empty():batch.failed="unreachable"
		return false
	var own:Dictionary=task(g,id,action)
	own.route=g.world._routes.get(id,[]);own.target=target;own.region=region;own.traveling=true
	return true
func slot(g:Node,id:String,center:Vector2)->Vector2:
	var index:int=g.steward.Pool.IDS.find(id)
	for radius in [4,6,8]:
		for i in 8:
			var at:Vector2=center+Vector2.from_angle(TAU*(index*2+i)/8)*radius
			if not g.world.walkable("home",at):continue
			var conflict:=false
			if not batch.is_empty() and batch.get("step",{}).action=="build":
				var site:Dictionary=g.world.leisure.sites.get(batch.step.get("target_id",""),{})
				if not site.is_empty():
					for box in g.world.leisure.art(site).recreation.obstacles:
						if Rect2(g.world.point(site)+Vector2(box[0],box[1]),Vector2(box[2],box[3])).grow(1).has_point(at):conflict=true
			if not conflict and (g.world.point(g.world.actors[id]).distance_to(at)<.2 or not g.world.find_route(id,at).is_empty()):return at
	return safe(g,center)
func regroup(g:Node,center:Vector2,leader_moves:bool=false)->bool:
	if not formation_center.is_finite() or formation_center.distance_to(center)>4:
		formation_center=center;formation_slots.clear()
	var ready:=true
	for id in g.steward.Pool.IDS:
		if paused.has(id):continue
		if id==g.steward.manager and not leader_moves:continue
		var w:RefCounted=g.world
		var distance:float=w.point(w.actors[id]).distance_to(center)
		if w.actors[id].region_id!="home" or distance>8:
			ready=false
			if not formation_slots.has(id):formation_slots[id]=center if id==g.steward.manager else slot(g,id,formation_center)
			if w.point(w.actors[id]).distance_to(formation_slots[id])>.5:move(g,id,formation_slots[id],"travel")
		elif w._routes.has(id):ready=false
	return ready
func candidates(g:Node)->Array:
	var w:RefCounted=g.world
	var options:Array=[]
	if w.standard.ready("home.barbecue"):
		for row in w.barbecues["home.barbecue"].fireside.menu(g.steward.manager):
			if int(row.maximum)>0 and row.ingredients.keys().all(func(item):return item=="fish" or w.storage.count(item)>=int(row.ingredients[item])):options.append({"id":"food:"+str(row.id),"text":str(row.get("name",row.id)),"kind":"food","value":row.id})
	if options.size()<2:
		options=[]
		for crop in ["turnip","tomato"]:
			if w.storage.count("seed."+crop)>0:options.append({"id":"crop:"+crop,"text":g.LocalText.content(str(w.farms.crops[crop].name)),"kind":"crop","value":crop})
	if options.size()<2:
		options=[{"id":"game:handkerchief","text":g.LocalText.text("play.handkerchief"),"kind":"game","value":"handkerchief"},{"id":"game:eagle","text":g.LocalText.text("play.eagle"),"kind":"game","value":"eagle"}]
	return options.slice(0,3)
func suggest(g:Node,id:String,reason:String)->void:
	var options:Array=candidates(g).filter(func(row):return row.id==id)
	if options.is_empty():ai_ignored+=1;note(g,"ai_suggestion_ignored",{"id":id});return
	ai_choice=id;ai_used+=1;note(g,"ai_preference",{"id":id,"reason":reason.left(120)})
func resolve(g:Node,timed_out:bool)->void:
	var choices:Array=question_options.filter(func(row):return row.id==selected)
	if choices.is_empty():return
	var choice:Dictionary=choices[0]
	preferences[choice.kind]=choice.value;preferences[choice.kind+"_source"]=preload("res://scripts/localization.gd").source("content.v06.text.4b61a0e70c4a2c") if timed_out and choice.id==ai_choice else preload("res://scripts/localization.gd").source("content.v06.text.0f98f12cf3aa27");answers+=1;question_until=0
	if is_instance_valid(card):card.hide()
	note(g,"owner_answer",{"selected":selected,"timeout":timed_out,"label":choice.text});say(g,"default",choice.text)
func question(g:Node)->void:
	question_options=candidates(g)
	var index:int=1 if g.world.intelligence.tag(g.steward.manager) in ["lively","laborious"] else 0
	selected=question_options[mini(index,question_options.size()-1)].id
	if question_options.any(func(row):return row.id==ai_choice):selected=ai_choice
	questions+=1;question_until=g.world.forest.clock+float(g.steward.trace_config.owner_answer_seconds)
	if is_instance_valid(card):card.queue_free()
	card=PanelContainer.new();g.island_hud.add_child(card);card.position=Vector2(360,150)
	var body:=VBoxContainer.new();card.add_child(body)
	var label:=Label.new();label.text=preload("res://scripts/localization.gd").source("content.v06.text.ad86779c051723") if TranslationServer.get_locale().begins_with("zh") else "Which would you like this time?";body.add_child(label)
	for option in question_options:
		var button:=Button.new();button.text=option.text;body.add_child(button)
		var choice:String=option.id
		button.pressed.connect(func():selected=choice;resolve(g,false))
	style_card(card)
	note(g,"owner_question",{"question":label.text,"options":question_options,"default":selected});say(g,"question")
func chess_source(g:Node,id:String)->String:
	# Select an existing leisure preset. Neither the engine's strength nor match budget changes.
	return "local_easy" if g.world.intelligence.tag(id) in ["gentle","lively"] else "local_normal"
func human_accepted()->bool:return not batch.is_empty() and invited.get(batch.key,false)
func invite(g:Node,key:String)->bool:
	if invited.has(key):return true
	if invitation_for!=key:
		invitation_for=key;invitation_answer=false;invitations+=1
		invitation_deadline=g.world.forest.clock+15
		if is_instance_valid(invitation_card):invitation_card.queue_free()
		invitation_card=PanelContainer.new();g.island_hud.add_child(invitation_card);invitation_card.position=Vector2(360,150)
		var body:=VBoxContainer.new();invitation_card.add_child(body)
		var title:=Label.new();title.text=preload("res://scripts/localization.gd").source("content.v06.text.dea88c7d13b91d") if TranslationServer.get_locale().begins_with("zh") else "Would you like to join us?";body.add_child(title)
		for yes in [true,false]:
			var button:=Button.new();button.text=(preload("res://scripts/localization.gd").source("content.v06.text.f867f34178594f") if yes else preload("res://scripts/localization.gd").source("content.v06.text.59275de2fad284")) if TranslationServer.get_locale().begins_with("zh") else ("Yes" if yes else "Not now");body.add_child(button)
			var accept:bool=yes
			button.pressed.connect(func():
				if invitation_for!=key:return
				invitation_answer=accept;invited[key]=accept;invitation_card.hide()
				if accept and not batch.is_empty():
					var at:Vector2=safe(g,batch.at+Vector2(0,2))
					g.world.command("human",{"intent":"move","region_id":"home","x":at.x,"y":at.y})
				note(g,"owner_invitation_answer",{"key":key,"accepted":accept,"timeout":false}))
		style_card(invitation_card)
		note(g,"owner_invitation",{"key":key});say(g,"invite")
	if g.world.forest.clock>=invitation_deadline:
		invited[key]=false;invitation_card.hide();note(g,"owner_invitation_answer",{"key":key,"accepted":false,"timeout":true})
	return invited.has(key)
func choose(g:Node)->Dictionary:
	var w:RefCounted=g.world
	var manager:String=g.steward.manager
	if g.steward.Pool.IDS.any(func(id):return w.hunger.rank(id)>=2) and w.standard.ready("home.barbecue"):
		return {"goal":{"id":"hunger","text":g.LocalText.text("watch.hungry")},"intents":[{"action":"roast","target_id":"home.barbecue","item_id":"single:mushroom","guest_ids":g.steward.Pool.IDS.filter(func(id):return id!=manager)}]}
	var clear_night:bool=w.days.phase().id=="night" and w.weather.current().id not in ["rain","fog"] and w.standard.goals.proof(w,"game")
	var proposal:Dictionary=g.steward.tutorial_planner.plan(g,"moon" if clear_night and not w.standard.board_completed.has("goal.moon") else "")
	if not proposal.is_empty() and proposal.get("intents",[]).any(func(step):return step.action=="chess") and g.steward.Pool.IDS.any(func(id):return w.hunger.rank(id)>=1):
		return {"goal":{"id":"hunger","text":g.LocalText.text("watch.hungry")},"intents":[{"action":"roast","target_id":"home.barbecue","item_id":"single:mushroom","guest_ids":g.steward.Pool.IDS.filter(func(id):return id!=manager)}]}
	if not proposal.is_empty() and proposal.get("intents",[]).any(func(step):return step.action=="chess"):
		var chess_step:Dictionary=proposal.intents[0]
		var table:Dictionary=w.gomoku.table(chess_step.target_id)
		var helper_sources:Array=w.objects.values().filter(func(o):return o.kind=="tree" and o.status=="mature" and o.region_id=="home" and not w.resort.retired(o) and not w.work.claims.has(o.id) and w.point(o).distance_to(w.point(table))<=10)
		helper_sources.append_array(w.all_mushrooms().values().filter(func(o):return o.region_id=="home" and o.id in w.standard.config.forage_ids and int(o.get("amount",0))>0 and not w.work.claims.has(o.id) and w.point(o).distance_to(w.point(table))<=10))
		if helper_sources.size()<2:
			# A two-player table is not a whole-team assignment when no real side
			# work exists. Defer it, and choose another existing goal/shared game.
			g.steward.tutorial_planner.retry[proposal.goal.id]=w.forest.clock+30
			return choose(g)
	if not proposal.is_empty() and int(failures.get(proposal.goal.id,0))>=2:return {}
	# When the next goal needs time or night, spend that time actually playing together.
	if proposal.is_empty():
		return {"goal":{"id":"free_play","text":g.LocalText.text("play.handkerchief")},"game":str(preferences.get("game","handkerchief"))}
	return proposal
func start_batch(g:Node,proposal:Dictionary)->void:
	var step:Dictionary={"action":"play"} if proposal.has("game") else proposal.intents[0].duplicate(true)
	var at:Vector2=g.world.point(g.world.actors[g.steward.manager])
	var target:String=str(step.get("target_id",""))
	var w:RefCounted=g.world
	if step.action=="build":
		var site:Dictionary=w.leisure.sites.get(target,{})
		if site.is_empty():return
		var config:Dictionary=w.leisure.art(site).recreation
		if config.get("game")=="gomoku" and not site.complete and int(site.invested)==0 and site.get("artwork",{}).is_empty() and not w.work.claims.has(site.id):
			# Search beside live resource clusters across this region, before any
			# investment. A finished/part-built table is never relocated.
			var origin:Array=site.position.duplicate()
			var best:Array=[];var best_score:=1;var best_distance:=INF
			var trees:Array=w.objects.values().filter(func(o):return o.kind=="tree" and o.status=="mature" and o.region_id==site.region_id and not w.resort.retired(o) and not w.work.claims.has(o.id))
			var centers:Array=[w.point(site)]
			for tree in trees:
				for radius in [6,8,10]:
					for angle in 8:centers.append(w.point(tree)+Vector2.from_angle(TAU*angle/8)*radius)
			var manager_at:Vector2=w.point(w.actors[g.steward.manager])
			var entry_offset:=Vector2(config.entry[0],config.entry[1])
			var manager_seat:=Vector2(config.slots[0][0],config.slots[0][1])
			for candidate:Vector2 in centers:
				# Match both choose()'s table range and supply_helpers()'s seated
				# leader range; do the cheap resource bound before geometry/path work.
				var available:int=trees.filter(func(o):return w.point(o).distance_to(candidate)<=10 and w.point(o).distance_to(candidate+manager_seat)<=10).size()
				var distance:float=manager_at.distance_squared_to(candidate+entry_offset)
				if available<2 or available<best_score or (available==best_score and distance>=best_distance):continue
				var probe:Dictionary=site.duplicate(true);probe.position=[candidate.x,candidate.y]
				if w.resort.retired(probe) or not w.leisure.chess_space_clear(probe,config):continue
				var entry_point:Vector2=candidate+entry_offset
				if not w.walkable(site.region_id,entry_point):continue
				if manager_at.distance_to(entry_point)>.5 and w.find_route(g.steward.manager,entry_point).is_empty():continue
				best_score=available;best_distance=distance;best=probe.position.duplicate()
			# Do not fall through to the old near-manager empty-ground fallback:
			# that freezes a resource-free table which choose() can never schedule.
			if best.is_empty():
				g.steward.tutorial_planner.retry[proposal.goal.id]=w.forest.clock+30
				return
			site.position=best
			if site.position!=origin:note(g,"site_relocated",{"site":site.id,"from":origin,"to":best,"helper_trees":best_score})
		if config.get("game")=="gomoku" and not site.complete and not w.leisure.chess_space_clear(site,config):
			if int(site.invested)>0:return
			var original:Array=site.position.duplicate()
			var found:=false
			for radius in [6,10,14,18]:
				for angle in 16:
					var candidate:Vector2=w.point(w.actors[g.steward.manager])+Vector2.from_angle(TAU*angle/16)*radius
					site.position=[candidate.x,candidate.y]
					if not w.resort.retired(site) and w.leisure.chess_space_clear(site,config):found=true;break
				if found:break
			if not found:site.position=original;return
			note(g,"site_relocated",{"site":site.id,"from":original,"to":site.position})
		var entry:Array=config.entry
		at=safe(g,w.point(site)+Vector2(entry[0],entry[1]))
	elif step.action in ["plant","harvest","water"]:
		if not w.farms.ready(target):return
		at=safe(g,Vector2(w.farms.farms[target].entrance[0],w.farms.farms[target].entrance[1]))
	elif step.action=="fish":
		var coast:Dictionary=w.fishing.contiguous_shores(g.steward.manager,g.steward.Pool.IDS)
		if coast.is_empty():return
		w.fishing.team_shores=coast
		at=Vector2(coast[g.steward.manager].position[0],coast[g.steward.manager].position[1])
	elif step.action=="stars":at=w.point(w.resort.activities[w.resort.nearest("stars")])
	elif step.action in ["light","roast"]:at=safe(g,w.point(w.barbecues[target].station)+Vector2(0,3))
	elif step.action=="chess":
		var site:Dictionary=w.gomoku.table(target)
		if site.is_empty():return
		var entry:Array=w.leisure.art(site).recreation.entry
		at=safe(g,w.point(site)+Vector2(entry[0],entry[1]))
	elif step.action=="chop":
		# Pick a real cluster for the whole team, not the nearest remaining lone tree.
		var trees:Array=w.objects.values().filter(func(o):return o.kind=="tree" and o.status=="mature" and o.region_id=="home" and not w.resort.retired(o) and not w.work.claims.has(o.id))
		trees.sort_custom(func(a,b):return w.point(a).distance_squared_to(at)<w.point(b).distance_squared_to(at))
		var best_count:=-1
		for tree in trees:
			var entry:Vector2=safe(g,w.point(tree)+Vector2(0,2))
			if not entry.is_finite():continue
			var count:int=mini(g.steward.Pool.IDS.size(),trees.filter(func(other):return w.point(other).distance_to(entry)<=12).size())
			if count<=best_count:continue
			if w.find_route(g.steward.manager,entry).is_empty() and w.point(w.actors[g.steward.manager]).distance_to(entry)>.5:continue
			best_count=count;at=entry;step.target_id=tree.id
			if count>=g.steward.Pool.IDS.size():break
	elif step.action=="go_to":at=Vector2(step.x,step.y)
	elif not target.is_empty():
		var object:Dictionary=w.all_mushrooms().get(target,{}) if step.action=="gather" else w.object_by_id(target)
		if not object.is_empty():at=safe(g,w.point(object)+Vector2(0,2))
	if not at.is_finite():return
	batch={"goal":proposal.goal,"step":step,"proposal":proposal,"phase":"approach","at":at,"last_progress":w.forest.clock,"watchdog_retries":0,"started":w.forest.clock,"key":str(serial)+":"+str(w.forest.clock),"members":[]}
	if step.action in ["roast","play","stars"]:invite(g,batch.key)
	g.steward.current_goal=proposal.goal
	g.steward.timeline=[{"phase":"now","reason":proposal.goal.text,"status":"running","intents":[step],"actors":[g.steward.manager]}]
	note(g,"batch_start",{"goal":proposal.goal,"step":step,"destination":at});say(g,"thought",proposal.goal.text)
func complete(g:Node,result:String)->void:
	var w:RefCounted=g.world
	var key:String=batch.goal.id
	var proven:bool=w.standard.goals.proof(w,key) or w.standard.board_completed.has("goal."+key)
	var catalog_goal:bool=w.standard.goals.definitions.any(func(row):return row.id==key)
	preferences["rest_after_close"]=result!="completed" or proven or not catalog_goal
	if invitation_for==batch.key:
		invitation_for=""
		if is_instance_valid(invitation_card):invitation_card.hide()
	if result!="completed":
		failures[key]=int(failures.get(key,0))+1
		g.steward.tutorial_planner.retry[key]=INF if int(failures[key])>=2 else w.forest.clock+float(g.steward.trace_config.retry_seconds)
		note(g,"skipped" if int(failures[key])>=2 else "batch_failed",{"goal":key,"reason":result,"attempts":failures[key]})
	else:
		if proven and not reported_goals.has(key):
			reported_goals[key]=true
			reports+=1;note(g,"report",{"goal":key,"result":result})
			var distance:float=w.point(w.actors[g.steward.manager]).distance_to(w.point(w.actors.human))
			if w.actors.human.region_id==w.actors[g.steward.manager].region_id:
				preferences["report_pending"]=batch.goal.text
			else:say(g,"report",batch.goal.text)
		else:note(g,"subtask_completed",{"goal":key,"action":batch.step.action})
	for id in tasks.keys():
		if tasks[id].get("source")==preload("res://scripts/localization.gd").source("content.v06.text.b70a891cbab1ea"):continue
		# Exact owned shared jobs stop after the joint activity; unrelated work is untouched.
		if tasks[id].has("owned_job") and w.work.jobs.get(id,{}).get("id")==tasks[id].owned_job:w.work.stop(id,false)
		release(g,id,result)
	batch.clear();closing=true
	formation_center=Vector2.INF;formation_slots.clear()
	# Regroup before the leader may leave for a report or begin the rest timer.
	regroup(g,w.point(w.actors[g.steward.manager]))
func dispatch_team(g:Node)->void:
	var w:RefCounted=g.world
	var action:String=batch.step.action
	var ids:Array=g.steward.Pool.IDS.filter(func(id):return idle(g,id))
	batch.members=[]
	if action in ["plant","harvest","water"]:
		var preview:Dictionary=w.farms.preview_host_orders(ids,"ready" if action=="harvest" else "plant",batch.step.target_id,str(batch.step.get("crop_id","mixed")))
		var result:Dictionary=w.farms.confirm_host_orders(preview,ids)
		for row in result.get("rows",[]):
			if row.get("ok",false):
				batch.members.append(row.actor_id);task(g,row.actor_id,action)
			else:note(g,"subtask_rejected",row)
		return
	var targets:Array=[]
	var chosen_targets:Array=[]
	if action in ["chop","gather"]:
		targets=(w.objects.values() if action=="chop" else w.all_mushrooms().values()).filter(func(o):return o.region_id=="home" and not w.work.claims.has(o.id) and (o.kind=="tree" and o.status=="mature" and not w.resort.retired(o) if action=="chop" else o.id in w.standard.config.forage_ids and int(o.get("amount",0))>0))
		targets=targets.filter(func(o):return w.point(o).distance_to(batch.at)<=12)
		targets.sort_custom(func(a,b):return w.point(a).distance_to(batch.at)<w.point(b).distance_to(batch.at))
	for id in ids:
		var step:Dictionary=batch.step.duplicate(true);step.erase("actor_ids")
		if action in ["chop","gather"]:
			if targets.is_empty():
				var helpers:Array=w.objects.values().filter(func(o):return o.kind=="tree" and o.status=="mature" and o.region_id=="home" and not w.work.claims.has(o.id) and o.id not in chosen_targets and not w.resort.retired(o) and w.point(o).distance_to(batch.at)<=12)
				if helpers.is_empty():note(g,"subtask_rejected",{"actor":id,"reason":"no_distinct_target"});continue
				step={"action":"chop","target_id":helpers[0].id,"text":"chop 1 tree"}
			else:
				step.target_id=targets.pop_front().id
				step.text="chop 1 tree" if action=="chop" else "gather mushrooms"
		if step.has("target_id"):chosen_targets.append(step.target_id)
		note(g,"dispatch",{"actor":id,"step":step,"vacation":w.resort.vacation(id),"region":w.actors[id].region_id})
		issuing=true
		var result:Dictionary=g.steward.assign(g.steward.manager,[step.merged({"actor_ids":[id]})],g.Channels.direct(g.steward.manager))
		issuing=false
		if result.get("ok",false):batch.members.append(id);task(g,id,"build_supply" if action=="chop" and batch.goal.id not in ["wood","hunger"] else action)
		else:note(g,"subtask_rejected",{"actor":id,"reason":result})
	batch.primary_tasks={}
	for id in batch.members:batch.primary_tasks[id]=tasks[id].id
func team_busy(g:Node)->bool:
	return batch.get("members",[]).any(func(id):return g.intentions.plans.has(id) or g.world.work.jobs.has(id) or g.world.farms.active(id) or g.world.deliveries.active(id))
func run_batch(g:Node)->void:
	var w:RefCounted=g.world
	var manager:String=g.steward.manager
	if batch.has("failed"):complete(g,str(batch.failed));return
	var action:String=batch.step.action
	if batch.phase!="running" and action in ["chop","gather","plant","harvest","water","build"] and w.hunger.rank(manager)>=2:
		note(g,"hunger_priority",{"goal":batch.goal.id,"actor":manager})
		for id in tasks.keys():
			if idle(g,id):release(g,id,"hunger_priority")
		batch.clear();return
	if w.forest.clock-float(batch.started)>float(g.steward.trace_config.get("batch_timeout_seconds",600)):complete(g,"batch_timeout");return
	if batch.phase=="invite_approach":
		var human_at:Vector2=w.point(w.actors.human)+Vector2(0,3)
		if w.actors.human.region_id!="home":batch.phase="approach";return
		if not regroup(g,human_at,true):return
		if w.point(w.actors[manager]).distance_to(human_at)>3:move(g,manager,human_at,"invite");return
		if action=="play":
			# Friends begin a real round while the host decides whether to join.
			# A pending invitation never makes the whole group stand still.
			batch.at=w.point(w.actors[manager])
			var played:Dictionary=g.playground.start(str(preferences.get("game",batch.proposal.game)),false)
			if not played.ok:complete(g,str(played.get("error","play_failed")));return
			invite(g,batch.key);task(g,manager,"play");batch.phase="running";batch.running_at=w.forest.clock;return
		if not invite(g,batch.key):return
		batch.phase="approach"
	if batch.phase=="approach":
		var ready:bool=true
		if action=="fish":
			for id in g.steward.Pool.IDS:
				var shore:Dictionary=w.fishing.team_shores.get(id,{})
				if shore.is_empty():ready=false;continue
				var point:=Vector2(shore.position[0],shore.position[1])
				if w.point(w.actors[id]).distance_to(point)>.1:
					ready=false;move(g,id,point,"travel")
				elif w._routes.has(id):ready=false
		else:ready=regroup(g,batch.at,true)
		if not ready:return
		if w.point(w.actors[manager]).distance_to(batch.at)>3:
			move(g,manager,batch.at,"travel");return
		if w._routes.has(manager):return
		batch.phase="thought";batch.thought_at=w.forest.clock;return
	if batch.phase=="thought":
		if w.forest.clock-float(batch.thought_at)<float(g.steward.trace_config.thought_pause_seconds):return
		if action in ["roast","stars"]:
			if not invite(g,batch.key):return
			if human_accepted() and w._routes.has("human") and w.forest.clock-float(batch.thought_at)<90:return
		if action=="play":
			var game_name:String=str(preferences.get("game",batch.proposal.game))
			var result:Dictionary=g.playground.start(game_name,invited.get(batch.key,false))
			if not result.ok:complete(g,str(result.get("error","play_failed")));return
			task(g,manager,"play");batch.phase="running";batch.running_at=w.forest.clock;return
		if action in ["chop","gather","plant","harvest","water","fish"]:
			dispatch_team(g);batch.phase="running";batch.running_at=w.forest.clock
			if batch.members.is_empty():batch.failed="no_team_work"
			return
		var own:Dictionary=batch.step.duplicate(true);own.erase("actor_ids")
		if action=="roast" and preferences.has("food") and batch.goal.id!="dish":
			var menu:Array=w.barbecues["home.barbecue"].fireside.menu(manager).filter(func(row):return row.id==preferences.food and row.maximum>0)
			if not menu.is_empty():own.item_id=preferences.food
		if action=="plant" and preferences.has("crop") and w.storage.count("seed."+str(preferences.crop))>0:own.crop_id=preferences.crop
		note(g,"dispatch",{"actor":manager,"step":own,"vacation":w.resort.vacation(manager),"region":w.actors[manager].region_id})
		issuing=true
		var result:Dictionary=g.steward.assign(manager,[own],g.Channels.direct(manager))
		issuing=false
		if not result.get("ok",false):complete(g,JSON.stringify(result));return
		var preferred_kind:String={"plant":"crop","roast":"food"}.get(action,"")
		var lease:Dictionary=task(g,manager,action,preload("res://scripts/localization.gd").source("content.v06.text.78905cde6757e2") if batch.goal.id=="hunger" else str(preferences.get(preferred_kind+"_source",preload("res://scripts/localization.gd").source("content.v06.text.0f98f12cf3aa27"))))
		lease.target_id=own.get("target_id","")
		if action=="build" and w.work.jobs.has(manager):w.work.jobs[manager].steward_entry=batch.at
		if action=="build":
			# Material planning already funded this three-second build. Starting
			# unrelated depot trips here strands helpers after the builder finishes.
			batch.members=[manager]
			if batch.goal.id=="camp" and not w.standard.goals.proof(w,"mushrooms"):supply_helpers(g)
		batch.phase="running";batch.running_at=w.forest.clock
		return
	if batch.phase=="running":
		var limit:float=float(g.steward.trace_config.task_timeouts.get(action,g.steward.trace_config.task_timeout_seconds))
		if action=="chess":limit=600
		if w.forest.clock-float(batch.running_at if batch.has("running_at") else batch.started)>limit:complete(g,"task_timeout");return
		if action=="play":
			invite(g,batch.key)
			if human_accepted() and not g.playground.kind.is_empty():g.playground.start(g.playground.kind,true)
			if not g.playground.kind.is_empty():return
			complete(g,"completed");return
		if action in ["chop","gather"] and batch.get("primary_tasks",{}).keys().any(func(id):return tasks.get(id,{}).get("id",-1)==batch.primary_tasks[id] and not idle(g,id)):
			supply_helpers(g)
		if action=="chess":
			supply_helpers(g)
			var matches:Array=w.gomoku.sessions.values().filter(func(row):return row.site_id==batch.step.target_id)
			if matches.any(func(row):return row.phase in ["arriving","playing"]):return
			if matches.any(func(row):return row.phase=="paused"):
				var match_row:Dictionary=matches[0]
				# Only our own local match may concede at its already-confirmed cap.
				# No resume, extra budget, synthetic draw, or model substitution.
				if match_row.get("mode")=="ai" and manager in w.gomoku.players(match_row) and match_row.history.size()>=int(match_row.ai.step_limit) and w.gomoku.players(match_row).all(func(id):return w.gomoku.source_for(match_row,id)!="model"):
					var ended:Dictionary=w.gomoku.command(manager,{"intent":"gomoku_resign","site_id":match_row.site_id,"match_id":match_row.id,"revision":match_row.revision})
					note(g,"chess_cap_concession",{"match_id":match_row.id,"moves":match_row.history.size(),"result":ended})
					if ended.get("ok",false):complete(g,"completed");return
				note(g,"chess_paused",{"matches":matches,"stops":w.work.stop_audit.slice(-12)})
				complete(g,"chess_paused");return
		if action=="roast":
			var fire:RefCounted=w.barbecues[batch.step.target_id].fireside
			if g.intentions.plans.has(manager) or fire.active() and not fire.circle_closed:return
		if action=="stars":
			for id in g.steward.Pool.IDS:
				if w.work.jobs.has(id) and not w.resort.using(id).is_empty():
					if not tasks.has(id):task(g,id,"stars")
					tasks[id].owned_job=w.work.jobs[id].id
			if w.forest.clock-float(batch.running_at)<45:return
			for id in tasks:
				if tasks[id].has("owned_job") and w.work.jobs.get(id,{}).get("id")==tasks[id].owned_job:w.work.stop(id,false)
		if team_busy(g):
			# A finished builder accompanies the exact team's real handover.
			# No helper is cancelled, and World still owns this route.
			if action=="build" and not g.intentions.plans.has(manager) and not w.work.jobs.has(manager) and batch.members.any(func(id):return w.work.jobs.get(id,{}).get("phase","")=="storage_delivery"):
				var handover:Vector2=w.deliveries.visit_slot(manager)
				if not w._routes.has(manager) and w.point(w.actors[manager]).distance_to(handover)>.5:move(g,manager,handover,"travel")
			return
		if g.intentions.plans.has(manager) or w.deliveries.active(manager):return
		if action not in ["roast","stars"] and w.work.jobs.has(manager):return
		complete(g,"completed")
func supply_helpers(g:Node)->void:
	var w:RefCounted=g.world
	for id in g.steward.Pool.IDS:
		if not idle(g,id) or w._routes.has(id):continue
		var claimed:Array=g.intentions.plans.values().map(func(plan):return plan.get("current",{}).get("target_id",""))
		var trees:Array=w.objects.values().filter(func(o):return o.kind=="tree" and o.status=="mature" and o.region_id=="home" and not w.work.claims.has(o.id) and o.id not in claimed and not w.resort.retired(o) and w.point(o).distance_to(w.point(w.actors[g.steward.manager]))<=10)
		var sources:Array=trees
		var action:="chop"
		if sources.is_empty():
			sources=w.all_mushrooms().values().filter(func(o):return o.region_id=="home" and o.id in w.standard.config.forage_ids and int(o.get("amount",0))>0 and not w.work.claims.has(o.id) and o.id not in claimed and w.point(o).distance_to(w.point(w.actors[g.steward.manager]))<=10)
			action="gather"
		if sources.is_empty():continue
		sources.sort_custom(func(a,b):return w.point(a).distance_to(w.point(w.actors[id]))<w.point(b).distance_to(w.point(w.actors[id])))
		issuing=true
		var result:Dictionary=g.steward.assign(g.steward.manager,[{"action":action,"target_id":sources[0].id,"text":"chop 1 tree" if action=="chop" else "gather mushrooms","actor_ids":[id]}],g.Channels.direct(g.steward.manager))
		issuing=false
		if result.get("ok",false):
			if id not in batch.members:batch.members.append(id)
			task(g,id,"build_supply" if action=="chop" else "gather")
func monitor(g:Node)->void:
	var w:RefCounted=g.world
	for id in tasks.keys():
		var own:Dictionary=tasks[id]
		if own.source==preload("res://scripts/localization.gd").source("content.v06.text.b70a891cbab1ea"):continue
		var target_id:String=str(own.get("target_id",""))
		if not target_id.is_empty() and own.action=="build" and not w.leisure.sites.has(target_id):
			release(g,id,"target_missing")
			if not batch.is_empty():batch.failed="target_missing"
			continue
		var at:Vector2=w.point(w.actors[id])
		var moving:bool=w._routes.has(id) and w.actors[id].activity=="walking" and own.action not in ["play","chess","stars","roast","eat"]
		own.traveling=moving
		if not moving:own.last_move=w.forest.clock;own.points=[];continue
		if at.distance_to(own.position)>.2:own.last_move=w.forest.clock;own.position=at
		var reason:=""
		if w.forest.clock-float(own.last_move)>=float(g.steward.trace_config.walking_stall_seconds):reason="walking_stall"
		var points:Array=own.points;points.append(at.snapped(Vector2(1,1)))
		if points.size()>8:points.pop_front()
		if points.size()==8 and points[0].distance_to(points[1])>1 and range(2,8).all(func(i):return points[i]==points[i%2]):reason="oscillation"
		if not reason.is_empty():
			var incident:Dictionary={"actor":id,"action":own.action,"goal":own.goal,"reason":reason,"clock":w.forest.clock}
			faults.append(incident);note(g,"director_recovery",incident);release(g,id,reason)
			if not batch.is_empty():batch.failed=reason
func new_goal_reports(rows:Array,current_id:String)->Array:
	var fresh:Array=[]
	for row in rows:
		if row.done and row.id!=current_id and not reported_goals.has(row.id):
			reported_goals[row.id]=true;fresh.append(row)
	return fresh
func tick(g:Node,_delta:float)->void:
	position_cards(g)
	var w:RefCounted=g.world
	var now:float=w.forest.clock
	if question_until>0 and now>=question_until:resolve(g,true)
	# Keep an idle follower's next leg close between the 2-second decision checks.
	# No path search occurs while that actor already has an owned route.
	if owner_visit or batch.is_empty() or batch.get("phase","")=="running":
		regroup(g,w.point(w.actors[g.steward.manager]))
	if now<next_check:return
	next_check=now+float(g.steward.trace_config.director_check_seconds)
	for id in paused.keys():
		if now-float(paused[id])>=3 and not w.work.jobs.has(id) and not w.farms.active(id) and not g.intentions.plans.has(id) and not w._routes.has(id) and not g._resident_chat_busy(id):paused.erase(id);tasks.erase(id);note(g,"player_return",{"actor":id})
	for id in g.steward.Pool.IDS:
		if paused.has(id):continue
		var shared_action:=""
		if id in g.playground.members:shared_action="play"
		elif w.gomoku.active(id):shared_action="chess"
		elif not w.resort.using(id).is_empty():shared_action="stars"
		else:
			for camp in w.barbecues.values():
				if camp.fireside.jobs.has(id):shared_action="eat"
		if not shared_action.is_empty() and tasks.get(id,{}).get("action","")!=shared_action:
			var shared:Dictionary=task(g,id,shared_action,preload("res://scripts/localization.gd").source("content.v06.text.78905cde6757e2") if batch.get("goal",{}).get("id","")=="hunger" else preload("res://scripts/localization.gd").source("content.v06.text.0f98f12cf3aa27"))
			if w.work.jobs.has(id):shared.owned_job=w.work.jobs[id].get("id","")
	monitor(g)
	watch_goal(g)
	if closing:
		# Old shared intents can own escorts as well as the leader. Let real jobs
		# finish, then revoke only this director's plans and their remaining routes.
		for id in g.steward.Pool.IDS:
			if paused.has(id):continue
			if w.work.jobs.has(id) or w.farms.active(id):return
			if g.intentions.plans.get(id,{}).get("sponsor","")==g.steward.manager:
				g.intentions.plans.erase(id)
				if w._routes.has(id):w._routes.erase(id);w.actors[id].activity="idle"
		if not regroup(g,w.point(w.actors[g.steward.manager])):return
		closing=false
		if preferences.get("rest_after_close",true):
			rest_until=now+float(g.steward.trace_config.rest_seconds)
			note(g,"rest",{"until":rest_until});say(g,"rest")
		else:rest_until=now
		preferences.erase("rest_after_close")
	if batch.is_empty() and preferences.has("report_pending"):
		var point:Vector2=w.deliveries.visit_slot(g.steward.manager)
		if w.point(w.actors[g.steward.manager]).distance_to(point)>.5:
			if not w._routes.has(g.steward.manager) and not regroup(g,w.point(w.actors[g.steward.manager])):return
			move(g,g.steward.manager,point,"report")
		elif w.deliveries.visit_ready(g.steward.manager):
			w.deliveries.finish_visit(g.steward.manager)
			say(g,"report",str(preferences.report_pending));preferences.erase("report_pending");tasks.erase(g.steward.manager)
		regroup(g,w.point(w.actors[g.steward.manager]));return
	if batch.is_empty() and now>=next_question and question_until==0 and invitation_for.is_empty() and idle(g,g.steward.manager) and not w._routes.has(g.steward.manager):
		var destination:Vector2=safe(g,w.point(w.actors.human)+Vector2(0,2),w.actors.human.region_id)
		if destination.is_finite() and w.actors.human.region_id=="home":
			if w.point(w.actors[g.steward.manager]).distance_to(destination)>3:
				owner_visit=move(g,g.steward.manager,destination,"question")
			else:
				owner_visit=false;question(g);next_question+=float(g.steward.trace_config.owner_question_seconds)
	if owner_visit:
		regroup(g,w.point(w.actors[g.steward.manager]))
		if not w._routes.has(g.steward.manager):
			owner_visit=false;question(g);next_question+=float(g.steward.trace_config.owner_question_seconds)
		return
	if question_until>0 and batch.is_empty():
		regroup(g,w.point(w.actors[g.steward.manager]));return
	if not batch.is_empty():run_batch(g)
	elif now>=rest_until and not paused.has(g.steward.manager) and not preferences.has("report_pending"):
		var proposal:Dictionary=choose(g)
		if not proposal.is_empty():start_batch(g,proposal)
	if batch.is_empty():
		regroup(g,w.point(w.actors[g.steward.manager]))
	for goal in new_goal_reports(w.standard.goals.rows(w),str(batch.get("goal",{}).get("id",""))):
		reports+=1;note(g,"report",{"goal":goal.id,"result":"observed_committed_fact"})
		if w.actors.human.region_id==w.actors[g.steward.manager].region_id:
			preferences["report_pending"]=goal.text
			if batch.is_empty():closing=true
		else:say(g,"report",goal.text)
	# Every owned route has a terminal state, independent of the next batch.
	for id in tasks.keys():
		if tasks[id].get("route")!=null and not w._routes.has(id):
			if tasks[id].action=="report" and preferences.has("report_pending"):
				if not w.deliveries.visit_ready(id):continue
				w.deliveries.finish_visit(id)
				say(g,"report",str(preferences.report_pending));preferences.erase("report_pending")
			note(g,"task_end",{"actor":id,"task":tasks[id],"result":"completed"});tasks.erase(id)
	if not invitation_for.is_empty() and invited.has(invitation_for):invitation_for=""

func watch_goal(g:Node)->void:
	if batch.is_empty():return
	var w:RefCounted=g.world
	var state:Array=[]
	for id in g.steward.Pool.IDS:
		state.append([w.actors[id].position,w.work.jobs.get(id,{}),w.farms.orders.get(id,{})])
	var site:Dictionary=w.leisure.sites.get(batch.step.get("target_id",""),{})
	var signature:String=JSON.stringify(state)+str(site.get("invested",0))+str(site.get("complete",false))
	if batch.step.action=="play" and not g.playground.kind.is_empty():signature+=str(g.playground.beat)
	if batch.step.action=="chess":signature+=JSON.stringify(w.gomoku.sessions)
	if batch.get("progress_signature","")!=signature:
		batch.progress_signature=signature;batch.last_progress=w.forest.clock
	if w.forest.clock-float(batch.get("last_progress",w.forest.clock))<float(g.steward.trace_config.get("goal_watchdog_seconds",20)):return
	if int(batch.get("watchdog_retries",0))>0:
		note(g,"goal_watchdog_skip",{"goal":batch.goal.id,"reason":"no_progress"})
		say(g,"thought",preload("res://scripts/localization.gd").source("content.v06.text.42cb608794871b") if TranslationServer.get_locale().begins_with("zh") else "Try later: no work progress")
		failures[batch.goal.id]=1;complete(g,"no_progress_try_later");return
	note(g,"goal_watchdog_retry",{"goal":batch.goal.id})
	for id in tasks.keys():
		if tasks[id].source==preload("res://scripts/localization.gd").source("content.v06.text.b70a891cbab1ea"):continue
		release(g,id,"watchdog_retry")
	batch.watchdog_retries=1;batch.last_progress=w.forest.clock;batch.phase="approach"

func position_cards(g:Node)->void:
	var viewport:Vector2=g.get_viewport_rect().size
	var anchor:Vector2=g.view.screen(g.world.point(g.world.actors[g.steward.manager]))
	for panel in [card,invitation_card]:
		if not is_instance_valid(panel) or not panel.visible:continue
		var remaining:float=question_until if panel==card else invitation_deadline
		var timer:Label=panel.get_node("body/countdown")
		var outside:bool=not Rect2(Vector2.ZERO,viewport).has_point(anchor)
		timer.text=("◀ " if anchor.x<0 else "▶ " if anchor.x>viewport.x else "↑ " if anchor.y<0 else "↓ " if outside else "")+str(maxi(0,ceili(remaining-g.world.forest.clock)))+" s"
		var bottom:float=viewport.y-12
		if is_instance_valid(g.island_hud.primary_actions) and g.island_hud.primary_actions.is_visible_in_tree():
			bottom=minf(bottom,g.island_hud.primary_actions.global_position.y-12)
		var maximum:=Vector2(maxf(12,viewport.x-panel.size.x-12),maxf(12,bottom-panel.size.y))
		panel.position=(anchor-Vector2(panel.size.x/2,panel.size.y+100*g.view.zoom)).clamp(Vector2(12,12),maximum)

func style_card(panel:PanelContainer)->void:
	var body:Node=panel.get_child(0);body.name="body"
	for child in body.get_children():
		child.set_meta("ui_font_base",24)
		child.add_theme_font_size_override("font_size",preload("res://scripts/ui_scale.gd").pixels(24))
		if child is Button:child.set_meta("ui_scale_min",Vector2(0,45));child.custom_minimum_size.y=preload("res://scripts/ui_scale.gd").pixels(45)
	var timer:=Label.new();timer.name="countdown";timer.set_meta("ui_font_base",24);body.add_child(timer)
