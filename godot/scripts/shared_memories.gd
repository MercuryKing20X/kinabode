class_name SharedMemories
extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
var localization_since:=-1.0
## Durable facts from existing commit records. Queries never create memories.
const KINDS := ["signature_taste","island_arrival","island_build","cat_contact","home_island_arrival","jieqi_result","dark_discovery","dark_beacon","dark_beacon","first_shared_meal","feeding","meal_reaction","moon_viewing","wish_completed","relationship_stage","gift","promise_result","proposal_decision","meal", "sat_together", "house_completed", "shared_barbecue", "fishing_catch", "gomoku_match"]
const MARK_LIMIT := 192 # Six source collections, each bounded to 32.
var _owner: WeakRef
var world: RefCounted:
	get: return _owner.get_ref()
var records: Array = []
var notebook:RefCounted
var committed:Callable
var source_marks: Array = []
var capacity := 256
var snapshot_limit := 6
var page_limit := 50

func _init(source: RefCounted) -> void:
	_owner = weakref(source)
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/memories.json"))
	if not config is Dictionary or config.get("version") != 1 or not _count(config.get("capacity"),4096) or config.capacity < MARK_LIMIT or not _count(config.get("snapshot_limit"),50) or config.snapshot_limit < 1 or not _count(config.get("page_limit"),50) or config.page_limit < config.snapshot_limit:
		world.error = LocalText.text("memory.config_invalid"); return
	capacity = int(config.capacity); snapshot_limit = int(config.snapshot_limit); page_limit = int(config.page_limit)

