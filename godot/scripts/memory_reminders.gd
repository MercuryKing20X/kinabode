extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
## Presentation over retained canonical facts only. Never imports or creates memories.
const KINDS := ["island_build","wish_completed","promise_result","meal","shared_barbecue","house_completed","fishing_catch","gomoku_match"]
var _owner: WeakRef
var world: RefCounted:
	get:return _owner.get_ref()
var config: Dictionary={}
var settings: ConfigFile
var path: String=""
var checks_after: Dictionary={}
func _init(source: RefCounted) -> void:
	_owner=weakref(source)
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/companions/local-life.json"))
	var value: Variant=data.get("memory_reminders",{})
	if valid_config(value):config=value.duplicate(true)
func valid_config(value: Variant) -> bool:
	if not value is Dictionary or not value.get("kinds") is Array or value.kinds.is_empty() or not value.kinds.all(func(kind):return kind in KINDS) or not value.get("lines") is Dictionary:return false
	for key in ["first_after","min_age","personal_gap","village_gap","check_interval","radius","large_fish_scale"]:
		if not value.get(key) is float and not value.get(key) is int:return false
		if not is_finite(value[key]) or value[key]<0 or value[key]>86400:return false
	if value.check_interval<=0 or value.personal_gap<=0 or value.village_gap<=0 or value.radius<=0 or value.radius>12 or value.large_fish_scale<1 or value.large_fish_scale>8:return false
	for key in KINDS+["legacy_meal"]:
		if not value.lines.get(key) is String or value.lines[key].is_empty() or value.lines[key].length()>80:return false
	return true
func setup(shared_settings: ConfigFile,filename: String) -> void:
	settings=shared_settings;path=filename
func section(id: String="") -> String:return "memory_reminders:"+world.world_id+(":"+id if not id.is_empty() else "")
func history(id: String) -> Variant:
	var value: Variant=settings.get_value(section(id),"mentioned",[])
	if not value is Array or value.size()>4096:return null
	var result: Array=[]
	for key in value:
		if not key is String or key.length()!=64 or not key.is_valid_hex_number(false) or key in result:return null
		result.append(key)
	return result
func deadline(part: String) -> float:
	var value: Variant=settings.get_value(part,"next_after",0.0)
	if not (value is float or value is int) or not is_finite(value) or value<0:return INF
	return float(value)
func eligible(id: String) -> bool:
	if not world.director.model_controlled(id):return false
	if config.is_empty() or settings==null or path.is_empty() or id=="human" or not world.director.routines.has(id):return false
	var routine: RefCounted=world.director.routines[id];var actor: Dictionary=world.actors[id]
	if not routine.enabled or not routine.chatter or routine.held or routine.blocked() or not routine.kind.is_empty():return false
	if routine.time<float(config.first_after) or routine.time<routine.next_speech or world.director.time<world.director.speech_after:return false
	if world.fishing.life.time<float(world.fishing.life.quiet_until.get(id,0)):return false
	if world.activities.held.get(id,false) or world.activities.blocked(id) or world.shared_activity.holds(id) or world.farms.active(id) or world.projects.active(id) or world.gomoku.active(id):return false
	if world.work.jobs.has(id) or world._routes.has(id) or world.loaded(id) or not world.fishing.held(id).is_empty() or actor.activity!="idle":return false
	if actor.region_id!=world.actors.human.region_id or world.point(actor).distance_to(world.point(world.actors.human))>float(config.radius):return false
	return world.forest.clock>=deadline(section(id)) and world.forest.clock>=deadline(section())
