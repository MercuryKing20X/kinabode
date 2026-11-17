class_name IslandSaveStore
extends RefCounted
const Opening=preload("res://scripts/world_opening.gd")
const CarryRetention=preload("res://scripts/carry_retention.gd")
const MAX_SAVE_BYTES := 64 * 1024 * 1024

static func save_world(world: RefCounted, directory: String) -> bool:
	if world.source_manifest=="res://content/home-v3/world.json" and world.resort!=null:world.resort.ready()
	DirAccess.make_dir_recursive_absolute(directory)
	var data := {"schema_version": 7, "content_version": world.catalog.regions.home.get("content_version", 1), "world_id": world.world_id, "actors": world.actors, "objects": world.objects, "drops": world.drops, "projects": {"plans": world.projects.plans, "memories": world.projects.memories}, "leisure":world.leisure.saved(), "farming": world.farms.saved(), "shared_life": world.life.state(), "interior": {"serial": world.interior.serial, "furniture": world.interior.furniture, "memories": world.interior.memories}}
	if world.activities.persist_follow:data["following"]=world.activities.following.keys()
	data["outdoor_plots"]=preload("res://scripts/outdoor_building.gd").saved(world)
	data["island_ingredients"] = world.ingredients.saved()
	data["cat"] = world.cat.saved()
	data["their_island"]=world.their_island.saved()
	if world.home_island!=null and not world.home_island.legacy:data["home_island_visited"]=world.home_island.landed
	if world.home_island!=null and not world.home_island.legacy and world.catalog.regions.home.get("layout",{}).has("homelands"):data["home_map_version"]=2
	if world.resort!=null and world.resort.migrated:data["vacation_version"]=4
	if world.resort!=null and world.resort.has_meta("retired_south_projects"):data["retired_south_projects"]=world.resort.get_meta("retired_south_projects").duplicate(true)
	if world.get("flower_creation")!=null:data["flower_creation"]=world.flower_creation.saved()
	data["storage"] = world.storage.saved()
	for job in (world.flower_creation.jobs.values() if world.get("flower_creation")!=null else []):
		if job.get("offered",false):
			var rose:String=world.flower_creation.item(job.color)
			data.storage.items[rose]=int(data.storage.items.get(rose,0))+1
	data["jieqi"] = world.jieqi.saved()
	if Opening.v3(world):data["template_id"]="home-v3";data["opening_id"]=world.opening_id
	if world.standard.active():data["standard_opening"]=world.standard.saved()
	data["ecology_version"] = 1
	data["fishing"] = world.fishing.saved()
	data["gomoku"] = world.gomoku.saved()
	data["homestead"]=world.homestead.saved()
	data["journal"]=world.journal.saved()
	data["shared_memories"] = world.memories.saved()
	data["forest_clock"] = world.forest.clock
	data["day_cycle"]=world.days.saved()
	data["promises"]=world.promises.saved()
	data["relationships"]=world.relationships.saved()
	data["wishes"]=world.wishes.saved()
	data["weather"]=world.weather.saved()
	data["hunger"]=world.hunger.saved()
	if world.dark!=null and world.dark.enabled():data["dark_island"]=world.dark.saved()
	data["barbecue_tastes"]=world.barbecue_tastes.duplicate(true)
	if world.moon!=null and not world.moon.config.is_empty():data["moon_island"]={"last_viewing_day":world.moon.last_viewing_day}
	if world.barbecues.size()>1:
		data["extra_barbecues"]={}
		for id in world.barbecues:
			if id!="home.barbecue":data.extra_barbecues[id]=world.barbecues[id].state()
	var encoded := JSON.stringify(data)
	if encoded.to_utf8_buffer().size()>=MAX_SAVE_BYTES:return false
	var path := directory.path_join("island-v2.json")
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: return false
	file.store_string(encoded); file.flush(); file.close()
	return DirAccess.rename_absolute(path + ".tmp", path) == OK

static func restore_human_appearance(world: RefCounted, directory: String) -> Dictionary:
	if not world.actors.has("human") or directory.is_empty(): return {"ok": false, "error": "invalid_context"}
	# Include unsaved legitimate progress before backing up, and never change the
	# appearance unless both saving and copying have succeeded.
	if not save_world(world, directory): return {"ok": false, "error": "save_failed"}
	var path := directory.path_join("island-v2.json")
	var backup := path + ".before-appearance-" + str(Time.get_ticks_usec())
	if DirAccess.copy_absolute(path, backup) != OK: return {"ok": false, "error": "backup_failed"}
	world.actors.human.appearance_id = world.residents.appearance_for("human")
	world.actors.human["custom_appearance"] = false
	world.revision += 1
	return {"ok": true, "backup": backup}

