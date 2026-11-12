class_name ResidentCatalog
extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
var definitions: Dictionary = {}
var error := ""
var capacity := 32
const SOCIAL := ["island_propose","give","promise","promise_cancel","propose","move","stop","enter","exit","sit","use_facility","come_near","greet","dance","watch","gesture","gomoku_read","gomoku_join","gomoku_move","gomoku_leave","gomoku_resign","journal_read","homestead_read"]
func _init() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/residents.json"))
	if not data is Dictionary or not data.get("residents") is Array: error=LocalText.text("system.resident_catalog.the_resident_catalog_is_invalid"); return
	var limit: Variant = data.get("resident_capacity", 32)
	if not (limit is int or limit is float) or not is_finite(limit) or limit != int(limit) or limit < 2 or limit > 4096:
		error=LocalText.text("system.resident_catalog.the_resident_capacity_is_invalid"); return
	capacity = int(limit)
	if data.residents.size() > capacity: error=LocalText.text("system.resident_catalog.the_resident_catalog_exceeds_capacity"); return
	for entry in data.residents:
		if not valid(entry) or definitions.has(entry.id): error=LocalText.text("system.resident_catalog.resident_entries_are_duplicated_or_invalid"); return
		definitions[entry.id]=entry
	var intelligence:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/intelligence/bindings.json"))
	if not intelligence is Dictionary or intelligence.get("version")!=1 or not intelligence.get("residents") is Dictionary:error=LocalText.text("system.resident_catalog.the_intelligence_resident_bindings_are_invalid");return
	for id in intelligence.residents:
		if not intelligence.residents[id] is Dictionary:error=LocalText.text("system.resident_catalog.invalid_intelligence_preference_binding")+id;return
		if definitions.has(id):
			var candidate:Dictionary=definitions[id].duplicate(true);candidate.preferences=intelligence.residents[id].get("preferences",{})
			if not valid(candidate):error=LocalText.text("system.resident_catalog.invalid_intelligence_preferences")+id;return
			definitions[id]=candidate
func valid(entry: Variant) -> bool:
	if not entry is Dictionary: return false
	for key in ["id","name","role","appearance_id"]:
		if not entry.get(key) is String or entry[key].is_empty() or entry[key].length()>64: return false
	if entry.role not in ["human","companion","npc"] or (entry.role=="human" and entry.id!="human") or entry.name.length()>24:return false
	for c in entry.id:
		if not c in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.":return false
	if entry.id in ["npc.luca","npc.eli"]:return false
	if entry.has("controller") and entry.controller not in (["human"] if entry.id=="human" else ["model","local"]):return false
	if entry.has("capabilities") and (not entry.capabilities is Array or not entry.capabilities.all(func(value):return value in ["social","work"])):return false
	if entry.has("preferences"):
		var prefs: Variant=entry.preferences
		if not prefs is Dictionary:return false
		for key in prefs:
			if key not in ["weights","facilities","wander_radius","facility_radius","fishing_style","personality"]:return false
		if prefs.has("personality") and (not prefs.personality is String or prefs.personality.is_empty() or prefs.personality.length()>32):return false
		if prefs.has("fishing_style") and prefs.fishing_style not in ["calm","lively","curious"]:return false
		for key in ["weights","facilities"]:
			if not prefs.has(key):continue
			if not prefs[key] is Dictionary:return false
			for name in prefs[key]:
				if name not in (["wander","look","stretch","watch","nearby","rest","garden","facility","flower_gift"] if key=="weights" else ["swing","sit","dance"]):return false
				var n: Variant=prefs[key][name]
				if not (n is float or n is int) or not is_finite(n) or n<0 or n>10:return false
		for key in ["wander_radius","facility_radius"]:
			if prefs.has(key) and (not (prefs[key] is float or prefs[key] is int) or not is_finite(prefs[key]) or prefs[key]<2 or prefs[key]>48):return false
	if not entry.get("position") is Array or entry.position.size()!=2: return false
	return entry.position.all(func(n): return (n is int or n is float) and is_finite(float(n)))
func name_for(id: String, fallback: String = LocalText.text("system.resident_catalog.companion")) -> String:
	return str(definitions.get(id,{}).get("name",fallback))
func appearance_for(id: String, fallback: String = "human-starter") -> String:
	return str(definitions.get(id,{}).get("appearance_id",fallback))
func supports(actor: Dictionary, intent: String) -> bool:
	return intent=="stop" or ("social" in capabilities(actor) if intent in SOCIAL else "work" in capabilities(actor))
const PARTNERS=["codex","companion-2","npc.mira","npc.nora"]
func apply_names(world: RefCounted) -> void:
	for id in world.actors:
		if id in PARTNERS:world.actors[id].role="companion"
		if definitions.has(id) and int(world.actors[id].get("name_version",0))<1:
			world.actors[id].name=name_for(id);world.actors[id]["name_version"]=1;world.revision+=1
func rename(world: RefCounted, id: String, value: String) -> Dictionary:
	var cleaned:=value.strip_edges()
	if not world.actors.has(id) or cleaned.is_empty() or cleaned.length()>24 or cleaned.contains("\n") or cleaned.contains("\r"): return {"ok":false,"error":"invalid_name"}
	world.actors[id].name=cleaned;world.actors[id]["custom_name"]=true;world.actors[id]["name_version"]=1;world.revision+=1
	return {"ok":true,"status":"completed"}

func provision(world: RefCounted) -> void:
	for definition in definitions.values():
		if world.actors.has(definition.id):continue
		var p:=Vector2(definition.position[0],definition.position[1])
		if world.locations.v3():
			for plot in world.catalog.regions.home.layout.residential:
				if plot.owner_id==definition.id:
					var site:Dictionary=world.objects[plot.site_id];p=world.point(site)+Vector2(0,world.site_size(site).y/2+1.5)
		if not world.walkable("home",p):continue
		world._add_actor(definition.id,definition.name,definition.role,p)
		if definition.role=="npc" and definition.id not in world.village.ids():
			world.village.definitions.append({"id":definition.id,"name":definition.name,"start":definition.position,"points":[[p.x,p.y],[p.x+2,p.y],[p.x,p.y+2]]})
	world.village.provision()

func controller_for(id: String, role: String) -> String:
	return str(definitions.get(id,{}).get("controller","human" if id=="human" else "model" if role=="companion" else "local"))

func capabilities(actor: Dictionary) -> Array:
	return definitions.get(actor.id,{}).get("capabilities",["social"] if actor.role=="npc" else ["social","work"]).duplicate()

func preferences_for(id: String) -> Dictionary:
	var prefs: Dictionary={"weights":{"wander":3,"look":1,"stretch":1,"watch":1,"nearby":1,"rest":1,"garden":2,"facility":4,"flower_gift":2},"facilities":{"swing":2,"sit":2,"dance":2},"wander_radius":8.0,"facility_radius":38.0}
	var custom: Dictionary=definitions.get(id,{}).get("preferences",{})
	for key in custom:
		if custom[key] is Dictionary:prefs[key].merge(custom[key],true)
		else:prefs[key]=custom[key]
	return prefs
