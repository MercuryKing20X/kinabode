extends RefCounted
## One decision owner per stable identity. Executors retain all physical validation.
var owner:WeakRef
var world:RefCounted:
	get:return owner.get_ref()
var id:String
var config:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/brain.json"))
var rng:=RandomNumberGenerator.new()
var needs:Dictionary={"tired":0.0,"bored":.25,"missing":0.0,"curious":.5}
var current:Dictionary={}
var history:Array=[]
var recent:Dictionary={}
var balance_events:Array=[]
var category_recent:Dictionary={}
var last_host_busy:=-100000.0
var invitation:Dictionary={}
var top:Array=[]
var next_decision:=0.0
var clock:=0.0
var executing:=false
var route:Variant=null
var last_position:=Vector2.ZERO
var still:=0.0
var last_near:=0.0
var seen_places:Dictionary={}
var generation:=-1
var external_busy:Callable
var external_cancel:Callable
var island_plan_ready:Callable
var trace_directory:=""
var trace_date:=""
var schedule_options:Array=[]
var schedule_due:=0.0
var offers:Dictionary={}
var provider_running:=false
var next_visit:=0.0
var special_provider:=""
var onlooker:RefCounted=preload("res://scripts/hungry_onlooker.gd").new()
var profile_usec:=0
var profile_frames:=0
var rhythm:RefCounted
var interactions:RefCounted
var refusal:Dictionary={}
var intention:RefCounted
var hold_reason:=""
var free_since:=-100000.0
var next_self_meal:=0.0
var paused_wood:Dictionary={}
var paused_wood_wait_near:=false
var paused_wood_wait_order:=""
func _init(w:RefCounted,who:String)->void:
	owner=weakref(w);id=who;reset()
func active()->bool:return world.intelligence!=null and not world.intelligence.compatibility
func reset()->void:
	paused_wood.clear();paused_wood_wait_near=false;paused_wood_wait_order=""
	if intention!=null:
		intention.finish("interrupted","world_reload")
		if not intention.pending.is_empty():intention.settle(intention.pending.plan,"interrupted","world_reload")
	balance_events.clear();category_recent.clear();last_host_busy=-100000.0
	current.clear();history.clear();recent.clear();invitation.clear();top.clear();route=null;still=0;next_decision=0;clock=0;last_near=0;seen_places.clear();schedule_due=0;next_visit=0;offers.clear();provider_running=false;special_provider=""
	intention=preload("res://scripts/brain_intention.gd").new(self)
	needs={"tired":0.0,"bored":.25,"missing":0.0,"curious":.5}
	generation=int(world.get("session_generation") if world.get("session_generation")!=null else 0)
	interactions=preload("res://scripts/brain_interactions.gd").new(self);rhythm=preload("res://scripts/brain_rhythm.gd").new(self);refusal.clear()
	var seed_text:String=OS.get_environment("HABITAT_BRAIN_SEED")
	rng.seed=(int(seed_text) if seed_text.is_valid_int() else world.life_seed if world.get("open_life")==true else int(config.seed))+int(id.hash())
func seed_life()->void:
	var fixed:String=OS.get_environment("HABITAT_BRAIN_SEED")
	rng.seed=(int(fixed) if fixed.is_valid_int() else hash("brain:"+str(world.life_seed)))+int(id.hash())
func accept_coordination(action:String)->bool:
	if action not in ["chop","build","harvest"] or not eligible() or busy() or world._routes.has(id) or world.hunger.rank(id)>=2:return false
	if current.has("ai_plan") or current.get("paired",false) or not intention.pending.is_empty():return false
	if not invitation.is_empty() and clock<float(invitation.get("until",0)):return false
	var preference:float=.86 if tag()=="laborious" else .55 if tag()=="quiet" else .66
	if current.get("action","") in ["rest","night_rest","read","play_lie"]:preference*=.55
	return rng.randf()<preference
func text(key:String,language:String="")->String:
	var lang:String=language if not language.is_empty() else ("en" if TranslationServer.get_locale().begins_with("en") else "zh")
	var voice:Dictionary=config.voices.get(tag(),config.voices.gentle)
	return str(voice.get(key,config.text.get(key,[key,key]))[1 if lang=="en" else 0])
func tag()->String:return world.intelligence.tag(id)
func moment_score()->float:
	return world.director.moment_pacing.score() if world.director.moment_pacing!=null else 0.0
func moment_observed(kind:String)->void:
	if world.director.moment_pacing!=null:world.director.moment_pacing.observe(kind)
func moment_candidate(action:String,body:Callable)->bool:
	var score:=moment_score()
	if score<0 or not eligible() or busy() or world.hunger.rank(id)>=3:return false
	return bool(effect("local",action,body))
func action_name(key:String,language:String="")->String:
	var outing_names:Dictionary=preload("res://scripts/brain_outing.gd").NAMES
	if outing_names.has(key):return str(outing_names[key][1 if language=="en" or (language.is_empty() and TranslationServer.get_locale().begins_with("en")) else 0])
	if config.command_labels.has(key):return str(config.command_labels[key][1 if (language=="en" or (language.is_empty() and TranslationServer.get_locale().begins_with("en"))) else 0])
	if key not in config.actions and not config.text.has(key):key="command_activity"
	var lang:String=language if not language.is_empty() else ("en" if TranslationServer.get_locale().begins_with("en") else "zh")
	return str(config.actions.get(key,{}).get(lang,text(key,lang)))