static func load_world(world: RefCounted, directory: String) -> Dictionary:
	var path := directory.path_join("island-v2.json")
	if not FileAccess.file_exists(path): return {"ok": true, "loaded": false}
	var file := FileAccess.open(path, FileAccess.READ)
	var data: Variant = null
	if file != null and file.get_length() < MAX_SAVE_BYTES: data = JSON.parse_string(file.get_as_text())
	if file != null: file.close()
	if data is Dictionary:
		ignore_retired_food_fields(data)
		if not preload("res://scripts/storage_migration.gd").migrate(data,world):data=null
	if data is Dictionary and not preload("res://scripts/home_island_migration.gd").migrate(world,data):data=null
	if data is Dictionary and data.get("opening_id")=="standard":world.standard.install_geometry()
	if data is Dictionary and data.get("template_id","core")!=world.catalog.manifest.get("template_id","core"):
		var backup:String=path+".wrong-template-"+str(Time.get_ticks_usec())
		var copied:bool=DirAccess.copy_absolute(path,backup)==OK
		return {"ok":false,"error":"world_template_mismatch","backup":backup if copied else "","safe_to_save":false}
	if data is Dictionary and not preload("res://scripts/resort_revision_migration.gd").migrate(world,data):data=null
	if data is Dictionary and not preload("res://scripts/outdoor_building.gd").install(world,data):data=null
	if not data is Dictionary or not _valid(world, data):
		var backup := path + ".invalid-%s" % Time.get_ticks_usec()
		var copied := DirAccess.copy_absolute(path, backup) == OK
		return {"ok": false, "error": "invalid_save", "backup": backup if copied else "", "safe_to_save": copied}
	world.resort.migrated=bool(float(data.get("vacation_version",0))>=1)
	if data.has("retired_south_projects"):world.resort.set_meta("retired_south_projects",data.retired_south_projects.duplicate(true))
	world.storage.restore(data.get("storage", {"items": {}}))
	for id in data.actors:
		if id in ["npc.luca","npc.eli"]: continue
		if id in world.village.ids() and not world.actors.has(id): world.village.provision()
		if not world.actors.has(id):
			if world.residents.definitions.has(id):
				var definition: Dictionary=world.residents.definitions[id]
				world._add_actor(id,definition.name,definition.role,Vector2(definition.position[0],definition.position[1]))
			else:world._add_actor(id, str(data.actors[id].name), "companion", world.point(data.actors[id]))
		world.actors[id].erase("furniture_id");world.actors[id].erase("pocketed");world.actors[id].erase("retained_carry")
		for key in ["name", "region_id", "position", "carry", "facing", "furniture_id", "appearance_id", "name_version", "custom_name", "custom_appearance", "controller", "pocketed", "retained_carry"]:
			if data.actors[id].has(key): world.actors[id][key] = data.actors[id][key]
		CarryRetention.preserve_legacy(world.actors[id])
		world.actors[id].activity = "idle"
		if not data.actors[id].has("name_version"): world.actors[id].name_version=0
	_migrate_orange_default(world)
	world.residents.apply_names(world)
	world.opening_id=str(data.get("opening_id",""))
	world.world_id = data.world_id
	world.ingredients.restore(data.get("island_ingredients",{}))
	# Add only new catalog IDs; all existing progress stays authoritative.
	world.objects = world.catalog.objects.duplicate(true)
	for id in data.objects: world.objects[id] = data.objects[id].duplicate(true)
	world.drops = data.drops.duplicate(true)
	if world.moon!=null:world.moon.last_viewing_day=int(data.get("moon_island",{}).get("last_viewing_day",0))
	for id in data.get("extra_barbecues",{}):
		var barbecue:RefCounted=world.barbecues[id];var extra:Dictionary=data.extra_barbecues[id]
		var patch_positions:Dictionary={}
		for patch_id in barbecue.patches:patch_positions[patch_id]=barbecue.patches[patch_id].position.duplicate()
		barbecue.station=extra.station.duplicate(true);barbecue.patches=extra.patches.duplicate(true);barbecue.memories=[]
		for patch_id in barbecue.patches:barbecue.patches[patch_id].position=patch_positions[patch_id]
	if data.has("shared_life"):
		world.life.station = data.shared_life.station.duplicate(true)
		var patch_positions:Dictionary={}
		for patch_id in world.life.patches:patch_positions[patch_id]=world.life.patches[patch_id].position.duplicate()
		world.life.patches = data.shared_life.patches.duplicate(true)
		for patch_id in world.life.patches:world.life.patches[patch_id].position=patch_positions[patch_id]
		world.life.memories = data.shared_life.memories.duplicate(true)
	if data.has("interior"):
		world.interior.serial = int(data.interior.serial)
		world.interior.furniture = data.interior.furniture.duplicate(true)
		world.interior.memories = data.interior.memories.duplicate(true)
	world.director.interrupt_all(8)
	world._routes.clear(); world._forced_runs.clear(); world._walk_facings.clear();world.reset_motion(); world._grids.clear(); world._terrain_solids.clear(); world.work.jobs.clear(); world.work.claims.clear()
	if world.their_island!=null:world.their_island.clear_session()
	world.projects.restore(data.get("projects", {}))
	if data.has("leisure"): world.leisure.restore(data.leisure)
	if data.has("farming"): world.farms.restore(data.farming)
	if data.has("cat"):world.cat.restore(data.cat)
	world.shared_activity.restore(data.get("shared_activity", {}))
	world.forest.restore(float(data.get("forest_clock", 0)))
	world.fishing.restore(data.get("fishing",{}))
	world.gomoku.restore(data.get("gomoku",{}))
	world.jieqi.restore(data.get("jieqi",{}))
	world.homestead.restore(data.get("homestead",{}))
	world.journal.restore(data.get("journal",{}))
	world.days.restore(data.get("day_cycle",{}))
	world.memories.restore(data.get("shared_memories", {}))
	world.their_island.restore(data.get("their_island",{}))
	world.flower_creation.restore(data.get("flower_creation",{}))
	if world.home_island!=null:world.home_island.restore_visited(bool(data.get("home_island_visited",false)))
	world.session_generation+=1
	world.memories.sync()
	world.promises.restore(data.get("promises",{}));world.promises.reconcile_load()
	world.director.moods.reset()
	for brain in world.director.brains.values():brain.reset()
	world.relationships.restore(data.get("relationships",{}))
	world.wishes.restore(data.get("wishes",{}))
	world.weather.restore(data.get("weather",{}));world.schedules.reset();world.personality.reset()
	world.activities.following.clear();world.activities.explicit_selected.clear();world.activities.persist_follow=data.has("following")
	world.hunger.restore(data.get("hunger",{}))
	for id in data.get("following",[]):world.activities.following[id]=true
	if world.dark!=null:world.dark.restore(data.get("dark_island",{}))
	world.barbecue_tastes=data.get("barbecue_tastes",{"version":1,"known":false,"by_actor":{}}).duplicate(true)
	for barbecue in world.barbecues.values():barbecue.fireside.after_load()
	world.standard.restore(data.get("standard_opening",{}))
	world.standard.baseline_meals=[]
	world.standard.baseline_meals.append_array(world.memories.records.filter(func(e):return e.kind=="shared_barbecue" and e.facts.get("version")==2).map(func(e):return e.source.id))
	world.deposit_all("human")
	world.pocket_warned=false;world.auto_stow_idle()
	world.deliveries.pending.clear()
	for id in world.actors:
		if id!="human" and not CarryRetention.unprotected(world.actors[id]).is_empty() and world.homestead.plans.get(id,{}).get("receipt",{}).is_empty() and not world.actors[id].has("furniture_id"):world.deliveries.request(id,false)
	world.resort.ready()
	world.rescue_obstructed()
	world.revision += 1
	return {"ok": true, "loaded": true}

