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
var free_since:=-100000.0
func _init(w:RefCounted,who:String)->void:
	owner=weakref(w);id=who;reset()
func active()->bool:return world.intelligence!=null and not world.intelligence.compatibility
func reset()->void:
	balance_events.clear();category_recent.clear();last_host_busy=-100000.0
	current.clear();history.clear();recent.clear();invitation.clear();top.clear();route=null;still=0;next_decision=0;clock=0;last_near=0;seen_places.clear();schedule_due=0;next_visit=0;offers.clear();provider_running=false;special_provider=""
	needs={"tired":0.0,"bored":.25,"missing":0.0,"curious":.5}
	generation=int(world.get("session_generation") if world.get("session_generation")!=null else 0)
	interactions=preload("res://scripts/brain_interactions.gd").new(self);rhythm=preload("res://scripts/brain_rhythm.gd").new(self);refusal.clear()
	var seed_text:String=OS.get_environment("HABITAT_BRAIN_SEED")
	rng.seed=(int(seed_text) if not seed_text.is_empty() else int(config.seed))+int(id.hash())
func text(key:String,language:String="")->String:
	var lang:String=language if not language.is_empty() else ("en" if TranslationServer.get_locale().begins_with("en") else "zh")
	var voice:Dictionary=config.voices.get(tag(),config.voices.gentle)
	return str(voice.get(key,config.text.get(key,[key,key]))[1 if lang=="en" else 0])
func tag()->String:return world.intelligence.tag(id)
func action_name(key:String,language:String="")->String:
	if config.command_labels.has(key):return str(config.command_labels[key][1 if (language=="en" or (language.is_empty() and TranslationServer.get_locale().begins_with("en"))) else 0])
	if key not in config.actions and not config.text.has(key):key="command_activity"
	var lang:String=language if not language.is_empty() else ("en" if TranslationServer.get_locale().begins_with("en") else "zh")
	return str(config.actions.get(key,{}).get(lang,text(key,lang)))
func finish(outcome:String,reason:String="")->void:
	if current.is_empty():return
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
	if source=="steward" and current.get("source","")==source and current.get("action","")==action:return
	finish("interrupted","higher_priority")
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
func category(action:String)->String:
	for group in config.balance.groups:
		if action in config.balance.groups[group]:return group
	return action
func balance_penalty(action:String)->float:
	var group:String=category(action)
	return float(config.balance.freshness_penalty)*maxf(0,1-(clock-float(category_recent.get(group,-100000)))/float(config.balance.freshness_seconds))
func social_allowed(action:String,peer:String="")->bool:
	if clock-last_host_busy<float(config.balance.host_activity_quiet_seconds):return false
	var count:=0;var pairs:=0;var total:=0;var village:=0
	for brain in world.director.brains.values():
		for row in brain.balance_events:
			if row.action==action and clock-float(row.at)<float(config.balance.window_seconds):village+=1
	if village>=2*int(config.balance.social_village_limits[action]):return false
	for row in balance_events:
		if clock-float(row.at)>=float(config.balance.window_seconds):continue
		if clock-float(row.at)<float(config.balance.social_cooldown_seconds):return false
		total+=1
		if row.action==action:
			count+=1
			if row.peer==peer:pairs+=1
	return total<int(config.balance.social_total_limit) and count<int(config.balance.social_actor_limit) and (peer.is_empty() or pairs<int(config.balance.social_pair_limit))
func effect(source:String,action:String,body:Callable)->Variant:
	if source=="local" and action=="social_banter" and not social_allowed(action):return false
	trace({"actor":id,"at":clock,"event":"candidate","choice":action,"source":source,"score":float(config.scores.mandatory),"reasons":[source]})
	var result:Variant=body.call()
	if source=="local" and action=="social_banter" and social_ledger().by_actor.has(id):
		var session:Dictionary=social_ledger().sessions[social_ledger().by_actor[id]]
		if session.members.any(func(who):return not world.director.brains[who].social_allowed(action,session.members[1] if who==session.members[0] else session.members[0])):
			social_ledger().end(session,"frequency_limit");return false
	var row:Dictionary={"actor":id,"at":clock,"day":world.days.day(),"event":"dispatch","choice":action,"source":source,"via":"ResidentBrain","reasons":[source],"outcome":"completed" if result==null or result else "deferred"}
	trace(row)
	if result==null or result:
		history.append(row.duplicate(true))
		if history.size()>int(config.history_limit):history.pop_front()
	return result