func finish(outcome:String,reason:String="")->void:
	if current.is_empty():return
	if current.has("basic_plan") and outcome!="completed":intention.basic.interrupted(reason)
	intention.finish(outcome,reason)
	if current.has("outing_job"):intention.outings.cancel(current.outing_job,outcome,reason)
	var row:Dictionary={"actor":id,"at":clock,"day":world.days.day(),"event":"outcome","choice":current.action,"source":current.source,"outcome":outcome,"reason":reason}
	trace(row)
	if not history.is_empty():history[-1].outcome=outcome;history[-1].reason=reason
	if current.source=="local":
		if current.action=="hold_cat" and world.cat.carrier==id:world.cat.interact(id,"release")
		if provider_running:world.director.routines[id].interrupt(0);provider_running=false;special_provider=""
		if route!=null and is_same(route,world._routes.get(id)):world._routes.erase(id)
		world.lively.active.erase(id)
		world.director.destinations.erase(id)
		world.director.routines[id].owns_route=false
		world.director.routines[id].kind=""
		if not world.work.jobs.has(id) and not world._routes.has(id):world.actors[id].activity="idle"
	current.clear();route=null;still=0;next_decision=clock
func begin_external(source:String,action:String)->void:
	if not active() or executing:return
	finish("interrupted",source+":"+action)
	world.hunger.clear_follow(id)
	world.director.routines[id].interrupt(0)
	current={"action":action,"source":source,"start":clock,"duration":float(config.external_timeout),"reasons":[source],"score":float(config.scores.mandatory)}
	record([{ "action":action,"score":float(config.scores.mandatory),"reasons":[source]}])
func mandate(source:String,action:String,body:Callable)->Dictionary:
	if not active() or executing:return body.call()
	begin_external(source,action)
	executing=true
	trace({"actor":id,"at":clock,"event":"dispatch","choice":action,"source":source,"via":"ResidentBrain","score":float(config.scores.mandatory),"reasons":[source]})
	var result:Dictionary=body.call()
	executing=false
	if not current.is_empty():
		current["job_id"]=world.work.jobs.get(id,{}).get("id","")
		last_position=world.point(world.actors[id]);still=0
	if not result.get("ok",false):finish("failed",str(result.get("error","rejected")))
	elif result.get("status")=="completed" and not busy() and not world._routes.has(id):finish("completed")
	return result
# Session-only scoring history. Commands and very-hungry behavior bypass balance.
func effect(source:String,action:String,body:Callable)->Variant:
	trace({"actor":id,"at":clock,"event":"candidate","choice":action,"source":source,"score":float(config.scores.mandatory),"reasons":[source]})
	var result:Variant=body.call()
	var row:Dictionary={"actor":id,"at":clock,"day":world.days.day(),"event":"dispatch","choice":action,"source":source,"via":"ResidentBrain","reasons":[source],"outcome":"completed" if result==null or result else "deferred"}
	trace(row)
	if result==null or result:
		history.append(row.duplicate(true))
		if history.size()>int(config.history_limit):history.pop_front()
	return result
func command(args:Dictionary)->Dictionary:
	var intent:String=str(args.get("intent",""))
	if intent=="stop" and not executing:paused_wood.clear();paused_wood_wait_order=""
	if intent=="move" and world.activities.explicit_selected.has(id) and not world.host_issuing.has(id) and not world.activities.suspended_follow.has(id) and not world.activities.commanded(id):return world._command_body(id,args)
	if not active() or executing or intent.ends_with("_read") or intent in ["query_state","propose","promise","promise_cancel","journal_read"]:return world._command_body(id,args)
	return mandate("command",intent,func():return world._command_body(id,args))
func sheltering()->bool:
	if current.get("source","")!="local" or world._routes.has("human") or world.hunger.rank(id)>=3:return false
	return (current.get("action")=="night_rest" and world.days.phase().id=="night") or (current.get("action")=="rain_shelter" and world.weather.current().id=="rain")
func follow(dark_fear:bool=false)->void:
	if world.actors[id].has("world_door_client"):return
	if (current.has("ai_plan") or current.has("heart_guest") or current.has("basic_plan")) and world.hunger.rank(id)<3 and not dark_fear:return
	if not active() or executing:world.hunger._follow_body(id,dark_fear);return
	# Other providers request follow; only the brain may grant it while idle.
	if current.get("source","") in ["command"] or busy() or sheltering():return
	if current.get("source","")=="local" and current.action in ["follow","food"]:
		executing=true;world.hunger._follow_body(id,dark_fear);executing=false
		if world._routes.has(id):route=world._routes[id];current.arrived=-1.0;current.erase("status")
		return
	if current.get("source","")=="local" and not world._routes.has("human") and distance()<=float(config.follow_max):return
	if current.get("source","")=="local":finish("interrupted","host_moved")
	executing=true;world.hunger._follow_body(id,dark_fear);executing=false
	if current.is_empty() and world._routes.has(id):
		current={"action":"food" if world.hunger.rank(id)>=3 else "follow","source":"local","start":clock,"arrived":-1.0,"duration":float(config.actions.follow.duration),"score":float(config.scores.return),"reasons":["hunger" if world.hunger.rank(id)>=3 else "follow"],"partner":""}
		route=world._routes[id];world.director.routines[id].owns_route=true;last_position=world.point(world.actors[id]);record([{ "action":current.action,"score":float(config.scores.return),"reasons":current.reasons}])
func continuing_follow()->bool:
	return active() and current.get("source","")=="local" and current.get("action","")=="follow" and route!=null and is_same(route,world._routes.get(id)) and not world.director.routines[id].held and not busy()
func preference_changed(following:bool)->void:
	if not active() or (following and continuing_follow()):return
	if current.get("source","")=="local" and not (executing and current.get("origin")=="native"):finish("interrupted","follow_preference")
	if not following:
		free_since=clock
		next_visit=clock+float(world.director.routines[id].return_visit.options(world.director.routines[id]).interval_seconds)
	next_decision=clock