static func _quantity(value: Variant, maximum: int = 100000) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == floor(float(value)) and value >= 0 and value <= maximum

static func _wood(value: Variant, maximum: int = 100000) -> bool:
	return value is Dictionary and value.keys().all(func(key): return key in ["firefly.jar","wood", "mushroom", "turnip", "tomato", "pumpkin", "daisy", "blueberry", "apple", "seed.turnip", "seed.tomato", "seed.pumpkin", "seed.daisy", "seed.blueberry", "seed.apple"]) and value.values().all(func(amount): return _quantity(amount, maximum)) and value.values().reduce(func(total, n): return total + int(n), 0) <= maximum

static func _carry(world:RefCounted,value:Variant,id:String)->bool:
	if not value is Dictionary:return false
	return _wood(value,world.work.CARRY_LIMIT)

static func _valid(world: RefCounted, data: Dictionary) -> bool:
	if data.has("following"):
		if not data.following is Array or data.following.size()>world.residents.capacity:return false
		var seen_follow:Dictionary={}
		for id in data.following:
			if not id is String or id=="human" or not data.get("actors",{}).has(id) or seen_follow.has(id):return false
			seen_follow[id]=true
	if data.has("retired_south_projects") and not preload("res://scripts/resort_revision_migration.gd").valid_archive(data.retired_south_projects):return false
	if data.has("vacation_version") and (not _quantity(data.vacation_version,4) or data.vacation_version!=1 and data.vacation_version!=2 and data.vacation_version!=3 and data.vacation_version!=4):return false
	if data.has("their_island") and not world.their_island.valid_saved(data.their_island):return false
	if data.has("home_island_visited") and not data.home_island_visited is bool:return false
	if data.has("home_map_version") and (not (data.home_map_version is int or data.home_map_version is float) or not is_finite(data.home_map_version) or data.home_map_version!=2):return false
	if data.has("island_ingredients") and not world.ingredients.valid(data.island_ingredients):return false
	if data.has("cat") and not preload("res://scripts/cat_companion.gd").valid(data.cat):return false
	if data.has("flower_creation"):
		# Frozen pre-flower worlds still validate the optional field with the same strict validator.
		var flowers:RefCounted=world.get("flower_creation")
		if flowers==null:flowers=preload("res://scripts/flower_creation.gd").new(world)
		if not flowers.valid_saved(data.flower_creation,data.get("actors",{})):return false
	if data.has("storage") and not world.storage.valid_saved(data.storage): return false
	if data.has("jieqi") and not world.jieqi.valid_saved(data.jieqi,data.get("actors",{})):return false
	if data.has("barbecue_tastes") and not _valid_tastes(world,data.barbecue_tastes,data.get("actors",{})):return false
	if data.has("opening_id") and data.opening_id not in ["","showcase","standard"]:return false
	if data.has("standard_opening") and (data.get("opening_id")!="standard" or not world.standard.valid(data.standard_opening)):return false
	if data.get("interior",{}).get("furniture",{}).values().any(func(item):return item.get("preset_origin")=="standard") and data.get("opening_id")!="standard":return false
	if data.get("leisure",{}).get("sites",{}).keys().any(func(id):return id.begins_with("play.standard.")) and data.get("opening_id")!="standard":return false
	if data.has("ecology_version") and data.ecology_version != 1: return false
	if data.has("forest_clock") and (not world.catalog._number(data.forest_clock) or data.forest_clock < 0): return false
	if (data.get("schema_version") != 2 and data.get("schema_version") != 3 and data.get("schema_version") != 4 and data.get("schema_version") != 5 and data.get("schema_version") != 6 and data.get("schema_version") != 7) or not data.get("world_id") is String or not data.get("actors") is Dictionary or not data.get("objects") is Dictionary or not data.get("drops") is Dictionary: return false
	if not world.hunger.valid(data.get("hunger",{}),data.actors):return false
	if world.dark!=null and not world.dark.valid(data.get("dark_island",{}),data.actors):return false
	if not data.actors.has("human") or not data.actors.has("codex") or data.actors.size() > world.residents.capacity or data.objects.size() > world.objects.size(): return false
	var content_version: Variant = data.get("content_version", 1)
	if not _quantity(content_version, int(world.catalog.regions.home.get("content_version", 1))) or content_version < 1: return false
	for id in world.objects:
		if id.begins_with("homelands.house.") and not data.objects.has(id):continue
		if int(world.objects[id].get("introduced_in", 1)) <= int(content_version) and not data.objects.has(id): return false
	for id in data.actors:
		var generated_companion: bool = id.begins_with("companion-") and id.trim_prefix("companion-").is_valid_int() and id.trim_prefix("companion-").to_int() >= 2 and id.length() <= 64
		if id not in ["human", "codex"] and not generated_companion and id not in world.village.ids()+["npc.luca","npc.eli"] and not world.residents.definitions.has(id): return false
		var actor: Variant = data.actors[id]
		if not actor is Dictionary or not actor.get("name") is String or actor.name.length() > 48 or not actor.get("region_id") is String or not world.catalog._pair(actor.get("position")) or not _carry(world,actor.get("carry"),id): return false
		if actor.has("pocketed") and (not actor.pocketed is bool):return false
		if actor.has("retained_carry") and not CarryRetention.valid(actor.retained_carry,actor.carry):return false
		# Local residents may now own genuinely received gifts; normal carry validation still applies.
		if actor.has("controller") and actor.controller not in (["human"] if id=="human" else ["model","local"]):return false
		if actor.has("name_version") and not _quantity(actor.name_version,1):return false
		if actor.has("custom_name") and not actor.custom_name is bool:return false
		if actor.has("custom_appearance") and not actor.custom_appearance is bool:return false
		if actor.has("appearance_id") and (not actor.appearance_id is String or actor.appearance_id.length()>64):return false
		if actor.region_id == "home" and not world.terrain_surface("home",world.point(actor)): return false
		if data.get("schema_version") < 4 and (actor.region_id != "home" or not str(actor.get("furniture_id", "")).is_empty()): return false
	for id in data.objects:
		if not world.objects.has(id): return false
		var object: Variant = data.objects[id]
		if object is Dictionary and object.get("preset_origin")=="standard" and (data.get("opening_id")!="standard" or id!=world.standard.config.house.site_id):return false
		var base: Dictionary = world.objects[id]
		if not object is Dictionary or object.get("kind") != base.kind or object.get("region_id") != base.region_id or not world.catalog._pair(object.get("position")) or world.point(object).distance_to(world.point(base)) > .0001: return false
		if object.has("host_completed") and (base.kind!="construction_site" or not object.host_completed is bool or object.host_completed!=true or object.get("stage_index")!=5):return false
		if object.has("house_appearance") and (base.kind!="construction_site" or object.house_appearance not in ["classic","personal","personal_legacy"]):return false
		if base.kind == "tree" and (not world.forest.valid_tree(object, world.catalog._number) or not _quantity(object.get("health", 6), 6) or object.get("wood_yield") != base.wood_yield): return false
		if base.kind == "construction_site" and (not _quantity(object.get("stage_index", 0), 5) or not _quantity(object.get("invested", 0), 1000) or not _wood(object.get("delivered"), 200)): return false
		if object.has("preset_origin") and (not Opening.allowed_preset(world,object.preset_origin) or not Opening.house(world,id) or object.get("invested")!=0 or not object.get("delivered",{}).is_empty() or not object.get("contributions",{}).is_empty() or object.get("stage_index")!=5):return false
		if base.kind == "construction_site" and not world.projects.valid_contributions(object, data.actors): return false
		if base.kind == "construction_site" and object.has("blueprint"):
			var blueprint: Variant = object.blueprint
			if not blueprint is Dictionary or not world.Blueprint.valid_structure(blueprint.get("structure")): return false
			var quote: Dictionary = world.Blueprint.quote(blueprint.structure)
			if not blueprint.get("stages") is Array or blueprint.stages.size() != 5 or blueprint.get("wood") != quote.wood: return false
			for index in range(5):
				if blueprint.stages[index] != quote.stages[index]: return false
			var validator = load("res://scripts/character_library.gd").new()
			if not blueprint.get("artwork") is Dictionary or not validator.valid(blueprint.artwork): return false
			if blueprint.artwork.get("kind") != "building" or blueprint.artwork.structure != blueprint.structure: return false
	for id in data.drops:
		var drop: Variant = data.drops[id]
		if not drop is Dictionary or drop.get("id") != id or drop.get("region_id") not in (["home","dark"] if world.dark!=null and world.dark.enabled() else ["home"]) or not world.catalog._pair(drop.get("position")) or not _quantity(drop.get("wood"), 8): return false
	if data.has("moon_island") and (not data.moon_island is Dictionary or data.moon_island.keys()!=["last_viewing_day"] or not _quantity(data.moon_island.last_viewing_day,1000000)):return false
	if data.has("extra_barbecues"):
		if not data.extra_barbecues is Dictionary or data.extra_barbecues.size()>world.barbecues.size()-1:return false
		for id in data.extra_barbecues:
			if id=="home.barbecue" or not world.barbecues.has(id) or not _valid_life(world,data.extra_barbecues[id],data.actors,world.barbecues[id]) or not data.extra_barbecues[id].memories.is_empty():return false
	if data.has("shared_life") and not _valid_life(world, data.shared_life, data.actors): return false
	if data.get("schema_version") >= 4 and not _valid_interior(world, data): return false
	if (data.get("schema_version") >= 5 or data.has("projects")) and not world.projects.valid_saved(data.get("projects"), data): return false
	if (data.get("schema_version")>=7 or data.has("leisure")) and not world.leisure.valid_saved(data.get("leisure")):return false
	if (data.get("schema_version") >= 6 or data.has("farming")) and not world.farms.validated_saved(data.get("farming"),data.actors,data.get("leisure",{}).get("sites",{})):return false
	if data.has("fishing") and not world.fishing.valid_saved(data.fishing,data.actors):return false
	var consumed_fish:Dictionary={}
	var drying:Dictionary=data.get("island_ingredients",{}).get("drying",{})
	if not drying.is_empty():
		if data.get("fishing",{}).get("fish",{}).has(drying.fish_id):return false
		consumed_fish[drying.fish_id]=true
	var stations:Array=[data.get("shared_life",{}).get("station",{})]
	for value in data.get("extra_barbecues",{}).values():stations.append(value.get("station",{}))
	for station in stations:
		if station.get("fireside",{}).get("current",{}).get("food_id")==world.homestead.config.unlock_recipe.id and data.get("homestead",{}).get("site",{}).get("state")!="completed":return false
		var fish:Dictionary=station.get("fireside",{}).get("current",{}).get("fish",{})
		if fish.is_empty():continue
		if consumed_fish.has(fish.id) or data.get("fishing",{}).get("fish",{}).has(fish.id):return false
		consumed_fish[fish.id]=true
	if data.has("journal") and not world.journal.valid_saved(data.journal,data.actors):return false
	if data.has("day_cycle") and not world.days.valid_saved(data.day_cycle,data.actors,data.get("forest_clock")):return false
	if data.has("homestead") and not world.homestead.valid_saved(data.homestead,data):return false
	if data.has("gomoku") and (not data.get("leisure") is Dictionary or not data.leisure.get("sites") is Dictionary or not world.gomoku.valid_saved(data.gomoku,data.actors,data.leisure.sites)):return false
	if data.has("promises") and not world.promises.valid_saved(data.promises,data.actors,float(data.get("day_cycle",{}).get("origin",world.days.origin))):return false
	if data.has("relationships") and not world.relationships.valid_saved(data.relationships,data.actors):return false
	if data.has("wishes") and not world.wishes.valid_saved(data.wishes,data.actors):return false
	if data.has("weather") and not world.weather.valid_saved(data.weather):return false
	if data.has("shared_memories") and not world.memories.valid_saved(data.shared_memories,data.actors,data.world_id):return false
	return true

