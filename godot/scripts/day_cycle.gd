class_name DayCycle
extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
## Calendar is a projection of ForestSystem.clock, never a second advancing clock.
var _owner: WeakRef
var world: RefCounted:
	get:return _owner.get_ref()
var config: Dictionary={}
var origin:=0.0
var day_seconds:=1500.0
var marked_day:=1
var spoken: Array=[]
var small: Dictionary={}
var first_today: Dictionary={}
var pending_catches: Dictionary={}
var owned_job_id:=""
var owned_actor:=""

func _init(source: RefCounted) -> void:
	_owner=weakref(source)
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/day-cycle.json"))
	if not valid_config(data):world.error=LocalText.text("system.day_cycle.the_day_cycle_and_daily_event_settings_are");return
	config=data;day_seconds=float(config.day_seconds);origin=float(int(floor(world.forest.clock*1000)))/1000.0
func number(value: Variant,maximum: int) -> bool:
	return (value is int or value is float) and is_finite(value) and value==floor(value) and value>=0 and value<=maximum
func valid_config(data: Variant) -> bool:
	if not data is Dictionary or data.get("version")!=1 or not world.catalog._number(data.get("day_seconds")) or data.day_seconds<1200 or data.day_seconds>1800:return false
	for field in ["greeting_after","small_after","personal_gap","village_gap","radius"]:
		if not world.catalog._number(data.get(field)) or data[field]<1 or data[field]>600:return false
	if data.radius>12 or data.small_after>=data.day_seconds or not data.get("phases") is Array or data.phases.is_empty() or data.phases.size()>8:return false
	var previous:=-1.0;var seen: Dictionary={}
	for phase in data.phases:
		if not phase is Dictionary or not phase.get("id") is String or phase.id.is_empty() or phase.id.length()>32 or seen.has(phase.id) or not phase.get("name") is String or phase.name.is_empty() or phase.name.length()>12 or not world.catalog._number(phase.get("start")) or phase.start<=previous or phase.start>=1 or phase.start<0:return false
		if not phase.get("lines") is Array or phase.lines.is_empty() or phase.lines.size()>12 or not phase.lines.all(func(line):return line is String and not line.is_empty() and line.length()<=50):return false
		seen[phase.id]=true;previous=float(phase.start)
	if data.phases[0].start!=0 or not data.get("small_events") is Array or data.small_events.is_empty() or data.small_events.size()>16:return false
	seen.clear()
	for event in data.small_events:
		if not event is Dictionary or not event.get("id") is String or event.id.is_empty() or event.id.length()>64 or seen.has(event.id) or event.get("gesture") not in ["wave","stretch"] or not event.get("line") is String or event.line.is_empty() or event.line.length()>50:return false
		seen[event.id]=true
	return true
func ticks(value: float) -> int:return int(round(value*1000))
func day() -> int:return 1+int(floor(float(maxi(0,ticks(world.forest.clock)-ticks(origin)))/ticks(day_seconds)))
func within_day() -> float:return float(maxi(0,ticks(world.forest.clock)-ticks(origin))%ticks(day_seconds))/1000.0
func phase() -> Dictionary:
	var result: Dictionary=config.phases[0]
	for entry in config.phases:
		if within_day()/day_seconds>=float(entry.start):result=entry
	return result
func summary(id: String) -> Dictionary:
	var current:=day();var part:=phase()
	return {"day":current,"phase":part.id,"phase_name":part.name,"day_seconds":day_seconds,"small_status":small.get("status","available") if marked_day==current else "available","today_first_count":first_today.get(id,{}).size() if marked_day==current else 0}
func today(id: String,combination: String) -> Dictionary:
	return first_today.get(id,{}).get(combination,{}).duplicate(true) if marked_day==day() else {}
func _rollover() -> void:
	var current:=day()
	if marked_day==current:return
	marked_day=current;spoken.clear();small.clear();first_today.clear();world.revision+=1