func distance()->float:
	return world.point(world.actors[id]).distance_to(world.point(world.actors.human)) if world.actors[id].region_id==world.actors.human.region_id else INF
func busy(ignore_paused_follow:bool=false)->bool:
	if provider_running:return false
	return (world.flower_creation!=null and world.flower_creation.active(id)) or (not ignore_paused_follow and world.activities.suspended_follow.has(id)) or world.work.jobs.has(id) or world.farms.active(id) or world.projects.active(id) or world.homestead.active(id) or world.deliveries.active(id) or world.activities.blocked(id,false) or world.activities.commanded(id) or (external_busy.is_valid() and external_busy.call())
func eligible(allow_fish:bool=false)->bool:
	var r:RefCounted=world.director.routines[id]
	return r.enabled and not r.held and (clock>=r.visual_quiet_until or (world.hunger.rank(id)>=3 and world.hunger.can_follow(id))) and not r.transporting() and (allow_fish or world.fishing.held(id).is_empty()) and not world.hunger.rushes.has(id)
func join_heart_outing(token:String,at:Vector2,place:String)->bool:
	if not eligible() or busy() or world.hunger.rank(id)>=3 or current.has("ai_plan") or current.has("heart_guest"):return false
	var path:Array[Vector2]=world.find_route(id,at)
	if path.is_empty():return false
	finish("interrupted","accepted_invitation")
	world.hunger.clear_follow(id)
	if not world._apply_route(id,path):return false
	route=world._routes.get(id)
	current={"action":"watch_sea" if place=="sea" else "visit","source":"local","heart_guest":token,"arrived":-1.0,"start":clock,"duration":120.0,"reasons":["invite"]}
	return true
func update_needs(delta:float)->void:
	var rates:Dictionary=config.rates.get(tag(),config.rates.gentle)
	for key in needs:needs[key]=clampf(float(needs[key])+float(rates[key])*delta,0,1)
	if distance()<=float(config.needs_context.near_distance):
		last_near=clock;needs.missing=maxf(0,float(needs.missing)-float(rates.satisfy)*delta)
	if not current.is_empty() and current.source=="local":
		var need:String=config.actions.get(current.action,{}).get("need","bored")
		if needs.has(need):needs[need]=maxf(0,float(needs[need])-float(rates.satisfy)*delta)
		if need=="tired":needs.tired=maxf(0,float(needs.tired)-float(rates.rest)*delta)
	var p:Vector2=world.point(world.actors[id])
	var place:String=world.actors[id].region_id+":"+str(Vector2i(p/float(config.needs_context.place_cell)))
	if not seen_places.has(place):
		seen_places[place]=true;needs.curious=minf(1,float(needs.curious)+float(config.needs_context.new_place_boost))
		if seen_places.size()>256:seen_places.erase(seen_places.keys()[0])
func candidates()->Array:
	var choices:Array=[]
	for action in ["wander","local_sit","watch_sea"]:
		if config.actions.has(action):
			choices.append({"action":action,"score":0.0,"reasons":["personality"],"partner":""})
	return choices
func candidate_layer(_row:Dictionary)->int:return 2
func offer(action:String,body:Callable,score:float=-1)->void:
	if not offers.has(action):
		offers[action]={"body":body,"until":clock+float(config.decision_seconds)*2}
		if score>=0:offers[action]["score"]=score

func record(options:Array)->void:
	top=options.slice(0,3).duplicate(true)
	var row:Dictionary={"actor":id,"at":clock,"day":world.days.day(),"event":"choice","choice":current.action,"layer":candidate_layer(current),"source":current.source,"top":top.duplicate(true),"reasons":current.reasons.duplicate(),"outcome":"running","phase":world.days.phase().id,"weather":world.weather.current().id,"hunger_rank":world.hunger.rank(id)}
	history.append(row.duplicate(true))
	if history.size()>int(config.history_limit):history.pop_front()
	trace(row)
func job_outcome(job:Dictionary,status:String)->void:
	if not active() or current.is_empty():return
	trace({"actor":id,"at":clock,"day":world.days.day(),"event":"job_outcome","job_id":job.get("id",""),"intent":job.get("intent",""),"outcome":status})
	if current.get("job_id","")==job.get("id","missing"):current["job_result"]=status