static func _valid_life(world: RefCounted, data: Variant, actors: Dictionary,barbecue:RefCounted=null) -> bool:
	if barbecue==null:barbecue=world.life
	if not data is Dictionary or not data.get("station") is Dictionary or not data.get("patches") is Dictionary or not data.get("memories") is Array: return false
	var station: Dictionary = data.station
	if barbecue!=world.life and (station.get("region_id")!=barbecue.station.region_id or station.get("place_id")!=barbecue.station.place_id):return false
	if station.get("id") != barbecue.station.id or not world.catalog._pair(station.get("position")) or station.position[0]!=barbecue.station.position[0] or station.position[1]!=barbecue.station.position[1] or station.get("state") not in ["cold", "cooking", "needs_turn", "ready", "eating", "embers"]: return false
	var batch: Variant = station.get("batch_size", 2)
	if not _quantity(batch, barbecue.activity_rules.seat_offsets.size()) or batch < 2: return false
	var portion_limit: int=160 if station.has("fireside") else int(batch)
	if station.has("fireside") and not barbecue.fireside.valid(station.fireside,actors,station):return false
	if not _wood(station.get("supplies"), int(batch) + 2) or station.supplies.keys().any(func(key):return key not in ["wood", "mushroom"]) or int(station.supplies.get("wood", 0)) > 2 or int(station.supplies.get("mushroom", 0)) > int(batch) or not _quantity(station.get("portions"), portion_limit) or not _quantity(station.get("fuel_used")) or not _quantity(station.get("meals_eaten")): return false
	if not world.catalog._number(station.get("timer")) or station.timer < 0 or station.timer > 20 or not station.get("turned") is bool: return false
	if not station.get("artwork") is Dictionary: return false
	if not station.artwork.is_empty():
		var validator = load("res://scripts/character_library.gd").new()
		if not validator.valid(station.artwork) or station.artwork.get("kind") != "facility": return false
	if data.patches.size() != barbecue.patches.size() or data.memories.size() > 32: return false
	for event in data.memories:
		if event is Dictionary and event.has("meal_type") and world.memories.meal_facts(event,actors).is_empty():return false
	for id in data.patches:
		if not barbecue.patches.has(id): return false
		var patch: Variant = data.patches[id]
		if not patch is Dictionary or not _patch_position(world,id,patch.get("position"),barbecue.patches[id].position) or not _quantity(patch.get("amount"), 4) or not world.catalog._number(patch.get("ready_at")): return false
	return true

