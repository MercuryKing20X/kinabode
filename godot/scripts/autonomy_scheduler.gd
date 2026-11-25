extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
## Host-side event observer. No model polling, no world mutations, no saved queue.
var _owner: WeakRef
var world: RefCounted:
	get:return _owner.get_ref()
var preferences: RefCounted
var config: Dictionary={}
var dispatch: Callable
var available: Callable
var codex_high: Callable
var histories: Callable
var company_fireside:Callable
var company_ready:Callable
var company_progress:Callable
var queues: Dictionary={}
var active: Dictionary={}
var causal: Dictionary={}
var seen: Dictionary={}
var last_day:=1
var last_input:=0.0
var input_seen:=false
var reflection_after: Dictionary={}
var labor_seen: Dictionary={}
var serial:=0
var life_clock:=0.0
var life_due:Dictionary={}
var error:=""
var records: RefCounted
signal ultra_notice(actor_id: String,estimated_hour: int)

func setup(source: RefCounted,prefs: RefCounted,sender: Callable,can_send: Callable,history: Callable=Callable()) -> void:
	_owner=weakref(source);preferences=prefs;dispatch=sender;available=can_send;histories=history
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/autonomy.json"))
	if not valid_config(data):error=LocalText.text("system.autonomy_scheduler.autonomy_settings_are_invalid_autonomy_is_disabled");return
	world.promises.execution_started.connect(note_model_action);world.promises.settled.connect(dialogue_finished)
	config=data;records=preload("res://scripts/autonomy_records.gd").new(prefs,int(config.get("record_limit",20)));reset()
	for id in world.director.routines:records.recover(id)
func valid_config(data: Variant) -> bool:
	if not data is Dictionary or data.get("version")!=1:return false
	for key in ["presence_seconds","settling_seconds","event_ttl_seconds","threshold"]:
		if not number(data.get(key),3600) or data[key]<1:return false
	if not data.get("event_scores") is Dictionary or not data.get("levels") is Dictionary:return false
	for key in ["meal","shared_barbecue","house_completed","fishing_catch","gomoku_match","homestead_completed","work_blocked","work_completed","day_changed","player_returned","reflection"]:
		if not number(data.event_scores.get(key),100):return false
	for level in ["low","medium","high","ultra"]:
		if not data.levels.get(level) is Dictionary:return false
		for key in ["cooldown","hourly","daily","tools","turn_tokens","daily_tokens","reflection_seconds"]:
			if not number(data.levels[level].get(key),2000000):return false
		var policy: Dictionary=data.levels[level]
		if policy.tools>8 or policy.daily>200 or policy.hourly>policy.daily or policy.turn_tokens>64000:return false
		if level!="low" and (policy.cooldown<30 or policy.hourly<1 or policy.turn_tokens<1000 or policy.daily_tokens<policy.turn_tokens):return false
		if level!="ultra" and policy.reflection_seconds!=0:return false
	if data.levels.has("lifeblood"):
		var life:Variant=data.levels.lifeblood
		if not life is Dictionary:return false
		for key in ["cooldown","hourly","daily","tools","turn_tokens","daily_tokens","reflection_seconds"]:
			if not number(life.get(key),2000000):return false
		if life.cooldown!=30 or life.reflection_seconds!=30 or life.hourly!=120 or life.daily!=2880 or life.tools>8 or life.turn_tokens>64000:return false
	return data.levels.ultra.reflection_seconds>=120
func number(value: Variant,maximum: int) -> bool:
	return (value is float or value is int) and is_finite(value) and value==floor(value) and value>=0 and value<=maximum
func now() -> float:return maxf(world.forest.clock,Time.get_unix_time_from_system())
func day_key() -> int:return int(floor((now()+Time.get_time_zone_from_system().bias*60)/86400.0))
func reset() -> void:
	queues.clear();active.clear();causal.clear();seen.clear();reflection_after.clear();labor_seen.clear()
	last_day=world.days.day();last_input=now();input_seen=false
	# Reload is a baseline, never a replay of retained memories or work logs.
	for entry in world.memories.records:seen["memory:"+entry.id]=true
	for entry in world.work.events:seen["work:"+entry.id]=true
	var completion: Dictionary=world.homestead.site.get("completion",{})
	if not completion.is_empty():seen["homestead:"+str(completion.get("id",""))]=true
func usage(id: String) -> Dictionary:
	var ledger: Dictionary=preferences.accounting(id)
	if ledger.get("day",-1)!=day_key():
		# Outstanding unknown usage from yesterday stays yesterday; no queue replay.
		ledger={"day":day_key(),"calls":0,"tokens":0,"input_tokens":0,"output_tokens":0,"reserved":0,"times":ledger.get("times",[]),"last_at":ledger.get("last_at",0.0),"unknown_turns":0,"turns":[]}
	var times: Array=ledger.get("times",[])
	ledger.times=times.filter(func(at):return at>now()-3600 and at<=now())
	return ledger
