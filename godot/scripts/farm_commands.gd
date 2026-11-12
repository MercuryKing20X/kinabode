extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
## Local one-line farm commands for residents without a model. Pure parsing: it never
## moves anyone or uses stock. The host still confirms before FarmSystem.host_order.
const DATA_PATH := "res://content/companions/farm-commands.json"
const KEYS := ["version","plant_words","harvest_words","guarded_words","ignore_words","crops","farms","examples"]
const FILLER := ("system.farm_commands.chinese_command_filler_characters_kept_unchanged_for_parsing")
var data: Dictionary = {}
var lexicon:Dictionary={}
var syntax:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/companions/command-grammar.json"))
func grammar(key:String)->String:return str(syntax[key])
func command_words(action:String)->Array:return lexicon.get(action,[])

func _init(path: String = DATA_PATH) -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	data = raw if valid(raw) else {}
	for lang in ["zh","en"]:
		var words:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/companions/commands."+lang+".json"))
		if words is Dictionary:
			for action in words:
				if not lexicon.has(action):lexicon[action]=[]
				lexicon[action].append_array(words[action])

static func _words(value: Variant) -> bool:
	if not value is Array or value.is_empty() or value.size() > 32: return false
	for word in value:
		if not word is String or word.strip_edges().is_empty() or word.length() > 12: return false
	return true

static func _aliases(value: Variant) -> bool:
	if not value is Dictionary or value.is_empty() or value.size() > 16: return false
	for key in value:
		if not key is String or key.is_empty() or not _words(value[key]): return false
	return true

static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.size() != KEYS.size() or not value.has_all(KEYS) or value.version != 1: return false
	for key in ["plant_words","harvest_words","ignore_words","examples"]:
		if not _words(value[key]): return false
	if not value.guarded_words is Dictionary or value.guarded_words.size() != 2 or not _words(value.guarded_words.get("plant")) or not _words(value.guarded_words.get("harvest")): return false
	return _aliases(value.crops) and _aliases(value.farms)

static func _first(text: String, words: Array) -> int:
	var best := -1
	for word in words:
		var at := text.find(word)
		if at >= 0 and (best < 0 or at < best): best = at
	return best

static func _match(text: String, table: Dictionary) -> Dictionary:
	var best := {}
	for key in table:
		for word in table[key]:
			var at := text.find(word)
			if at >= 0 and (best.is_empty() or word.length() > best.word.length()): best = {"id":key,"word":word,"at":at}
	return best

func nearest_farm(world: RefCounted) -> String:
	var best := ""; var distance := INF
	var at: Vector2 = world.point(world.actors.human)
	for id in world.farms.farms:
		if not world.farms.allowed("human", id): continue
		var meeting: Array = world.farms.farms[id].meeting_at
		var d := at.distance_to(Vector2(meeting[0], meeting[1]))
		if d < distance: best = id; distance = d
	return best