static func _patch_position(world:RefCounted,id:String,value:Variant,current:Array)->bool:
	if world.catalog._pair(value) and Vector2(value[0],value[1])==Vector2(current[0],current[1]):return true
	if not world.locations.v3() or not world.catalog._pair(value):return false
	if id=="home.mushrooms.1" and Vector2(value[0],value[1])==Vector2(50,100):return true
	var previous:Dictionary={"moon.mushrooms.1":[-40,86],"home.mushrooms.1":[50,52]}
	return previous.has(id) and Vector2(value[0],value[1])==Vector2(previous[id][0],previous[id][1])

static func _valid_interior(world: RefCounted, data: Dictionary) -> bool:
	var inside: Variant = data.get("interior")
	if not inside is Dictionary or not inside.get("furniture") is Dictionary or not inside.get("memories") is Array or not _quantity(inside.get("serial"), 10000000): return false
	if inside.furniture.size() > 64 or inside.memories.size() > 32: return false
	var probe: RefCounted = world.get_script().new(world.source_manifest)
	probe.objects = data.objects.duplicate(true)
	probe.actors = data.actors.duplicate(true)
	probe.interior.furniture = inside.furniture.duplicate(true)
	var rooms: Dictionary = probe.interior.rooms()
	if data.get("cat",{}).has("position"):
		var saved_cat:Dictionary=data.cat
		if not probe.walkable(saved_cat.region_id,Vector2(saved_cat.position[0],saved_cat.position[1])):return false
	var validator = load("res://scripts/character_library.gd").new()
	var held := {}
	for id in inside.furniture:
		var item: Variant = inside.furniture[id]
		if not id is String or not id.begins_with("furniture.") or not id.trim_prefix("furniture.").is_valid_int(): return false
		if int(id.trim_prefix("furniture.")) < 1 or int(id.trim_prefix("furniture.")) > int(inside.serial): return false
		if not item is Dictionary or item.get("id") != id or not item.get("recipe_id") is String or not probe.interior.RECIPES.has(item.recipe_id): return false
		var recipe: Dictionary = probe.interior.RECIPES[item.recipe_id]
		if (item.get("invested") != recipe.wood and not Opening.furniture(world,item)) or not item.get("name") is String or item.name.length() > 48: return false
		if item.get("kind") != "furniture" or item.get("capacity") != 0: return false
		if not _wood(item.get("items"), int(item.capacity)) or item.get("facing") not in ["up", "down"]: return false
		if not world.catalog._pair(item.get("position")) or not rooms.has(item.get("region_id", "")) or not item.get("holder_id") is String: return false
		if not item.get("artwork") is Dictionary: return false
		if not item.artwork.is_empty() and (not validator.valid(item.artwork) or item.artwork.get("id") != "furniture-" + item.recipe_id or item.artwork.get("kind") != "facility" or item.artwork.get("facility_type") != "furniture"): return false
		if not item.holder_id.is_empty():
			if not data.actors.has(item.holder_id) or held.has(item.holder_id) or data.actors[item.holder_id].get("furniture_id") != id or (not data.actors[item.holder_id].carry.is_empty() and not (data.actors[item.holder_id].get("pocketed",false) and data.actors[item.holder_id].carry.keys().all(func(k):return world.pocket_item(str(k))))) or not _wood(item.items, 0): return false
			held[item.holder_id] = id
		elif not probe.interior.placement(item.region_id, item, id, false): return false
	for id in data.actors:
		var actor: Dictionary = data.actors[id]
		if actor.get("furniture_id", "") != held.get(id, ""): return false
		if actor.region_id == "homelands" and world.catalog.regions.has("homelands"):
			if not world.walkable("homelands",world.point(actor)):return false
		elif actor.region_id == "dark" and world.dark!=null and world.dark.enabled():
			if not world.walkable("dark",world.point(actor)):return false
		elif actor.region_id != "home":
			if not rooms.has(actor.region_id) or not probe.interior.walkable(actor.region_id, probe.point(actor)): return false
	for memory in inside.memories:
		if not memory is Dictionary or memory.get("kind") != "sat_together" or not rooms.has(memory.get("room_id", "")) or not memory.get("actors") is Array or memory.actors.size() != 2 or memory.actors[0] == memory.actors[1] or not world.catalog._number(memory.get("at")): return false
		for id in memory.actors:
			if not data.actors.has(id): return false
	return true

