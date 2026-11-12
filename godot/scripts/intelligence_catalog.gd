extends RefCounted
const ACTIONS=["nearby","wander","rest","facility","garden","watch","stretch","look","flower_gift"]
const CONDITIONS=["hunger_at_least","player_idle","player_actions","relationship_below","interaction_age_at_least","nearby_count_at_least","phases","weather","task_active"]
static func number(v:Variant,lo:float=0,hi:float=86400)->bool:return (v is int or v is float) and is_finite(v) and v>=lo and v<=hi
static func strings(v:Variant)->bool:return v is Array and v.size()<=128 and v.all(func(x):return x is String and not x.is_empty() and x.length()<=160)
static func identifier(v:Variant)->bool:
	if not v is String or v.is_empty() or v.length()>64 or v[0] not in "abcdefghijklmnopqrstuvwxyz":return false
	for c in v:
		if c not in "abcdefghijklmnopqrstuvwxyz0123456789_.-":return false
	return true
static func identifiers(v:Variant)->bool:
	if not strings(v):return false
	var seen:Dictionary={}
	for x in v:
		if not identifier(x) or seen.has(x):return false
		seen[x]=true
	return true
static func condition(v:Variant)->bool:
	if not v is Dictionary or v.keys().any(func(k):return k not in CONDITIONS):return false
	for k in v:
		match k:
			"player_idle","task_active":
				if not v[k] is bool:return false
			"hunger_at_least":
				if v[k] not in ["full","peckish","hungry","very_hungry"]:return false
			"relationship_below":
				if v[k] not in ["new","familiar","close","attuned","family"]:return false
			"interaction_age_at_least","nearby_count_at_least":
				if not number(v[k]):return false
				if k=="nearby_count_at_least" and (v[k]!=floor(v[k]) or v[k]>64):return false
			_:
				if not strings(v[k]) or v[k].is_empty():return false
				var allowed:Array={"player_actions":["idle","move","chop","gather_wood","gather_mushrooms","forage","fish","cook","plant","water","harvest","build","build_house","homestead","eat","play_gomoku","chat"],"phases":["morning","afternoon","dusk","night"],"weather":["sunny","cloudy","rain","fog"]}[k]
				if v[k].any(func(x):return x not in allowed):return false
	return true
static func valid_gait(value:Variant)->bool:
	var limits:Dictionary={"step_scale":[.4,2],"bounce":[0,10],"squash":[0,.12],"sway":[0,4],"lean":[-.12,.12],"dust":[0,2],"spin_every":[0,120],"spin_seconds":[.2,2],"look_every":[0,120],"look_seconds":[.2,2],"full_boost":[1,1.5],"hungry_scale":[.2,1],"head_drop":[0,6]}
	var optional:Dictionary={"run_bounce":[0,16],"run_sway":[0,2],"run_lean":[0,0.3],"run_stretch":[0,0.12],"run_dust":[0,3],"run_frames_per_step":[0.4,2]}
	if not value is Dictionary:return false
	for key in value:
		if not limits.has(key) and not optional.has(key):return false
		if optional.has(key) and not number(value[key],optional[key][0],optional[key][1]):return false
	for key in limits:
		if not number(value.get(key),limits[key][0],limits[key][1]):return false
	for key in ["spin_every","look_every"]:
		if value[key]!=0 and value[key]<5:return false
	return true