func enabled(id: String) -> bool:
	return world.director.model_controlled(id) and preferences.preference(id).runtime_active
func note_model_action(id: String) -> void:
	# Until its engine plans/jobs settle, every consequence is model-originated.
	causal[id]=true
func input_received() -> void:
	if input_seen and now()-last_input>=config.presence_seconds:
		for id in world.director.routines:enqueue(id,"player-return:"+str(serial),"player_returned",LocalText.text("system.autonomy_scheduler.the_player_returned_to_the_game"))
	last_input=now();input_seen=true;serial+=1
func enqueue(id: String,key: String,kind: String,text: String) -> void:
	if not enabled(id) or causal.has(id) or not config.event_scores.has(kind):return
	var queue: Array=queues.get(id,[])
	if queue.any(func(entry):return entry.id==key):return
	queue.append({"id":key,"kind":kind,"text":text.left(160),"at":now(),"score":config.event_scores[kind]})
	if queue.size()>12:queue.pop_front()
	queues[id]=queue
func observe_sources() -> void:
	var retained: Dictionary={}
	for entry in world.memories.records:
		var key: String="memory:"+entry.id;retained[key]=true
		if seen.has(key):continue
		seen[key]=true
		# Host-confirmed AI chess already owns its bounded turns, including local/local games.
		if entry.kind=="gomoku_match" and world.gomoku.memories.any(func(match_record):return match_record.id==entry.source.id and match_record.get("mode")=="ai"):continue
		# A model-caused shared event may not wake ANY participant.
		if entry.participants.any(func(id):return causal.has(id)):continue
		for id in entry.participants:enqueue(id,key,entry.kind,world.memories._describe(entry).get("summary",entry.kind))
	for entry in world.work.events:
		var key: String="work:"+entry.id;retained[key]=true
		if seen.has(key):continue
		seen[key]=true
		records.job_finished(entry)
		if entry.get("source")=="promise":continue
		if entry.status in ["blocked","completed"]:enqueue(entry.actor_id,key,"work_"+entry.status,str(entry.message))
	var completion: Dictionary=world.homestead.site.get("completion",{})
	if not completion.is_empty() and not world.homestead.site.has("host_completion_source"):
		var key: String="homestead:"+str(completion.get("id",""));retained[key]=true
		if not seen.has(key):
			seen[key]=true
			for id in world.homestead.site.contributions:enqueue(id,key,"homestead_completed",LocalText.text("system.autonomy_scheduler.the_homestead_flowerbed_is_complete_and_a_new_recipe"))
	if last_day!=world.days.day():
		last_day=world.days.day()
		for id in world.director.routines:enqueue(id,"day:"+str(last_day),"day_changed",LocalText.text("system.autonomy_scheduler.day_d_has_begun_on_the_island")%last_day)
	seen=retained
	# Observe the completion before releasing its causal barrier.
	for id in causal.keys():
		if not world.work.jobs.has(id) and not world._routes.has(id) and not world.projects.active(id) and not world.farms.active(id) and not world.homestead.active(id) and not pending_consequences(id):causal.erase(id)
func observe_labor() -> void:
	# State edges only: enabling observes current opportunities once. Existing
	# targets never cause periodic inference; model consequences are baselined.
	for id in world.director.routines:
		if not enabled(id) or preferences.preference(id).level not in ["high","ultra"]:
			labor_seen.erase(id);continue
		var actor: Dictionary=world.actors[id]
		var current: Dictionary={}
		for plot in world.farms.plots.values():
			if plot.region_id!=actor.region_id or world.point(plot).distance_to(world.point(actor))>12 or not world.farms.ready(plot.farm_id):continue
			var stage: String=world.farms.stage(plot)
			if stage in ["mature","dry"]:current[plot.id+":"+stage]={"intent":"harvest" if stage=="mature" else "water","target_id":plot.id}
		for tree in world.objects.values():
			if tree.kind=="tree" and tree.status!="mature":labor_seen.get(id,{}).erase(tree.id+":0")
			if tree.kind=="tree" and tree.status=="mature" and tree.region_id==actor.region_id and world.point(tree).distance_to(world.point(actor))<=12:
				current[tree.id+":"+str(tree.get("regrow_at",0))]={"intent":"chop","target_id":tree.id}
		var previous: Dictionary=labor_seen.get(id,{})
		# Remember targets even after walking away; returning cannot replay them.
		for key in current:
			if previous.has(key):continue
			previous[key]=true
			if causal.has(id) or not causal.is_empty() or world.hunger.rank(id)>=2:continue
			var queue: Array=queues.get(id,[])
			queue.append({"id":"labor:"+key,"kind":"labor_opportunity","text":JSON.stringify(current[key]),"at":now(),"score":config.threshold})
			if queue.size()>12:queue.pop_front()
			queues[id]=queue
		labor_seen[id]=previous
