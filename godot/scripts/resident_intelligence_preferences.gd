extends RefCounted

# Player opt-in and host accounting only; no credentials or world save fields.
signal preference_changed(actor_id: String, preference: Dictionary)
const LEVELS := ["low", "medium", "high", "ultra", "lifeblood"]
var settings := ConfigFile.new()
var path := ""
var world_id := ""
var runtime_supported: Dictionary = {}
func setup(directory: String, identity: String) -> void:
	path = directory.path_join("resident-intelligence-ui.cfg"); world_id = identity
	settings.load(path)
func section(actor_id: String) -> String: return world_id + "/" + actor_id
func preference(actor_id: String) -> Dictionary:
	var level: String = str(settings.get_value(section(actor_id), "level", "medium"))
	if level not in LEVELS: level = "medium"
	return {"version":1,"level":level,"requested_reasoning_effort":level,"requested_call_policy":"frequent_events" if level in ["ultra","lifeblood"] else "user_triggered","autonomy_enabled":bool(settings.get_value(section(actor_id), "autonomy_enabled", false)),"runtime_active":bool(runtime_supported.get(actor_id,false)) and level!="low" and bool(settings.get_value(section(actor_id),"autonomy_enabled",false))}
func choose(actor_id: String, level: String) -> bool:
	if actor_id.is_empty() or level not in LEVELS: return false
	var previous: Variant = settings.get_value(section(actor_id), "level") if settings.has_section_key(section(actor_id), "level") else null
	var before_enabled: bool=bool(settings.get_value(section(actor_id),"autonomy_enabled",false))
	settings.set_value(section(actor_id), "level", level)
	if level=="low":settings.set_value(section(actor_id),"autonomy_enabled",false)
	if persist() != OK:
		settings.set_value(section(actor_id),"autonomy_enabled",before_enabled)
		if previous == null: settings.erase_section_key(section(actor_id), "level")
		else: settings.set_value(section(actor_id), "level", previous)
		return false
	preference_changed.emit(actor_id, preference(actor_id)); return true

func enable_autonomy(actor_id: String, enabled: bool) -> bool:
	if actor_id.is_empty() or (enabled and preference(actor_id).level=="low"):return false
	var before: bool=bool(settings.get_value(section(actor_id),"autonomy_enabled",false))
	if enabled:reset_failure(actor_id)
	settings.set_value(section(actor_id),"autonomy_enabled",enabled)
	if persist()!=OK:settings.set_value(section(actor_id),"autonomy_enabled",before);return false
	preference_changed.emit(actor_id,preference(actor_id));return true
func accounting(actor_id: String) -> Dictionary:
	var value: Variant=settings.get_value(section(actor_id),"autonomy_accounting",{})
	if not value is Dictionary or value.is_empty():return {}
	for field in ["day","calls","tokens","input_tokens","output_tokens","reserved","last_at","unknown_turns"]:
		if not (value.get(field) is int or value.get(field) is float) or not is_finite(value[field]) or value[field]<0:return {}
	if not value.get("times") is Array or value.times.size()>200 or not value.times.all(func(at):return (at is int or at is float) and is_finite(at) and at>0):return {}
	return value.duplicate(true)
func save_accounting(actor_id: String,value: Dictionary) -> bool:
	var before: Dictionary=accounting(actor_id)
	settings.set_value(section(actor_id),"autonomy_accounting",value.duplicate(true))
	if persist()==OK:return true
	settings.set_value(section(actor_id),"autonomy_accounting",before);return false

func persist() -> Error:
	var result:=settings.save(path+".tmp")
	if result!=OK:return result
	return DirAccess.rename_absolute(path+".tmp",path)

func failure_state(id: String) -> Dictionary:
	var value: Variant=settings.get_value(section(id),"autonomy_failure",{})
	return value.duplicate(true) if value is Dictionary else {}
func fail_runtime(id: String,reason: String,limit: int) -> void:
	var prior: Dictionary=failure_state(id)
	var count: int=int(prior.get("count",0))+1 if prior.get("reason")==reason else 1
	settings.set_value(section(id),"autonomy_failure",{"reason":reason,"count":count,"unavailable":count>=limit})
	if count>=limit:runtime_supported[id]=false
	persist()
func reset_failure(id: String) -> void:
	if settings.has_section_key(section(id),"autonomy_failure"):settings.erase_section_key(section(id),"autonomy_failure");persist()