# Explicit host reset only. Character works and settings are in separate files.
static func archive_progress(directory: String) -> bool:
	var path := directory.path_join("island-v2.json")
	if not FileAccess.file_exists(path): return true
	return DirAccess.rename_absolute(path, path + ".before-farms-%s" % Time.get_ticks_usec()) == OK

# Explicit fresh-world identity transfer only; no positions, inventory, jobs or history.
static func read_identity(directory:String)->Dictionary:
	var path:String=directory.path_join("island-v2.json")
	if not FileAccess.file_exists(path):return {}
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>=MAX_SAVE_BYTES:return {}
	var data:Variant=JSON.parse_string(file.get_as_text());file.close()
	if not data is Dictionary or not data.get("actors") is Dictionary:return {}
	var result:Dictionary={}
	for id in data.actors:
		var actor:Variant=data.actors[id]
		if not id is String or not actor is Dictionary or not actor.get("name") is String or actor.name.length()>48:continue
		var entry:Dictionary={"name":actor.name,"name_version":1}
		var role:String=str(actor.get("role","human" if id=="human" else "companion"))
		if role in (["human"] if id=="human" else ["companion","npc"]):entry["role"]=role
		for key in ["appearance_id","custom_appearance","custom_name","controller"]:
			if not actor.has(key):continue
			if key=="appearance_id" and actor[key] is String and actor[key].length()<=64:entry[key]=actor[key]
			if key in ["custom_appearance","custom_name"] and actor[key] is bool:entry[key]=actor[key]
			if key=="controller" and actor[key] in (["human"] if id=="human" else ["local","model"]):entry[key]=actor[key]
		result[id]=entry
	return result
