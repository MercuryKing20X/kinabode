extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
## A bounded engine calendar, never an inference scheduler or a resource shortcut.
var _owner: WeakRef
var world: RefCounted:
	get:return _owner.get_ref()
var config: Dictionary={}
var entries: Dictionary={}
var next_attempt: Dictionary={}
const SOCIAL=["social_sunrise","social_fireside"]
var offered_days:Dictionary={}
var queued_social:Array=[]
signal execution_started(actor_id: String)
signal settled(actor_id: String)
func _init(source: RefCounted) -> void:
	_owner=weakref(source);config=JSON.parse_string(FileAccess.get_file_as_string("res://content/promises.json"))
func now() -> float:return maxf(world.forest.clock,Time.get_unix_time_from_system())
func target_valid(action: String,target: String,saved: bool=false) -> bool:
	if action=="social_sunrise":return target=="plaza" and world.locations.v3()
	if action=="social_fireside":return world.barbecues.has(target)
	if not config.actions.has(action):return false
	match str(config.actions[action].target):
		"plot":return world.farms.plots.has(target)
		"sea":return world.fishing.waters.has(target)
		"human":return target=="human"
	return false
func due(day: int,phase: String,origin: float) -> float:
	for part in world.days.config.phases:
		if part.id==phase:return origin+(day-1)*world.days.day_seconds+float(part.start)*world.days.day_seconds
	return -1
func phase_end(entry: Dictionary) -> float:
	var parts: Array=world.days.config.phases
	for index in range(parts.size()):
		if parts[index].id==entry.phase:
			var ending: float=float(parts[index+1].start) if index+1<parts.size() else 1.0
			return world.days.origin+(int(entry.day)-1+ending)*world.days.day_seconds
	return float(entry.expires_at)
func own(id: String) -> Array:return entries.values().filter(func(entry):return entry.resident_id==id).duplicate(true)
func social(id:String)->Array:
	return own(id).filter(func(entry):return entry.action_type in SOCIAL)
func offer_social(id:String,day:int)->bool:
	if id=="human" or not world.actors.has(id) or int(offered_days.get(id,0))>=day or not social(id).is_empty():return false
	offered_days[id]=day;world.revision+=1;return true
func accept_social(id:String,kind:String,target:String,offer_day:int)->bool:
	if not kind in SOCIAL or not target_valid(kind,target) or not social(id).is_empty() or offer_day!=world.days.day() or offered_days.get(id)!=offer_day:return false
	if kind=="social_fireside" and not world.standard.ready(target):return false
	var day:int=world.days.day()+1
	var phase:String="morning" if kind=="social_sunrise" else "dusk"
	var at:float=due(day,phase,world.days.origin)
	var valid:int=int(config.default_valid_seconds)
	var key:String="promise-"+Crypto.new().generate_random_bytes(12).hex_encode()
	entries[key]={"id":key,"resident_id":id,"action_type":kind,"target_id":target,"day":day,"phase":phase,"due_at":at,"valid_seconds":valid,"expires_at":at+valid,"status":"pending","job_id":"","started_at":0.0}
	world.revision+=1;return true
func command(id: String,args: Dictionary) -> Dictionary:
	if args.get("intent")=="promise_cancel":
		if args.keys().any(func(key):return key not in ["intent","promise_id"]):return world._error("invalid_promise")
		var key: String=str(args.get("promise_id",""))
		if not entries.has(key) or entries[key].resident_id!=id:return world._error("not_owned_promise")
		finish(entries[key],"cancelled",LocalText.text("system.promise_system.this_promise_was_explicitly_canceled"),true);return {"ok":true,"status":"cancelled"}
	if id=="human" or not world.director.model_controlled(id) or args.keys().any(func(key):return key not in ["intent","action_type","target_id","day","phase","valid_seconds"]):return world._error("invalid_promise")
	if not args.get("action_type") is String or not args.get("target_id") is String or not target_valid(args.action_type,args.target_id) or not args.get("phase") is String:return world._error("invalid_promise_target")
	var day: Variant=args.get("day");var valid: Variant=args.get("valid_seconds",config.default_valid_seconds)
	if not number(day) or day<world.days.day() or day>world.days.day()+int(config.max_future_days) or not number(valid) or valid<1 or valid>config.max_valid_seconds:return world._error("invalid_promise_date")
	var at:=due(int(day),args.phase,world.days.origin)
	if at<=now():return world._error("promise_time_passed")
	if own(id).filter(func(entry):return entry.action_type not in SOCIAL).size()>=int(config.per_resident):return world._error("promise_limit")
	var key: String="promise-"+Crypto.new().generate_random_bytes(12).hex_encode()
	entries[key]={"id":key,"resident_id":id,"action_type":args.action_type,"target_id":args.target_id,"day":int(day),"phase":args.phase,"due_at":at,"valid_seconds":int(valid),"expires_at":at+valid,"status":"pending","job_id":"","started_at":0.0}
	world.revision+=1;return {"ok":true,"status":"promised","promise_id":key}