static func valid(family:String,d:Variant)->bool:
	if family not in ["speech","behavior","traits","presets"]:return false
	if not d is Dictionary or not identifier(d.get("id")):return false
	var required:Dictionary={"speech":["id","context","lines","autonomy_output"],"behavior":["id","action","conditions","cooldown_seconds","requires_target"],"traits":["id","name","description","speech_units","behavior_units","speech_multiplier","hunger_multiplier","activation"],"presets":["id","name","main_trait","context_traits","speech_style","mode"]}
	var optional:Dictionary={"speech":[],"behavior":["weight","aspect"],"traits":["weights","wish_weights","schedule_weights","favorite_foods","gait","eating_style","voice","return_visit"],"presets":["autonomy_level"]}
	if required[family].any(func(k):return not d.has(k)) or d.keys().any(func(k):return k not in required[family]+optional[family]):return false
	match family:
		"speech":
			if not identifier(d.context) or not strings(d.lines) or d.lines.is_empty() or not d.autonomy_output is bool:return false
			var seen:Dictionary={}
			for line in d.lines:
				if seen.has(line):return false
				seen[line]=true
			return true
		"behavior":return d.action in ACTIONS and condition(d.conditions) and number(d.cooldown_seconds,0,86400) and d.requires_target is bool and number(d.get("weight",1),0,100) and d.get("aspect","idle") in ["idle","speech","wishes","schedules","fishing","gomoku","flower","social","rest","movement","leisure"]
		"traits":
			if not d.name is String or d.name.is_empty() or d.name.length()>160 or not d.description is String or not identifiers(d.speech_units) or not identifiers(d.behavior_units) or not number(d.speech_multiplier,.05,10) or not number(d.hunger_multiplier,.05,10):return false
			if d.has("voice") and not preload("res://scripts/game_audio.gd").valid_voice(d.voice):return false
			if d.has("gait") and not valid_gait(d.gait):return false
			if d.has("return_visit") and not preload("res://scripts/companion_return.gd").valid(d.return_visit):return false
			if d.has("eating_style") and d.eating_style not in ["default","patient","eager","hearty","quiet"]:return false
			if not strings(d.get("favorite_foods",["none"])) or d.get("favorite_foods",[]).any(func(f):return f not in ["*","fish","fruit","vegetable","mushroom","dish","blueberry-jam","grilled-fish","honey-berry-apple","sea-land-skewers","harvest-stew","dark-truffle-soup"]):return false
			if d.activation!=null and (not condition(d.activation) or d.activation.is_empty()):return false
			for field in ["weights","wish_weights","schedule_weights"]:
				if not d.get(field,{}) is Dictionary or not d.get(field,{}).values().all(func(v):return number(v,0,100)):return false
				if d.get(field,{}).keys().any(func(k):return not identifier(k) or (field=="weights" and k not in ACTIONS)):return false
			return true
		"presets":return d.name is String and not d.name.is_empty() and identifier(d.main_trait) and identifiers(d.context_traits) and d.context_traits.size()<=16 and d.speech_style is String and d.mode in ["local","model"] and (not d.has("autonomy_level") if d.mode=="local" else d.get("autonomy_level") in ["low","medium","high","ultra"])
	return false
static func read_all(root:String="res://content/intelligence")->Dictionary:
	var result:Dictionary={"speech":{},"behavior":{},"traits":{},"presets":{}}
	for family in result:
		var folder:String=root.path_join({"speech":"units/speech","behavior":"units/behavior","traits":"traits","presets":"presets"}[family])
		for filename in DirAccess.get_files_at(folder):
			if not filename.ends_with(".json"):continue
			var path:String=folder.path_join(filename);var d:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
			if not valid(family,d) or d.id+".json"!=filename or result[family].has(d.id):return {"ok":false,"error":"invalid intelligence entry: "+path}
			result[family][d.id]=d
	for t in result.traits.values():
		for id in t.speech_units:
			if not result.speech.has(id):return {"ok":false,"error":t.id+".speech_units: missing "+id}
		for id in t.behavior_units:
			if not result.behavior.has(id):return {"ok":false,"error":t.id+".behavior_units: missing "+id}
	for p in result.presets.values():
		if not result.traits.has(p.main_trait) or result.traits[p.main_trait].activation!=null:return {"ok":false,"error":p.id+".main_trait"}
		for id in p.context_traits:
			if not result.traits.has(id) or result.traits[id].activation==null:return {"ok":false,"error":p.id+".context_traits: "+id}
	result["ok"]=true;return result