func _count(value: Variant, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(value) and value == floor(value) and value >= 0 and value <= maximum

func _time(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(value) and value > 0 and value <= 253402300799

func _ids(value: Variant, actors: Dictionary, minimum := 1) -> bool:
	if not value is Array or value.size() < minimum or value.size() > world.residents.capacity: return false
	var seen := {}
	for id in value:
		if not id is String or not actors.has(id) or seen.has(id): return false
		seen[id] = true
	return true

func _sorted(value: Array) -> Array:
	var result := value.duplicate(); result.sort(); return result

func _canonical(value: Variant) -> String:
	# JSON decodes counts as floats; equivalent integers must have one fact key.
	if (value is int or value is float) and is_finite(value) and value==floor(value): return str(int(value))
	if value is Dictionary:
		var keys: Array = value.keys(); keys.sort(); var pieces: Array[String] = []
		for key in keys: pieces.append(JSON.stringify(key) + ":" + _canonical(value[key]))
		return "{" + ",".join(pieces) + "}"
	if value is Array:
		var pieces: Array[String] = []
		for item in value: pieces.append(_canonical(item))
		return "[" + ",".join(pieces) + "]"
	return JSON.stringify(value)

func _record_id(world_id: String, kind: String, source_id: String) -> String:
	return (world_id + "|" + kind + "|" + source_id).sha256_text()

func _contributions(value: Variant, actors: Dictionary) -> Dictionary:
	if not value is Dictionary: return {}
	var result := {}
	for id in value:
		var count: Variant = value[id]
		if not id is String or not actors.has(id) or not count is Dictionary or not _count(count.get("wood"),100000) or not _count(count.get("stages"),5): return {}
		if int(count.wood) > 0 or int(count.stages) > 0: result[id] = {"wood":int(count.wood),"stages":int(count.stages)}
	return result

func _normalize(kind: String, raw: Variant) -> Dictionary:
	if not raw is Dictionary: return {}
	# Use the same number precision as saved source records, including legacy timestamps.
	var data: Dictionary = JSON.parse_string(JSON.stringify(raw))
	var at: Variant = data.get("time") if kind == "meal" else data.get("at")
	if not _time(at): return {}
	var participants: Array = []; var facts := {}; var region := "home"; var source_id := ""
	match kind:
		"gomoku_match":
			if world.gomoku==null or not world.gomoku.valid_game(data,world.actors,world.leisure.sites) or data.phase!="finished":return {}
			participants=_sorted([data.black_id,data.white_id]);source_id=data.id
			facts={"match_id":data.id,"site_id":data.site_id,"black_id":data.black_id,"white_id":data.white_id,"winner_id":data.winner_id,"result":data.result,"move_count":data.history.size()}
		"fishing_catch":
			if not data.get("id") is String or not data.id.begins_with("fish-") or data.id.length()!=29 or not world.actors.has(data.get("actor_id","")) or not world.fishing.known_water(data.get("water_id","")):return {}
			if not world.catalog._number(data.get("scale")) or data.scale<1 or data.scale>8 or not world.fishing.rules.species.any(func(s):return s.id==data.get("species_id")) or not world.fishing.rules.colors.any(func(c):return c.id==data.get("color_id")):return {}
			participants=[data.actor_id];source_id=data.id
			facts={"fish_id":data.id,"catcher_id":data.actor_id,"species_id":data.species_id,"color_id":data.color_id,"scale":data.scale,"water_id":data.water_id}
		"shared_barbecue":
			if not data.get("id") is String or data.id.is_empty(): return {}
			if data.get("kind") != kind or not _ids(data.get("participants"),world.actors,2) or not _ids(data.get("ate"),world.actors,2) or _sorted(data.participants) != _sorted(data.ate) or not data.get("steps") is Dictionary: return {}
			if data.steps.size() != 3 or data.steps.keys().any(func(key):return key not in ["prepare","turn","cleanup"]) or data.steps.values().any(func(id):return id not in data.participants): return {}
			participants = _sorted(data.participants); source_id = str(data.get("id",""))
			facts = {"activity_id":source_id,"consumed_by":participants.duplicate(),"roles":data.steps.duplicate(true)}
		"meal":
			if data.has("meal_type"):
				facts=meal_facts(data,world.actors)
				if facts.is_empty():return {}
				participants=_sorted(data.ate) if data.meal_type=="cooked" else [data.actor_id]
				source_id=data.event_id
			else:
				if data.has("event_id") and (not data.event_id is String or data.event_id.is_empty() or data.event_id.length()>64):return {}
				if not data.get("actor_id") is String or not world.actors.has(data.actor_id) or not _ids(data.get("companions"),world.actors,0) or data.actor_id in data.companions: return {}
				participants = _sorted([data.actor_id] + data.companions)
				facts = {"eater_id":data.actor_id,"food":"mushroom","quantity":1,"overlapped_with":_sorted(data.companions)}
				if data.has("activity_id"):
					if not data.activity_id is String or data.activity_id.is_empty() or data.activity_id.length()>64:return {}
					facts["activity_id"] = data.activity_id
				source_id = str(data.get("event_id",""))
		"sat_together":
			if data.has("event_id") and (not data.event_id is String or data.event_id.is_empty() or data.event_id.length()>64):return {}
			if data.get("kind") != kind or not _ids(data.get("actors"),world.actors,2) or data.actors.size()!=2 or not world.interior.rooms().has(data.get("room_id","")): return {}
			participants = _sorted(data.actors); region = data.room_id; facts = {"room_id":region}
			source_id = str(data.get("event_id",""))
		"house_completed":
			if not data.get("project_id") is String or data.project_id.is_empty():return {}
			var site: Dictionary = world.objects.get(data.get("site_id",""),{})
			if site.get("kind") != "construction_site" or site.get("stage_index") != 5: return {}
			var contributions := _contributions(data.get("contributors"),world.actors)
			if contributions.is_empty(): return {}
			participants = _sorted(contributions.keys()); region = str(site.region_id)
			facts = {"site_id":site.id,"contributions":contributions}
			source_id = str(data.get("project_id",""))
		_: return {}
	if kind in ["meal","shared_barbecue"] and data.has("station_id"):
		if not meal_place_valid(data):return {}
		facts["station_id"]=data.station_id;facts["place_id"]=data.place_id
	if source_id.length()>128: return {}
	var result := {"kind":kind,"occurred_at":float(at),"region_id":region,"participants":participants,"facts":facts,"source":{"system":kind,"id":source_id}}
	if source_id.is_empty(): result.source.id = "legacy:" + _canonical(result).sha256_text()
	return result

func meal_facts(data: Dictionary,actors: Dictionary) -> Dictionary:
	if not data.get("event_id") is String or data.event_id.is_empty() or data.event_id.length()>64 or not _time(data.get("time")):return {}
	var facts: Dictionary={}
	var participants: Array=[]
	if data.get("meal_type")=="cooked":
		if not data.get("ate") is Array:return {}
		participants=data.ate
		facts={"meal_type":"cooked","batch_id":data.event_id,"recipe_id":data.get("recipe_id"),"dish_name":data.get("dish_name"),"invited":data.get("invited"),"participants":data.get("participants"),"ate":data.ate,"portions_by_actor":data.get("portions_by_actor"),"quantity":data.get("quantity"),"ingredients":data.get("ingredients"),"fish":data.get("fish")}
	elif data.get("meal_type")=="farm":
		participants=[data.get("actor_id")]
		facts={"meal_type":"farm","eater_id":data.get("actor_id"),"food":data.get("item_id"),"quantity":data.get("quantity"),"farm_id":data.get("farm_id")}
	return facts if valid_meal_facts(facts,participants,actors,data.event_id) else {}
func valid_meal_facts(facts: Dictionary,participants: Array,actors: Dictionary,source_id: String) -> bool:
	if not _ids(participants,actors):return false
	if facts.get("meal_type")=="farm":
		return facts.size()==5 and participants==[facts.get("eater_id")] and world.farms.crops.has(facts.get("food","")) and world.farms.farms.has(facts.get("farm_id","")) and facts.get("quantity")==2 and source_id.begins_with("farm-meal-")
	if facts.get("meal_type")!="cooked" or facts.size()!=11 or facts.get("batch_id")!=source_id or not source_id.begins_with("meal-") or source_id.length()!=29:return false
	if not facts.get("recipe_id") is String or facts.recipe_id.is_empty() or facts.recipe_id.length()>64 or not facts.get("dish_name") is String or facts.dish_name.is_empty() or facts.dish_name.length()>32:return false
	if not _ids(facts.get("invited"),actors) or not _ids(facts.get("participants"),actors) or not _ids(facts.get("ate"),actors) or _sorted(facts.ate)!=_sorted(participants) or not facts.participants.all(func(id):return id in facts.invited) or not facts.ate.all(func(id):return id in facts.participants):return false
	if not _count(facts.get("quantity"),8) or facts.quantity<1 or not facts.get("portions_by_actor") is Dictionary or _sorted(facts.portions_by_actor.keys())!=_sorted(facts.ate):return false
	var total:=0
	for quantity in facts.portions_by_actor.values():
		if not _count(quantity,8) or quantity<1:return false
		total+=int(quantity)
	if total!=facts.quantity or not facts.get("ingredients") is Dictionary or facts.ingredients.is_empty() or facts.ingredients.size()>4 or facts.ingredients.keys().any(func(key):return key not in world.recipes.INGREDIENT_IDS):return false
	if facts.ingredients.values().any(func(quantity):return not _count(quantity,24) or quantity<1) or not facts.get("fish") is Dictionary:return false
	if not facts.fish.is_empty():
		if facts.fish.size()!=5 or not facts.fish.get("fish_id") is String or not facts.fish.fish_id.begins_with("fish-") or facts.fish.fish_id.length()!=29 or not actors.has(facts.fish.get("owner_id","")) or not facts.fish.get("source_id") is String or not world.fishing.known_water(facts.fish.source_id) or facts.fish.get("size_id") not in ["person","large","huge","giant"] or not world.catalog._number(facts.fish.get("scale")) or facts.fish.scale<1 or facts.fish.scale>8:return false
	return true

func sync() -> void:
	var existing := {}; var marked := {}; var current: Array = []; var additions: Array = []
	for entry in records: existing[entry.id] = true
	for id in source_marks: marked[id] = true
	var sources := [["meal",world.life.memories],["sat_together",world.interior.memories],["house_completed",world.projects.memories],["shared_barbecue",world.shared_activity.memories],["fishing_catch",world.fishing.memories]]
	if world.gomoku!=null:sources.append(["gomoku_match",world.gomoku.memories])
	for pair in sources:
		var occurrences := {}
		for raw in pair[1]:
			var entry := _normalize(pair[0],raw)
			if entry.is_empty(): continue
			var key: String = entry.source.id
			if key.begins_with("legacy:"):
				var ordinal: int = int(occurrences.get(key,0)); occurrences[key] = ordinal + 1
				entry.source.id = key + ":%s" % ordinal
			entry["world_id"] = world.world_id
			entry["id"] = _record_id(world.world_id,entry.kind,entry.source.id)
			if entry.id in current: continue
			current.append(entry.id)
			if existing.has(entry.id) or marked.has(entry.id): continue
			existing[entry.id] = true; additions.append(entry)
	# Legacy imports have an actual chronology; never infer events from current state.
	additions.sort_custom(func(a,b):return a.occurred_at<b.occurred_at or (a.occurred_at==b.occurred_at and a.id<b.id))
	for entry in additions:
		if float(entry.occurred_at)>localization_since:entry["text_version"]=1
		records.append(entry)
		if committed.is_valid():committed.call(entry)
		if records.size()>capacity: records.pop_front()
	if source_marks != current or not additions.is_empty(): source_marks = current; world.revision += 1

func _describe(entry: Dictionary, language:String="") -> Dictionary:
	LocalText.ensure()
	var translated:Callable=func(key:String)->String:return LocalText.text(key) if language.is_empty() else str(LocalText.entries.get(key,{}).get(language,LocalText.source(key)))
	var content_label:Callable=func(value:String)->String:return LocalText.content(value) if language.is_empty() else (translated.call(str(LocalText.content_keys[value])) if LocalText.content_keys.has(value) else value)
	var resident_name:Callable=func(id:String)->String:
		if language.is_empty():return LocalText.resident(world,id)
		var actor:Dictionary=world.actors.get(id,{})
		if actor.get("custom_name",false):return str(actor.get("name",id))
		var key:String={"human":"resident.you","codex":"resident.snow","companion-2":"resident.skye","npc.mira":"resident.clem","npc.nora":"resident.raven"}.get(id,"")
		return translated.call(key) if not key.is_empty() else str(actor.get("name",id))
	var result:Dictionary=entry.duplicate(true);var names:Dictionary={};var labels:Array[String]=[]
	var localized:bool=entry.get("text_version",0)==1
	var t:Callable=func(key:String)->String:return translated.call("memory."+key) if localized else LocalText.source("memory."+key)
	var display:Callable=func(value:String)->String:return content_label.call(value) if localized else value
	for id in entry.participants:
		names[id]=resident_name.call(id) if localized and world.actors.has(id) else str(world.actors.get(id,{}).get("name",t.call("departed")%id))
		labels.append(names[id])
	result["participant_names"]=names
	var joined:String=str(t.call("join")).join(labels);var f:Dictionary=entry.facts
	match str(entry.kind):
		"signature_taste":result["summary"]=translated.call("content.signature.memory")%[names[f.actor_id],content_label.call(world.recipes.recipe_catalog[f.recipe_id].name)]
		"cat_contact":result["summary"]=translated.call("cat.memory."+str(f.action))%names[f.actor_id]
		"island_arrival":result["summary"]=translated.call("theirs.arrival_memory")%names[f.resident_id]
		"island_build":result["summary"]=translated.call("theirs.memory")%[resident_name.call(str(f.resident_id)),str(f.name)]
		"home_island_arrival":result["summary"]=translated.call("homeisland.memory")
		"jieqi_result":
			result["summary"]=translated.call("memory.jieqi."+str(f.winner))%[names[f.opponent_id],int(f.moves)]
		"dark_discovery":
			var relics:Array=world.dark.discoveries.config.objects.filter(func(item):return item.id==f.id)
			result["summary"]=t.call("stars") if f.id=="stars" else t.call("discovery")%display.call(str(relics[0].name))
		"dark_beacon":result["summary"]=t.call("beacon")%display.call(str(f.name))
		"first_shared_meal":result["summary"]=t.call("first_night" if f.phase=="night" else "first_meal")
		"feeding":result["summary"]=t.call("feeding")%[names[f.giver_id],names[f.receiver_id],display.call(str(world.farms.crops.get(str(f.item_id),{}).get("name",f.item_id)))]
		"meal_reaction":result["summary"]=t.call("meal_reaction")%[names[f.eater_id],display.call(str(f.previous_state))]
		"moon_viewing":result["summary"]=t.call("moon")%[joined,f.day]
		"wish_completed":result["summary"]=t.call("wish")%[names[f.resident_id],display.call(str(f.title))]
		"relationship_stage":result["summary"]=t.call("relationship")%[names[f.resident_id],display.call(str(f.stage_name))]
		"gift":result["summary"]=t.call("gift")%[names[f.giver_id],f.quantity,display.call(str(f.item_id)),names[f.receiver_id]]
		"promise_result":
			var action:String=display.call(str(world.promises.config.actions.get(f.action_type,{}).get("name",f.action_type)))
			result["summary"]=t.call("promise_done")%[names[f.resident_id],action] if f.outcome=="completed" else t.call("promise_failed")%[names[f.resident_id],action,f.reason]
		"proposal_decision":result["summary"]=t.call("proposal_accept" if f.decision=="accepted" else "proposal_decline")%[names[f.resident_id],f.text]
		"gomoku_match":result["summary"]=t.call("gomoku_draw")%[joined,f.move_count] if f.result=="draw" else t.call("gomoku_win" if f.result=="five" else "gomoku_resign")%[joined,f.move_count,names[f.winner_id]]
		"fishing_catch":
			var label:String=f.species_id
			for species in world.fishing.rules.species:
				if species.id==f.species_id:label=species.name
			result["summary"]=t.call("catch")%[names[f.catcher_id],display.call(label),str(f.scale)]
		"shared_barbecue":result["summary"]=t.call("barbecue" if f.get("version")==2 else "legacy_barbecue")%joined
		"meal":
			if f.get("meal_type")=="cooked":result["summary"]=t.call("cooked_together" if labels.size()>1 else "cooked_alone")%[joined,display.call(str(f.dish_name)),f.quantity]
			elif f.get("meal_type")=="farm":result["summary"]=t.call("farm_meal")%names[f.eater_id]
			else:result["summary"]=t.call("mushroom")%names[f.eater_id]
		"sat_together":result["summary"]=t.call("sat")%joined
		"house_completed":result["summary"]=t.call("house")%joined
	if entry.kind in ["meal","shared_barbecue"] and f.get("place_id")=="home.moon":result.summary+=str(t.call("moon_suffix"))
	return result

func query(actor_id: String, args: Dictionary = {}) -> Dictionary:
	if not world.actors.has(actor_id):return {"ok":false,"error":"unknown_resident"}
	for key in args:
		if key not in ["kind","with_resident","region_id","after","before","memory_id","offset","limit","revision"]:return {"ok":false,"error":"invalid_memory_query"}
	for key in ["kind","with_resident","region_id","memory_id","revision"]:
		if args.has(key) and (not args[key] is String or args[key].is_empty() or args[key].length()>128):return {"ok":false,"error":"invalid_memory_query"}
	if args.has("kind") and args.kind not in KINDS:return {"ok":false,"error":"invalid_memory_query"}
	if args.has("with_resident") and not world.actors.has(args.with_resident):return {"ok":false,"error":"unknown_resident"}
	for key in ["after","before"]:
		if args.has(key) and (not _count(args[key],9223372036854775807) and not _time(args[key])):return {"ok":false,"error":"invalid_memory_query"}
	if args.has("after") and args.has("before") and args.after>args.before:return {"ok":false,"error":"invalid_memory_query"}
	var offset: Variant=args.get("offset",0);var limit: Variant=args.get("limit",12)
	if not _count(offset,10000) or not _count(limit,page_limit) or limit<1:return {"ok":false,"error":"invalid_memory_query"}
	var visible: Array = records.filter(func(entry):return actor_id in entry.participants and not forgotten(actor_id,entry))
	var completed := {}
	for entry in visible:
		if entry.kind=="shared_barbecue":completed[entry.facts.activity_id]=true
	var selected: Array = []
	for entry in visible:
		if args.has("kind") and entry.kind!=args.kind:continue
		if args.has("memory_id") and entry.id!=args.memory_id:continue
		if not args.has("kind") and not args.has("memory_id") and entry.kind=="meal" and completed.has(entry.facts.get("activity_id","")):continue
		if args.has("with_resident") and args.with_resident not in entry.participants:continue
		if args.has("region_id") and entry.region_id!=args.region_id:continue
		if args.has("after") and entry.occurred_at<float(args.after):continue
		if args.has("before") and entry.occurred_at>float(args.before):continue
		selected.append(_describe(entry))
	if args.has("memory_id") and selected.is_empty():return {"ok":false,"error":"memory_not_found"}
	selected.sort_custom(func(a,b):return a.occurred_at>b.occurred_at or (a.occurred_at==b.occurred_at and a.id<b.id))
	var filters: Dictionary=args.duplicate();filters.erase("offset");filters.erase("limit");filters.erase("revision")
	var revision: String = _canonical([world.world_id,actor_id,filters,selected]).sha256_text()
	if (int(offset)>0 and not args.has("revision")) or (args.has("revision") and args.revision!=revision):return {"ok":false,"error":"stale_memories","revision":revision}
	return {"ok":true,"schema_version":1,"self_actor_id":actor_id,"revision":revision,"total":selected.size(),"offset":offset,"limit":limit,"next_offset":offset+limit if offset+limit<selected.size() else -1,"memories":selected.slice(int(offset),int(offset+limit)),"capacity":capacity}

func saved() -> Dictionary: return {"version":1,"records":records.duplicate(true),"source_marks":source_marks.duplicate()}
func restore(data: Dictionary) -> void:
	records=data.get("records",[]).duplicate(true);source_marks=data.get("source_marks",[]).duplicate();localization_since=world.forest.clock

func valid_saved(data: Variant, actors: Dictionary, world_id: String) -> bool:
	if not data is Dictionary or data.get("version")!=1 or not data.get("records") is Array or data.records.size()>capacity or not data.get("source_marks") is Array or data.source_marks.size()>MARK_LIMIT:return false
	var marked := {}
	for id in data.source_marks:
		if not id is String or id.length()!=64 or not id.is_valid_hex_number(false) or marked.has(id):return false
		marked[id]=true
	var seen := {}
	for entry in data.records:
		if entry is Dictionary and entry.keys().any(func(key):return key not in ["id","world_id","kind","occurred_at","region_id","participants","facts","source","text_version"]):return false
		if not entry is Dictionary or entry.get("world_id")!=world_id or entry.get("kind") not in KINDS or not _time(entry.get("occurred_at")) or not entry.get("region_id") is String or entry.region_id.is_empty() or entry.region_id.length()>128 or not _ids(entry.get("participants"),actors) or not entry.get("facts") is Dictionary or not entry.get("source") is Dictionary:return false
		if entry.source.size()!=2 or entry.source.get("system")!=entry.kind or not entry.source.get("id") is String or entry.source.id.is_empty() or entry.source.id.length()>128 or entry.get("id")!=_record_id(world_id,entry.kind,entry.source.id) or seen.has(entry.id):return false
		seen[entry.id]=true
		if entry.has("text_version") and (not _count(entry.text_version,1) or entry.text_version!=1):return false
		var facts: Dictionary=entry.facts
		match str(entry.kind):
			"signature_taste","island_arrival","island_build","home_island_arrival","cat_contact","jieqi_result","dark_discovery","dark_beacon","first_shared_meal","feeding","meal_reaction","moon_viewing","wish_completed","relationship_stage","gift","promise_result","proposal_decision":
				if not engine_facts_valid(entry.kind,facts,entry.participants,actors):return false
			"gomoku_match":
				if facts.size()!=7 or facts.get("match_id")!=entry.source.id or not facts.get("site_id") is String or facts.site_id.is_empty() or facts.site_id.length()>128 or not _ids([facts.get("black_id"),facts.get("white_id")],actors,2) or _sorted([facts.black_id,facts.white_id])!=_sorted(entry.participants) or not _count(facts.get("move_count"),225):return false
				if facts.get("result") not in ["five","draw","resign"] or (facts.result=="draw" and (facts.get("winner_id")!="" or facts.move_count!=225)) or (facts.result!="draw" and facts.get("winner_id") not in entry.participants) or (facts.result=="five" and facts.move_count<9):return false
			"fishing_catch":
				if facts.size()!=6 or facts.get("fish_id")!=entry.source.id or not facts.get("fish_id") is String or not facts.fish_id.begins_with("fish-") or facts.fish_id.length()!=29 or entry.participants!=[facts.get("catcher_id")]:return false
				if not world.fishing.known_water(facts.get("water_id","")) or not world.catalog._number(facts.get("scale")) or facts.scale<1 or facts.scale>8 or not world.fishing.rules.species.any(func(s):return s.id==facts.get("species_id")) or not world.fishing.rules.colors.any(func(c):return c.id==facts.get("color_id")):return false
			"shared_barbecue":
				if facts.get("version")==2:
					if not fireside_facts_valid(facts,entry.participants,actors):return false
					continue
				if facts.keys().size()!=(5 if facts.has("station_id") else 3) or (facts.has("station_id") and not meal_place_valid(facts)) or not facts.get("activity_id") is String or facts.activity_id!=entry.source.id or not _ids(facts.get("consumed_by"),actors,2) or _sorted(facts.consumed_by)!=_sorted(entry.participants) or not facts.get("roles") is Dictionary or facts.roles.size()!=3 or facts.roles.keys().any(func(key):return key not in ["prepare","turn","cleanup"]) or facts.roles.values().any(func(id):return id not in entry.participants):return false
			"meal":
				if facts.has("meal_type"):
					if not valid_meal_facts(facts,entry.participants,actors,entry.source.id):return false
					continue
				if facts.keys().any(func(key):return key not in ["eater_id","food","quantity","overlapped_with","activity_id","station_id","place_id"]) or not facts.get("eater_id") is String or facts.eater_id not in entry.participants or facts.get("food")!="mushroom" or facts.get("quantity")!=1 or not _ids(facts.get("overlapped_with"),actors,0) or facts.eater_id in facts.overlapped_with or _sorted([facts.eater_id]+facts.overlapped_with)!=_sorted(entry.participants):return false
				if facts.has("station_id") and not meal_place_valid(facts):return false
				if facts.has("activity_id") and (not facts.activity_id is String or facts.activity_id.is_empty() or facts.activity_id.length()>64):return false
			"sat_together":
				if entry.participants.size()!=2 or facts.size()!=1 or facts.get("room_id")!=entry.region_id or not entry.region_id.begins_with("room."):return false
			"house_completed":
				if facts.size()!=2 or not facts.get("site_id") is String or facts.site_id.is_empty() or facts.site_id.length()>128:return false
				var contributions := _contributions(facts.get("contributions"),actors)
				if contributions.is_empty() or _canonical(contributions)!=_canonical(facts.contributions) or _sorted(contributions.keys())!=_sorted(entry.participants):return false
	return true

func engine_facts_valid(kind: String,facts: Dictionary,participants: Array,actors: Dictionary) -> bool:
	if kind=="signature_taste":
		if facts.size()!=2 or not actors.has(facts.get("actor_id","")) or facts.actor_id=="human" or facts.get("recipe_id") not in ["honey-berry-apple","sea-land-skewers","harvest-stew","dark-truffle-soup"]:return false
		return participants==[facts.actor_id] or _sorted(participants)==_sorted(["human",facts.actor_id])
	if kind=="island_arrival":return facts.size()==1 and actors.has(facts.get("resident_id","")) and facts.resident_id!="human" and _sorted(participants)==_sorted(["human",facts.resident_id])
	if kind=="island_build":return facts.size()==3 and actors.has(facts.get("resident_id","")) and facts.resident_id!="human" and _sorted(participants)==_sorted(["human",facts.resident_id]) and facts.get("site_id") is String and facts.site_id.begins_with("play.custom.") and facts.get("name") is String and facts.name.length()>0 and facts.name.length()<=40 and not "\n" in facts.name and not "\r" in facts.name
	if kind=="cat_contact":return facts.size()==2 and facts.get("action") in ["hold","pet"] and actors.has(facts.get("actor_id","")) and participants==[facts.actor_id]
	if kind=="home_island_arrival":return facts=={"region_id":"homelands"} and participants==["human"] and actors.has("human")
	if kind=="jieqi_result":
		return facts.size()==4 and actors.has(facts.get("opponent_id","")) and facts.opponent_id!="human" and _sorted(participants)==_sorted(["human",facts.opponent_id]) and facts.get("winner") in ["human","opponent","draw"] and _count(facts.get("seed"),4294967295) and _count(facts.get("moves"),100000)
	if kind=="dark_discovery":
		return facts.size()==1 and "human" in participants and (facts.get("id")=="stars" or world.dark.discoveries.config.objects.any(func(i):return i.id==facts.get("id")))
	if kind=="dark_beacon":
		if world.dark==null or not world.dark.enabled() or facts.size()!=3 or "human" not in participants:return false
		for area in world.dark.config.areas:
			if area.id==facts.get("area_id") and area.has("beacon"):return facts.get("name")==area.name and facts.get("beacon")==area.beacon
		return false
	if kind=="shared_barbecue" and facts.get("version")==2:return fireside_facts_valid(facts,participants,actors)
	if kind=="first_shared_meal":
		return facts.size()==5 and _ids(participants,actors,4) and (_sorted(participants)==_sorted(world.standard.config.companions) or _sorted(participants)==_sorted(["human"]+world.standard.config.companions)) and facts.get("ate") is Array and _sorted(facts.ate)==_sorted(participants) and facts.get("activity_id") is String and facts.activity_id.length()==24 and facts.get("station_id")=="home.barbecue" and _count(facts.get("day"),1000000) and facts.day>=1 and facts.get("phase") in ["morning","afternoon","dusk","night"]
	if kind=="feeding":
		return facts.size()==4 and facts.get("giver_id")=="human" and actors.has(facts.get("receiver_id")) and facts.receiver_id!="human" and _sorted(participants)==_sorted(["human",facts.receiver_id]) and (facts.get("item_id") in world.hunger.config.snack_items or (facts.get("item_id") is String and str(facts.item_id).begins_with("meal:") and str(facts.item_id).trim_prefix("meal:") in world.recipes.recipe_catalog)) and facts.get("quantity")==1
	if kind=="meal_reaction":
		return facts.size()==4 and actors.has(facts.get("eater_id")) and facts.eater_id!="human" and participants==[facts.eater_id] and facts.get("previous_state") in [LocalText.source("content.hunger.full"),LocalText.source("content.hunger.peckish"),LocalText.source("content.hunger.hungry"),LocalText.source("content.hunger.very_hungry")] and facts.get("meal_type") in ["barbecue","cooked","farm"] and facts.get("place_id") is String and (facts.place_id in world.barbecues or facts.place_id in world.farms.farms)
	if kind=="moon_viewing":
		return facts.size()==6 and _ids(participants,actors,2) and "human" in participants and facts.get("place_id")=="home.moon" and facts.get("site_id") in world.catalog.regions.home.layout.get("moon",{}).get("platform_sites",[]) and _count(facts.get("day"),1000000) and facts.day>=1 and facts.get("phase")=="night" and _count(facts.get("moon_phase"),7) and facts.moon_phase==posmod(int(facts.day)-1,8) and facts.get("weather") in ["sunny","cloudy","fog","rain"]
	if kind=="wish_completed":
		return facts.size()==7 and facts.get("resident_id") in actors and facts.resident_id!="human" and _sorted(participants)==_sorted(["human",facts.resident_id]) and facts.get("wish_id") is String and facts.wish_id.begins_with("wish-") and facts.wish_id.length()==29 and facts.get("template_id") is String and not world.wishes.template(facts.template_id).is_empty() and facts.get("title") is String and facts.title.length()>0 and facts.title.length()<=30 and facts.get("kind") in ["meal","fish","furniture","facility","homestead"] and facts.get("target_id") is String and facts.target_id.length()>0 and facts.target_id.length()<=128 and facts.get("proof_id") is String and facts.proof_id.length()>0 and facts.proof_id.length()<=128
	if kind=="relationship_stage":
		return facts.size()==4 and facts.get("resident_id") in actors and facts.resident_id!="human" and _sorted(participants)==_sorted(["human",facts.resident_id]) and _count(facts.get("stage_index"),4) and facts.stage_index>=1 and facts.get("stage_id")==world.relationships.config.stages[int(facts.stage_index)].id and facts.get("stage_name")==world.relationships.config.stages[int(facts.stage_index)].name
	if kind=="gift":
		var items: Array=["wood","mushroom"]+world.farms.crops.keys()
		for crop in world.farms.crops:items.append("seed."+crop)
		return facts.size()==4 and facts.get("giver_id") in actors and facts.get("receiver_id") in actors and facts.giver_id!=facts.receiver_id and _sorted(participants)==_sorted([facts.giver_id,facts.receiver_id]) and facts.get("item_id") in items and _count(facts.get("quantity"),world.work.CARRY_LIMIT) and facts.quantity>0
	if kind=="promise_result":
		return facts.size()==7 and facts.get("resident_id") in actors and facts.resident_id!="human" and _sorted(participants)==_sorted(["human",facts.resident_id]) and facts.get("action_type") in ["water","harvest","fish","cook","come_near"] and facts.get("target_id") is String and facts.target_id.length()>0 and facts.target_id.length()<=128 and _count(facts.get("day"),1000000) and facts.day>=1 and facts.get("phase") is String and facts.phase.length()>0 and facts.phase.length()<=32 and facts.get("outcome") in ["completed","failed","cancelled"] and facts.get("reason") is String and facts.reason.length()<=160
	if kind=="proposal_decision":
		return facts.size()==5 and facts.get("resident_id") in actors and facts.resident_id!="human" and _sorted(participants)==_sorted(["human",facts.resident_id]) and facts.get("text") is String and facts.text.length()>0 and facts.text.length()<=40 and facts.get("activity") in ["fish_together","cook_together","homestead_together","sit_together","watch_fishery"] and facts.get("target_id") is String and not facts.target_id.is_empty() and facts.target_id.length()<=128 and facts.get("decision") in ["accepted","declined"]
	return false
func record_event(kind: String,key: String,participants: Array,facts: Dictionary) -> bool:
	if kind not in KINDS or not engine_facts_valid(kind,facts,participants,world.actors):return false
	var identity:=_record_id(world.world_id,kind,key)
	if records.any(func(entry):return entry.id==identity):return false
	records.append({"id":identity,"world_id":world.world_id,"kind":kind,"occurred_at":maxf(world.forest.clock,Time.get_unix_time_from_system()),"region_id":world.actors[participants[0]].region_id,"participants":_sorted(participants),"facts":facts.duplicate(true),"text_version":1,"source":{"system":kind,"id":key}})
	if committed.is_valid():committed.call(records[-1])
	if records.size()>capacity:records.pop_front()
	world.revision+=1;return true

func meal_place_valid(facts:Dictionary)->bool:
	return facts.get("station_id") in world.barbecues and facts.get("place_id")==world.barbecues[facts.station_id].station.get("place_id","") and not str(facts.place_id).is_empty()

func fireside_facts_valid(facts:Dictionary,participants:Array,actors:Dictionary)->bool:
	if facts.size()!=8 or facts.get("version")!=2 or not facts.get("activity_id") is String or facts.activity_id.length()!=24 or not _ids(participants,actors) or not _ids(facts.get("attended"),actors):return false
	if facts.get("station_id") not in world.barbecues or facts.get("place_id")!=world.barbecues[facts.station_id].station.get("place_id","home"):return false
	if not _ids(facts.get("consumed_by"),actors) or _sorted(facts.consumed_by)!=_sorted(participants) or participants.any(func(id):return id not in facts.attended):return false
	if not facts.get("roles") is Dictionary or facts.roles.size()!=2 or facts.roles.keys().any(func(key):return key not in ["light","roast"]) or facts.roles.values().any(func(who):return not actors.has(who)) or not facts.get("foods") is Dictionary or _sorted(facts.foods.keys())!=_sorted(participants):return false
	for id in facts.foods:
		if not facts.foods[id] is Array or facts.foods[id].is_empty() or facts.foods[id].size()>256:return false
		for food in facts.foods[id]:
			if not food is Dictionary or food.size()!=5 or not food.get("first_time") is bool or not food.get("first_time_known") is bool or not food.get("name") is String or food.name.is_empty() or food.name.length()>32 or food.get("category") not in ["fish","mushroom","vegetable","fruit","dish"]:return false
			if not food.get("food_id") is String:return false
			if food.get("food_id")!="fish" and food.get("food_id") not in world.life.fireside.config.singles and food.food_id not in world.recipes.recipe_catalog and (not food.food_id is String or not food.food_id.begins_with("fish-")):return false
	return true

func forgotten(actor_id:String,entry:Dictionary)->bool:
	return notebook!=null and notebook.deleted.has((actor_id+"|"+str(entry.world_id)+"|"+str(entry.id)+"|facts").sha256_text())