func number(value: Variant) -> bool:return (value is int or value is float) and is_finite(value) and value==floor(value) and value>=0 and value<253402300799
func busy(id: String) -> bool:
	return world.work.jobs.has(id) or world._routes.has(id) or world.projects.active(id) or world.farms.active(id) or world.homestead.active(id) or world.activities.blocked(id) or world.gomoku.active(id)
func action(entry: Dictionary) -> Dictionary:
	match str(entry.action_type):
		"water","harvest":return {"intent":entry.action_type,"target_id":entry.target_id}
		"fish":return {"intent":"fish"} if world.fishing.shore(entry.resident_id).get("water_id","")==entry.target_id else {}
		"come_near":return {"intent":"come_near"}
	return {}
func advance(delta: float) -> void:
	if delta<=0:return
	for key in entries.keys():
		if not entries.has(key):continue
		var entry: Dictionary=entries[key];var id: String=entry.resident_id
		if entry.action_type in SOCIAL:
			advance_social(entry)
			continue
		if entry.status=="running":
			if world.work.jobs.get(id,{}).get("id")==entry.job_id:
				if now()-float(entry.started_at)>float(config.job_timeout):finish(entry,"failed",LocalText.text("system.promise_system.the_task_timed_out_and_stopped_real_materials_are"),true)
				continue
			var ended: Array=world.work.events.filter(func(event):return event.get("job_id")==entry.job_id)
			var completed: bool=not ended.is_empty() and ended[-1].status=="completed"
			if completed and entry.action_type=="come_near":completed=world.actors[id].region_id==world.actors.human.region_id and world.point(world.actors[id]).distance_to(world.point(world.actors.human))<=float(config.arrival_distance)
			finish(entry,"completed" if completed else "failed",LocalText.text("system.promise_system.the_actual_task_is_complete") if completed else LocalText.text("system.promise_system.the_task_stopped_or_conditions_changed_completion_is_not"))
			continue
		if now()<float(entry.due_at):continue
		if now()>=minf(float(entry.expires_at),phase_end(entry)):finish(entry,"failed",LocalText.text("system.promise_system.the_promised_time_ended_it_was_not_completed_or"));continue
		if not world.director.model_controlled(id):finish(entry,"failed",LocalText.text("system.promise_system.the_controller_changed_no_action_was_taken_on_the"));continue
		if now()<float(next_attempt.get(key,0)):continue
		if busy(id):next_attempt[key]=now()+float(config.get("retry_seconds",30));continue
		if not target_valid(entry.action_type,entry.target_id):finish(entry,"failed",LocalText.text("system.promise_system.the_target_is_no_longer_available"));continue
		var command_args:=action(entry)
		if command_args.is_empty():finish(entry,"failed",LocalText.text("system.promise_system.not_at_a_natural_coast_in_the_promised_sea"));continue
		var result: Dictionary=world.command(id,command_args)
		if not result.get("ok",false):finish(entry,"failed",str(result.get("message",result.get("error",LocalText.text("system.promise_system.conditions_are_not_met")))));continue
		execution_started.emit(id)
		entry.status="running";entry.job_id=str(world.work.jobs.get(id,{}).get("id",""));entry.started_at=now()
		if world.work.jobs.has(id):world.work.jobs[id]["source"]="promise";world.work.jobs[id]["promise_id"]=entry.id
		if entry.job_id.is_empty():finish(entry,"failed",LocalText.text("system.promise_system.no_trackable_engine_task_was_accepted_completion_is_not"))
		world.revision+=1
func finish(entry: Dictionary,outcome: String,reason: String,stop_owned: bool=false) -> void:
	if not entries.has(entry.id):return
	if stop_owned and not str(entry.job_id).is_empty() and world.work.jobs.get(entry.resident_id,{}).get("id")==entry.job_id:world.work.stop(entry.resident_id)
	var facts: Dictionary={"resident_id":entry.resident_id,"action_type":entry.action_type,"target_id":entry.target_id,"day":entry.day,"phase":entry.phase,"outcome":outcome,"reason":reason.left(160)}
	world.memories.record_event("promise_result",entry.id,["human",entry.resident_id],facts)
	entries.erase(entry.id);next_attempt.erase(entry.id);settled.emit(str(entry.resident_id));world.revision+=1
func advance_social(entry:Dictionary)->void:
	var t:float=world.forest.clock
	if t<float(entry.due_at):return
	var id:String=entry.resident_id
	if t>=minf(float(entry.expires_at),phase_end(entry)):
		queued_social.append({"actor":id,"outcome":"failed","day":int(entry.day),"target":entry.target_id})
		finish(entry,"failed",LocalText.text("company.promise_missed"));return
	var actor:Dictionary=world.actors[id]
	var human:Dictionary=world.actors.human
	if actor.region_id!=human.region_id or world.hunger.rank(id)>=3:return
	var together:=false
	if entry.action_type=="social_sunrise" and actor.region_id=="home":
		var anchor:Array=world.map_anchor("plaza.center")
		if anchor.size()==2:
			var square:=Vector2(anchor[0],anchor[1])
			together=world.point(human).distance_to(square)<=5 and world.point(actor).distance_to(world.point(human))<=4 and not world._routes.has("human") and not world._routes.has(id) and not world.work.jobs.has(id) and not world.work.jobs.has("human")
	elif entry.action_type=="social_fireside":
		var fire:RefCounted=world.barbecues[entry.target_id].fireside
		together=fire.jobs.has(id) and fire.jobs.has("human") and actor.activity in ["fire_sit","fire_squat","fire_eat"] and human.activity in ["fire_sit","fire_squat","fire_eat"]
	if not together:return
	queued_social.append({"actor":id,"outcome":"completed","day":int(entry.day),"target":entry.target_id})
	world.memories.record_event("company_promise_first",id,["human",id],{"actor_id":id})
	finish(entry,"completed",LocalText.text("company.promise_kept"))
