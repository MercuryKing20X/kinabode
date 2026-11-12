extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
const Data=preload("res://scripts/intelligence_catalog.gd")
var _owner:WeakRef
var world:RefCounted:
	get:return _owner.get_ref()
var catalog:Dictionary={}
var bindings:Dictionary={}
var legacy:Dictionary={}
var runtime:Dictionary={}
var active:Dictionary={}
var cooldowns:Dictionary={}
var last_input:=0.0
var preferences:=ConfigFile.new()
var preference_path:=""
var compatibility:=true
var behavior_after:Dictionary={}
var gait_defaults:Dictionary={}
func _init(owner:RefCounted)->void:
	_owner=weakref(owner);catalog=Data.read_all()
	if not catalog.ok:world.error=catalog.error;return
	var raw_bindings:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/intelligence/bindings.json"))
	var raw_legacy:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/intelligence/legacy-profiles.json"))
	var raw_runtime:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/intelligence/runtime.json"))
	if not raw_bindings is Dictionary or not raw_legacy is Dictionary or not raw_runtime is Dictionary:world.error=LocalText.text("content.remaining.intelligence_bindings_legacy_projection_and_runtime_configuration_must");return
	bindings=raw_bindings;legacy=raw_legacy;runtime=raw_runtime
	if bindings.keys().size()!=2 or bindings.get("version")!=1 or not bindings.get("residents") is Dictionary or runtime.get("version")!=1 or not legacy.get("profiles") is Dictionary:world.error=LocalText.text("content.remaining.invalid_intelligence_bindings");return
	if runtime.keys().size()!=6 or not Data.number(runtime.get("phase"),2,3) or runtime.phase!=floor(runtime.phase) or runtime.get("activation_limit")!=2 or runtime.get("exit_cooldown")!=60 or not Data.identifiers(runtime.get("priority")) or not runtime.get("reactions") is Dictionary:world.error=LocalText.text("content.remaining.invalid_intelligence_activation_settings");return
	for key in runtime.reactions:
		if not catalog.traits.has(key) or runtime.reactions[key] not in ["watch","look","stretch"]:world.error=LocalText.text("content.remaining.invalid_intelligence_reaction_settings")+str(key);return
	for tag in legacy.profiles:
		var p:Variant=legacy.profiles[tag]
		if not p is Dictionary or not Data.identifiers(p.get("speech_units")):world.error=LocalText.text("content.remaining.invalid_legacy_intelligence_projection")+str(tag);return
		for uid in p.speech_units:
			if not catalog.speech.has(uid):world.error=LocalText.text("content.remaining.missing_speech_in_legacy_intelligence_projection")+uid;return
	for id in bindings.residents:
		if not bindings.residents[id] is Dictionary:world.error=LocalText.text("content.remaining.intelligence_binding_must_be_an_object")+str(id);return
		var b:Dictionary=bindings.residents[id]
		if b.size()!=4 or not catalog.presets.has(b.get("preset_id")) or not legacy.profiles.has(b.get("legacy_tag")) or not b.get("preferences") is Dictionary or not b.get("hunger_enabled") is bool:world.error=LocalText.text("content.remaining.invalid_intelligence_binding")+id;return
	# A host starts the layered local-life session after loading identity/preferences.
	# Bare World fixtures retain the explicit equivalence projection.
	compatibility=true
	var gait_data:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/gaits.json"))
	if not gait_data is Dictionary or gait_data.size()!=3 or gait_data.get("version")!=1 or not Data.valid_gait(gait_data.get("default")) or not Data.valid_gait(gait_data.get("human")):world.error=LocalText.text("content.remaining.invalid_gait_configuration");return
	gait_defaults=gait_data

func gait(id:String)->Dictionary:
	# Appearance and names never choose a gait. Use the current authored main
	# personality even in a bare legacy test world; this is presentation only.
	if id=="human":return gait_defaults.get("human",{}).duplicate(true)
	var result:Dictionary=gait_defaults.get("default",{}).duplicate(true)
	var main:String=str(preset(id).get("main_trait",tag(id)))
	result.merge(catalog.traits.get(main,{}).get("gait",{}),true)
	return result
