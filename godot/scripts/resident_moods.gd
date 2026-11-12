extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
## Derived presentation state. No score, persistence, task authorization or simulation rate.
const IDS := ["calm","happy","tired","quiet"]
const LABOR := ["chop","gather_wood","build","build_house","deliver_wood","furnish","house_work","build_facility","plant","water","harvest","farm_store","farm_take","cook","homestead","collect","store","take","forage"]
var _owner: WeakRef
var world: RefCounted:
	get:return _owner.get_ref()
var config: Dictionary={}
var states: Dictionary={}
var labor: Dictionary={}
var resting: Dictionary={}
var changed_at: Dictionary={}
var last_input:=0.0
var next_check:=0.0
func _init(source: RefCounted) -> void:
	_owner=weakref(source)
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/companions/local-life.json"))
	var value: Variant=data.get("moods",{})
	if valid_config(value):config=value.duplicate(true)
func valid_config(value: Variant) -> bool:
	if not value is Dictionary or not value.get("states") is Dictionary or value.states.size()!=IDS.size():return false
	for key in ["check_interval","minimum_hold","happy_seconds","inactive_seconds","tired_after","rest_after","village_gap"]:
		if not (value.get(key) is float or value.get(key) is int) or not is_finite(value[key]) or value[key]<=0 or value[key]>86400:return false
	for id in IDS:
		var part: Variant=value.states.get(id)
		if not part is Dictionary or not part.get("name") is String or part.name.is_empty() or not part.get("weights") is Dictionary or not part.get("lines") is Array or part.lines.size()<2:return false
		if not part.lines.all(func(line):return line is String and not line.is_empty() and line.length()<=40):return false
		for key in part.weights:
			if key not in ["wander","look","stretch","watch","nearby","rest","garden","facility","flower_gift"] or not (part.weights[key] is float or part.weights[key] is int) or not is_finite(part.weights[key]) or part.weights[key]<0 or part.weights[key]>3:return false
		for key in ["action_interval","speech_interval"]:
			if not (part.get(key) is float or part.get(key) is int) or not is_finite(part[key]) or part[key]<.5 or part[key]>3:return false
	return true
func player_input() -> void:last_input=world.director.time
func reset() -> void:
	states.clear();labor.clear();resting.clear();changed_at.clear()
	last_input=world.director.time;next_check=world.director.time
func summary(id: String) -> Dictionary:
	if id=="human" or not world.director.routines.has(id):return {}
	return states.get(id,{"id":"calm","name":LocalText.text("system.resident_moods.calm"),"reason":LocalText.text("system.resident_moods.no_particular_mood_right_now")}).duplicate()
func lines(id: String) -> Array:
	return config.states[summary(id).id].lines.duplicate() if not config.is_empty() else []
func weights(id: String,base: Dictionary) -> Dictionary:
	var result:=base.duplicate()
	if config.is_empty():return result
	var factors: Dictionary=config.states[summary(id).id].weights
	for key in result:result[key]=float(result[key])*float(factors.get(key,1))
	return result
func interval(id: String,kind: String) -> float:
	return float(config.states[summary(id).id][kind+"_interval"]) if not config.is_empty() else 1.0
func laboring(id: String) -> bool:
	var job: Dictionary=world.work.jobs.get(id,{})
	return job.get("source")!="local_rules" and job.get("intent") in LABOR
func happy(id: String) -> bool:
	if world.memories==null:return false
	for entry in world.memories.records:
		if entry.world_id!=world.world_id or id not in entry.participants or "human" not in entry.participants:continue
		var age: float=world.forest.clock-float(entry.occurred_at)
		if age<0 or age>float(config.happy_seconds):continue
		if entry.kind=="meal":
			if entry.facts.get("meal_type")=="cooked" and id in entry.facts.ate and "human" in entry.facts.ate:return true
			# Legacy portions prove one eater plus table overlap, not that both finished.
			var others: Array=world.memories.records.filter(func(other):return other.kind=="meal" and other.facts.get("eater_id")=="human" and id in other.facts.get("overlapped_with",[]) and other.region_id==entry.region_id and other.facts.get("activity_id","")==entry.facts.get("activity_id","") and world.forest.clock-float(other.occurred_at)>=0 and world.forest.clock-float(other.occurred_at)<=float(config.happy_seconds))
			if entry.facts.get("eater_id")==id and "human" in entry.facts.get("overlapped_with",[]) and not others.is_empty():return true
		elif entry.kind in ["shared_barbecue","house_completed","gomoku_match"]:return true
	return false
func desired(id: String) -> Dictionary:
	if world.hunger!=null and world.hunger.rank(id)>=2:return {"id":"quiet","name":LocalText.text("system.resident_moods.a_little_low"),"reason":LocalText.text("system.resident_moods.feeling_hungry")}
	if float(labor.get(id,0))>=float(config.tired_after):return {"id":"tired","name":config.states.tired.name,"reason":LocalText.text("system.resident_moods.a_long_spell_of_real_work")}
	if world.director.time-last_input>=float(config.inactive_seconds):return {"id":"quiet","name":config.states.quiet.name,"reason":LocalText.text("system.resident_moods.the_player_has_been_away_from_the_controls")}
	if happy(id):return {"id":"happy","name":config.states.happy.name,"reason":LocalText.text("system.resident_moods.a_recent_shared_activity")}
	if world.days!=null and world.days.phase().id=="night":return {"id":"quiet","name":config.states.quiet.name,"reason":LocalText.text("system.resident_moods.night")}
	return {"id":"calm","name":config.states.calm.name,"reason":LocalText.text("system.resident_moods.no_particular_mood_right_now")}
func advance(delta: float) -> void:
	if config.is_empty():return
	for id in world.director.routines:
		if laboring(id):labor[id]=float(labor.get(id,0))+delta;resting[id]=0.0
		else:
			resting[id]=float(resting.get(id,0))+delta
			if float(resting[id])>=float(config.rest_after):labor[id]=0.0
	if world.director.time<next_check:return
	next_check=world.director.time+float(config.check_interval)
	for id in world.director.routines:
		var next:=desired(id);var current: Dictionary=summary(id)
		if not states.has(id) or (next!=current and world.director.time-float(changed_at.get(id,0))>=float(config.minimum_hold)):
			states[id]=next;changed_at[id]=world.director.time
			if current!=next:world.revision+=1
func can_speak(id: String,context:String="") -> bool:
	var routine: RefCounted=world.director.routines[id]
	var true_thanks:bool=context=="need_satisfied" and routine.needs.choose(world,id).get("kind")=="satisfied"
	return not routine.blocked(false,not true_thanks) and not world.activities.blocked(id,false) and not world.shared_activity.holds(id) and world.fishing.life.time>=float(world.fishing.life.quiet_until.get(id,0))