func pending_consequences(id: String) -> bool:
	return world.gomoku.active(id) or (world.shared_activity.session.get("status") in ["active","paused"] and world.shared_activity.contains(id))
func idle(id: String) -> bool:
	return not world.work.jobs.has(id) and not world._routes.has(id) and not world.projects.active(id) and not world.farms.active(id) and not world.homestead.active(id) and not world.shared_activity.holds(id) and not world.gomoku.active(id)
func advance(_delta: float,held: Dictionary={}) -> void:
	if config.is_empty() or world==null or _delta<=0:return
	life_clock+=_delta
	observe_labor()
	observe_sources()
	for id in world.director.routines:
		var pref: Dictionary=preferences.preference(id)
		var queue: Array=queues.get(id,[])
		queue=queue.filter(func(entry):return now()-entry.at<=config.event_ttl_seconds)
		queues[id]=queue
		if not enabled(id):queues.erase(id);continue
		var policy: Dictionary=policy_for(id)
		if pref.level=="lifeblood":
			if not life_due.has(id):life_due[id]=life_clock+30.0
			if life_clock>=float(life_due[id]):
				enqueue(id,"lifeblood:"+str(serial),"reflection","Observe your surroundings and feelings; talk to someone nearby, do a small permitted activity, or write grounded feelings/about_you memory. Player instructions, hunger and management take priority.")
				serial+=1;life_due[id]=life_clock+30.0
		var company_only:bool=company_fireside.is_valid() and company_fireside.call(id)
		var companion_event:bool=company_ready.is_valid() and company_ready.call(id)
		if held.get(id,false) or active.has(id) or (not company_only and (world.activities.blocked(id) or not idle(id))):gate(id,"busy",companion_event);continue
		if not input_seen or now()-last_input>config.presence_seconds:gate(id,"not_present",companion_event);continue
		if not available.is_valid() or not available.call(id):gate(id,"unavailable",companion_event);continue
		if pref.level=="ultra" and now()>=float(reflection_after.get(id,now()+policy.reflection_seconds)):
			enqueue(id,"reflection:"+str(serial),"reflection",LocalText.text("system.autonomy_scheduler.idle_reflection_decide_whether_an_action_is_needed_from"))
			serial+=1;reflection_after[id]=now()+policy.reflection_seconds
		elif not reflection_after.has(id):reflection_after[id]=now()+policy.reflection_seconds
		queue=queues.get(id,[])
		if companion_event:queue=[{"id":"company","kind":"reflection","text":"","at":now(),"score":config.threshold}]
		var score:=0
		for entry in queue:score+=int(entry.score)
		if queue.is_empty() or score<config.threshold:records.gate(id,"waiting_event",now());continue
		if not companion_event and pref.level!="lifeblood" and now()-queue[0].at<config.settling_seconds:records.gate(id,"settling",now());continue
		var ledger: Dictionary=usage(id)
		if pref.level!="lifeblood" and now()-float(ledger.last_at)<policy.cooldown:gate(id,"cooldown",companion_event);continue
		if ledger.times.size()>=policy.hourly or ledger.calls>=policy.daily or (int(policy.daily_tokens)>0 and int(ledger.tokens)+int(ledger.reserved)+int(policy.turn_tokens)>int(policy.daily_tokens)):gate(id,"budget",companion_event);continue
		var previous_last_at: float=float(ledger.last_at)
		var charged_at: float=now()
		ledger.calls+=1;ledger.last_at=charged_at;ledger.times.append(charged_at);ledger.reserved+=int(policy.turn_tokens)
		if not preferences.save_accounting(id,ledger):continue
		serial+=1
		var token: String="autonomy-%d-%d"%[int(now()*1000),serial]
		active[id]={"id":token,"day":day_key(),"tokens":0,"input":0,"output":0,"reserve":int(policy.turn_tokens),"charged_at":charged_at,"previous_last_at":previous_last_at}
		var context: Dictionary=world.autonomy_context(id,queue,histories.call(id) if histories.is_valid() else [])
		if not companion_event:queues.erase(id)
		reflection_after[id]=now()+policy.reflection_seconds
		if not context.get("ok",false) or JSON.stringify(context).to_utf8_buffer().size()>4096:
			reject(id,"context_rejected");continue
		var estimate: int=preload("res://scripts/autonomy_estimate.gd").tokens(config,context)
		records.start(id,token,queue,now(),estimate)
		if pref.level=="ultra" and records.notice_once(id,day_key()):ultra_notice.emit(id,estimate*int(policy.hourly))
		if not dispatch.call(id,context,policy.duplicate(true),token):reject(id,"dispatch_rejected")