static func team(w:RefCounted,ids:Array,action:String,body:Callable)->Dictionary:
	if ids.is_empty():return body.call()
	var who:String=str(ids[0])
	if not w.director.brains.has(who):return team(w,ids.slice(1),action,body)
	return w.director.brains[who].mandate("steward",action,func():return team(w,ids.slice(1),action,body))
func command(args:Dictionary)->Dictionary:
	var intent:String=str(args.get("intent",""))
	if intent=="move" and world.activities.explicit_selected.has(id) and not world.host_issuing.has(id) and not world.activities.suspended_follow.has(id) and not world.activities.commanded(id):return world._command_body(id,args)
	if not active() or executing or intent.ends_with("_read") or intent in ["query_state","propose","promise","promise_cancel","journal_read"]:return world._command_body(id,args)
	return mandate("steward" if not world.host_issuing.has(id) and not world.activities.squad_leader.is_empty() else "command",intent,func():return world._command_body(id,args))
func sheltering()->bool:
	if current.get("source","")!="local" or world._routes.has("human") or world.hunger.rank(id)>=3:return false
	return (current.get("action")=="night_rest" and world.days.phase().id=="night") or (current.get("action")=="rain_shelter" and world.weather.current().id=="rain")
func follow(dark_fear:bool=false)->void:
	if not active() or executing:world.hunger._follow_body(id,dark_fear);return
	# Other providers request follow; only the brain may grant it while idle.
	if current.get("source","") in ["command","steward"] or busy() or sheltering():return
	if current.get("source","")=="local" and current.action in ["follow","food"]:
		executing=true;world.hunger._follow_body(id,dark_fear);executing=false
		if world._routes.has(id):route=world._routes[id];current.arrived=-1.0
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
	if current.get("source","")=="local":finish("interrupted","follow_preference")
	if not following:
		free_since=clock
		next_visit=clock+float(world.director.routines[id].return_visit.options(world.director.routines[id]).interval_seconds)
	next_decision=clock
func distance()->float:
	return world.point(world.actors[id]).distance_to(world.point(world.actors.human)) if world.actors[id].region_id==world.actors.human.region_id else INF
func busy()->bool:
	if provider_running:return false
	return world.activities.suspended_follow.has(id) or world.work.jobs.has(id) or world.farms.active(id) or world.projects.active(id) or world.homestead.active(id) or world.deliveries.active(id) or world.activities.blocked(id,false) or world.activities.commanded(id) or (external_busy.is_valid() and external_busy.call())
func eligible()->bool:
	var r:RefCounted=world.director.routines[id]
	return r.enabled and not r.held and (clock>=r.visual_quiet_until or (world.hunger.rank(id)>=3 and world.hunger.can_follow(id))) and not r.transporting() and world.fishing.held(id).is_empty() and not world.hunger.rushes.has(id)
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
func social_ledger()->RefCounted:
	if world.director.brain_social==null:world.director.brain_social=preload("res://scripts/brain_social.gd").new(world)
	return world.director.brain_social