func trace(row:Dictionary)->void:
	# Local choices and authored lines only; no private dialogue or provider configuration.
	if trace_directory.is_empty():return
	var date:String=Time.get_date_string_from_system()
	if date!=trace_date:
		trace_date=date;DirAccess.make_dir_recursive_absolute(trace_directory)
		var files:Array=Array(DirAccess.get_files_at(trace_directory)).filter(func(f):return f.begins_with("brain-trace-") and f.ends_with(".jsonl"));files.sort()
		var cutoff:int=int(Time.get_unix_time_from_datetime_string(date))-int(config.trace_days-1)*86400
		for f in files:
			if int(Time.get_unix_time_from_datetime_string(str(f).trim_prefix("brain-trace-").trim_suffix(".jsonl")))<cutoff:DirAccess.remove_absolute(trace_directory.path_join(f))
	var path:String=trace_directory.path_join("brain-trace-"+date+".jsonl")
	var file:=FileAccess.open(path,FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file!=null:file.seek_end();file.store_line(JSON.stringify(row));file.close()
func invite(who:String,action:String)->bool:
	if not world.director.brains.has(who) or who==id:return false
	var other:RefCounted=world.director.brains[who]
	if not other.interactions.social(action,id).ok:return false
	other.invitation={"from":id,"action":action,"until":clock+float(config.invite_seconds)};other.next_decision=clock
	return true
func destination(action:String)->Vector2:
	var a:Dictionary=world.actors[id];var same:bool=a.region_id==world.actors.human.region_id
	var center:Vector2=world.point(world.actors.human) if same and (world.activities.following.has(id) or action in ["follow","food"]) else world.point(a)
	var radius:float=float(config.follow_max) if world.activities.following.has(id) or action in ["follow","food"] else float(config.free_radius)
	var inner:float=float(config.follow_min)
	if same and world.hunger.rank(id)<3 and action not in ["food"]:
		var mood:Dictionary=world.hearts.mood(id);var bounds:Dictionary=world.hearts.config.proximity
		if float(mood.hurt)-float(world.hearts.config.baseline.hurt)>=float(bounds.threshold):
			center=world.point(world.actors.human);inner=minf(radius,float(bounds.hurt_inner));radius=minf(radius,float(bounds.hurt_outer))
		elif float(mood.joy)-float(world.hearts.config.baseline.joy)>=float(bounds.threshold):
			center=world.point(world.actors.human);inner=minf(radius,float(bounds.joy_inner));radius=minf(radius,float(bounds.joy_outer))
	for attempt in int(config.destination_attempts):
		var p:Vector2=center+Vector2.from_angle(rng.randf()*TAU)*rng.randf_range(inner,radius)
		if world.walkable(a.region_id,p) and world.director.available_position(id,a.region_id,p):return p
	return Vector2.INF
func start(choice:Dictionary,options:Array)->void:
	finish("interrupted","better_choice")
	if choice.action!="food" or world.hunger.rank(id)<3:world.hunger.clear_follow(id)
	var action:String=choice.action;var a:Dictionary=config.actions.get(action,{"duration":20})
	current=choice.duplicate(true);current.merge({"source":"local","start":clock,"arrived":clock,"duration":float(a.duration)})
	current["layer"]=candidate_layer(current)
	intention.started()
	recent[action]=clock
	record(options)
	if choice.get("outing",false):
		var job:Dictionary=intention.outings.start(current.ai_plan)
		if not job.ok:finish("failed",str(job.error));return
		current["outing_job"]=job
		intention.executing_plan()
		return
	if current.get("ai_plan",{}).has("with") and action in ["chat","back_to_back","pair_sea","pair_sweep"] and intention.outings.meetings!=null:
		var meeting:Dictionary=intention.outings.start_social(current.ai_plan)
		if not meeting.ok:finish("failed",str(meeting.error));return
		current["outing_job"]=meeting
		intention.executing_plan()
		return
	if a.get("requires","")=="rhythm":
		var at:Vector2=rhythm.target(action)
		if at.is_finite():choice["point"]=at
	if choice.get("paired",false):
		invitation.clear()
		if action=="social_banter":offers.erase(action)
	if choice.get("onlooker",false):pose();return
	if action=="host_interaction":
		if distance()>float(interactions.data.near_distance):
			var p:Vector2=destination("follow")
			if not p.is_finite():finish("failed","no_reachable_position");return
			executing=true;var result:Dictionary=world.host_command(id,{"intent":"move","x":p.x,"y":p.y,"region_id":world.actors[id].region_id});executing=false
			if not result.get("ok",false):finish("failed","unreachable");return
			route=world._routes.get(id);world.director.routines[id].owns_route=route!=null;last_position=world.point(world.actors[id]);current.arrived=-1.0
		return
	if action=="follow":next_visit=clock+float(world.director.routines[id].return_visit.options(world.director.routines[id]).interval_seconds)
	if action in ["dark_life","island_story"]:
		provider_running=true;special_provider=action
		if not advance_special(0.01):finish("failed","special_unavailable")
		return
	if offers.has(action):
		executing=true;var accepted:bool=offers[action].body.call();executing=false;offers.erase(action)
		if not accepted:finish("failed","provider_rejected");return
		provider_running=true;route=world._routes.get(id);current["job_id"]=world.work.jobs.get(id,{}).get("id","");return
	if action=="legacy_idle":
		executing=true
		var r:RefCounted=world.director.routines[id]
		var accepted:bool=world.relationships.try_reward(id) or world.schedules.try_start(r) or (float(r.preferences.weights.get("wander",0))>0 and r._start("wander"))
		executing=false
		if not accepted:finish("failed","provider_rejected");return
		provider_running=true;route=world._routes.get(id);return
	if action in ["flower_gift","facility"]:
		executing=true;var accepted:bool=world.director.routines[id]._start(action);executing=false
		if not accepted:finish("failed","provider_rejected");return
		provider_running=true;route=world._routes.get(id);current["job_id"]=world.work.jobs.get(id,{}).get("id","");return
	if action in ["hold_cat","pet_cat"]:
		if not world.cat.interact(id,"hold" if action=="hold_cat" else "pet"):finish("failed","cat_busy");return
	if action=="wander":world.director.routines[id].kind="wander"
	if choice.has("scheduled"):
		world.director.routines[id].kind="schedule"
		current.duration=float(world.schedules.config.stay_seconds)
		world.schedules.next_after[id]=clock+float(world.schedules.config.interval)
		world.schedules.statistics.started[id]=int(world.schedules.statistics.started.get(id,0))+1
		world.schedules.targets[id]=choice.scheduled.merged({"phase":world.days.phase().id,"arrived":false})
		schedule_options.clear();schedule_due=float(world.schedules.next_after[id])
	if not str(choice.partner).is_empty() and not choice.get("paired",false):
		if not invite(choice.partner,action):finish("failed","social_refused");return
		var other:RefCounted=world.director.brains[choice.partner]
		var center:Vector2=world.point(world.actors[choice.partner])
		choice["point"]=center+Vector2(1.5,0)
		current["paired"]=true
		other.invitation["point"]=center
		other.invitation["paired"]=true
		other.interactions.peer_session=id+":"+str(clock)
		other.interactions.peer_reply=false
		interactions.peer_reply=false
		trace({"actor":id,"at":clock,"event":"peer_accept","choice":action,"partner":choice.partner,"reasons":["social"],"session":other.interactions.peer_session})
		interactions.peer_session=other.interactions.peer_session
		interactions.deliver("peer_invite","invitation:"+action,choice.partner,"peer_invitation")
	var feelings:Dictionary=world.hearts.mood(id)
	var bounds:Dictionary=world.hearts.config.proximity
	var emotion_move:bool=world.hunger.rank(id)<3 and not choice.has("point") and not choice.has("scheduled") and str(choice.partner).is_empty() and ((action in world.hearts.config.choice.solitude_actions and float(feelings.hurt)-float(world.hearts.config.baseline.hurt)>=float(bounds.threshold) and distance()<float(bounds.hurt_inner)) or (float(feelings.joy)-float(world.hearts.config.baseline.joy)>=float(bounds.threshold) and distance()>float(bounds.joy_outer)))
	var move:bool=emotion_move or choice.has("point") or choice.has("scheduled") or action in ["wander","follow","food"] or distance()>float(config.follow_max) or distance()<float(config.follow_min)
	if move:
		var p:Vector2=choice.point if choice.has("point") else choice.scheduled.point if choice.has("scheduled") else destination(action)
		if not p.is_finite():finish("failed","no_reachable_position");return
		if world.open_life and action=="social_banter":
			# Local posture changes use World without emitting a player-order cooldown.
			if world.point(world.actors[id]).distance_to(p)>.05 and not world.route_to(id,p):finish("failed","unreachable");return
		else:
			executing=true
			world.host_issuing[id]=true;world.director.routines[id].issuing=true
			var result:Dictionary=world.command(id,{"intent":"move","x":p.x,"y":p.y,"region_id":world.actors[id].region_id})
			world.director.routines[id].issuing=false;world.host_issuing.erase(id);executing=false
			if not result.get("ok",false):finish("failed",str(result.get("error","unreachable")));return
		route=world._routes.get(id);world.director.routines[id].owns_route=route!=null;last_position=world.point(world.actors[id]);current.arrived=-1.0
		world.director.destinations[id]={"region":world.actors[id].region_id,"point":p}
	world.intelligence.note_behavior(id,action)
	intention.executing_plan()
	pose()
func advance_special(delta:float)->bool:
	executing=true
	var r:RefCounted=world.director.routines[id]
	var running:bool=world.dark.companions.tick(r,delta) if special_provider=="dark_life" else world.their_island.story_tick(r,delta)
	executing=false
	return running
func pose()->void:
	if current.is_empty() or current.source!="local" or world._routes.has(id):return
	var a:Dictionary=config.actions.get(current.action,config.actions.daydream)
	var visual:String="local_look" if current.get("onlooker",false) else str(a.pose)
	world.actors[id].activity=visual if visual in ["play_cute","play_squat","play_lie","local_sit"] else "local_look"
	world.lively.active[id]={"action":visual,"start":float(current.arrived),"until":clock+float(current.duration)}
	world.lively.time=clock
	if current.action=="play_cute":world.actors[id].activity="play_cute"
	if a.get("requires","")=="rhythm":rhythm.speak(current.action)
func advance(delta:float)->void:
	var measured:int=Time.get_ticks_usec()
	_advance_body(delta)
	profile_usec+=Time.get_ticks_usec()-measured;profile_frames+=1

func owns_local_job() -> bool:
	if current.get("origin") not in ["local","self_meal"]:return false
	var job_id:String=str(current.get("job_id",""))
	return not job_id.is_empty() and world.work.jobs.get(id,{}).get("id")==job_id

func pause_for_player(wait_near:bool=false)->void:
	if world.director.model_controlled(id) or world.actors[id].has("world_door_client"):return
	var job:Dictionary=world.work.jobs.get(id,{})
	if owns_local_job() and job.get("intent")=="gather_wood":
		paused_wood={"job":job.duplicate(true),"plan":current.basic_plan.duplicate(true),"index":current.index,"origin":current.origin}
		paused_wood_wait_order=""
	if not paused_wood.is_empty():paused_wood_wait_near=wait_near
	if current.get("source")=="local":finish("interrupted","player_order")

func resume_player_paused_wood()->bool:
	if paused_wood.is_empty() or not paused_wood_wait_order.is_empty() or not eligible(true) or busy() or world.director.model_controlled(id):return false
	if paused_wood_wait_near and world.activities.following.has(id) and distance()>4:return false
	if world._routes.has(id):return false
	var job:Dictionary=paused_wood.job
	if world.actors[id].region_id!=job.region_id:return false
	var saved:Dictionary=paused_wood.duplicate()
	paused_wood.clear()
	var target:Dictionary={}
	if job.phase=="chop":
		target=world.objects.get(job.target_id,{})
		if target.get("status")!="mature":target={}
	elif job.phase in ["fall_wait","pickup"]:
		target=world.drops.get(job.drop_id,{})
		job.phase="pickup"
	if not target.is_empty() and not world.work.claims.has(target.id) and world.approach(id,target):
		world.work.claims[target.id]=id
	elif job.phase!="gather_prepare":
		if job.phase=="pickup" and not job.has("active_tree_id"):job.erase("drop_id")
		if job.phase in ["chop","pickup"] and int(job.get("trees_cut",0))>0 and target.is_empty() and int(world.actors[id].carry.get("wood",0))==0:
			# Another resident has already hauled the original drop. No second cut.
			return false
		job.phase="gather_prepare"
	finish("interrupted","resume_player_paused_wood")
	world.work.jobs[id]=job
	route=world._routes.get(id)
	current={"action":"basic_plan","source":"local","basic_plan":saved.plan,"index":saved.index,"until":clock+120,"region":job.region_id,"origin":saved.origin,"action_id":"","job_id":job.id}
	world.revision+=1
	return true

func owns_local_route() -> bool:
	return current.get("origin")=="local" and route!=null and is_same(route,world._routes.get(id))

func try_self_meal() -> bool:
	if not world.open_life or world.director.model_controlled(id) or world.hunger.rank(id)<2 or clock<next_self_meal or busy() or not eligible():return false
	if current.has("basic_plan"):return false
	next_self_meal=clock+15
	var camp:Dictionary=world.barbecues.get("home.barbecue",{}).station
	if world.actors[id].region_id!=camp.region_id:return false
	var fire:RefCounted=world.barbecues["home.barbecue"].fireside
	if fire.active() and not fire.circle_closed and not fire.state.current.is_empty():return false
	for brain in world.director.brains.values():
		if brain.current.get("origin")=="self_meal":return false
	var steps:Array=[]
	var fuel:int=0 if fire.burning() else int(fire.config.wood)
	var site_id:String=world.standard.site_for(camp.id)
	if not world.standard.ready(camp.id):
		var site:Dictionary=world.leisure.sites[site_id]
		if not world.residents.supports(world.actors[id],"build_facility"):return false
		fuel+=maxi(0,world.leisure.cost(site)-int(site.invested))
	if world.storage.count("wood")<fuel:steps.append({"action":"chop_and_haul","target":""})
	if not world.standard.ready(camp.id):steps.append({"action":"build","target":site_id})
	steps.append({"action":"eat_mushrooms","target":camp.id})
	var why:String="想去烤点蘑菇。" if not TranslationServer.get_locale().begins_with("en") else "I could use some roasted mushrooms."
	return intention.basic.accept({"reason":why,"steps":steps},"self_meal")

func _advance_body(delta:float)->void:
	if not active() or delta<=0:return
	if generation!=int(world.get("session_generation") if world.get("session_generation")!=null else 0):reset()
	clock=world.director.time
	if world.actors[id].has("world_door_client"):
		paused_wood.clear()
		if current.get("origin")=="world_door":
			if world.director.routines[id].held:finish("interrupted","held")
			else:intention.basic.tick()
		return
	intention.advance()
	var routine:RefCounted=world.director.routines[id]
	if not world.activities.following.has(id) and not world.director.model_controlled(id):
		var idle_contact:bool=not current.has("basic_plan") and not world.work.jobs.has(id) and not world.deliveries.active(id) and not world._routes.has(id)
		routine.return_visit.observe(routine,distance(),idle_contact)
	if current.has("basic_plan") and current.get("origin") in ["requested_help","native_world","native","island_ai"]:
		if routine.held or (current.origin!="native" and clock<routine.visual_quiet_until):
			finish("interrupted","held" if routine.held else "stop_quiet")
		else:intention.basic.tick()
		return
	if not routine.enabled or routine.held:
		if current.get("source","")=="local" and (routine.held or current.get("action","") not in ["follow","food"]):finish("interrupted",hold_reason if routine.held and not hold_reason.is_empty() else "held" if routine.held else "activity_disabled")
		return
	update_needs(delta)
	if world.work.jobs.has("human") or world._routes.has("human"):last_host_busy=clock
	interactions.observe();interactions.refusal_tick()
	if not interactions.pending.is_empty() and current.get("action","")!="host_interaction":
		var committed_reply:bool=interactions.pending.get("kind")=="host_reply"
		var reply_range:float=float(config.host_replies.witness_radius if committed_reply else interactions.data.near_distance)
		if distance()<=reply_range and (committed_reply or busy() or world.hunger.rank(id)>=2):
			if interactions.deliver_pending():trace({"actor":id,"at":clock,"event":"candidate","choice":"host_interaction","source":"local","reasons":["observed_event"],"outcome":"delivered_without_interrupt"})
	interactions.tick_current()
	if id in world.activities.opening_party and world.hunger.rank(id)<3:
		if current.get("source","")=="local":finish("interrupted","opening_welcome")
		return
	if not eligible(true):
		if current.get("source","")=="local":finish("interrupted","stop_quiet" if clock<routine.visual_quiet_until else "holding_item_or_rushing")
		return
	# A newly accepted AI intention outranks an idle local scene. End that exact
	if current.get("source","")=="local" and world.dark!=null and world.dark.here() and world.actors[id].region_id=="dark" and not world.dark.permanent(world.point(world.actors.human)) and current.action!="dark_life" and not (world.hunger.rank(id)>=3 and current.action=="food"):finish("interrupted","dark_fear")
	if current.has("basic_plan"):
		intention.basic.tick()
		return
	if island_plan_ready.is_valid() and island_plan_ready.call():return
	if resume_player_paused_wood():return
	if current.is_empty() and begin_return_visit(routine,delta):return
	if try_self_meal():return
	if current.has("outing_job"):
		if not world.flower_creation.active(id) and busy():finish("interrupted","real_activity");return
		intention.outings.advance(current.outing_job,current.ai_plan)
		return
	if current.has("heart_guest"):
		if busy() or (world._routes.has(id) and not is_same(route,world._routes[id])):finish("interrupted","guest_route_or_command");return
		if clock-float(current.start)>155:finish("timeout","guest_route_timeout");return
		if not world._routes.has(id):
			if float(current.arrived)<0:current.arrived=clock
			pose()
		return
	if not current.is_empty() and current.source!="local" and world._routes.has(id):
		var p:Vector2=world.point(world.actors[id]);still=still+delta if p.distance_to(last_position)<.001 else 0.0;last_position=p
		if still>=float(config.stall_seconds):
			var job:String=str(current.get("job_id",""))
			if not job.is_empty() and world.work.jobs.get(id,{}).get("id")==job:world.work.stop(id,false)
			elif not busy():world._routes.erase(id)
			finish("timeout","route_stalled");return
	if provider_running:
		if special_provider=="return_visit":
			if busy_for_visit() or not advance_return_visit(routine,delta):
				finish("interrupted","visit_blocked")
			elif routine.kind!="return_visit":
				finish("completed")
			return
		if not special_provider.is_empty():
			if not advance_special(delta):finish("completed")
			elif clock-float(current.start)>float(config.external_timeout):finish("timeout","special_timeout")
			return
		if world._routes.has(id):
			var p:Vector2=world.point(world.actors[id]);still=still+delta if p.distance_to(last_position)<.001 else 0.0;last_position=p
			if still>=float(config.stall_seconds):finish("timeout","provider_stalled");return
		executing=true;world.director.routines[id].advance_brain_executor(delta);executing=false
		if world.director.routines[id].kind.is_empty():finish("completed" if current.get("job_result","completed")=="completed" else "failed",str(current.get("job_result","")));return
		if clock-float(current.start)>float(config.external_timeout):finish("timeout","provider_timeout")
		return
	if rhythm.home_door():return
	if busy():
		if not current.is_empty() and current.source!="local" and clock-float(current.start)>float(config.external_timeout):
			if external_cancel.is_valid():external_cancel.call()
			var job:String=str(current.get("job_id",""))
			if not job.is_empty() and world.work.jobs.get(id,{}).get("id")==job:world.work.stop(id,false)
			finish("timeout","executor_timeout");return
		if current.get("source","")=="local":finish("interrupted","real_activity")
		if current.is_empty():begin_external("command","blocked")
		return
	if not current.is_empty() and current.source!="local":
		if not world._routes.has(id):finish("completed" if current.get("job_result","completed")=="completed" else "failed",str(current.get("job_result","")))
		elif clock-float(current.start)>float(config.external_timeout):finish("timeout","executor_timeout")
		else:return
	if not world.open_life and not world.activities.following.has(id) and not world.activities.default_follow_excluded.has(id):world.activities.following[id]=true
	if not current.is_empty():
		if not str(current.get("partner","")).is_empty() and str(current.get("coop","")).is_empty() and not current.get("outing_guest",false):
			var peer:Dictionary=world.actors.get(current.partner,{})
			if peer.is_empty() or peer.region_id!=world.actors[id].region_id or world.point(peer).distance_to(world.point(world.actors[id]))>float(world.lively.config.pair_distance):finish("failed","partner_left");return
		if (current.action=="night_rest" and world.days.phase().id!="night") or (current.action=="rain_shelter" and world.weather.current().id!="rain"):
			if current.action=="night_rest" and float(current.arrived)>=0:world.hearts.react(id,"wake")
			finish("completed","conditions_changed");return
		if current.get("onlooker",false) and onlooker.presentation(world,id,clock,false).is_empty():finish("completed","meal_finished");return
		if current.action=="stars" and (world.days.phase().id!="night" or world.weather.current().id in ["rain","fog"]):finish("completed","conditions_changed");return
		if route!=null and world._routes.has(id):
			if not is_same(route,world._routes[id]):finish("interrupted","route_replaced");return
			var p:Vector2=world.point(world.actors[id]);still=still+delta if p.distance_to(last_position)<.001 else 0.0;last_position=p
			if still>=float(config.stall_seconds) or clock-float(current.start)>=float(config.route_timeout):finish("timeout","route_stalled");return
		elif float(current.arrived)<0:
			current.arrived=clock;route=null;world.director.routines[id].owns_route=false
			if current.action=="food":current["status"]="waiting_for_meal"
			if current.action=="follow" and distance()<=8:
				var visits:Array=world.director.routines[id].return_visit.arrivals
				visits.append({"at":clock,"distance":distance(),"travel_seconds":clock-float(current.start)})
				if visits.size()>64:visits.pop_front()
			if current.has("scheduled"):world.schedules.targets[id].arrived=true;world.schedules.statistics.arrived[id]=int(world.schedules.statistics.arrived.get(id,0))+1
		if not current.is_empty() and float(current.arrived)>=0:
			pose()
			if current.action not in ["small_coop","social_banter"] and current.get("paired",false) and clock>=interactions.next_pair:
				var other:RefCounted=world.director.brains.get(current.partner)
				if other!=null and other.current.get("action","")==current.action and other.current.get("paired",false):
					if not interactions.peer_reply and interactions.deliver("peer_comment",interactions.peer_session,current.partner,"peer_comment"):
						interactions.peer_reply=true;interactions.next_pair=clock+float(interactions.data.pair_seconds)
			if current.action!="host_interaction" and str(current.get("coop","")).is_empty() and clock-float(current.arrived)>=float(current.duration):finish("completed")
	# A live two-person scene keeps its already accepted local pose until its dialogue ends.
	# Commands, held/quiet, real work, host movement and very-hungry checks still win above.
	if current.has("ai_plan"):return
	if not current.is_empty() or clock<next_decision:return
	if intention.outings.meetings!=null and intention.outings.meetings.reserved_guest(id):return
	next_decision=clock+2
	var choices:Array=candidates()
	var proposed:Dictionary=intention.candidate(choices)
	if not proposed.is_empty():
		start(proposed,[proposed])
		return
	if world.director.model_controlled(id):return
	if world.dark!=null and world.dark.here() and world.actors[id].region_id=="dark":
		var dark_choice:Dictionary={"action":"dark_life","score":0.0,"reasons":["dark"],"partner":""}
		start(dark_choice,[dark_choice])
		return
	if world.activities.following.has(id):
		follow()
		return
	if begin_return_visit(routine,delta):return
	if not world.open_life and clock>=routine.next_decision:
		var idle_choice:Dictionary={"action":"legacy_idle","score":0.0,"reasons":["schedule"],"partner":""}
		start(idle_choice,[idle_choice])
		if provider_running:return
	var options:Array=["wander","chop_and_haul","play"]
	var staying_near:bool=island_plan_ready.is_valid() and world.actors[id].region_id=="home" and world.point(world.actors[id]).x< -30
	if staying_near:options=["wander","play","explore_moon"]
	if world.hunger.rank(id)<2:
		options.append("fish")
	var choice:String=options[rng.randi_range(0,options.size()-1)]
	var steps:Array=[]
	if not world.fishing.held(id).is_empty():return
	match choice:
		"wander":
			var piece:Dictionary=world.flower_creation.creations.local_piece(id)
			if not piece.is_empty():steps=[piece]
		"fish":steps=[{"action":"fish"}]
		"chop_and_haul":steps=[{"action":"chop_and_haul","target":""}]
		"play":
			var nearby:Array=[]
			for site in world.leisure.sites.values():
				if site.get("complete",false) and site.get("template_id")=="play-bench" and not world.standard.sites.has(site.id):
					if staying_near:
						if world.point(site).distance_to(world.point(world.actors[id]))<=16:nearby.append(site.id)
						continue
					steps=[{"action":"play_at","target":site.id}]
					break
			if not nearby.is_empty():steps=[{"action":"play_at","target":nearby[rng.randi_range(0,nearby.size()-1)]}]
		"explore_moon":
			var anchor:Array=world.map_anchor("moon.lookout")
			if anchor.size()==2:
				var waypoint:String="moon.camp" if world.point(world.actors[id]).distance_to(Vector2(anchor[0],anchor[1]))<6 else "moon.lookout"
				steps=[{"action":"go_to","target":waypoint}]
	if not steps.is_empty() and intention.basic.accept({"reason":"Daily life","steps":steps},"local"):return
	if not choices.is_empty():start(choices[rng.randi_range(0,choices.size()-1)],choices)
func busy_for_visit()->bool:
	return world.activities.following.has(id) or world.work.jobs.has(id) or world.farms.active(id) or world.projects.active(id) or world.deliveries.active(id) or world.activities.blocked(id,false) or world.activities.commanded(id) or world.director.model_controlled(id)
func begin_return_visit(routine:RefCounted,delta:float)->bool:
	if busy_for_visit() or world._routes.has(id) or not advance_return_visit(routine,delta):return false
	current={"action":"follow","source":"local","start":clock,"arrived":-1.0,"duration":float(config.actions.follow.duration),"reasons":["visit"],"partner":""}
	provider_running=true
	special_provider="return_visit"
	route=world._routes.get(id)
	return true
func advance_return_visit(routine:RefCounted,delta:float)->bool:
	executing=true
	var advanced:bool=routine.return_visit.tick(routine,delta)
	executing=false
	return advanced
func can_take_chat_break()->bool:return false
func summary(language:String="")->Dictionary:
	var lang:String=language if not language.is_empty() else ("en" if TranslationServer.get_locale().begins_with("en") else "zh")
	var action:String=str(current.get("action","held" if world.director.routines[id].held else "quiet"))
	if current.get("source","")=="command" and not config.command_labels.has(action):action="command_activity"
	var reasons:Array=current.get("reasons",["follow"])
	var lines:Array=[]
	for reason in reasons.slice(0,3):
		lines.append(str(config.voices.get(tag(),config.voices.gentle).personality[1 if lang=="en" else 0]) if reason=="personality" else text(reason,lang))
	var words:Dictionary={}
	for key in needs:words[key]=config.need_words[key][1 if float(needs[key])>=float(config.needs_context.word_thresholds[0]) and float(needs[key])<float(config.needs_context.word_thresholds[1]) else 2 if float(needs[key])>=float(config.needs_context.word_thresholds[1]) else 0][1 if lang=="en" else 0]
	words.hunger=preload("res://scripts/localization.gd").text(world.hunger.NAMES[world.hunger.rank(id)])
	var voice:Dictionary=config.voices.get(tag(),config.voices.gentle)
	var detail:String=action_name(action,lang)
	var sentence:String=str(voice.prefix[1 if lang=="en" else 0])+ (" " if lang=="en" else "")+detail+( ", " if lang=="en" else "，")+str(voice.because[1 if lang=="en" else 0])+(" " if lang=="en" else "")+("; " if lang=="en" else "、").join(lines)+("." if lang=="en" else "。")
	return {"action":action,"sentence":sentence,"needs":words,"recent":history.slice(-int(config.panel_history)).duplicate(true)}

func execute_provider(action:String,body:Callable,explicit:bool=false)->bool:
	if not explicit and (current.has("ai_plan") or not intention.pending.is_empty()):return false
	if not eligible() or busy() or world._routes.has(id):return false
	var choice:Dictionary={"action":action,"score":float(config.special_score)+float(config.scores.return),"reasons":["social"],"partner":""}
	offer(action,body);start(choice,[choice])
	return provider_running