func queue_catch(fish_id: String) -> void:
	var fish: Dictionary=world.fishing.fish.get(fish_id,{})
	if fish.is_empty() or (fish.get("location")!="pending" and not (fish.get("owner_id")=="human" and fish.get("location")=="storage")) or not world.actors.has(fish.get("owner_id","")):return
	var job: Dictionary=world.work.jobs.get(fish.owner_id,{})
	if job.get("intent")!="fish" or job.get("phase")!="fish_reel" or not job.get("caught",false) or job.get("water_id")!=fish.source_id:return
	var fact: Dictionary={"fish_id":fish.id,"species_id":fish.species_id,"color_id":fish.color_id,"size_id":fish.size_id,"scale":fish.scale,"source_id":fish.source_id,"caught_at":fish.caught_at}
	if not world.journal.valid_first(fact) or pending_catches.size()>=world.residents.capacity:return
	pending_catches[fish.owner_id]=fact
func advance() -> void:
	_rollover()
	for id in pending_catches:
		var fact: Dictionary=pending_catches[id]
		var combination: String=world.journal.key(fact.species_id,fact.color_id,fact.size_id)
		var own: Dictionary=first_today.get(id,{})
		if not own.has(combination):own[combination]=fact.duplicate(true);first_today[id]=own;world.revision+=1
	pending_catches.clear()
	# No backlog is replayed. Only a currently idle, opted-in resident is eligible.
	if world.work.jobs.has("human") or world._routes.has("human") or world.activities.blocked("human"):return
	var candidates: Array=[]
	for id in world.director.routines:
		if eligible(id):candidates.append(id)
	if candidates.is_empty():return
	candidates.sort()
	var id: String=candidates[posmod((world.world_id+str(marked_day)).hash(),candidates.size())]
	if small.is_empty() and owned_job_id.is_empty() and within_day()>=float(config.small_after):
		_start_small(id);return
	var part:=phase()
	if part.id in spoken or within_day()-float(part.start)*day_seconds<float(config.greeting_after):return
	var line: String=part.lines[posmod((world.world_id+str(marked_day)+part.id).hash(),part.lines.size())]
	if world.director.say_local(id,line,"day_phase_"+part.id,config.personal_gap,config.village_gap):spoken.append(part.id);world.revision+=1
func eligible(id: String) -> bool:
	if id=="human" or not world.director.routines.has(id):return false
	# Arriving at the meal is still the rush, not a new idle opportunity.
	if world.hunger!=null and world.hunger.has_method("rushing") and world.hunger.rushes.has(id):return false
	var actor: Dictionary=world.actors[id];var routine: RefCounted=world.director.routines[id]
	if not routine.enabled or not routine.chatter or routine.held or not routine.kind.is_empty() or routine.time<routine.next_speech or world.director.time<world.director.speech_after:return false
	if world.work.jobs.has(id) or world._routes.has(id) or world.loaded(id) or not world.fishing.held(id).is_empty() or world.activities.blocked(id) or world.shared_activity.holds(id) or world.farms.active(id) or world.projects.active(id) or world.gomoku.active(id):return false
	if world.fishing.life.time<float(world.fishing.life.quiet_until.get(id,0)):return false
	return actor.region_id==world.actors.human.region_id and world.point(actor).distance_to(world.point(world.actors.human))<=float(config.radius) and world.residents.supports(actor,"gesture")
func defer_idle(id: String,for_action: bool=false) -> bool:
	# Reserve only an already eligible idle opportunity; final selection stays after forest advance.
	if world.work.jobs.has("human") or world._routes.has("human") or world.activities.blocked("human") or not eligible(id):return false
	if (marked_day!=day() or small.is_empty()) and owned_job_id.is_empty() and within_day()>=float(config.small_after):return true
	if for_action:return false
	var part:=phase()
	return (marked_day!=day() or part.id not in spoken) and within_day()-float(part.start)*day_seconds>=float(config.greeting_after)