func candidates()->Array:
	var result:Array=[]
	var r:RefCounted=world.director.routines[id]
	if clock>=r.next_decision and not world.activities.following.has(id) and r.preferences.weights.values().reduce(func(sum,value):return sum+float(value),0.0)>0 and world.hunger.rank(id)<3:
		result.append({"action":"legacy_idle","score":float(config.special_score)+float(config.scores.return),"reasons":["curious"],"partner":""})
	if world.hunger.rank(id)==2 and not onlooker.presentation(world,id,clock,false).is_empty():
		result.append({"action":"food","score":float(config.special_score)+float(config.scores.return),"reasons":["hunger"],"partner":"","onlooker":true})
	var hungry:bool=world.hunger.rank(id)>=3
	var following:bool=world.activities.following.has(id)
	var dark_fear:bool=world.dark!=null and world.dark.here() and world.actors[id].region_id=="dark" and not world.dark.permanent(world.point(world.actors.human))
	var peer:String=""
	var ids:Array=world.director.brains.keys();ids.sort()
	for who in ids:
		if who!=id and world.actors[who].region_id==world.actors[id].region_id and world.point(world.actors[who]).distance_to(world.point(world.actors[id]))<=5:peer=who;break
	var visit:Dictionary=world.director.routines[id].return_visit.options(world.director.routines[id])
	var return_due:bool=clock-last_near>=float(visit.interval_seconds)
	var far_due:bool=distance()>float(visit.far_distance) and clock-last_near>=float(visit.far_seconds)
	if clock>=schedule_due:
		schedule_due=clock+float(world.schedules.config.retry)
		schedule_options=world.schedules.options(id) if clock>=float(world.schedules.config.first_after) and rng.randf()<float(world.schedules.config.chance) else []
	var phase_weights:Dictionary=rhythm.weights()
	for key in config.actions:
		var a:Dictionary=config.actions[key]
		var scheduled:Dictionary={}
		if a.requires in ["interaction","social_scene"]:continue
		if a.requires=="rhythm" and not rhythm.available(key):continue
		if a.requires=="dark" and (world.dark==null or not world.dark.here() or world.actors[id].region_id!="dark"):continue
		if a.requires=="story":
			var story:RefCounted=world.their_island
			if story==null or world.actors[id].region_id!="home" or not story.config.presets.has(id) or story.story_busy(world.director.routines[id]):continue
			var arrival:bool=world.home_island.here() and world.home_island.contains(world.point(world.actors[id])) and id not in story.arrivals
			var intro:bool=world.opening_id=="standard" and not story.introduced and not world.home_island.here()
			if not (story.unlocked or world.opening_id=="showcase") or not (arrival or intro):continue
		if a.requires=="schedule":
			for option in schedule_options:
				if key!="schedule_"+str(option.place):continue
				if following and world.point(world.actors.human).distance_to(option.point)>float(config.follow_max):continue
				if scheduled.is_empty() or option.weight>scheduled.weight:scheduled=option
			if scheduled.is_empty():continue
		if a.requires=="pet" and (not world.cat.discovered or world.cat.region!=world.actors[id].region_id or world.cat.position.distance_to(world.point(world.actors[id]))>3 or not world.cat.carrier.is_empty()):continue
		if a.requires=="flower_gift" and (not world.flower_gifts.eligible(id) or not world.flower_gifts.patches.any(func(patch):return patch.point.distance_to(world.point(world.actors.human))<=float(config.follow_max))):continue
		if a.requires=="facility" and not world.leisure.sites.values().any(func(site):return site.complete and site.region_id==world.actors[id].region_id and world.point(site).distance_to(world.point(world.actors.human))<=float(config.follow_max)):continue
		if hungry and key!="food":continue
		if key=="food" and world.hunger.rank(id)<0:continue
		if dark_fear and not hungry and key!="dark_life":continue
		if key=="follow" and not following and (clock-free_since<float(world.director.routines[id].return_visit.options(world.director.routines[id]).far_seconds) or (not return_due and not far_due and clock<next_visit)):continue
		if a.requires=="night_clear" and (world.days.phase().id!="night" or world.weather.current().id in ["rain","fog"]):continue
		if a.requires=="near_cat" and (not world.cat.discovered or world.cat.region!=world.actors[id].region_id or world.cat.position.distance_to(world.point(world.actors[id]))>8):continue
		if a.requires=="peer" and peer.is_empty():continue
		if key=="pair_sea" and world.fishing.shore(id).is_empty():continue
		if a.requires=="near_coast":
			var sea:Array=world.catalog.regions.home.get("layout",{}).get("schedule_anchors",{}).get("sea",[])
			if sea.is_empty() or not sea.any(func(anchor):var p:Array=world.map_anchor(anchor);return Vector2(p[0],p[1]).distance_to(world.point(world.actors[id]))<=32):continue
		var preference:float=float(config.preferences.get(tag(),{}).get(key,0))
		var n:float=float(world.hunger.rank(id))/3.0 if a.need=="hunger" else float(needs.get(a.need,0))
		var components:Array=[{"key":"personality","value":preference},{"key":a.need,"value":n*float(a.need_weight)*(1+preference/float(config.needs_context.personality_need_scale))}]
		if following:components.append({"key":"follow","value":float(config.scores.follow)})
		if key in ["follow","food"] and (distance()>float(config.follow_max) or return_due or hungry or (key=="follow" and not following and clock>=next_visit)):components.append({"key":"hunger" if hungry else "missing","value":float(config.scores.return)})
		if a.requires in ["dark","story"]:components.append({"key":"curious","value":float(config.special_score)})
		if key=="follow" and not following and (far_due or return_due):components.append({"key":"missing","value":float(config.special_score)})
		if key=="stars":components.append({"key":"night","value":float(config.scores.night)})
		if key in ["chat","back_to_back"]:components.append({"key":"social","value":float(config.scores.social)+float(world.relationships.index(id))*float(config.social_relation_weight)})
		if not scheduled.is_empty():components.append({"key":"weather","value":float(scheduled.weight)*float(config.schedule_weight)})
		if world.weather.current().id in ["rain","fog"] and a.need=="tired":components.append({"key":"weather","value":float(config.scores.weather)})
		if invitation.get("action")==key and clock<float(invitation.get("until",0)):components.append({"key":"invite","value":float(config.invite_bonus)})
		if phase_weights.has(key):components.append({"key":"rhythm_rain" if world.weather.current().id=="rain" and key=="rain_shelter" else "rhythm_"+str(world.days.phase().id),"value":float(phase_weights[key])})
		if key=="food":
			var rank:int=world.hunger.rank(id)
			components=[{"key":"hunger","value":float(config.food_scoring.base_by_rank[rank])+float(config.food_scoring.return_by_rank[rank])+(float(config.food_scoring.lively_by_rank[rank]) if tag()=="lively" else 0.0)}]
		var score:float=float(a.base)+rng.randf_range(-float(config.jitter),float(config.jitter))
		for component in components:score+=float(component.value)
		if recent.has(key):score-=float(config.novelty_penalty)*maxf(0,1-(clock-float(recent[key]))/float(config.novelty_seconds))
		if not hungry:
			score-=balance_penalty(key)
			if world.days.phase().id=="morning" and key in config.balance.morning_actions:score+=float(config.balance.morning_rhythm_bonus)
			if key in config.balance.signatures.get(tag(),[]):score+=float(config.balance.signature_bonus)
			if key=="food":score-=float(config.balance.food_penalty_by_rank[world.hunger.rank(id)])
			if key=="follow" and following and last_host_busy>0 and not sheltering() and distance()>float(config.follow_max):score+=float(config.balance.return_score)
		components.sort_custom(func(x,y):return x.value>y.value)
		var candidate:Dictionary={"action":key,"score":score,"reasons":components.filter(func(c):return float(c.value)>0).slice(0,3).map(func(c):return c.key),"partner":peer if a.requires=="peer" else ""}
		if not scheduled.is_empty():candidate["scheduled"]=scheduled
		result.append(candidate)
	for action in offers.keys():
		if float(offers[action].until)<clock:offers.erase(action);continue
		if not hungry:result.append({"action":action,"score":float(offers[action].get("score",float(config.special_score)+float(config.scores.return))),"reasons":["social"],"partner":""})
	if not hungry and invitation.has("point") and clock<float(invitation.until):
		result.append({"action":invitation.action,"score":float(config.invite_bonus)+100,"reasons":["invite","social"],"partner":invitation.from,"paired":true,"point":invitation.point,"coop":invitation.get("coop","")})
	var cooperative:Dictionary=social_ledger().candidate(self)
	if not cooperative.is_empty() and not hungry and social_allowed("small_coop",cooperative.partner) and world.director.brains[cooperative.partner].social_allowed("small_coop",id):result.append(cooperative)
	var interaction:Dictionary=interactions.candidate()
	if not interaction.is_empty() and not hungry:
		if interaction.get("interaction",{}).get("kind","")!="host_reply":interaction.score-=balance_penalty(interaction.action)
		result.append(interaction)
	result.sort_custom(func(a,b):return a.score>b.score if a.score!=b.score else str(a.action)<str(b.action))
	return result