func activate_presets()->void:
	compatibility=false
	if world.director!=null:
		for routine in world.director.routines.values():routine.apply_intelligence_preferences()
func personality_config()->Dictionary:
	var result:=legacy.duplicate(true);result.erase("profiles");result["traits"]={}
	# Profiles preserve the equivalence migration; cadence comes from the live
	# authored settings, including the host-approved 2026-11-05 speech update.
	var current:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/personalities.json"))
	if current is Dictionary:
		for key in ["personal_gap","village_gap"]:result[key]=current.get(key,result[key])
	for tag in legacy.profiles:
		var p:Dictionary=legacy.profiles[tag].duplicate(true);p["lines"]={}
		for uid in p.speech_units:
			var unit:Dictionary=catalog.speech[uid];p.lines[unit.context]=unit.lines.duplicate()
		p.erase("speech_units");result.traits[tag]=p
	return result
func preset_id(id:String)->String:return str(preferences.get_value("bindings",id,bindings.residents.get(id,{}).get("preset_id","")))
func preset(id:String)->Dictionary:return catalog.presets.get(preset_id(id),{})
func tag(id:String)->String:
	if compatibility:return str(bindings.residents.get(id,{}).get("legacy_tag",""))
	return str(preset(id).get("main_trait",""))
func summary(id:String)->Dictionary:
	var p:=preset(id)
	if p.is_empty():return {}
	return {"id":preset_id(id),"name":str(preferences.get_value("names",preset_id(id),p.name)),"main_trait":p.main_trait,"active":active.get(id,[]).duplicate(),"source":"local_rules"}
func display_name(id:String)->String:
	var data:Dictionary=summary(id)
	if data.is_empty():return LocalText.resident(world,id)
	var default:Dictionary=catalog.presets.get(str(data.id),{})
	return LocalText.content(str(data.name)) if not preferences.has_section_key("names",str(data.id)) and str(data.name)==str(default.get("name","")) else str(data.name)
func profile(id:String)->Dictionary:
	var main:String=tag(id)
	if not catalog.traits.has(main):return {}
	var t:Dictionary=catalog.traits[main];var result:Dictionary={"name":t.name,"action":runtime.reactions.get(main,"watch"),"weights":t.get("weights",{}).duplicate(),"wish_weights":t.get("wish_weights",{}).duplicate(),"schedule_weights":t.get("schedule_weights",{}).duplicate(),"idle_speech_scale":t.speech_multiplier,"lines":{}}
	for uid in t.speech_units:
		var u:Dictionary=catalog.speech[uid]
		if not u.context.begins_with("bbq_"):result.lines[u.context]=u.lines.duplicate()
	if compatibility:return result
	var claimed:Dictionary={"weights":{},"wish_weights":{},"schedule_weights":{},"speech":{}}
	for context_id in active.get(id,[]):
		var context:Dictionary=catalog.traits[context_id]
		for uid in context.speech_units:
			var u:Dictionary=catalog.speech[uid]
			if not claimed.speech.has(u.context):result.lines[u.context]=u.lines.duplicate();claimed.speech[u.context]=true
		for aspect in ["weights","wish_weights","schedule_weights"]:
			for key in context.get(aspect,{}):
				if not claimed[aspect].has(key):result[aspect][key]=context[aspect][key];claimed[aspect][key]=true
		result.idle_speech_scale*=float(context.speech_multiplier)
	return result
func preferences_for(id:String)->Dictionary:
	var result:Dictionary=world.residents.preferences_for(id)
	if compatibility or preset(id).is_empty():return result
	result["personality"]=tag(id)
	result["fishing_style"]="lively" if tag(id) in ["lively","laborious"] else "curious" if tag(id)=="curious" else "calm"
	return result
func speech_pool(id:String,context:String)->Array:
	var result:Array=profile(id).get("lines",{}).get(context,[]).duplicate()
	var candidates:Array=active.get(id,[]).duplicate();candidates.append(tag(id))
	for trait_id in candidates:
		for uid in catalog.traits.get(trait_id,{}).get("speech_units",[]):
			var unit:Dictionary=catalog.speech[uid]
			if unit.context!=context or unit.lines!=result:continue
			for line in result:LocalText.remember_speech(id,str(line),str(line),{},str(uid))
			return result
	return result
