extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
## Progress over committed facts; never an inventory owner, model trigger or second routine.
var _owner: WeakRef
var world: RefCounted:
	get:return _owner.get_ref()
var config: Dictionary={}
var states: Dictionary={}
var legacy_proofs: Dictionary={}
var seen: Array=[]
var next_check:=0.0
var last_input:=0.0
var returned: Dictionary={}
func _init(source: RefCounted) -> void:
	_owner=weakref(source)
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/relationships.json"))
	if not valid_config(data):world.error=LocalText.text("system.relationship_system.the_relationship_settings_are_invalid");return
	config=data;last_input=world.director.time
func valid_config(data: Variant) -> bool:
	if not data is Dictionary or data.get("version")!=1 or not data.get("stages") is Array or data.stages.size()!=5 or not data.get("weights") is Dictionary or not data.get("labels") is Dictionary or not data.get("lines") is Dictionary:return false
	for key in ["check_interval","per_kind_day_limit","lifetime_kind_limit","near_radius","personal_gap","village_gap","return_after","seat_near_radius"]:
		if not world.catalog._number(data.get(key)) or data[key]<=0 or data[key]>86400:return false
	if not integer(data.per_kind_day_limit,8) or not integer(data.lifetime_kind_limit,64) or data.near_radius>12:return false
	var previous:=-1
	for stage in data.stages:
		if not stage is Dictionary or not stage.get("id") is String or not stage.get("name") is String or stage.id.is_empty() or stage.name.is_empty() or stage.id.length()>32 or stage.name.length()>12 or not integer(stage.get("threshold"),10000) or int(stage.threshold)<=previous:return false
		previous=int(stage.threshold)
	if data.stages[0].threshold!=0 or not data.get("legacy_pacing") is Dictionary:return false
	var legacy: Dictionary=data.legacy_pacing
	if not legacy.get("thresholds") is Array or legacy.thresholds.size()!=5 or not legacy.get("weights") is Dictionary or not integer(legacy.get("lifetime_kind_limit"),64):return false
	for n in range(5):
		if not integer(legacy.thresholds[n],10000) or (n>0 and legacy.thresholds[n]<=legacy.thresholds[n-1]):return false
	for key in legacy.weights:
		if not integer(legacy.weights[key],20):return false
	for kind in data.weights:
		if kind not in ["meal","shared_barbecue","house_completed","homestead_completed","fishing","gomoku_match","promise_result","gift","proposal_decision","wish_completed"] or not integer(data.weights[kind],20) or not data.labels.get(kind) is String or data.labels[kind].length()>40:return false
	for pool in data.lines.values():
		if not pool is Array or pool.size()<4 or not pool.all(func(line):return line is String and not line.is_empty() and line.length()<=60):return false
	var rewards: Variant=data.get("rewards")
	if not rewards is Dictionary or not rewards.get("default_address") is String or rewards.default_address.is_empty() or rewards.default_address.length()>12:return false
	for key in ["address_max_length","action_interval","action_chance","notice_radius","passing_radius","stay_seconds"]:
		if not world.catalog._number(rewards.get(key)) or rewards[key]<=0 or rewards[key]>86400:return false
	if rewards.action_chance>1 or rewards.notice_radius>24 or rewards.passing_radius>8 or rewards.address_max_length>12 or not rewards.get("stand_distances") is Array or not rewards.stand_distances.all(func(n):return world.catalog._number(n) and n>=2 and n<=6) or not rewards.get("work_lines") is Dictionary:return false
	for key in ["chop","fish","cook","farm"]:
		if not rewards.work_lines.get(key) is Array or rewards.work_lines[key].size()<4 or not rewards.work_lines[key].all(func(line):return line is String and line.length()<=60):return false
	return true
func empty() -> Dictionary:return {"counts":{},"day":world.days.day(),"today":{},"stage":0,"announced":0,"recent":[]}
func index(id: String) -> int:return int(states.get(id,{}).get("stage",0))
func summary(id: String) -> Dictionary:
	var stage: Dictionary=config.stages[index(id)]
	return {"stage":stage.id,"name":stage.name,"address":address(id),"our_place_id":our_place(id).get("target_id",""),"recent":states.get(id,{}).get("recent",[]).map(func(entry):return str(config.labels.get(entry.kind,""))).slice(0,3)}
func points(state: Dictionary) -> int:
	var result:=0
	for kind in state.counts:result+=int(state.counts[kind])*int(config.weights.get(kind,0))
	return result
func mark(key: String) -> bool:
	var hash_value:=key.sha256_text()
	if hash_value in seen:return false
	seen.append(hash_value)
	if seen.size()>4096:seen.pop_front()
	return true