func offer(action:String,body:Callable,score:float=-1)->void:
	if not offers.has(action):
		offers[action]={"body":body,"until":clock+float(config.decision_seconds)*2}
		if score>=0:offers[action]["score"]=score

func record(options:Array)->void:
	top=options.slice(0,3).duplicate(true)
	var row:Dictionary={"actor":id,"at":clock,"day":world.days.day(),"event":"choice","choice":current.action,"source":current.source,"top":top.duplicate(true),"reasons":current.reasons.duplicate(),"outcome":"running","phase":world.days.phase().id,"weather":world.weather.current().id,"hunger_rank":world.hunger.rank(id)}
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
	for attempt in int(config.destination_attempts):
		var p:Vector2=center+Vector2.from_angle(rng.randf()*TAU)*rng.randf_range(float(config.follow_min),radius)
		if world.walkable(a.region_id,p) and world.director.available_position(id,a.region_id,p):return p
	return Vector2.INF
func start(choice:Dictionary,options:Array)->void:
	finish("interrupted","better_choice")
	if choice.action!="food" or world.hunger.rank(id)<3:world.hunger.clear_follow(id)
	var action:String=choice.action;var a:Dictionary=config.actions.get(action,{"duration":20})
	current=choice.duplicate(true);current.merge({"source":"local","start":clock,"arrived":clock,"duration":float(a.duration)})
	recent[action]=clock;category_recent[category(action)]=clock
	record(options)
	if a.get("requires","")=="rhythm":
		var at:Vector2=rhythm.target(action)
		if at.is_finite():choice["point"]=at
	if choice.get("paired",false):
		invitation.clear()
		if action=="social_banter":offers.erase(action)
	if action=="small_coop":
		if not choice.get("paired",false) and not social_ledger().prepare(self,choice):finish("failed","social_refused");return
		current.merge(choice,true);current.duration=float(config.social_scenes.session_seconds)
	if action=="social_banter" and not choice.get("paired",false) and offers.has(action):
		executing=true;var accepted:bool=offers[action].body.call();executing=false;offers.erase(action)
		if not accepted:finish("failed","social_unavailable");return
		choice.merge({"point":invitation.point,"paired":true,"coop":invitation.coop,"partner":invitation.from},true)
		current.merge(choice,true);current.duration=float(config.social_scenes.session_seconds);invitation.clear()
	if action in ["social_banter","small_coop"]:
		balance_events=balance_events.filter(func(row):return clock-float(row.at)<float(config.balance.window_seconds))
		balance_events.append({"at":clock,"action":action,"peer":choice.get("partner","")})
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
	if action=="food" and world.hunger.rank(id)>=3:
		executing=true;world.hunger._follow_body(id);executing=false
		route=world._routes.get(id);world.director.routines[id].owns_route=route!=null;last_position=world.point(world.actors[id]);current.arrived=-1.0 if route!=null else clock
		return
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
	var move:bool=choice.has("point") or choice.has("scheduled") or action in ["wander","follow","food"] or distance()>float(config.follow_max) or distance()<float(config.follow_min)
	if move:
		var p:Vector2=choice.point if choice.has("point") else choice.scheduled.point if choice.has("scheduled") else destination(action)
		if not p.is_finite():finish("failed","no_reachable_position");return
		executing=true
		world.host_issuing[id]=true;world.director.routines[id].issuing=true
		var result:Dictionary=world.command(id,{"intent":"move","x":p.x,"y":p.y,"region_id":world.actors[id].region_id})
		world.director.routines[id].issuing=false;world.host_issuing.erase(id);executing=false
		if not result.get("ok",false):finish("failed",str(result.get("error","unreachable")));return
		route=world._routes.get(id);world.director.routines[id].owns_route=route!=null;last_position=world.point(world.actors[id]);current.arrived=-1.0
		world.director.destinations[id]={"region":world.actors[id].region_id,"point":p}
	world.intelligence.note_behavior(id,action)
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
	if current.action=="small_coop" and social_ledger().sessions.has(current.get("coop","")):
		var session:Dictionary=social_ledger().sessions[current.coop]
		visual=str(social_ledger().data.cooperation[session.context].poses[session.members.find(id)])
	world.actors[id].activity=visual if visual in ["play_cute","play_squat","play_lie","local_sit"] else "local_look"
	world.lively.active[id]={"action":visual,"start":float(current.arrived),"until":clock+float(current.duration)}
	world.lively.time=clock
	if current.action=="play_cute":world.actors[id].activity="play_cute"
	if a.get("requires","")=="rhythm":rhythm.speak(current.action)