func behavior_weights(id:String,base:Dictionary)->Dictionary:
	if compatibility:return base
	var result:=base.duplicate();var visited:Dictionary={};var traits:Array=active.get(id,[]).duplicate();traits.append(tag(id))
	for tid in traits:
		for uid in catalog.traits.get(tid,{}).get("behavior_units",[]):
			var unit:Dictionary=catalog.behavior[uid];var action:String=unit.action
			if visited.has(action):continue
			visited[action]=true
			if not matches(id,unit.conditions) or world.director.time<float(behavior_after.get(id+":"+uid,0)):result[action]=0
			else:result[action]=float(result.get(action,0))*float(unit.get("weight",1))
	return result
func note_behavior(id:String,action:String)->void:
	if compatibility:return
	var traits:Array=active.get(id,[]).duplicate();traits.append(tag(id))
	for tid in traits:
		for uid in catalog.traits.get(tid,{}).get("behavior_units",[]):
			var unit:Dictionary=catalog.behavior[uid]
			if unit.action==action:behavior_after[id+":"+uid]=world.director.time+float(unit.cooldown_seconds);return
func setup(path:String)->void:
	preference_path=path;preferences.load(path)
func rename_preset(id:String,value:String)->bool:
	if not catalog.presets.has(id) or value.strip_edges().is_empty() or value.length()>24:return false
	preferences.set_value("names",id,value.strip_edges());return preference_path.is_empty() or preferences.save(preference_path)==OK
func assign(id:String,value:String)->bool:
	if id=="human" or not world.actors.has(id) or not catalog.presets.has(value):return false
	preferences.set_value("bindings",id,value);active.erase(id);world.revision+=1
	return preference_path.is_empty() or preferences.save(preference_path)==OK
func hunger_multiplier(id:String)->float:
	var main:String=str(preset(id).get("main_trait",""))
	if not catalog.traits.has(main):return 1
	var value:float=catalog.traits[main].hunger_multiplier
	for t in active.get(id,[]):value=maxf(value,float(catalog.traits[t].hunger_multiplier))
	return value
func matches(id:String,condition:Dictionary)->bool:
	for key in condition:
		var value:Variant=condition[key]
		match key:
			"hunger_at_least":
				if world.hunger==null or world.hunger.rank(id)<["full","peckish","hungry","very_hungry"].find(value):return false
			"player_idle":
				if (world.actors.human.activity=="idle" and not world.work.jobs.has("human"))!=value:return false
			"player_actions":
				if world.work.jobs.get("human",{}).get("intent",world.actors.human.activity) not in value:return false
			"relationship_below":
				var stages:Array=["new","familiar","close","attuned","family"]
				if world.relationships.index(id)>=stages.find(value):return false
			"interaction_age_at_least":
				if world.director.time-world.director.moods.last_input<float(value):return false
			"nearby_count_at_least":
				var count:=0
				for other in world.actors.values():
					if other.id!=id and other.region_id==world.actors[id].region_id and world.point(other).distance_to(world.point(world.actors[id]))<12:count+=1
				if count<int(value):return false
			"phases":
				if world.days.phase().id not in value:return false
			"weather":
				if world.weather.current().id not in value:return false
			"task_active":
				if world.work.jobs.has(id)!=value:return false
	return true
func advance()->void:
	if compatibility:return
	for id in bindings.residents:
		if not world.actors.has(id):continue
		var choices:Array=[];var old:Array=active.get(id,[])
		for tid in preset(id).get("context_traits",[]):
			if matches(id,catalog.traits[tid].activation) and world.director.time>=float(cooldowns.get(id+":"+tid,0)):choices.append(tid)
		choices.sort_custom(func(a,b):return priority(a)<priority(b))
		var next:Array=choices.slice(0,2)
		for tid in old:
			if tid not in next:cooldowns[id+":"+tid]=world.director.time+float(runtime.exit_cooldown)
		active[id]=next
func priority(tid:String)->int:
	var i:int=runtime.priority.find(tid);return i if i>=0 else 100