func gate(id:String,reason:String,companion_event:bool)->void:
	records.gate(id,reason,now())
	if companion_event and company_progress.is_valid():company_progress.call(id,reason)
func record_usage(id: String,total: int,input: int,output: int) -> bool:
	if not active.has(id) or total<0 or input<0 or output<0 or total<input+output:return false
	var turn: Dictionary=active[id]
	if total<int(turn.tokens) or input<int(turn.input) or output<int(turn.output):return false
	var ledger: Dictionary=usage(id)
	var delta: int=total-int(turn.tokens)
	ledger.tokens+=delta;ledger.input_tokens+=input-int(turn.input);ledger.output_tokens+=output-int(turn.output)
	var freed: int=mini(int(turn.reserve),delta) if turn.day==day_key() else 0
	ledger.reserved=maxi(0,int(ledger.reserved)-freed)
	update_turn(ledger,str(turn.id),"autonomy",total,input,output,"reported_partial")
	if not preferences.save_accounting(id,ledger):return false
	turn.reserve-=freed
	turn.tokens=total;turn.input=input;turn.output=output
	records.update(id,str(turn.id),total,"reported_partial");return true
func finish(id: String,usage_known: bool=true) -> void:
	if not active.has(id):return
	var turn: Dictionary=active[id];var ledger: Dictionary=usage(id)
	if turn.day==day_key():
		if usage_known:ledger.reserved=maxi(0,int(ledger.reserved)-int(turn.reserve))
		else:ledger.unknown_turns+=1
	else:
		if not usage_known:ledger.reserved+=int(turn.reserve);ledger.unknown_turns+=1
	update_turn(ledger,str(turn.id),"autonomy",int(turn.tokens),int(turn.input),int(turn.output),"complete" if usage_known else "unknown")
	preferences.save_accounting(id,ledger)
	records.update(id,str(turn.id),int(turn.tokens),"complete" if usage_known else "unknown")
	active.erase(id)

func update_turn(ledger: Dictionary,key: String,kind: String,total: int,input: int,output: int,status: String) -> void:
	var turns: Array=ledger.get("turns",[])
	var entry: Dictionary={"id":key,"kind":kind,"total_tokens":total,"input_tokens":input,"output_tokens":output,"status":status}
	var index: int=turns.find_custom(func(item):return item.id==key)
	if index>=0:turns[index]=entry
	else:turns.append(entry)
	if turns.size()>200:turns.pop_front()
	ledger.turns=turns

func reject(id: String,reason: String) -> void:
	if not active.has(id):return
	var turn: Dictionary=active[id];var ledger: Dictionary=usage(id)
	if turn.day==day_key():
		ledger.calls=maxi(0,int(ledger.calls)-1);ledger.reserved=maxi(0,int(ledger.reserved)-int(turn.reserve))
		var index: int=ledger.times.find(turn.charged_at)
		if index>=0:ledger.times.remove_at(index)
		ledger.last_at=turn.previous_last_at
	update_turn(ledger,str(turn.id),"autonomy",0,0,0,"rejected:"+reason)
	preferences.save_accounting(id,ledger);active.erase(id)
	records.update(id,str(turn.id),0,"rejected:"+reason)
	preferences.fail_runtime(id,reason,int(config.get("failure_limit",3)))
func dialogue_finished(id: String) -> void:
	var ledger: Dictionary=usage(id);ledger.last_at=now();preferences.save_accounting(id,ledger)
	reflection_after[id]=now()+float(config.levels[preferences.preference(id).level].reflection_seconds)

func policy_for(id: String) -> Dictionary:
	var level: String=preferences.preference(id).level
	var result: Dictionary=config.levels[level].duplicate(true)
	if level=="high" and codex_high.is_valid() and codex_high.call(id):
		var extra: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://bridge/codex_high_budget.json"))
		result.turn_tokens=int(extra.autonomy_turn_tokens)
		result.daily_tokens=int(extra.daily_tokens)
	var caps:=ConfigFile.new();caps.load(preferences.path.get_base_dir().path_join("connection-mode.cfg"))
	result.daily_tokens=int(caps.get_value("daily_limit",id,0))
	return result