func advance(delta:float)->void:
	var measured:int=Time.get_ticks_usec()
	_advance_body(delta)
	profile_usec+=Time.get_ticks_usec()-measured;profile_frames+=1
func _advance_body(delta:float)->void:
	if not active() or delta<=0:return
	if generation!=int(world.get("session_generation") if world.get("session_generation")!=null else 0):reset()
	clock=world.director.time
	var routine:RefCounted=world.director.routines[id]
	if not routine.enabled or routine.held:
		if current.get("source","")=="local" and (routine.held or current.get("action","") not in ["follow","food"]):finish("interrupted","held_or_quiet")
		return
	update_needs(delta)
	if world.work.jobs.has("human") or world._routes.has("human"):last_host_busy=clock
	interactions.observe();interactions.refusal_tick()
	if social_ledger().by_actor.has(id) or social_allowed("social_banter"):social_ledger().observe(self)
	if not interactions.pending.is_empty() and distance()<=float(interactions.data.near_distance) and current.get("action","")!="host_interaction" and (busy() or world.hunger.rank(id)>=2):
		if interactions.deliver_pending():trace({"actor":id,"at":clock,"event":"candidate","choice":"host_interaction","source":"local","reasons":["observed_event"],"outcome":"delivered_without_interrupt"})
	interactions.tick_current()
	if not world.activities.squad_leader.is_empty():
		if not current.is_empty() and current.source=="steward" and not busy() and not world._routes.has(id):finish("completed")
		if current.get("source","")=="local":finish("interrupted","steward")
		return
	if not eligible():
		if current.get("source","")=="local":finish("interrupted","held_or_quiet")
		return
	if world.hunger.rank(id)>=3 and current.get("source","")=="local" and current.action!="food":finish("interrupted","very_hungry")
	if current.get("source","")=="local" and world.dark!=null and world.dark.here() and world.actors[id].region_id=="dark" and not world.dark.permanent(world.point(world.actors.human)) and current.action!="dark_life" and not (world.hunger.rank(id)>=3 and current.action=="food"):finish("interrupted","dark_fear")
	if not current.is_empty() and current.source!="local" and world._routes.has(id):
		var p:Vector2=world.point(world.actors[id]);still=still+delta if p.distance_to(last_position)<.001 else 0.0;last_position=p
		if still>=float(config.stall_seconds):
			var job:String=str(current.get("job_id",""))
			if not job.is_empty() and world.work.jobs.get(id,{}).get("id")==job:world.work.stop(id,false)
			elif not busy():world._routes.erase(id)
			finish("timeout","route_stalled");return
	if provider_running:
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
	if not world.activities.following.has(id) and not world.activities.default_follow_excluded.has(id):world.activities.following[id]=true
	if not current.is_empty():
		if not str(current.get("partner","")).is_empty() and str(current.get("coop","")).is_empty():
			var peer:Dictionary=world.actors.get(current.partner,{})
			if peer.is_empty() or peer.region_id!=world.actors[id].region_id or world.point(peer).distance_to(world.point(world.actors[id]))>float(world.lively.config.pair_distance):finish("failed","partner_left");return
		if (current.action=="night_rest" and world.days.phase().id!="night") or (current.action=="rain_shelter" and world.weather.current().id!="rain"):finish("completed","conditions_changed");return
		if current.get("onlooker",false) and onlooker.presentation(world,id,clock,false).is_empty():finish("completed","meal_finished");return
		if current.action=="stars" and (world.days.phase().id!="night" or world.weather.current().id in ["rain","fog"]):finish("completed","conditions_changed");return
		if route!=null and world._routes.has(id):
			if not is_same(route,world._routes[id]):finish("interrupted","route_replaced");return
			var p:Vector2=world.point(world.actors[id]);still=still+delta if p.distance_to(last_position)<.001 else 0.0;last_position=p
			if still>=float(config.stall_seconds) or clock-float(current.start)>=float(config.route_timeout):finish("timeout","route_stalled");return
		elif float(current.arrived)<0:
			current.arrived=clock;route=null;world.director.routines[id].owns_route=false
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
	if current.has("coop") and not str(current.coop).is_empty() and social_ledger().by_actor.get(id,"")==current.coop and not world._routes.has("human"):return
	if clock<next_decision:return
	if not world.activities.following.has(id) and clock<world.director.routines[id].next_decision and current.is_empty():return
	next_decision=clock+float(config.decision_seconds)
	var choices:Array=candidates()
	if choices.is_empty():return
	if current.is_empty():start(choices[0],choices);return
	# Arrival satisfies the distance bonus; do not retain a far-away score while
	# already settled beside the host. Keep every authored weight unchanged.
	if current.action=="follow" and float(current.arrived)>=0:
		for choice in choices:
			if choice.action=="follow":current.score=choice.score;break
	if world.activities.following.has(id) and not sheltering() and (distance()>float(config.follow_max)+1 or world._routes.has("human")):
		if current.action not in ["follow","food"]:finish("interrupted","host_moved")
		follow();return
	if current.action!="host_interaction" and choices[0].action!=current.action and float(choices[0].score)>float(current.score)+float(config.persistence)+float(config.switch_margin):start(choices[0],choices)