func grant(id: String,kind: String,key: String) -> void:
	if id=="human" or not world.actors.has(id) or not config.weights.has(kind):return
	var state: Dictionary=states.get(id,empty())
	if state.day!=world.days.day():state.day=world.days.day();state.today={}
	if int(state.today.get(kind,0))>=int(config.per_kind_day_limit) or int(state.counts.get(kind,0))>=int(config.lifetime_kind_limit):return
	state.counts[kind]=int(state.counts.get(kind,0))+1;state.today[kind]=int(state.today.get(kind,0))+1
	for n in range(config.stages.size()):
		if points(state)>=int(config.stages[n].threshold):state.stage=maxi(int(state.stage),n)
	state.recent.push_front({"kind":kind,"source_id":key.sha256_text()})
	if state.recent.size()>3:state.recent.pop_back()
	states[id]=state;world.revision+=1
func eligible(entry: Dictionary,id: String) -> bool:
	if id=="human" or id not in entry.participants or "human" not in entry.participants:return false
	match str(entry.kind):
		"meal":return (entry.facts.get("meal_type")=="cooked" and id in entry.facts.ate and "human" in entry.facts.ate)
		"promise_result":return entry.facts.resident_id==id and entry.facts.outcome=="completed"
		"proposal_decision":return entry.facts.resident_id==id and entry.facts.decision=="accepted"
		"gift":return true
		"wish_completed":return entry.facts.resident_id==id
		"house_completed","shared_barbecue","gomoku_match":return entry.kind!="gomoku_match" or int(entry.facts.move_count)>0
	return false
func observe() -> void:
	for entry in world.memories.records.duplicate():
		if not mark("memory:"+entry.id):continue
		for id in entry.participants:
			if eligible(entry,id):grant(id,entry.kind,entry.id)
	for entry in world.fishing.memories:
		if not mark("fish:"+entry.id):continue
		var present: Array=entry.companions.duplicate();present.append(entry.actor_id)
		if "human" in present:
			for id in present:grant(id,"fishing","fish:"+entry.id)
	var completion: Dictionary=world.homestead.site.get("completion",{})
	if not world.homestead.site.has("host_completion_source") and not completion.is_empty() and mark("homestead:"+str(completion.get("id",""))):
		var contributors: Array=world.homestead.site.contributions.keys()
		if "human" in contributors:
			for id in contributors:grant(id,"homestead_completed",completion.id)
func advance(delta: float) -> void:
	if delta<=0 or world.director.time<next_check:return
	next_check=world.director.time+float(config.check_interval);observe()
	var region: String=world.actors.human.region_id
	if not last_human_region.is_empty() and last_human_region!="home" and region=="home":
		for id in world.director.routines:
			if index(id)>=4:returned[id]=true
	last_human_region=region
func player_input() -> void:
	if world.director.time-last_input>=float(config.return_after):
		for id in world.director.routines:
			if index(id)>=4:returned[id]=true
	last_input=world.director.time
func available(id: String) -> bool:
	var r: RefCounted=world.director.routines[id];var actor: Dictionary=world.actors[id]
	return r.enabled and r.chatter and not r.blocked() and not world.work.jobs.has(id) and not world._routes.has(id) and r.kind!="flower_gift" and not world.shared_activity.holds(id) and world.fishing.life.time>=float(world.fishing.life.quiet_until.get(id,0)) and actor.region_id==world.actors.human.region_id and world.point(actor).distance_to(world.point(world.actors.human))<=float(config.near_radius)
func try_event(id: String) -> bool:
	if not config.get("stage_events_enabled",true) or not states.has(id) or not available(id):return false
	if not world.director.can_say_local(id):return false
	var state: Dictionary=states[id]
	if int(state.announced)>=int(state.stage):return false
	var number:=int(state.announced)+1;var stage: Dictionary=config.stages[number]
	var r: RefCounted=world.director.routines[id];var options: Array=addressed(id,config.lines[stage.id])
	var text: String=options[r.rng.randi_range(0,options.size()-1)]
	if not world.director.say_local(id,text,"relationship_stage",float(config.personal_gap),float(config.village_gap)):return false
	r.authored_reaction("watch");state.announced=number
	world.memories.record_event("relationship_stage","stage:"+(id+":"+str(number)).sha256_text(),["human",id],{"resident_id":id,"stage_id":stage.id,"stage_name":stage.name,"stage_index":number})
	return true
func weights(id: String,base: Dictionary) -> Dictionary:
	var result:=base.duplicate()
	for level in config.behavior_weights:
		if index(id)>=int(level):
			for key in config.behavior_weights[level]:result[key]=float(result.get(key,0))*float(config.behavior_weights[level][key])
	return result