static func apply_identity(world:RefCounted,identity:Dictionary)->void:
	for id in identity:
		if not world.actors.has(id) and not world.add_companion(id,str(identity[id].name),str(identity[id].get("role","companion"))):continue
		for key in identity[id]:world.actors[id][key]=identity[id][key]
	_migrate_orange_default(world)
	world.residents.apply_names(world)

static func _valid_tastes(world:RefCounted,value:Variant,actors:Dictionary)->bool:
	if not value is Dictionary or value.keys().any(func(k):return k not in ["version","known","by_actor","cooked"]) or value.get("version")!=1 or not value.get("known") is bool or not value.get("by_actor") is Dictionary or value.by_actor.size()>actors.size():return false
	if value.has("cooked"):
		if not value.cooked is Array or value.cooked.size()>world.recipes.recipe_catalog.size():return false
		var seen_cooked:Array=[]
		for recipe_id in value.cooked:
			if not recipe_id is String or not world.recipes.recipe_catalog.has(recipe_id) or recipe_id in seen_cooked:return false
			seen_cooked.append(recipe_id)
	var ids:Array=world.life.fireside.config.singles.keys()+["fish"]+world.recipes.recipe_catalog.keys()
	for species in ["noodle","eel","kite","cutlass"]:ids.append("fish:"+species)
	for id in value.by_actor:
		if not actors.has(id) or not value.by_actor[id] is Array or value.by_actor[id].size()>ids.size():return false
		var seen:Array=[]
		for food in value.by_actor[id]:
			if food not in ids or food in seen:return false
			seen.append(food)
	return true