func _start_small(id: String) -> void:
	var event: Dictionary=config.small_events[posmod((world.world_id+str(marked_day)+"small").hash(),config.small_events.size())]
	var routine: RefCounted=world.director.routines[id]
	routine.issuing=true
	var result: Dictionary=world.command(id,{"intent":"gesture","gesture":event.gesture})
	routine.issuing=false
	if not result.get("ok",false):return
	var identifier: String="small-"+Crypto.new().generate_random_bytes(12).hex_encode()
	small={"id":identifier,"actor_id":id,"event_id":event.id,"status":"started"}
	owned_job_id=result.job_id;owned_actor=id
	world.work.jobs[id]["source"]="local_rules";world.work.jobs[id]["daily_event_id"]=identifier
	routine.kind="daily_gesture";routine.owned_job_id=owned_job_id;routine.elapsed=0;routine.owns_route=false
	world.director.say_local(id,event.line,"daily_small",config.personal_gap,config.village_gap);world.revision+=1
func job_finished(id: String,job: Dictionary,outcome: String) -> void:
	if id!=owned_actor or job.get("id")!=owned_job_id or owned_job_id.is_empty():return
	if small.get("id")==job.get("daily_event_id") and marked_day==day():small.status="completed" if outcome=="completed" else "interrupted"
	owned_job_id="";owned_actor="";world.revision+=1
func job_stopped(id: String,job: Dictionary) -> void:job_finished(id,job,"interrupted")
func interrupt(id: String) -> void:
	if not owned_job_id.is_empty() and id==owned_actor and world.work.jobs.get(id,{}).get("id")==owned_job_id:world.work.stop(id,false)

func saved() -> Dictionary:
	return {"version":1,"origin":origin,"day_seconds":day_seconds,"marked_day":marked_day,"spoken":spoken.duplicate(),"small":small.duplicate(true),"first_today":first_today.duplicate(true)}
func restore(data: Dictionary) -> void:
	owned_job_id="";owned_actor="";pending_catches.clear()
	if data.is_empty():
		origin=float(int(floor(world.forest.clock*1000)))/1000.0;day_seconds=float(config.day_seconds);marked_day=1;spoken.clear();small.clear();first_today.clear();return
	origin=float(ticks(float(data.origin)))/1000.0;day_seconds=float(data.day_seconds);marked_day=int(data.marked_day)
	spoken=data.spoken.duplicate();small=data.small.duplicate(true);first_today=data.first_today.duplicate(true)
	if small.get("status")=="started":small.status="interrupted"
	_rollover()
func valid_saved(data: Variant,actors: Dictionary,forest_clock: Variant) -> bool:
	if not data is Dictionary or data.size()!=7 or data.get("version")!=1 or not world.catalog._number(forest_clock) or forest_clock<0 or forest_clock>253402300799 or not world.catalog._number(data.get("origin")) or data.origin<0 or ticks(data.origin)>ticks(forest_clock) or not world.catalog._number(data.get("day_seconds")) or data.day_seconds<1200 or data.day_seconds>1800:return false
	var maximum:=1+int(floor(float(ticks(forest_clock)-ticks(data.origin))/ticks(data.day_seconds)))
	if not number(data.get("marked_day"),maximum) or data.marked_day<1 or not data.get("spoken") is Array or data.spoken.size()>config.phases.size() or not data.get("small") is Dictionary or not data.get("first_today") is Dictionary or data.first_today.size()>actors.size():return false
	var seen: Dictionary={}
	for id in data.spoken:
		if not id is String or seen.has(id) or not config.phases.any(func(part):return part.id==id):return false
		seen[id]=true
	if not data.small.is_empty():
		var value: Dictionary=data.small
		if value.size()!=4 or not value.get("id") is String or value.id.length()!=30 or not value.id.begins_with("small-") or not value.id.substr(6).is_valid_hex_number(false) or not actors.has(value.get("actor_id","")) or value.actor_id=="human" or value.get("status") not in ["started","completed","interrupted"] or not config.small_events.any(func(event):return event.id==value.get("event_id")):return false
	seen.clear()
	for id in data.first_today:
		if not actors.has(id) or not data.first_today[id] is Dictionary or data.first_today[id].size()>world.journal.entries.size():return false
		for combination in data.first_today[id]:
			var fact: Variant=data.first_today[id][combination]
			if not world.journal.valid_first(fact) or combination!=world.journal.key(fact.species_id,fact.color_id,fact.size_id) or seen.has(fact.fish_id):return false
			seen[fact.fish_id]=true
	return true