func lines(id: String,context: String) -> Array:
	var n:=index(id)
	if n>=4 and returned.get(id,false):return addressed(id,config.lines.returned)
	if n>=2 and world.director.routines[id].kind=="relationship_sea" and not world.fishing.shore("human").is_empty():return addressed(id,config.lines.sea)
	if n>=2 and world.director.routines[id].kind=="rest":return addressed(id,config.lines.close)
	if n>=4 and world.days.phase().id=="night":return addressed(id,config.lines.family)
	if n>=3 and not work_context().is_empty():return addressed(id,config.rewards.work_lines[work_context()])
	var camp:RefCounted=world.nearest_barbecue(id,8)
	if n>=2 and camp!=null and camp.station.state in ["ready","eating"] and int(camp.station.portions)>0:return config.lines.meal_ready.duplicate()
	if n>=1 and context in ["arrive","greet"]:return addressed(id,config.lines[config.stages[n].id])
	if n>=1 and context in ["ambient","near"]:
		var counts: Dictionary=states.get(id,{}).get("counts",{})
		var common: Array=counts.keys().filter(func(key):return int(counts[key])>=2)
		if not common.is_empty():return config.lines.common.map(func(line):return str(line).replace("{activity}",str(config.labels[common[0]])))
	return []
func saved() -> Dictionary:return {"version":1,"pacing_version":2,"legacy_proofs":legacy_proofs.duplicate(true),"states":states.duplicate(true),"seen":seen.duplicate()}
func legacy_points(counts: Dictionary) -> int:
	var total:=0
	for key in counts:total+=int(counts[key])*int(config.legacy_pacing.weights.get(key,0))
	return total
func proof_valid(proof: Variant,state: Dictionary) -> bool:
	if not proof is Dictionary or proof.size()!=2 or not integer(proof.get("stage"),4) or not proof.get("counts") is Dictionary:return false
	if int(proof.stage)>int(state.stage):return false
	for key in proof.counts:
		if not config.legacy_pacing.weights.has(key) or not integer(proof.counts[key],int(config.legacy_pacing.lifetime_kind_limit)) or int(proof.counts[key])>int(state.counts.get(key,0)):return false
	return legacy_points(proof.counts)>=int(config.legacy_pacing.thresholds[int(proof.stage)])
func valid_saved(data: Variant,actors: Dictionary) -> bool:
	if not data is Dictionary or data.get("version")!=1 or not data.get("states") is Dictionary or data.states.size()>actors.size() or not data.get("seen") is Array or data.seen.size()>4096:return false
	if (data.get("pacing_version",1)!=1 and data.get("pacing_version",1)!=2) or not data.get("legacy_proofs",{}) is Dictionary:return false
	var proofs: Dictionary=data.get("legacy_proofs",{})
	for id in proofs:
		if not data.states.has(id):return false
	var unique: Dictionary={}
	for key in data.seen:
		if not key is String or key.length()!=64 or not key.is_valid_hex_number(false) or unique.has(key):return false
		unique[key]=true
	for id in data.states:
		var state: Variant=data.states[id]
		if id=="human" or not actors.has(id) or not state is Dictionary or state.size()!=6:return false
		if not state.get("counts") is Dictionary or not state.get("today") is Dictionary or not integer(state.get("day"),1000000) or state.day<1 or not integer(state.get("stage"),4) or not integer(state.get("announced"),int(state.stage)) or not state.get("recent") is Array or state.recent.size()>3:return false
		for group in [state.counts,state.today]:
			for kind in group:
				if not config.weights.has(kind) or not integer(group[kind],int(config.lifetime_kind_limit)):return false
		for recent in state.recent:
			if not recent is Dictionary or recent.size()!=2 or not config.weights.has(recent.get("kind","")) or not recent.get("source_id") is String or recent.source_id.length()!=64 or not recent.source_id.is_valid_hex_number(false):return false
		if int(data.get("pacing_version",1))==1:
			if not proofs.is_empty() or legacy_points(state.counts)<int(config.legacy_pacing.thresholds[int(state.stage)]):return false
		else:
			if proofs.has(id) and not proof_valid(proofs[id],state):return false
			if points(state)<int(config.stages[int(state.stage)].threshold) and int(proofs.get(id,{}).get("stage",0))<int(state.stage):return false
	return true