func text_for(id: String,entry: Dictionary) -> String:
	if entry.world_id!=world.world_id or id not in entry.participants or entry.kind not in config.kinds or world.forest.clock-float(entry.occurred_at)<float(config.min_age):return ""
	var facts: Dictionary=entry.facts
	if entry.kind=="island_build":return str(config.lines.island_build).replace("{name}",str(facts.name)) if facts.resident_id==id else ""
	if entry.kind=="wish_completed":
		return str(config.lines.wish_completed).replace("{wish}",str(facts.title)) if facts.resident_id==id else ""
	if entry.kind=="promise_result":
		if facts.resident_id!=id:return ""
		return str(config.lines.promise_result).replace("{activity}",world.promises.config.actions.get(facts.action_type,{}).get("name",facts.action_type)).replace("{result}",LocalText.source("content.remaining.later_kept_the_promise") if facts.outcome=="completed" else LocalText.source("content.remaining.couldn_t_keep_the_promise"))
	if entry.kind=="fishing_catch":
		return str(config.lines.fishing_catch) if facts.catcher_id==id and float(facts.scale)>=float(config.large_fish_scale) else ""
	if "human" not in entry.participants:return ""
	if entry.kind=="shared_barbecue" and facts.get("version")==2:
		var place:String=str(world.barbecues[facts.station_id].station.get("name",world.catalog.regions[entry.region_id].name))
		return str(world.intelligence.catalog.speech.get("barbecue-reminder-v2",{}).get("lines",[""])[0]).replace("{place}",place)
	if entry.kind=="meal":
		# A completed activity has its own canonical reminder, not each portion again.
		if facts.has("activity_id") and world.memories.records.any(func(other):return other.kind=="shared_barbecue" and other.facts.activity_id==facts.activity_id):return ""
		if facts.get("meal_type")=="cooked":
			return str(config.lines.meal).replace("{dish}",str(facts.dish_name)) if id in facts.ate and "human" in facts.ate else ""
		# Legacy overlap confirms presence at the table, not that both finished eating.
		return str(config.lines.legacy_meal) if facts.get("eater_id")==id and "human" in facts.get("overlapped_with",[]) else ""
	if entry.kind=="shared_barbecue" and facts.get("place_id")=="home.moon":return str(config.lines.get("moon_barbecue",config.lines.shared_barbecue))
	if entry.kind=="gomoku_match" and int(facts.move_count)<1:return ""
	return str(config.lines[entry.kind])
func try_speak(id: String) -> bool:
	if not eligible(id):return false
	var routine: RefCounted=world.director.routines[id]
	if routine.time<float(checks_after.get(id,0)):return false
	checks_after[id]=routine.time+float(config.check_interval)
	var mentioned: Variant=history(id)
	if mentioned==null:return false
	if world.memories.notebook!=null:
		for entry in world.memories.notebook.list_for(id):
			if entry.id in mentioned or entry.layer not in ["about_you","facts"] or entry.params.get("human_quote",false) and entry.layer=="facts" or entry.event_id=="reunion":continue
			if world.forest.clock-float(entry.at)<float(config.min_age):continue
			if world.memories.records.any(func(raw):return raw.id==entry.params.get("legacy",{}).get("id","")):continue
			var line:String=LocalText.text("memory.recall."+world.intelligence.tag(id)+"."+entry.layer+"."+str(mentioned.size()%4)).replace("{memory}",world.memories.notebook.render(entry))
			if world.director.say_local(id,line,"memory_reminder",float(config.personal_gap),float(config.village_gap)):
				mentioned.append(entry.id);settings.set_value(section(id),"mentioned",mentioned.slice(-4096));settings.set_value(section(id),"next_after",world.forest.clock+float(config.personal_gap));settings.set_value(section(),"next_after",world.forest.clock+float(config.village_gap));settings.save(path);return true
	for entry in world.memories.records:
		if entry.id in mentioned or world.memories.forgotten(id,entry):continue
		var text:=text_for(id,entry)
		if text.is_empty():continue
		# Keep only IDs of retained facts: no unbounded historical payload or source reads.
		var retained: Array=world.memories.records.map(func(record):return record.id)
		var next: Array=mentioned.filter(func(key):return key in retained);next.append(entry.id)
		var before: Dictionary={}
		for part in [section(id),section()]:
			before[part]={}
			for key in ["mentioned","next_after"]:
				if settings.has_section_key(part,key):before[part][key]=settings.get_value(part,key)
		settings.set_value(section(id),"mentioned",next)
		settings.set_value(section(id),"next_after",world.forest.clock+float(config.personal_gap))
		settings.set_value(section(),"next_after",world.forest.clock+float(config.village_gap))
		# Persist before speaking; a failed write must never announce an unrecorded reminder.
		var saved: bool=settings.save(path)==OK
		if saved and world.director.say_local(id,text,"memory_reminder",float(config.personal_gap),float(config.village_gap)):return true
		for part in before:
			for key in ["mentioned","next_after"]:
				if before[part].has(key):settings.set_value(part,key,before[part][key])
				elif settings.has_section_key(part,key):settings.erase_section_key(part,key)
		if saved:settings.save(path)
		return false
	return false