func summary(language:String="")->Dictionary:
	var lang:String=language if not language.is_empty() else ("en" if TranslationServer.get_locale().begins_with("en") else "zh")
	var action:String=str(current.get("action","held" if world.director.routines[id].held else "quiet"))
	if current.get("source","")=="command" and not config.command_labels.has(action):action="command_activity"
	elif current.get("source","")=="steward" and not config.command_labels.has(action):action="steward_activity"
	var reasons:Array=current.get("reasons",["follow"])
	var lines:Array=[]
	for reason in reasons.slice(0,3):
		lines.append(str(config.voices.get(tag(),config.voices.gentle).personality[1 if lang=="en" else 0]) if reason=="personality" else text(reason,lang))
	var words:Dictionary={}
	for key in needs:words[key]=config.need_words[key][1 if float(needs[key])>=float(config.needs_context.word_thresholds[0]) and float(needs[key])<float(config.needs_context.word_thresholds[1]) else 2 if float(needs[key])>=float(config.needs_context.word_thresholds[1]) else 0][1 if lang=="en" else 0]
	words.hunger=preload("res://scripts/localization.gd").text(world.hunger.NAMES[world.hunger.rank(id)])
	var voice:Dictionary=config.voices.get(tag(),config.voices.gentle)
	var sentence:String=str(voice.prefix[1 if lang=="en" else 0])+ (" " if lang=="en" else "")+action_name(action,lang)+( ", " if lang=="en" else "，")+str(voice.because[1 if lang=="en" else 0])+(" " if lang=="en" else "")+("; " if lang=="en" else "、").join(lines)+("." if lang=="en" else "。")
	return {"action":action,"sentence":sentence,"needs":words,"recent":history.slice(-int(config.panel_history)).duplicate(true)}

func execute_provider(action:String,body:Callable)->bool:
	if not eligible() or busy() or world._routes.has(id):return false
	var choice:Dictionary={"action":action,"score":float(config.special_score)+float(config.scores.return),"reasons":["social"],"partner":""}
	offer(action,body);start(choice,[choice])
	return provider_running