func integer(value: Variant,limit: int) -> bool:return (value is int or value is float) and is_finite(value) and value==floor(value) and value>=0 and value<=limit
func restore(data: Dictionary) -> void:
	states=data.get("states",{}).duplicate(true);legacy_proofs=data.get("legacy_proofs",{}).duplicate(true)
	if int(data.get("pacing_version",1))==1:
		for id in states:
			if int(states[id].stage)>0:legacy_proofs[id]={"stage":int(states[id].stage),"counts":states[id].counts.duplicate()}
	seen=data.get("seen",[]).duplicate();returned.clear();action_after.clear();last_human_region=world.actors.human.region_id;next_check=0;last_input=world.director.time
	# Legacy data is a baseline, never free progress from old events.
	if data.is_empty():
		for entry in world.memories.records:mark("memory:"+entry.id)
		for entry in world.fishing.memories:mark("fish:"+entry.id)
		var completion: Dictionary=world.homestead.site.get("completion",{})
		if not completion.is_empty():mark("homestead:"+str(completion.get("id","")))

# Stage rewards remain preferences/actions on the original routine, never an inventory owner.
var preference_file: ConfigFile
var preference_path:=""
var action_after: Dictionary={}
var last_human_region:=""
func setup_preferences(settings: ConfigFile,path: String) -> void:
	preference_file=settings;preference_path=path
func address(id: String) -> String:
	if index(id)<1:return str(config.rewards.default_address)
	var value: String=str(preference_file.get_value("resident:"+id,"human_address",config.rewards.default_address)) if preference_file!=null else str(config.rewards.default_address)
	return value if not value.is_empty() and value.length()<=int(config.rewards.address_max_length) and not value.contains("\n") and not value.contains("\r") else str(config.rewards.default_address)
func set_address(id: String,value: String) -> bool:
	var text:=value.strip_edges()
	if index(id)<1 or id not in world.director.routines or text.is_empty() or text.length()>int(config.rewards.address_max_length) or text.contains("\n") or text.contains("\r") or preference_file==null:return false
	var section:="resident:"+id;var old: Variant=preference_file.get_value(section,"human_address") if preference_file.has_section_key(section,"human_address") else null
	preference_file.set_value(section,"human_address",text)
	if preference_file.save(preference_path)==OK:world.revision+=1;return true
	if old==null:preference_file.erase_section_key(section,"human_address")
	else:preference_file.set_value(section,"human_address",old)
	return false
func addressed(id: String,options: Array) -> Array:return options.map(func(line):return str(line).replace("{address}",address(id)))
func pair_memories(id: String) -> Array:
	var rows: Array=[]
	for entry in world.memories.records:
		var shared: bool=id in entry.participants and "human" in entry.participants
		if entry.kind=="fishing_catch":
			for catch_record in world.fishing.memories:
				if catch_record.id!=entry.source.id:continue
				var present: Array=catch_record.companions.duplicate();present.append(catch_record.actor_id)
				shared=id in present and "human" in present
		if shared:rows.append(world.memories._describe(entry))
	rows.sort_custom(func(a,b):return a.occurred_at<b.occurred_at or (a.occurred_at==b.occurred_at and a.id<b.id))
	return rows.duplicate(true)
func our_place(id: String) -> Dictionary:
	if index(id)<3:return {}
	var counts: Dictionary={}
	for entry in pair_memories(id):
		var target:=""
		match str(entry.kind):
			"meal","shared_barbecue":target=str(entry.facts.get("station_id","home.barbecue"))
			"house_completed","gomoku_match":target=str(entry.facts.get("site_id",""))
		if not target.is_empty():counts[target]=int(counts.get(target,0))+1
	if counts.is_empty():return {}
	var keys: Array=counts.keys();keys.sort_custom(func(a,b):return counts[a]>counts[b] or (counts[a]==counts[b] and str(a)<str(b)))
	var target: String=keys[0];var object: Dictionary=world.barbecues[target].station if world.barbecues.has(target) else world.object_by_id(target)
	if object.is_empty() and world.leisure.sites.has(target):object=world.leisure.sites[target]
	if object.is_empty():return {}
	return {"target_id":target,"region_id":object.get("region_id","home"),"position":object.position.duplicate(),"name":str(object.get("name",LocalText.text("system.relationship_system.camp"))),"evidence_count":counts[target]}
func work_context() -> String:
	var job: Dictionary=world.work.jobs.get("human",{})
	var intent: String=str(job.get("intent",""))
	if intent in ["chop","gather_wood"]:return "chop"
	if intent=="fish":return "fish"
	if intent=="cook":return "cook"
	if intent in ["plant","water","harvest","manage_farm"]:return "farm"
	return ""