static func ignore_retired_food_fields(data:Dictionary)->void:
	# Only the explicitly retired optional food workflow is ignored. Raw stock is authoritative.
	data.erase("cooking");data.erase("shared_activity")
	if data.get("promises") is Dictionary and data.promises.get("entries") is Array:data.promises.entries=data.promises.entries.filter(func(e):return not e is Dictionary or e.get("action_type")!="cook")
	for actor in data.get("actors",{}).values():
		if not actor is Dictionary or not actor.get("carry") is Dictionary:continue
		for item in actor.carry.keys():
			if str(item).begins_with("meal:"):actor.carry.erase(item)
	var stations:Array=[data.get("shared_life",{}).get("station",{})]
	for extra in data.get("extra_barbecues",{}).values():stations.append(extra.get("station",{}))
	for station in stations:
		station.erase("cooking_batch_id")
		if not station.get("fireside",{}) is Dictionary or station.get("fireside",{}).get("version")!=4:station.erase("fireside")
		if not station.has("fireside"):
			station.state="cold";station.portions=0;station.supplies={};station.timer=0;station.turned=false;station.artwork={}
	for fish_id in data.get("fishing",{}).get("fish",{}).keys():
		if data.fishing.fish[fish_id].get("location")=="cooking":data.fishing.fish.erase(fish_id)

# Only an untouched bundled default follows a new bundled default.
static func _migrate_orange_default(world:RefCounted)->void:
	if not world.actors.has("npc.mira"):return
	var orange:Dictionary=world.actors["npc.mira"]
	if orange.get("appearance_id","")=="orange-haired-girl" and not orange.get("custom_appearance",false):orange.appearance_id="orange-sunflower-girl"