## {} = not a farm command (keep the normal hint). ok=false carries a player-facing reason.
func parse(world: RefCounted, text: String) -> Dictionary:
	var cleaned := text.strip_edges()
	if data.is_empty() or cleaned.is_empty() or cleaned.length() > 40: return {}
	var probe := cleaned
	for word in data.ignore_words: probe = probe.replace(word, " ".repeat(word.length()))
	var crop := _match(probe, data.crops)
	var farm := _match(probe, data.farms)
	if not crop.is_empty() and not world.farms.crops.has(crop.id): crop = {}
	if not farm.is_empty() and not world.farms.farms.has(farm.id): farm = {}
	var mentioned := not crop.is_empty() or not farm.is_empty()
	var plant_at := _first(probe, data.plant_words)
	var harvest_at := _first(probe, data.harvest_words)
	var guarded_plant := _first(probe, data.guarded_words.plant)
	var guarded_harvest := _first(probe, data.guarded_words.harvest)
	var unknown_crop := false
	if plant_at < 0 and guarded_plant >= 0 and (mentioned or cleaned.length() <= 12):
		plant_at = guarded_plant; unknown_crop = not mentioned
	if harvest_at < 0 and guarded_harvest >= 0 and mentioned: harvest_at = guarded_harvest
	if plant_at < 0 and harvest_at < 0: return {}
	var intent := "plant" if harvest_at < 0 or (plant_at >= 0 and plant_at < harvest_at) else "ready"
	if intent == "plant" and crop.is_empty() and not unknown_crop:
		# LocalText.text("system.farm_commands.help_me_plant_bananas"): anything left after the verb that is not a farm name or filler is a crop we lack.
		var rest := probe.substr(plant_at)
		for word in data.plant_words + data.guarded_words.plant: rest = rest.replace(word, "")
		if not farm.is_empty(): rest = rest.replace(farm.word, "")
		for c in LocalText.source(FILLER): rest = rest.replace(c, "")
		unknown_crop = not rest.is_empty()
	var farm_id: String = farm.get("id", "")
	if farm_id.is_empty(): farm_id = nearest_farm(world)
	if farm_id.is_empty(): return {"ok":false,"error":"no_farm","message":LocalText.text("system.farm_commands.there_are_no_usable_fields_nearby_build_a_field")}
	var info: Dictionary = world.farms.farms[farm_id]
	var names: PackedStringArray = []
	for id in info.crop_ids: names.append(LocalText.content(str(world.farms.crops[id].name)))
	if intent == "ready": return {"ok":true,"intent":"ready","farm_id":farm_id,"crop_id":"","summary":LocalText.text("system.farm_commands.harvest_s") % LocalText.content(info.name)}
	if unknown_crop: return {"ok":false,"error":"crop_unknown","message":LocalText.text("system.farm_commands.s_can_grow_s") % [LocalText.content(info.name), "、".join(names)]}
	var crop_id: String = crop.get("id", "mixed")
	if crop_id != "mixed" and crop_id not in info.crop_ids:
		return {"ok":false,"error":"crop_unsuitable","message":LocalText.text("system.farm_commands.s_cannot_grow_s_suitable_crops_s") % [LocalText.content(info.name), LocalText.content(world.farms.crops[crop_id].name), "、".join(names)]}
	var what: String = LocalText.text("system.farm_commands.a_mix_of_suitable_crops") if crop_id == "mixed" else LocalText.content(str(world.farms.crops[crop_id].name))
	return {"ok":true,"intent":"plant","farm_id":farm_id,"crop_id":crop_id,"summary":LocalText.text("system.farm_commands.plant_s_with_s") % [LocalText.content(info.name), what]}

## Multi-recipient host text parser. Read-only; actor identity always comes from catalog IDs.
func closest_local(world:RefCounted)->String:
	var nearest:="";var distance:=INF
	for id in world.actors:
		if id=="human" or world.director.model_controlled(id) or world.actors[id].region_id!=world.actors.human.region_id:continue
		var d:float=world.point(world.actors[id]).distance_squared_to(world.point(world.actors.human))
		if d<distance:nearest=id;distance=d
	return nearest
func _contains_alias(probe:String,alias:String)->bool:
	if alias.is_empty():return false
	if alias.to_utf8_buffer().size()==alias.length() and alias.to_lower()!=alias.to_upper():
		var escaped:String=alias
		for character in ["\\",".","(",")","[","]","{","}","*","+","?","^","$","|"]:escaped=escaped.replace(character,"\\"+character)
		var expression:=RegEx.new();expression.compile("(?i)(?<![a-z0-9_])"+escaped+"(?![a-z0-9_])")
		return expression.search(probe)!=null
	return probe.contains(alias.to_lower())