func saved() -> Dictionary:
	var save:Dictionary={"version":1,"entries":entries.values().duplicate(true)}
	if not offered_days.is_empty():save["company_offer_days"]=offered_days.duplicate()
	if not queued_social.is_empty():save["company_notices"]=queued_social.duplicate(true)
	return save
func valid_saved(data: Variant,actors: Dictionary,origin: float) -> bool:
	if not data is Dictionary or data.get("version")!=1 or not data.get("entries") is Array or data.entries.size()>actors.size()*(int(config.per_resident)+1):return false
	var offers:Variant=data.get("company_offer_days",{})
	if not offers is Dictionary or offers.keys().any(func(id):return id=="human" or not actors.has(id) or not number(offers[id]) or offers[id]<1 or offers[id]>1000000):return false
	var notices:Variant=data.get("company_notices",[])
	if not notices is Array or notices.size()>actors.size():return false
	var noticed:Dictionary={}
	for row in notices:
		if not row is Dictionary or row.size()!=4 or not actors.has(row.get("actor")) or row.actor=="human" or noticed.has(row.actor) or row.get("outcome") not in ["completed","failed"] or not number(row.get("day")) or int(row.day)<1 or (row.get("target")!="plaza" and not world.barbecues.has(row.get("target"))):return false
		noticed[row.actor]=true
	var counts: Dictionary={};var ids: Dictionary={}
	for entry in data.entries:
		if not entry is Dictionary or entry.size()!=12 or not entry.get("id") is String or not entry.id.begins_with("promise-") or entry.id.length()!=32 or ids.has(entry.id) or not actors.has(entry.get("resident_id","")) or entry.resident_id=="human":return false
		if not entry.get("action_type") is String or not entry.get("target_id") is String or not target_valid(entry.action_type,entry.target_id,true) or not number(entry.get("day")) or entry.day<1 or not entry.get("phase") is String:return false
		if not number(entry.get("valid_seconds")) or entry.valid_seconds<1 or entry.valid_seconds>config.max_valid_seconds or not world.catalog._number(entry.get("due_at")) or not world.catalog._number(entry.get("expires_at")) or absf(float(entry.due_at)-due(int(entry.day),entry.phase,origin))>.001 or absf(float(entry.expires_at)-float(entry.due_at)-entry.valid_seconds)>.001:return false
		if due(int(entry.day),entry.phase,origin)<=0:return false
		if entry.get("status")=="pending" and (entry.get("job_id")!="" or entry.get("started_at")!=0):return false
		if entry.get("status")=="running" and (not str(entry.get("job_id","")).begins_with("job-") or float(entry.get("started_at",0))<float(entry.due_at)):return false
		if entry.get("status") not in ["pending","running"] or not entry.get("job_id") is String or not world.catalog._number(entry.get("started_at")) or entry.started_at<0:return false
		if entry.action_type in SOCIAL:
			var slot:String="social:"+entry.resident_id
			if counts.has(slot) or entry.status!="pending" or entry.phase!=("morning" if entry.action_type=="social_sunrise" else "dusk"):return false
			ids[entry.id]=true;counts[slot]=1;continue
		ids[entry.id]=true;counts[entry.resident_id]=int(counts.get(entry.resident_id,0))+1
		if counts[entry.resident_id]>int(config.per_resident):return false
	return true
func restore(data: Dictionary) -> void:
	entries.clear();next_attempt.clear();queued_social.clear();offered_days=data.get("company_offer_days",{}).duplicate()
	for row in data.get("company_notices",[]):
		if world.memories.records.any(func(fact):
			return fact.kind=="promise_result" and fact.facts.resident_id==row.actor and fact.facts.action_type in SOCIAL and fact.facts.target_id==row.target and int(fact.facts.day)==int(row.day) and fact.facts.outcome==row.outcome):
			queued_social.append(row.duplicate())
	for entry in data.get("entries",[]):
		var copy: Dictionary=entry.duplicate(true)
		if copy.action_type not in SOCIAL and (copy.status=="running" or float(copy.due_at)<=now()):copy.status="interrupted"
		entries[copy.id]=copy
func reconcile_load() -> void:
	for entry in entries.values().duplicate():
		if entry.status=="interrupted":finish(entry,"failed",LocalText.text("system.promise_system.reloading_interrupted_the_promise_or_its_time_passed_while"))