func reward_available(id: String) -> bool:
	if id not in world.director.routines:return false
	var r: RefCounted=world.director.routines[id]
	return r.enabled and world.residents.supports(world.actors[id],"move") and not r.blocked() and not r.owns_job() and not world.work.jobs.has(id) and not world._routes.has(id) and not world.shared_activity.holds(id) and world.fishing.life.time>=float(world.fishing.life.quiet_until.get(id,0))
func approach(id: String,kind: String="nearby",focus: Vector2=Vector2.ZERO) -> bool:
	var r: RefCounted=world.director.routines[id];var human: Dictionary=world.actors.human
	if world.actors[id].region_id!=human.region_id:return false
	r.interrupt(8)
	var origin: Vector2=world.point(human)
	for radius in config.rewards.stand_distances:
		for angle in range(12):
			var p: Vector2=origin+Vector2.from_angle(angle*TAU/12)*float(radius)
			if r._move_to(p):
				r.kind=kind;r.elapsed=0;r.duration=float(config.rewards.stay_seconds);r.focus_point=focus
				return true
	return false
func reward(id: String,action: String,explicit: bool=false) -> bool:
	if world.director.brains.has(id) and world.director.brains[id].active() and not world.director.brains[id].executing:
		return world.director.brains[id].execute_provider("relationship_"+action,func():return reward(id,action,explicit))
	var level:=index(id)
	if not reward_available(id):return false
	var r: RefCounted=world.director.routines[id];var actor: Dictionary=world.actors[id];var human: Dictionary=world.actors.human
	if actor.region_id!=human.region_id or world.point(actor).distance_to(world.point(human))>float(config.rewards.notice_radius):return false
	if action=="passing" and level>=1 and world.point(actor).distance_to(world.point(human))<=float(config.rewards.passing_radius):
		r._start("watch")
		var options:=addressed(id,config.lines.passing);var candidates: Array=world.personality.selection(id,options,r.recent_lines)
		if r.chatter and not candidates.is_empty():world.director.say_local(id,candidates[r.rng.randi_range(0,candidates.size()-1)],"relationship_greeting",float(config.personal_gap),float(config.village_gap))
		return true
	if action=="sit" and level>=2:
		# Original rest owns the exact physical seat claim and original validated World route.
		var seats: Array=world.nearby_camp_seats(id) if actor.region_id=="home" else world.interior.furniture.values().filter(func(item):return item.recipe_id=="chair" and item.region_id==actor.region_id and world.interior.placed(item))
		if not seats.any(func(seat):return not world.work.claims.has(seat.id) and world.director.available_position(id,actor.region_id,world.point(seat)) and world.point(seat).distance_to(world.point(human))<=float(config.seat_near_radius)):return false
		if r._start("rest"):r.duration=float(config.rewards.stay_seconds);return true
		return approach(id,"relationship_sit_approach")
	if action=="sea" and level>=2:
		var shore: Dictionary=world.fishing.shore("human")
		return not shore.is_empty() and approach(id,"relationship_sea",Vector2(shore.hook[0],shore.hook[1]))
	if action=="work" and level>=3 and not work_context().is_empty():return approach(id,"relationship_work")
	if action=="welcome" and level>=4 and returned.get(id,false):return approach(id,"relationship_welcome")
	if action=="place" and level>=3:
		var place:=our_place(id)
		if place.is_empty() or place.region_id!=actor.region_id:return false
		for offset in [Vector2(2,2),Vector2(-2,2),Vector2(3,0),Vector2(-3,0)]:
			if r._move_to(Vector2(place.position[0],place.position[1])+offset):
				r.kind="relationship_place";r.elapsed=0;r.duration=float(config.rewards.stay_seconds);return true
	return false
func try_reward(id: String) -> bool:
	if index(id)<1 or not reward_available(id):return false
	var r: RefCounted=world.director.routines[id]
	if r.time<float(action_after.get(id,0)):return false
	action_after[id]=r.time+float(config.rewards.action_interval)
	if r.decision_rng.randf()>float(config.rewards.action_chance):return false
	if returned.get(id,false) and reward(id,"welcome"):return true
	if not work_context().is_empty() and reward(id,"work"):return true
	if index(id)>=2 and (world.days.phase().id=="afternoon" or (world.nearest_barbecue("human",8)!=null)) and reward(id,"sit"):return true
	if index(id)>=2 and not world.fishing.shore("human").is_empty() and reward(id,"sea"):return true
	if index(id)>=3 and r.decision_rng.randf()<.3 and reward(id,"place"):return true
	return reward(id,"passing")
func book(id: String) -> Array:return pair_memories(id) if index(id)>=4 else []
func delivered(id: String,text: String) -> void:
	if text in addressed(id,config.lines.returned):returned.erase(id)