func parse_command(world:RefCounted,text:String,fallback_ids:Array=[])->Dictionary:
	if world.memories.notebook!=null and fallback_ids.size()==1:text=world.memories.notebook.resolve(str(fallback_ids[0]),text)
	LocalText.ensure()
	if text.begins_with(LocalText.source("memory.teach_prefix")) or text.begins_with("When I say "):return {}
	var cleaned:String=text.strip_edges()
	if cleaned in [LocalText.source("content.overnight.text.ef1920c1bab412"),LocalText.source("content.overnight.text.dcb3c256839799")]:cleaned=LocalText.source("content.overnight.text.3e0da8855fa512")
	if cleaned.to_lower() in ["plant vegetables","go plant vegetables"]:cleaned="plant"
	var probe:String=cleaned.to_lower()
	if cleaned.is_empty() or cleaned.length()>240:return {}
	var chain:String=cleaned.trim_prefix(grammar("token_0")).replace(grammar("token_1"),grammar("token_2")).replace(grammar("token_3"),grammar("token_2")).replace(grammar("token_4"),"|").replace(grammar("token_5"),"|").replace(" then ","|")
	if chain.contains("|"):
		var parts:PackedStringArray=chain.split("|",false,1)
		if parts.size()!=2:return {"ok":false,"action":"","actor_ids":fallback_ids,"explicit_targets":false}
		var first:Dictionary=parse_command(world,parts[0].strip_edges().trim_suffix("，").trim_suffix(","),fallback_ids)
		if first.get("ok",false):
			var second:Dictionary=parse_command(world,parts[1].strip_edges(),first.actor_ids)
			if not second.get("ok",false):first.ok=false
			else:first.next_text=parts[1].strip_edges()
		return first
	var ids:Array=[];var removed:Array=[];var excluded:Array=[]
	for id in world.actors:
		if id=="human":continue
		var names:Array=[str(world.actors[id].name),LocalText.resident(world,id)]
		for name in names.duplicate():
			if LocalText.content_keys.has(name):
				var entry:Dictionary=LocalText.entries[LocalText.content_keys[name]];names.append(str(entry.zh));names.append(str(entry.en))
		for alias in names:
			if _contains_alias(probe,str(alias)):
				if probe.contains(grammar("token_6")+str(alias).to_lower()) or probe.contains("except "+str(alias).to_lower()):excluded.append(id)
				elif id not in ids:ids.append(id)
				removed.append(str(alias).to_lower())
	# “和你一起” includes the addressed resident, alongside explicitly named peers.
	if probe.contains(preload("res://scripts/localization.gd").source("content.health_20261107.26a0bf4bacc3")) or probe.contains("with you"):
		for addressed in fallback_ids:
			if addressed!="human" and world.actors.has(addressed) and addressed not in ids:ids.append(addressed)
	var all_people:bool=[grammar("token_7"),grammar("token_8"),grammar("token_9"),grammar("token_10"),grammar("token_11"),"everyone","everybody","all of you","allofyou","you all"].any(func(word):return probe.contains(word))
	var action:=""
	if command_words("query_state").any(func(word):return _contains_alias(probe,word)):action="query_state"
	elif command_words("unfollow").any(func(word):return _contains_alias(probe,word)):action="unfollow"
	elif command_words("stop").any(func(word):return _contains_alias(probe,word)):action="stop"
	elif command_words("follow").any(func(word):return _contains_alias(probe,word)):action="follow"
	elif command_words("barbecue").any(func(word):return _contains_alias(probe,word)):action="barbecue"
	elif command_words("forage").any(func(word):return _contains_alias(probe,word)):action="forage"
	elif command_words("gather").any(func(word):return _contains_alias(probe,word)):action="gather"
	elif command_words("ready").any(func(word):return _contains_alias(probe,word)):action="ready"
	elif command_words("forage").any(func(word):return _contains_alias(probe,word)):action="forage"
	elif command_words("water").any(func(word):return _contains_alias(probe,word)):action="water"
	elif command_words("fish").any(func(word):return _contains_alias(probe,word)) or probe.contains(preload("res://scripts/localization.gd").source("content.health_20261107.8fcf062e19c4")) or probe.contains(preload("res://scripts/localization.gd").source("content.health_20261107.e504672095f0")):action="fish"
	elif command_words("chop").any(func(word):return _contains_alias(probe,word)):action="chop"
	elif command_words("hand_over").any(func(word):return _contains_alias(probe,word)):action="hand_over"
	elif command_words("open_chess").any(func(word):return _contains_alias(probe,word)):action="open_chess"
	elif command_words("vacation").any(func(word):return _contains_alias(probe,word)):action="vacation"
	elif command_words("build_stage").any(func(word):return _contains_alias(probe,word)):action="build_stage"
	elif command_words("start_project").any(func(word):return _contains_alias(probe,word)):action="start_project"
	elif command_words("plant").any(func(word):return _contains_alias(probe,word)):action="plant"
	if action!="unfollow" and [grammar("token_12"),grammar("token_13"),grammar("token_14"),grammar("token_15"),grammar("token_16"),"don't","do not","never"].any(func(word):return probe.contains(word)):action=""
	if not action.is_empty() and (probe.contains(grammar("token_17")) or probe.contains(grammar("token_18"))) and ids.is_empty():all_people=true
	if ids.is_empty() and (action in ["unfollow","stop"] or probe in [LocalText.source("content.one_line.literal_15"),LocalText.source("content.command_alias.follow.1"),LocalText.source("content.one_line.literal_16"),LocalText.source("content.one_line.literal_17"),"follow me","come with me"]):all_people=true
	if all_people:ids=world.actors.keys().filter(func(id):return id!="human")
	elif ids.is_empty():
		ids=fallback_ids.filter(func(id):return id!="human" and world.actors.has(id))
		if ids.is_empty():
			var nearby:String=closest_local(world)
			if not nearby.is_empty():ids=[nearby]
	ids=ids.filter(func(id):return id not in excluded)
	var result:Dictionary={"ok":not action.is_empty(),"action":action,"actor_ids":ids,"explicit_targets":all_people or not removed.is_empty(),"source_text":cleaned,"farm_id":"","crop_id":"mixed","target":"human"}
	if action in ["plant","ready"]:
		var words:String=probe
		removed.sort_custom(func(a,b):return a.length()>b.length())
		for alias in removed:words=words.replace(alias,"")
		for word in [grammar("token_7"),grammar("token_8"),grammar("token_9"),grammar("token_10"),grammar("token_11"),"everyone","everybody","all of you","allofyou","you all",grammar("token_18"),grammar("token_17"),grammar("token_19"),grammar("token_20"),"please","and"]:words=words.replace(word,"")
		for filler in [LocalText.source("content.command_grammar.token_6"),LocalText.source("content.one_line.literal_18"),LocalText.source("content.one_line.literal_19"),LocalText.source("content.one_line.literal_20"),LocalText.source("content.one_line.literal_21"),LocalText.source("content.one_line.literal_22")]:words=words.replace(filler,"")
		var crop:Dictionary=_match(words,data.crops);var farm:Dictionary=_match(words,data.farms)
		for crop_id in world.farms.crops:
			if [str(crop_id),str(crop_id)+"s",{"potato":"potatoes","tomato":"tomatoes","blueberry":"blueberries","daisy":"daisies"}.get(crop_id,str(crop_id))].any(func(alias):return _contains_alias(words,alias)):crop={"id":crop_id,"word":crop_id}
		for farm_id in world.farms.farms:
			var farm_name:String=str(world.farms.farms[farm_id].name)
			if LocalText.content_keys.has(farm_name):
				var english:String=str(LocalText.entries[LocalText.content_keys[farm_name]].en)
				if _contains_alias(words,english):farm={"id":farm_id,"word":str(data.farms.get(farm_id,[farm_name])[0])}
		var canonical:String=words
		if not farm.is_empty():
			var without_farm:String=canonical.replace(str(farm.word),"").strip_edges()
			if without_farm in [grammar("token_21"),grammar("token_22"),grammar("token_23"),grammar("token_24"),grammar("token_25"),grammar("token_26")]:canonical=grammar("token_25")+str(farm.word)
		for verb in ["harvest","plant","sow"]:canonical=canonical.replace(verb,grammar("token_27") if action=="ready" else grammar("token_28"))
		if not crop.is_empty():canonical=(grammar("token_29") if action=="ready" else grammar("token_30")+str(data.crops[crop.id][0]))+(str(farm.word) if not farm.is_empty() else "")
		elif action=="ready":canonical=grammar("token_27")+(str(farm.word) if not farm.is_empty() else "")
		elif canonical.strip_edges() in [grammar("token_31"),grammar("token_32"),grammar("token_33"),grammar("token_34"),grammar("token_21"),grammar("token_22"),grammar("token_23"),grammar("token_24"),grammar("token_28"),grammar("token_25"),grammar("token_26"),grammar("token_35"),grammar("token_36")]:canonical=grammar("token_25")+(str(farm.word) if not farm.is_empty() else "")
		var parsed:Dictionary=parse(world,canonical.strip_edges())
		if parsed.is_empty():result.ok=false;return result
		if not parsed.get("ok",false):
			if parsed.get("error")=="no_farm" and (action=="ready" or not crop.is_empty() or canonical.begins_with(grammar("token_25"))):
				result.crop_id=str(crop.get("id","mixed")) if action=="plant" else "";return result
			result.merge(parsed,true);return result
		result.crop_id=parsed.crop_id;result.farm_id=str(farm.get("id",""));result.summary=parsed.summary
	if action=="water":
		var farm:Dictionary=_match(probe,data.farms)
		result.farm_id=str(farm.get("id",""))
	if action=="gather":
		if [grammar("token_37"),grammar("token_38"),"south island","their island"].any(func(word):return probe.contains(word)):result.target="south"
		elif [grammar("token_39"),grammar("token_40"),"cottage","house"].any(func(word):return probe.contains(word)):result.target="house"
		elif [grammar("token_41"),grammar("token_42"),"campfire","fire"].any(func(word):return probe.contains(word)):result.target="campfire"
	return result
