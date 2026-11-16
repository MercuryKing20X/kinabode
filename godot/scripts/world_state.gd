class_name IslandWorld
extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
const CarryRetention=preload("res://scripts/carry_retention.gd")

const Catalog = preload("res://scripts/world_catalog.gd")
const Life = preload("res://scripts/shared_life.gd")
const Blueprint = preload("res://scripts/blueprint_rules.gd")
const Layout = preload("res://scripts/home_layout.gd")
const Interior = preload("res://scripts/interior_system.gd")
const Projects = preload("res://scripts/construction_projects.gd")
const Gathering = preload("res://scripts/wood_gathering.gd")
const Farms = preload("res://scripts/farm_system.gd")
const Work = preload("res://scripts/work_system.gd")
const SPEED := 150.0 / 32.0
const CARRY_SPEED := 125.0 / 32.0
const RUN_SPEED := 260.0 / 32.0
const RUN_DISTANCE := 12.0
var lively:RefCounted=preload("res://scripts/lively_companions.gd").new(self)
var ingredients:RefCounted=preload("res://scripts/island_ingredients.gd").new(self)
var cat:RefCounted=preload("res://scripts/cat_companion.gd").new(self)
var residents := preload("res://scripts/resident_catalog.gd").new()
var intelligence:RefCounted
var hunger:RefCounted
var activities: RefCounted
var their_island:RefCounted
var resort:RefCounted
var home_island:RefCounted
var dark:RefCounted
var moon:RefCounted
var shared_activity: RefCounted
var fishing: RefCounted
var gomoku: RefCounted
var cooperation: RefCounted
var relationships: RefCounted
var scene_speech:RefCounted
var weather: RefCounted
var personality: RefCounted
var schedules: RefCounted
var wishes: RefCounted
var promises: RefCounted
var proposals: RefCounted
var homestead: RefCounted
var recipes: RefCounted
var journal: RefCounted
var days: RefCounted
var memories: RefCounted
var leisure: RefCounted
var catalog := Catalog.new()
var deliveries: RefCounted
var jieqi: RefCounted
var storage := preload("res://scripts/system_storage.gd").new()
var actors: Dictionary = {}
var objects: Dictionary = {}
var drops: Dictionary = {}
var projects: RefCounted
var gathering: RefCounted
var farms: RefCounted
var forest: RefCounted
var flower_creation: RefCounted
var flower_gifts: RefCounted
var work: RefCounted
var barbecues:Dictionary={}
var life: RefCounted
var interior: RefCounted
var library: RefCounted
var director: RefCounted
var local_companion: RefCounted
var village: RefCounted
var revision := 1
var world_id := Crypto.new().generate_random_bytes(16).hex_encode()
var _grids: Dictionary = {}
var _terrain_solids: Dictionary = {}
var _land_polygons: Dictionary = {}
var _routes: Dictionary = {}
var _forced_runs: Dictionary = {}
var _walk_facings:Dictionary={}
var _motion_states:Dictionary={}
var barbecue_tastes:Dictionary={"version":1,"known":true,"by_actor":{}}
var error := ""
var locations:RefCounted
var opening_id:=""
var standard:RefCounted
var session_generation:=0
var source_manifest:="res://content/world.json"

func _init(manifest_path:String="res://content/world.json") -> void:
	source_manifest=manifest_path
	if not residents.error.is_empty():error=residents.error;return
	if not catalog.load_world(manifest_path):
		error = catalog.error
		return
	preload("res://scripts/resort_system.gd").install(catalog)
	if catalog.manifest.spawn.has("anchor"):
		catalog.manifest.spawn["position"]=map_anchor(str(catalog.manifest.spawn.anchor))
	locations=preload("res://scripts/world_content.gd").new(self)
	for region in catalog.regions: _land_polygons[region] = catalog.polygon(catalog.regions[region])
	objects = catalog.objects.duplicate(true)
	for region in catalog.regions.values():storage.add(region.get("initial_storage",{}))
	intelligence=preload("res://scripts/intelligence_system.gd").new(self)
	if not error.is_empty():return
	work = Work.new(self)
	projects = Projects.new(self)
	gathering = Gathering.new(self)
	life = Life.new(self)
	barbecues[life.station.id]=life
	for configuration in catalog.regions.home.get("layout",{}).get("barbecue_points",[]):
		var extra:RefCounted=Life.new(self,configuration);barbecues[extra.station.id]=extra
	interior = Interior.new(self)
	farms = Farms.new(self)
	var spawn: Dictionary = catalog.manifest.get("spawn", {})
	if not catalog.regions.has(spawn.get("region_id", "")) or not catalog._pair(spawn.get("position")):
		error = LocalText.text("system.world_state.invalid_spawn_point")
		return
	var point := Vector2(spawn.position[0], spawn.position[1])
	if not catalog.walkable(spawn.region_id, point) or not catalog.walkable(spawn.region_id, point + Layout.points([locations.section("spawn_companion_offset")])[0]):
		error = LocalText.text("system.world_state.the_spawn_point_is_blocked")
		return
	_add_actor("human", LocalText.source("system.world_state.you"), "human", point)
	_add_actor("codex", LocalText.source("system.world_state.youqi"), "companion", point + Layout.points([locations.section("spawn_companion_offset")])[0])
	director = preload("res://scripts/resident_director.gd").new(self)
	local_companion = director.routines.codex
	village = preload("res://scripts/village_life.gd").new(self)
	activities = preload("res://scripts/resident_activity.gd").new(self)
	leisure = preload("res://scripts/leisure_system.gd").new(self)
	forest = preload("res://scripts/forest_system.gd").new(self)
	flower_gifts = preload("res://scripts/flower_gifts.gd").new(self)
	shared_activity = preload("res://scripts/shared_activity.gd").new(self)
	memories = preload("res://scripts/shared_memories.gd").new(self)
	fishing = preload("res://scripts/fishing_system.gd").new(self)
	gomoku = preload("res://scripts/gomoku_system.gd").new(self)
	recipes = preload("res://scripts/barbecue_recipes.gd").new(self)
	journal = preload("res://scripts/journal_system.gd").new(self)
	days = preload("res://scripts/day_cycle.gd").new(self)
	homestead = preload("res://scripts/homestead_system.gd").new(self)
	proposals = preload("res://scripts/proposal_system.gd").new(self)
	promises = preload("res://scripts/promise_system.gd").new(self)
	cooperation = preload("res://scripts/cooperation_system.gd").new(self)
	relationships=preload("res://scripts/relationship_system.gd").new(self)
	wishes=preload("res://scripts/wish_system.gd").new(self)
	weather=preload("res://scripts/weather_system.gd").new(self)
	schedules=preload("res://scripts/schedule_system.gd").new(self)
	moon=preload("res://scripts/moon_island.gd").new(self)
	personality=preload("res://scripts/personality_system.gd").new(self)
	hunger=preload("res://scripts/hunger_system.gd").new(self)
	standard=preload("res://scripts/standard_opening.gd").new(self)
	dark=preload("res://scripts/dark_island.gd").new(self)
	home_island=preload("res://scripts/home_island.gd").new(self)
	their_island=preload("res://scripts/their_island.gd").new(self)
	deliveries=preload("res://scripts/storage_delivery.gd").new(self)
	jieqi=preload("res://scripts/jieqi_system.gd").new(self)
	jieqi.completed.connect(_jieqi_completed)
	resort=preload("res://scripts/resort_system.gd").new(self)
	flower_creation=preload("res://scripts/flower_creation.gd").new(self)

func _add_actor(id: String, display_name: String, role: String, position: Vector2) -> void:
	actors[id] = {"id": id, "name": residents.name_for(id,display_name), "role": role, "region_id": catalog.manifest.spawn.region_id, "position": [position.x, position.y], "activity": "idle", "carry": {}, "retained_carry":{}, "facing": "down", "appearance_id": residents.appearance_for(id), "name_version":1, "controller":residents.controller_for(id,role)}
	if director!=null:director.register(id)

# Host-only; not exposed through game actions or model adapters.
func assign_appearance(id: String, artwork_id: String, allow_human: bool = false, confirmed: bool = false) -> bool:
	if not actors.has(id) or library == null or not library.artworks.has(artwork_id): return false
	if library.artworks[artwork_id].get("kind", "character") != "character": return false
	if "human_only" in library.artworks[artwork_id].get("tags",[]) and id!="human":return false
	if actors[id].get("role", "") == "human" and not (allow_human and confirmed): return false
	var previous_appearance:String=str(actors[id].appearance_id)
	actors[id].appearance_id = artwork_id
	if id=="human" and previous_appearance!=artwork_id:preload("res://scripts/brain_interactions.gd").host_event(self,"host_appearance","appearance:"+str(revision))
	actors[id]["custom_appearance"] = true
	revision += 1
	return true

# Local host provisioning only. Not exposed as an AI tool.
func add_companion(id: String, display_name: String,role:String="companion",appearance_id:String="") -> bool:
	if role not in ["companion","npc"] or id.is_empty() or actors.has(id) or actors.size() >= residents.capacity: return false
	if not appearance_id.is_empty() and (library==null or not library.artworks.has(appearance_id) or library.artworks[appearance_id].get("kind","character")!="character"):return false
	var spawn: Array = catalog.manifest.spawn.position
	var origin := Vector2(spawn[0], spawn[1])
	for radius in range(1, 17):
		for y in range(-radius, radius+1):
			for x in range(-radius, radius+1):
				if maxi(absi(x), absi(y)) != radius: continue
				var point := origin + Vector2(x,y)
				if not walkable(catalog.manifest.spawn.region_id, point): continue
				if actors.values().any(func(actor): return actor.region_id == catalog.manifest.spawn.region_id and self.point(actor).distance_to(point) < 1.0): continue
				_add_actor(id, display_name, role, point)
				if not appearance_id.is_empty():actors[id].appearance_id=appearance_id;actors[id]["custom_appearance"]=true
				revision += 1
				return true
	return false

func observe(actor_id: String, query: Dictionary = {}) -> Dictionary:
	if not actors.has(actor_id): return _error("unknown_resident")
	for key in query:
		if key not in ["region_id", "object_id", "offset", "limit", "revision"]: return _error("invalid_query")
	var offset: Variant = query.get("offset", 0)
	var limit: Variant = query.get("limit", 24)
	if not _integer(offset) or not _integer(limit) or offset < 0 or limit < 1 or limit > 100: return _error("invalid_pagination")
	if (int(offset) > 0 and not query.has("revision")) or (query.has("revision") and query.revision != revision): return _error("stale_snapshot")
	var region_id: String = str(query.get("region_id", actors[actor_id].region_id))
	if region_info(region_id).is_empty(): return _error("unknown_region")
	var summaries: Array = []
	for region in catalog.regions.values() + interior.rooms().values():
		summaries.append({"id": region.id, "name": region.name, "origin": region.origin, "size": region.size})
	var result := {"ok": true, "protocol_version": 1, "world_id": world_id, "template_id": catalog.manifest.get("template_id",catalog.manifest.id), "snapshot_revision": revision, "observed_at": Time.get_datetime_string_from_system(true), "self_actor_id": actor_id, "self": _resident(actor_id), "residents": [], "world_bounds": catalog.manifest.bounds, "regions": summaries, "region": {"id": region_id, "zones": region_info(region_id).zones}, "capabilities": {"read": true, "local_actions": ["move", "stop", "build_house", "pause_project", "resume_project", "cancel_project", "deliver_wood", "gather_wood", "chop", "store", "collect", "build", "forage", "select_blueprint", "enter", "exit", "furnish", "place_furniture", "pickup_furniture", "rotate_furniture", "sit", "take"], "external_actions": ["move", "stop", "build_house", "pause_project", "resume_project", "cancel_project", "deliver_wood", "gather_wood", "chop", "store", "collect", "build", "forage", "select_blueprint", "enter", "exit", "furnish", "place_furniture", "pickup_furniture", "rotate_furniture", "sit", "take"], "model_chat": true, "construction": true, "farming": true}, "coordinate_system": "independent room-local tile coordinates; enter/exit through house door" if region_id.begins_with("room.") else "region-local tile units; world position = region origin + local position"}
	result["storage"] = storage.saved()
	result["flower_creation"]=flower_creation.summary(actor_id)
	result["gathering"] = activities.snapshot()
	result["shared_activity"] = shared_activity.snapshot()
	result["memories"] = memories.query(actor_id,{"limit":memories.snapshot_limit})
	result["leisure"] = leisure.snapshot()
	result.capabilities.local_actions.append_array(["greet","come_near","dance","watch","build_facility","use_facility"])
	result.capabilities.external_actions.append_array(["greet","come_near","dance","watch","build_facility","use_facility"])
	result["actions"]=read_actions(actor_id)
	result["fishing"] = fishing.snapshot(actor_id)
	result["gomoku"] = gomoku.snapshot(actor_id)
	result["homestead"]=homestead.summary(actor_id)
	result.capabilities.local_actions.append_array(homestead.ACTIONS)
	result.capabilities.external_actions.append_array(homestead.ACTIONS)
	result["journal"]=journal.summary(actor_id)
	result["day"]=days.summary(actor_id)
	result["intelligence"]=intelligence.summary(actor_id)
	result.capabilities.local_actions.append_array(flower_creation.ACTIONS)
	result.capabilities.external_actions.append_array(flower_creation.ACTIONS)
	result.capabilities.local_actions.append("journal_read")
	result.capabilities.external_actions.append("journal_read")
	result.capabilities.local_actions.append_array(gomoku.ACTIONS)
	result.capabilities.external_actions.append_array(gomoku.ACTIONS)
	result.capabilities.local_actions.append("gesture")
	result.capabilities.external_actions.append("gesture")
	result.capabilities.local_actions.append_array(fishing.ACTIONS)
	result.capabilities.external_actions.append_array(fishing.ACTIONS)
	result["farming"] = farms.state(actor_id)
	result.capabilities.local_actions.append_array(Farms.ACTIONS)
	result.capabilities.external_actions.append_array(Farms.ACTIONS)
	result.capabilities.local_actions=result.capabilities.local_actions.filter(func(action):return residents.supports(actors[actor_id],action))
	result.capabilities.external_actions=result.capabilities.external_actions.filter(func(action):return action!="assign_farm" and residents.supports(actors[actor_id],action))
	result.capabilities.model_chat=director.model_controlled(actor_id)
	result["projects"] = []
	for resident_id in projects.plans: result.projects.append(projects.state(resident_id))
	result["house_memories"] = projects.memories.duplicate(true)
	result["promises"]=promises.own(actor_id)
	result.self["cooperative_delivery"]=cooperation.active(actor_id)
	result["construction"] = []
	for object in objects.values():
		if object.kind == "construction_site" and object.region_id == region_id: result.construction.append(construction_state(object.id))
	result["interior"] = interior.state(region_id)
	result["room"] = interior.rooms().get(region_id, {}).duplicate(true)
	result["barbecues"]=barbecue_summaries()
	result["shared_life"] = life.state()
	result.shared_life.station.erase("artwork")
	result.shared_life["seats"] = life.seats()
	for seat in result.shared_life.seats: seat["occupant_id"] = work.claims.get(seat.id, "")
	result.region["landmarks"] = region_info(region_id).get("layout", {}).get("landmarks", []).duplicate(true)
	result.region["water_obstacles"] = region_info(region_id).get("layout", {}).get("ponds", []).duplicate(true)
	result["jobs"] = {}
	for id in work.jobs: result.jobs[id] = job_summary(work.jobs[id])
	result["drops"] = drops.values().duplicate(true)
	result["events"] = work.events.duplicate(true)
	for id in actors: result.residents.append(_resident(id))
	if query.has("object_id"):
		var id := str(query.object_id)
		if object_by_id(id).is_empty(): return _error("unknown_object")
		if object_by_id(id).region_id != region_id: return _error("object_region_mismatch")
		result["objects"] = [object_by_id(id)]
		result["page"] = {"total": 1, "complete": true, "next_offset": null}
	else:
		var entries: Array = (objects.values().filter(func(item): return item.kind != "farm_plot") + farms.plots.values() + farms.containers.values() + interior.furniture.values().filter(func(item): return interior.placed(item))).filter(func(object): return object.region_id == region_id)
		result["objects"] = entries.slice(int(offset), int(offset) + int(limit))
		var complete: bool = offset + limit >= entries.size()
		result["page"] = {"total": entries.size(), "complete": complete, "next_offset": null if complete else int(offset) + int(limit)}
	result = result.duplicate(true)
	for object in result.get("objects", []):
		if object.kind == "tree": object["regrowth"] = forest.describe(object)
		if object.has("blueprint"): object.blueprint.erase("artwork")
		object.erase("artwork")
		if object.kind == "construction_site" and int(object.get("stage_index", 0)) == 5: object["room_id"] = interior.room_for(object.id)
	if library != null:
		result["blueprints"] = []
		for id in library.artworks:
			var art: Dictionary = library.artworks[id]
			if art.get("kind")!="building":continue
			result.blueprints.append({"id": id, "revision": art.revision, "structure": art.structure.duplicate(true), "quote": Blueprint.quote(art.structure)})
	return result

func _resident(id: String) -> Dictionary:
	var actor: Dictionary = actors[id].duplicate(true)
	actor["carry_limit"] = work.CARRY_LIMIT
	if hunger!=null:actor["hunger"]=hunger.summary(id) if hunger.has_method("summary") else {}
	actor["job"] = job_summary(work.jobs.get(id, {}))
	actor["project"] = projects.state(id)
	actor["homestead_plan"] = homestead.plans.get(id,{}).duplicate(true)
	actor["farm_order"] = farms.orders.get(id, {}).duplicate(true)
	if interior.furniture.has(actor.get("furniture_id", "")):
		actor["carried_furniture"] = interior.furniture[actor.furniture_id].duplicate(true)
		actor.carried_furniture.erase("artwork")
	if director.routines.has(id):
		actor["control"]=director.state(id);actor["local_life"]=director.routines[id].state()
	actor["zone_id"] = catalog.zone_at(actor.region_id, Vector2(actor.position[0], actor.position[1])) if catalog.regions.has(actor.region_id) else actor.region_id + ".living"
	return actor

func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))

func read_actions(actor_id: String, query: Dictionary={}) -> Dictionary:
	if not query.is_empty():return _error("invalid_action_query")
	return preload("res://scripts/game_actions.gd").describe(self,actor_id)

func read_map(actor_id: String, query: Dictionary = {}) -> Dictionary:
	return preload("res://scripts/map_catalog.gd").new(self).read(actor_id,query)

func read_memories(actor_id: String, query: Dictionary = {}) -> Dictionary:
	return memories.query(actor_id,query)

func autonomy_context(actor_id: String,events: Array=[],recent_dialogue: Array=[]) -> Dictionary:
	return preload("res://scripts/autonomy_context.gd").build(self,actor_id,events,recent_dialogue)

var host_issuing:Dictionary={}
# Synchronous host-scoped text/reserved-autonomy authorization. Never persisted.
func host_text_command(actor_id:String,args:Dictionary)->Dictionary:
	if actor_id=="human" or not actors.has(actor_id) or args.get("intent") not in ["gather_wood","forage"]:return _error("invalid_command")
	host_issuing[actor_id]=true
	var result:Dictionary=command(actor_id,args)
	host_issuing.erase(actor_id)
	return result

func command(actor_id: String, args: Dictionary) -> Dictionary:
	if flower_creation!=null:
		if args.get("intent")=="stop":flower_creation.cancel(actor_id)
		elif args.get("intent") in flower_creation.ACTIONS:
			var ready:Dictionary=flower_creation.preflight(actor_id)
			if not ready.ok:return ready
		elif args.get("intent")!="query_state" and not str(args.get("intent","")).ends_with("_read"):flower_creation.cancel(actor_id)
	if director!=null and director.brains.has(actor_id):return director.brains[actor_id].command(args)
	return _command_body(actor_id,args)

func _command_body(actor_id: String, args: Dictionary) -> Dictionary:
	if ingredients!=null and ingredients.resident_pending.has(actor_id) and str(args.get("intent",""))!="query_state" and not str(args.get("intent","")).ends_with("_read"):ingredients.resident_pending.erase(actor_id)
	if actor_id=="human" and dark!=null:dark.cancel()
	if not actors.has(actor_id): return _error("unknown_resident")
	if flower_creation!=null and args.get("intent") in flower_creation.ACTIONS:return flower_creation.execute(actor_id,args)
	if resort!=null and resort.enabled() and args.get("intent") in resort.WORK and ((actors[actor_id].region_id=="home" and resort.contains(point(actors[actor_id]))) or (objects.has(str(args.get("target_id",""))) and resort.retired(objects[str(args.target_id)]))):return {"ok":false,"error":"vacation_only","message":resort.line()}
	if str(args.get("intent","")) in ["follow","unfollow","hand_over","query_state","gather_at"]:
		return model_social_command(actor_id,args)
	var farm_issue:Dictionary=farms.host_grants.get(actor_id,{}) if farms!=null else {}
	var explicit_farm_order:bool=str(args.get("intent",""))=="manage_farm" and farm_issue.get("issuing",false) and str(farm_issue.get("farm_id",""))==str(args.get("farm_id",""))
	if not residents.supports(actors[actor_id],str(args.get("intent",""))) and not explicit_farm_order and not (host_issuing.has(actor_id) and args.get("intent") in ["gather_wood","forage"]): return _error("unsupported_capability")
	var intent: String = str(args.get("intent", ""))
	if intent=="move" and activities.explicit_selected.has(actor_id) and not host_issuing.has(actor_id) and not activities.suspended_follow.has(actor_id) and not activities.commanded(actor_id):return _error("following_active")
	if intent in ["cook","cook_read","eat","turn_food","cleanup","farm_meal"]:return work.fail("retired_action",LocalText.text("system.world_state.at_the_fire_choose_barbecue_invite_companions_then"))
	if not director.issuing(actor_id) and not intent.ends_with("_read") and intent not in ["island_propose","propose","promise","promise_cancel","give"]:
		for barbecue in barbecues.values():barbecue.fireside.command_received(actor_id,intent)

	if hunger!=null and hunger.rank(actor_id)>=2 and not work.jobs.has(actor_id) and not projects.active(actor_id) and not farms.active(actor_id) and not homestead.active(actor_id) and intent in ["chop","gather_wood","forage","plant","water","harvest","build","build_house","build_facility","deliver_wood","homestead_start"]:
		return work.fail("hungry",LocalText.text("system.world_state.you_are_hungry_have_something_to_eat_before"))
	if intent in ["store","take","collect","pickup_furniture","rotate_furniture","place_furniture"]:
		var target:Dictionary=object_by_id(str(args.get("target_id","")))
		var owner:String=storage_owner(target)
		if not owner.is_empty() and owner!=actor_id:return work.fail("private_storage",LocalText.text("system.world_state.these_items_belong_to_a_companion_their_owner"))
	if intent=="furnish":
		var owner:String=storage_owner({"region_id":actors[actor_id].region_id})
		if not owner.is_empty() and owner!=actor_id:return work.fail("private_home",LocalText.text("system.world_state.only_the_homeowner_may_furnish_their_home"))

	if gomoku!=null and gomoku.ai_active(actor_id) and intent not in ["gomoku_read","gomoku_move","gomoku_join","gomoku_leave","gomoku_resign","stop"]:return work.fail("chess_match_restricted",LocalText.text("system.world_state.a_match_is_running_pause_it_first"))
	if intent=="give":return work.give(actor_id,args)
	if intent=="island_propose":return their_island.propose(actor_id,args)
	if intent=="propose":return proposals.create(actor_id,args)
	if intent in ["promise","promise_cancel"]:return promises.command(actor_id,args)
	if intent=="journal_read":
		var query:=args.duplicate();query.erase("intent");return journal.query(actor_id,query)
	if intent in homestead.ACTIONS:
		if intent!="homestead_read" and (activities.members.has(actor_id) or shared_activity.holds(actor_id)):return work.fail("activity_active",LocalText.text("system.world_state.end_the_gathering_or_shared_activity_before_starting"))
		if intent!="homestead_read" and not director.issuing(actor_id):director.command_received(actor_id,intent)
		return homestead.command(actor_id,args)
	if homestead.active(actor_id) and intent!="stop":return work.fail("homestead_active",LocalText.text("system.world_state.you_already_have_a_homestead_task_stop_or"))
	if intent not in ["stop","gomoku_read"]:homestead.unrelated_command(actor_id)
	if intent=="gomoku_read":return gomoku.command(actor_id,args)
	if gomoku.active(actor_id) and intent not in gomoku.ACTIONS+["stop"]:return work.fail("chess_active",LocalText.text("system.world_state.pause_or_leave_the_chess_table_before_doing"))
	if not fishing.held(actor_id).is_empty() and intent not in ["move","stop","stock_fish","release_fish","enter","exit","greet","come_near","watch"]:return work.fail("holding_fish",LocalText.text("system.world_state.you_are_holding_a_fish_place_it_in"))
	if intent == "stop" and args.size() != 1: return _error("invalid_command")
	if hunger!=null and hunger.has_method("on_command"):hunger.on_command(actor_id,intent)
	if shared_activity.holds(actor_id) and shared_activity.issuing != actor_id:
		if intent == "stop" or (actor_id == "human" and intent != "move" and not (intent == "exit" and shared_activity.session.phase == "arriving")): shared_activity.pause(LocalText.text("system.world_state.the_previous_activity_is_paused_prepared_materials_are"))
		elif actor_id != "human": return work.fail("activity_active", LocalText.text("system.world_state.you_are_at_a_barbecue_the_host_must"))
	if activities.members.has(actor_id) and intent != "stop": return work.fail("assembly_active",LocalText.text("system.world_state.a_gathering_is_in_progress_the_host_must"))
	if not director.issuing(actor_id): director.command_received(actor_id,intent)
	if intent in gomoku.ACTIONS:return gomoku.command(actor_id,args)
	if intent == "stop":
		if args.size() != 1: return _error("invalid_command")
		activities.dismiss(actor_id)
		director.command_received(actor_id, intent)
		farms.pause(actor_id)
		if projects.active(actor_id): projects.pause(actor_id, LocalText.text("system.world_state.paused_materials_and_progress_are_kept"))
		work.stop(actor_id)
		return {"ok": true, "status": "completed"}
	if intent in ["greet","come_near","dance","watch"]:
		director.command_received(actor_id,intent)
		return activities.start(actor_id,args)
	if intent in ["build_facility","use_facility"]: return leisure.command(actor_id,args)
	if intent=="gesture":return preload("res://scripts/game_actions.gd").gesture(self,actor_id,args)
	if intent in fishing.ACTIONS:
		if projects.active(actor_id) or farms.active(actor_id):return work.fail("plan_active",LocalText.text("system.world_state.pause_your_current_plan_before_fishing"))
		return fishing.command(actor_id,args)
	if intent in Farms.ACTIONS:
		if projects.active(actor_id): return _error("project_active")
		return farms.command(actor_id, args)
	if farms.active(actor_id) and not (intent == "move" and director.issuing(actor_id) and farms.orders[actor_id].status == "waiting"): return work.fail("farm_order_active", LocalText.text("system.world_state.pause_the_farm_order_before_starting_other_work"))
	if intent in ["build_house", "pause_project", "resume_project", "cancel_project"]: return projects.command(actor_id, args)
	if projects.active(actor_id): return work.fail("project_active", LocalText.text("system.world_state.a_house_plan_is_active_pause_it_before"))
	if intent in ["enter", "exit", "furnish", "place_furniture", "pickup_furniture", "rotate_furniture", "sit"]:
		director.command_received(actor_id, intent)
		return interior.start(actor_id, args)
	if not str(actors[actor_id].get("furniture_id", "")).is_empty() and intent != "move": return work.fail("hands_full", LocalText.text("system.world_state.put_down_the_furniture_first"))
	if intent=="gather":
		if args.size()!=2 or not args.get("target_id") is String:return _error("invalid_command")
		if ingredients.sources().any(func(item):return item.id==args.target_id):return ingredients.begin_resident(actor_id,args.target_id)
		return command(actor_id,{"intent":"forage","target_id":args.target_id})
	if intent == "gather_wood": return gathering.start(actor_id, args)
	if intent == "select_blueprint":
		for key in args:
			if key not in ["intent", "target_id", "blueprint_id"]: return _error("invalid_command")
		return select_blueprint(str(args.get("target_id", "")), str(args.get("blueprint_id", "")))
	if intent in ["forage"] or (intent == "store" and actors[actor_id].carry.keys().any(func(key): return key != "wood")):
		for key in args:
			if key not in ["intent", "target_id"]: return _error("invalid_command")
		var barbecue:RefCounted=life_for_target(str(args.get("target_id","")))
		if intent != "store" and actors[actor_id].region_id != barbecue.station.region_id: return _error("different_region")
		director.command_received(actor_id, intent)
		var result:Dictionary=barbecue.start(actor_id,intent,str(args.get("target_id","")))
		if result.ok and work.jobs.has(actor_id):work.jobs[actor_id]["barbecue_id"]=barbecue.station.id
		return result
	if intent in ["chop", "store", "take", "collect", "build", "deliver_wood"]:
		for key in args:
			if key not in ["intent", "target_id"]: return _error("invalid_command")
		director.command_received(actor_id, intent)
		if intent == "deliver_wood": return work.deliver(actor_id, str(args.get("target_id", "")))
		if intent == "collect": return work.collect(actor_id, str(args.get("target_id", "")))
		return work.start(actor_id, intent, str(args.get("target_id", "")))
	if intent != "move": return _error("unsupported_action")
	if work.jobs.has(actor_id): return _error("busy")
	for key in args:
		if key not in ["intent", "region_id", "x", "y"]: return _error("invalid_command")
	if not args.has("x") or not args.has("y") or not catalog._number(args.x) or not catalog._number(args.y): return _error("invalid_position")
	var region_id: String = str(args.get("region_id", actors[actor_id].region_id))
	if region_id != actors[actor_id].region_id: return _error("travel_not_implemented")
	var destination := Vector2(float(args.x), float(args.y))
	if not walkable(region_id, destination): return _error("not_walkable")
	director.command_received(actor_id, intent)
	if not route_to(actor_id, destination): return _error("unreachable")
	return {"ok": true, "status": "accepted", "actor_id": actor_id}

func nearest_barbecue(actor_id:String="human",radius:float=INF)->RefCounted:
	if not actors.has(actor_id):return null
	var actor:Dictionary=actors[actor_id];var chosen:RefCounted=null;var distance:float=radius
	for candidate in barbecues.values():
		if candidate.station.region_id!=actor.region_id:continue
		var gap:float=point(actor).distance_to(point(candidate.station))
		if gap<=distance:chosen=candidate;distance=gap
	return chosen
func nearby_camp_seats(actor_id:String,radius:float=8)->Array:
	if not actors.has(actor_id):return []
	var actor:Dictionary=actors[actor_id];var result:Array=[]
	# Radius is actor-to-seat, as in the original rest rule, not actor-to-pit.
	for camp in barbecues.values():
		if camp.station.region_id!=actor.region_id or not standard.ready(camp.station.id):continue
		for seat in camp.seats():
			if point(actor).distance_to(point(seat))<=radius:result.append(seat)
	return result

func point(value: Dictionary) -> Vector2:
	return Vector2(value.position[0], value.position[1])

func nearest_walkable(region_id:String,position:Vector2)->Vector2:
	if walkable(region_id,position):return position
	var region:Dictionary=region_info(region_id)
	if region.is_empty():return Vector2.INF
	var origin:=Vector2i(position.floor())
	if catalog.regions.has(region_id):
		var start:=Vector2i(catalog.local_origin(region));var size:=Vector2i(region.size[0],region.size[1])
		origin=Vector2i(clampi(origin.x,start.x,start.x+size.x-1),clampi(origin.y,start.y,start.y+size.y-1))
	var best:=Vector2.INF;var best_distance:=INF
	for radius in range(0,257):
		var ring:Array[Vector2i]=[]
		for x in range(-radius,radius+1):
			ring.append(Vector2i(x,-radius))
			if radius>0:ring.append(Vector2i(x,radius))
		for y in range(-radius+1,radius):
			ring.append(Vector2i(-radius,y));ring.append(Vector2i(radius,y))
		for cell in ring:
			var candidate:=Vector2(origin+cell)+Vector2(.5,.5)
			var distance:=position.distance_squared_to(candidate)
			if distance>=best_distance or not walkable(region_id,candidate):continue
			best=candidate;best_distance=distance
		if best.is_finite() and radius>sqrt(best_distance)+1:return best
	return best

func rescue_actor(id:String)->bool:
	if not actors.has(id):return false
	var actor:Dictionary=actors[id];var original:Vector2=point(actor)
	if walkable(actor.region_id,original):return false
	var destination:=nearest_walkable(actor.region_id,original)
	if not destination.is_finite():return false
	actor.position=[destination.x,destination.y];_routes.erase(id);_forced_runs.erase(id);_walk_facings.erase(id)
	actor.activity="idle";revision+=1
	return true

func rescue_obstructed()->void:
	for id in actors:
		if not actors[id].has("furniture_id"):rescue_actor(id)
	if cat!=null and cat.discovered and cat.carrier.is_empty() and not walkable(cat.region,cat.position):
		var destination:=nearest_walkable(cat.region,cat.position)
		if destination.is_finite():cat.position=destination;cat.route.clear()
	for drop in drops.values():
		var original:Vector2=point(drop)
		if walkable(drop.region_id,original):continue
		var destination:=nearest_walkable(drop.region_id,original)
		if destination.is_finite():drop.position=[destination.x,destination.y]

func walkable(region_id: String, position: Vector2) -> bool:
	if region_id.begins_with("room."): return interior.rooms().has(region_id) and interior.walkable(region_id, position)
	if not _terrain_walkable(region_id,position) or (leisure!=null and leisure.blocked(region_id,position)) or (homestead!=null and homestead.blocks(region_id,position)): return false
	for object in objects.values():
		if object.region_id != region_id: continue
		if (object.kind == "tree" and object.status == "mature") and position.distance_to(point(object)) < 0.85: return false
		if object.kind=="construction_site" and not Rect2(point(object)-site_size(object)/2,site_size(object)).grow(4).has_point(position):continue
		if object.kind == "construction_site" and int(object.get("stage_index", 0)) == 5:
			for fence in Layout.yard_fences(point(object), site_size(object) / 2):
				if position.distance_to(Geometry2D.get_closest_point_to_segment(position, fence[0], fence[1])) < .3: return false
		if object.kind == "construction_site" and int(object.get("stage_index", 0)) > 0:
			var footprint := site_size(object)
			if Rect2(point(object) - footprint / 2, footprint).has_point(position): return false
	return true

func terrain_surface(region_id: String, position: Vector2) -> bool:
	if not catalog.regions.has(region_id): return false
	var on_surface:bool=catalog.on_land(catalog.regions[region_id],position)
	if not on_surface and region_id=="home":on_surface=catalog.on_dock(catalog.regions.home,position)
	return on_surface

# Immutable map-pack colliders. Each World owns its cache; new/load worlds rebuild it.
# Dynamic farms, construction, recreation and furniture remain independently checked.
var _layout_collision_source:Dictionary={}
var _layout_collision:Dictionary={}
# Call when mutating static map-pack layout in place (e.g. a future map editor).
# Ordinary construction/farm invalidation does not change these authored colliders.
func invalidate_layout_collision()->void:
	_layout_collision_source={};_layout_collision.clear()
func _layout_blocked_fast(layout:Dictionary,p:Vector2)->bool:
	if not is_same(_layout_collision_source,layout):
		_layout_collision_source=layout
		_layout_collision={"fences":[],"props":[],"cliffs":[],"ponds":[]}
		for f in layout.garden.fences:
			var a:=Vector2(f[0][0],f[0][1]);var b:=Vector2(f[1][0],f[1][1])
			_layout_collision.fences.append([a,b,Rect2(a,Vector2.ZERO).expand(b).grow(.38)])
		for prop in layout.get("solid_props",[]):
			var a:Array=layout.anchors[prop.anchor]
			_layout_collision.props.append(Rect2(Vector2(a[0]+prop.offset[0],a[1]+prop.offset[1]),Vector2(prop.size[0],prop.size[1])))
		for cliff in layout.get("cliffs",[]):
			_layout_collision.cliffs.append([Layout.points(cliff.polygon),Rect2(Vector2(cliff.stairs[0][0],cliff.stairs[0][1]),Vector2(cliff.stairs[1][0]-cliff.stairs[0][0],cliff.stairs[1][1]-cliff.stairs[0][1]))])
		for pond in layout.get("ponds",[]):
			var crossing:=Rect2()
			if pond.has("crossing_anchor"):
				var a:Array=layout.anchors[pond.crossing_anchor];var span:=Vector2(pond.crossing_size[0],pond.crossing_size[1])
				crossing=Rect2(Vector2(a[0],a[1])-span/2,span)
			_layout_collision.ponds.append([Vector2(pond.center[0],pond.center[1]),Vector2(pond.radius[0],pond.radius[1]),Layout.pond_shape(pond),crossing])
	for f in _layout_collision.fences:
		if f[2].has_point(p) and p.distance_to(Geometry2D.get_closest_point_to_segment(p,f[0],f[1]))<.38:return true
	for r in _layout_collision.props:
		if r.has_point(p):return true
	for c in _layout_collision.cliffs:
		if Geometry2D.is_point_in_polygon(p,c[0]) and not c[1].has_point(p):return true
	for pond in _layout_collision.ponds:
		if pond[3].has_point(p):continue
		var local:Vector2=(p-pond[0])/pond[1]
		if local.length_squared()<1.25 and Geometry2D.is_point_in_polygon(p,pond[2]):return true
	return false

func _farm_blocked_fast(p:Vector2)->bool:
	# Same FarmSystem predicates, with the pure broadphase before readiness.
	# No cached farm readiness: construction/load changes are visible immediately.
	for farm in farms.farms.values():
		if not farms.bounds(farm).grow(1.3).has_point(p):continue
		if not farms.ready(farm.id):continue
		for fence in farms.fences(farm):
			if p.distance_to(Geometry2D.get_closest_point_to_segment(p,fence[0],fence[1]))<.55:return true
	return false

func _terrain_walkable(region_id:String,position:Vector2)->bool:
	if not terrain_surface(region_id,position):return false
	if region_id=="dark" and dark!=null:
		for pond in dark.config.ponds:
			if Geometry2D.is_point_in_polygon(position,PackedVector2Array(pond.map(func(v):return Vector2(v[0],v[1])))):return false
	if region_id == "home" and (_layout_blocked_fast(catalog.regions.home.layout, position) or _farm_blocked_fast(position)): return false

	return true

func approach_route(actor_id: String, target: Dictionary) -> Array[Vector2]:
	if target.get("region_id", actors[actor_id].region_id) != actors[actor_id].region_id: return []
	var offsets := [Vector2(0, 1.6), Vector2(-1.6, 0), Vector2(1.6, 0), Vector2(0, -1.6)]
	if target.get("kind") == "seat": offsets = [Vector2.ZERO]
	if target.get("kind") == "construction_site":
		var size := site_size(target) / 2 + Vector2.ONE * 1.5
		offsets = [Vector2(0, size.y), Vector2(size.x, 0), Vector2(-size.x, 0)]
	for offset in offsets:
		var destination: Vector2 = point(target) + offset
		var route := find_route(actor_id, destination)
		if not route.is_empty(): return route
	return []

func can_approach(actor_id: String, target: Dictionary) -> bool:
	return not approach_route(actor_id, target).is_empty()

func approach(actor_id: String, target: Dictionary) -> bool:
	return _apply_route(actor_id, approach_route(actor_id, target))

func route_to(actor_id: String, destination: Vector2) -> bool:
	return _apply_route(actor_id, find_route(actor_id, destination))

func find_route(actor_id: String, destination: Vector2) -> Array[Vector2]:
	var region_id: String = actors[actor_id].region_id
	if not walkable(region_id, destination): return []
	rescue_actor(actor_id)
	# Every segment and local repair requires a walkable start; avoid searching
	# the whole grid repeatedly when a loaded actor is inside an obstacle.
	if not walkable(region_id,point(actors[actor_id])):return []
	if segment_clear(region_id,point(actors[actor_id]),destination):return [destination]
	if region_id=="home" and home_island!=null:
		var road:Array[Vector2]=home_island.road_route(point(actors[actor_id]),destination)
		if not road.is_empty():return road
	var region: Dictionary = region_info(region_id)
	if not _grids.has(region_id):
		var grid := AStarGrid2D.new()
		grid.region = Rect2i(Vector2i(catalog.local_origin(region)),Vector2i(region.size[0],region.size[1]))
		grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		grid.update()
		if region_id.begins_with("room."):
			for y in range(grid.region.position.y,grid.region.end.y):
				for x in range(grid.region.position.x,grid.region.end.x): grid.set_point_solid(Vector2i(x,y),not walkable(region_id,Vector2(x+.5,y+.5)))
		else:
			if not _terrain_solids.has(region_id):
				var free:Array[Vector2i]=[]
				if region_id=="home" and get_script().resource_path=="res://scripts/world_state.gd":
					_raster_home_terrain(grid,region)
					for y in range(grid.region.position.y,grid.region.end.y):
						for x in range(grid.region.position.x,grid.region.end.x):
							if not grid.is_point_solid(Vector2i(x,y)):free.append(Vector2i(x,y))
				else:
					for y in range(grid.region.position.y,grid.region.end.y):
						for x in range(grid.region.position.x,grid.region.end.x):
							if _terrain_walkable(region_id,Vector2(x+.5,y+.5)):free.append(Vector2i(x,y))
				_terrain_solids[region_id]={"free":free}
			grid.fill_solid_region(grid.region,true)
			for cell in _terrain_solids[region_id].free:grid.set_point_solid(cell,false)
			for site in leisure.sites.values():
				if not site.complete:continue
				var config: Dictionary=leisure.art(site).recreation
				for y in range(int(site.position[1]-config.depth),int(site.position[1]+config.depth)+1):
					for x in range(int(site.position[0]-config.width),int(site.position[0]+config.width)+1):
						if grid.region.has_point(Vector2i(x,y)) and leisure.blocked(region_id,Vector2(x+.5,y+.5)):grid.set_point_solid(Vector2i(x,y),true)
			if homestead!=null and homestead.site.state!="unstarted" and region_id==homestead.config.site.region_id:
				var rect: Rect2=homestead.area()
				for y in range(int(floor(rect.position.y)),int(ceil(rect.end.y))):
					for x in range(int(floor(rect.position.x)),int(ceil(rect.end.x))):
						if grid.region.has_point(Vector2i(x,y)):grid.set_point_solid(Vector2i(x,y),true)
			# Only re-evaluate cells near mutable obstacles after chopping/building.
			for object in objects.values():
				if object.region_id != region_id: continue
				var extent := Vector2(1.5,1.5)
				if object.kind == "construction_site" and int(object.get("stage_index",0))>0: extent=site_size(object)/2+Vector2(2.5,4.5)
				elif not (object.kind == "tree" and object.status=="mature"): continue
				var rect := Rect2i((point(object)-extent).floor(),(extent*2).ceil()+Vector2.ONE)
				for y in range(maxi(grid.region.position.y,rect.position.y),mini(grid.region.end.y,rect.end.y)):
					for x in range(maxi(grid.region.position.x,rect.position.x),mini(grid.region.end.x,rect.end.x)):
						var p:=Vector2(x+.5,y+.5)
						# Terrain/leisure/homestead are already marked above. Rasterize
						# this object only instead of rescanning every object per cell.
						var blocked:bool=false
						if object.kind=="tree":blocked=p.distance_to(point(object))<.85
						else:
							var footprint:Vector2=site_size(object)
							blocked=Rect2(point(object)-footprint/2,footprint).has_point(p)
							if not blocked and int(object.get("stage_index",0))==5:
								for fence in Layout.yard_fences(point(object),footprint/2):
									if p.distance_to(Geometry2D.get_closest_point_to_segment(p,fence[0],fence[1]))<.3:blocked=true;break
						if blocked:grid.set_point_solid(Vector2i(x,y),true)
		_grids[region_id] = grid
	var grid: AStarGrid2D = _grids[region_id]
	var current := point(actors[actor_id])
	var points := grid.get_id_path(Vector2i(current.floor()), Vector2i(destination.floor()))
	if points.is_empty():
		# A real coast/furniture-edge endpoint can be walkable while its coarse
		# cell centre is solid. Connect it to bounded, validated grid centres;
		# never clear a solid cell or create a second movement authority.
		var starts:Array[Vector2i]=grid_connections(region_id,current,grid)
		var finishes:Array[Vector2i]=grid_connections(region_id,destination,grid)
		for from_cell in starts:
			for to_cell in finishes:
				var attached:=grid.get_id_path(from_cell,to_cell)
				if attached.is_empty():continue
				var raw:Array[Vector2]=[]
				for cell in attached:raw.append(Vector2(cell)+Vector2(.5,.5))
				raw.append(destination)
				var connected:Array[Vector2]=straighten_route(region_id,current,raw)
				if not connected.is_empty():return connected
		if current.distance_to(destination)<=2:
			var repaired:Array[Vector2]=repair_segment(region_id,current,destination)
			if not repaired.is_empty():return straighten_route(region_id,current,repaired)
		return []
	var route: Array[Vector2] = []
	for index in range(1, points.size()): route.append(Vector2(points[index]) + Vector2(0.5, 0.5))
	route.append(destination)
	return straighten_route(region_id,current,route)

# Native span fill for polygon interiors; original predicates handle the two
# boundary cells and every possible static obstacle. Used only by home terrain.
func _raster_home_terrain(grid:AStarGrid2D,region:Dictionary)->void:
	grid.fill_solid_region(grid.region,true)
	for shape in catalog._geometry(region,"land")+catalog._geometry(region,"docks"):
		var poly:PackedVector2Array=shape.points;var bounds:Rect2=shape.bounds
		for y in range(maxi(grid.region.position.y,ceili(bounds.position.y-.5)),mini(grid.region.end.y,floori(bounds.end.y-.5)+1)):
			var py:float=y+.5;var crossings:Array[float]=[]
			for i in poly.size():
				var a:Vector2=poly[i];var b:Vector2=poly[(i+1)%poly.size()]
				if (a.y>py)!=(b.y>py):crossings.append(a.x+(py-a.y)*(b.x-a.x)/(b.y-a.y))
				if is_equal_approx(a.y,py) and is_equal_approx(b.y,py):
					for x in range(maxi(grid.region.position.x,ceili(minf(a.x,b.x)-.5)),mini(grid.region.end.x,floori(maxf(a.x,b.x)-.5)+1)):
						if terrain_surface("home",Vector2(x+.5,py)):grid.set_point_solid(Vector2i(x,y),false)
			crossings.sort()
			for i in range(0,crossings.size()-1,2):
				var left:int=maxi(grid.region.position.x,ceili(crossings[i]-.5));var right:int=mini(grid.region.end.x-1,floori(crossings[i+1]-.5))
				if right<left:continue
				grid.fill_solid_region(Rect2i(left,y,right-left+1,1),false)
				for x in [left,right]:
					if not terrain_surface("home",Vector2(x+.5,py)):grid.set_point_solid(Vector2i(x,y),true)
	# Build a small union of possible obstacle cells, then exact-check those only.
	_layout_blocked_fast(region.layout,Vector2(-10000,-10000))
	var areas:Array[Rect2]=[]
	for f in _layout_collision.fences:areas.append(f[2])
	for r in _layout_collision.props:areas.append(r)
	for c in _layout_collision.cliffs:
		var box:=Rect2(c[0][0],Vector2.ZERO)
		for p in c[0]:box=box.expand(p)
		areas.append(box)
	for pond in _layout_collision.ponds:areas.append(Rect2(pond[0]-pond[1]*1.12,pond[1]*2.24))
	for farm in farms.farms.values():areas.append(farms.bounds(farm).grow(1.3))
	var checked:Dictionary={}
	for box in areas:
		for y in range(maxi(grid.region.position.y,floori(box.position.y)-1),mini(grid.region.end.y,ceili(box.end.y)+1)):
			for x in range(maxi(grid.region.position.x,floori(box.position.x)-1),mini(grid.region.end.x,ceili(box.end.x)+1)):
				var c:=Vector2i(x,y)
				if checked.has(c) or grid.is_point_solid(c):continue
				checked[c]=true
				if not _terrain_walkable("home",Vector2(c)+Vector2(.5,.5)):grid.set_point_solid(c,true)

func grid_connections(region_id:String,endpoint:Vector2,grid:AStarGrid2D)->Array[Vector2i]:
	var result:Array[Vector2i]=[];var origin:=Vector2i(endpoint.floor())
	for y in range(-2,3):
		for x in range(-2,3):
			var cell:Vector2i=origin+Vector2i(x,y)
			if not grid.region.has_point(cell) or grid.is_point_solid(cell):continue
			var centre:=Vector2(cell)+Vector2(.5,.5)
			if endpoint.distance_to(centre)<=2.5 and segment_clear(region_id,endpoint,centre):result.append(cell)
	result.sort_custom(func(a,b):return endpoint.distance_squared_to(Vector2(a)+Vector2(.5,.5))<endpoint.distance_squared_to(Vector2(b)+Vector2(.5,.5)))
	return result.slice(0,8)

func segment_clear(region_id:String,start:Vector2,finish:Vector2)->bool:
	if not walkable(region_id,start) or not walkable(region_id,finish):return false
	# Farm fences are capsules with the same .55 radius as walkable(). A
	# grazing segment can enter that capsule between the terrain sample points.
	if region_id=="home" and farms!=null:
		var swept_bounds:=Rect2(start,Vector2.ZERO).expand(finish).grow(.55)
		for farm in farms.farms.values():
			if not swept_bounds.intersects(farms.bounds(farm).grow(1.3)) or not farms.ready(farm.id):continue
			for fence in farms.fences(farm):
				if Geometry2D.segment_intersects_segment(start,finish,fence[0],fence[1])!=null:return false
				var separation:float=minf(minf(start.distance_to(Geometry2D.get_closest_point_to_segment(start,fence[0],fence[1])),finish.distance_to(Geometry2D.get_closest_point_to_segment(finish,fence[0],fence[1]))),minf(fence[0].distance_to(Geometry2D.get_closest_point_to_segment(fence[0],start,finish)),fence[1].distance_to(Geometry2D.get_closest_point_to_segment(fence[1],start,finish))))
				if separation<.55:return false
	# Sampling can miss a very short clipped corner of a facility post. Test the
	# original obstacle rectangles continuously before the terrain samples.
	if region_id=="home" and leisure!=null:
		for site in leisure.sites.values():
			if not site.complete or (standard!=null and standard.sites.has(site.id)):continue
			var art:Dictionary=leisure.art(site)
			if art.is_empty():continue
			for box in art.recreation.obstacles:
				var rect:=Rect2(point(site)+Vector2(box[0],box[1]),Vector2(box[2],box[3])).grow(-.0001)
				var corners:Array[Vector2]=[rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]
				for edge in range(4):
					if Geometry2D.segment_intersects_segment(start,finish,corners[edge],corners[(edge+1)%4])!=null:return false
	var count:int=maxi(1,ceili(start.distance_to(finish)/.15))
	var previous:Vector2=start
	for index in range(1,count+1):
		var at:Vector2=start.lerp(finish,float(index)/count)
		if not walkable(region_id,at):return false
		var old_cell:=Vector2i(previous.floor());var cell:=Vector2i(at.floor())
		if old_cell.x!=cell.x and old_cell.y!=cell.y:
			if not walkable(region_id,Vector2(at.x,previous.y)) or not walkable(region_id,Vector2(previous.x,at.y)):return false
		previous=at
	return true
func repair_segment(region_id:String,start:Vector2,finish:Vector2)->Array[Vector2]:
	for elbow in [Vector2(start.x,finish.y),Vector2(finish.x,start.y)]:
		if segment_clear(region_id,start,elbow) and segment_clear(region_id,elbow,finish):return [elbow,finish]
	# Fine local repair only around a failed coarse segment, never a second mover.
	var grid:=AStarGrid2D.new();var a:=Vector2i((start*4).round());var b:=Vector2i((finish*4).round())
	var low:=Vector2i(mini(a.x,b.x)-10,mini(a.y,b.y)-10);var high:=Vector2i(maxi(a.x,b.x)+11,maxi(a.y,b.y)+11)
	grid.region=Rect2i(low,high-low);grid.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES;grid.update()
	for y in range(low.y,high.y):
		for x in range(low.x,high.x):grid.set_point_solid(Vector2i(x,y),not walkable(region_id,Vector2(x,y)/4))
	var candidates:Array[Vector2]=[]
	for cell in grid.get_id_path(a,b):candidates.append(Vector2(cell)/4)
	if candidates.is_empty():return []
	candidates.append(finish);var last:=start
	for at in candidates:
		if not segment_clear(region_id,last,at):return []
		last=at
	return candidates
func straighten_route(region_id:String,start:Vector2,raw:Array[Vector2])->Array[Vector2]:
	if raw.size()<3:return _straighten_original(region_id,start,raw)
	var corners:Array[Vector2]=[raw[0]]
	for i in range(1,raw.size()-1):
		var incoming:Vector2=raw[i]-raw[i-1];var outgoing:Vector2=raw[i+1]-raw[i]
		# Only exact same-direction collinear grid steps are redundant candidates.
		if incoming.cross(outgoing)!=0 or incoming.dot(outgoing)<=0:corners.append(raw[i])
	corners.append(raw.back())
	if corners.size()<raw.size():
		var route:Array[Vector2]=_straighten_original(region_id,start,corners)
		if not route.is_empty():return route
	return _straighten_original(region_id,start,raw)
func _straighten_original(region_id:String,start:Vector2,raw:Array[Vector2])->Array[Vector2]:
	var result:Array[Vector2]=[];var origin:Vector2=start;var first:=0
	while first<raw.size():
		var chosen:=raw.size()-1
		if not segment_clear(region_id,origin,raw[chosen]):
			if not segment_clear(region_id,origin,raw[first]):
				var repair:Array[Vector2]=repair_segment(region_id,origin,raw[first])
				if repair.is_empty():return []
				result.append_array(repair);origin=raw[first];first+=1;continue
			var low:=first;var high:=raw.size()-1
			while high-low>1:
				var middle:int=(low+high)/2
				if segment_clear(region_id,origin,raw[middle]):low=middle
				else:high=middle
			chosen=low
		result.append(raw[chosen]);origin=raw[chosen];first=chosen+1
	return result
func walk_facing(id:String,direction:Vector2,delta:float)->void:
	if direction.length_squared()<.0001:return
	# A moving body always faces its actual major axis, including a first step.
	actors[id].facing=walking_direction(direction)
	_walk_facings[id]={"heading":direction.normalized(),"age":delta}
func walking_direction(direction:Vector2)->String:
	return ("right" if direction.x>0 else "left") if absf(direction.x)>absf(direction.y) else ("down" if direction.y>0 else "up")

func motion_state(id:String)->Dictionary:
	return _motion_states.get(id,{"moving":false,"facing":actors[id].get("facing","down"),"still_seconds":1.0,"distance":0.0,"velocity":Vector2.ZERO}).duplicate()

func reset_motion()->void:
	_motion_states.clear()

func _finish_motion(delta:float,before:Dictionary)->void:
	for id in actors:
		var actor:Dictionary=actors[id]
		var old:Dictionary=before.get(id,{"region":actor.region_id,"point":point(actor)})
		var shift:Vector2=point(actor)-Vector2(old.point) if old.region==actor.region_id else Vector2.ZERO
		var moved:bool=shift.length()>0.00001
		var state:Dictionary=_motion_states.get(id,{"facing":actor.facing,"still_seconds":1.0})
		state["running"]=moved and bool(old.get("running",false))
		state["moving"]=moved;state["distance"]=shift.length();state["velocity"]=shift/delta
		state["still_seconds"]=0.0 if moved else minf(60,float(state.still_seconds)+delta)
		if moved:state.facing=walking_direction(shift)
		# Work, hunger, seating and conversations may request a look direction.
		# They can take effect only after the real body has settled for 0.3 seconds.
		if moved or float(state.still_seconds)<.3:actor.facing=state.facing
		_motion_states[id]=state

func _apply_route(actor_id: String, route: Array[Vector2]) -> bool:
	if route.is_empty(): return false
	if actor_id=="human" and hunger!=null and hunger.has_method("player_moving"):hunger.player_moving(route[0])
	_forced_runs[actor_id] = point(actors[actor_id]).distance_to(route.back()) > RUN_DISTANCE
	_routes[actor_id] = route
	actors[actor_id].activity = "walking"
	revision += 1
	return true

func force_human_run() -> void:
	if _routes.has("human"): _forced_runs["human"] = true

func is_running(actor_id: String) -> bool:
	if actor_id!="human" and actors.has(actor_id):
		if hunger!=null and hunger.rank(actor_id)>=2 and not hunger.rushing(actor_id):return false
		return _routes.has(actor_id) and not _routes[actor_id].is_empty() and actors[actor_id].activity=="walking"
	if hunger!=null and hunger.has_method("rushing") and hunger.rushing(actor_id) and not loaded(actor_id):return true
	if hunger!=null and actor_id!="human" and hunger.rank(actor_id)>=2:return false
	if not actors.has(actor_id) or not _routes.has(actor_id) or _routes[actor_id].is_empty(): return false
	if not _forced_runs.get(actor_id, false): return false
	if actors[actor_id].activity != "walking" or loaded(actor_id): return false
	var gathering:bool=work.jobs.get(actor_id,{}).get("phase","")=="fire_travel"
	if work.jobs.has(actor_id) and not gathering:return false
	if farms.active(actor_id) or projects.active(actor_id) or homestead.active(actor_id): return false
	if (activities.members.has(actor_id) or shared_activity.holds(actor_id)) and not gathering: return false
	if fishing != null and not fishing.held(actor_id).is_empty(): return false
	return true

func display_running(id:String)->bool:
	# The final displacement still belongs to the route that just ended.
	if _routes.has(id):return is_running(id)
	var state:Dictionary=motion_state(id)
	return bool(state.get("moving",false)) and bool(state.get("running",false))

func movement_speed(id:String)->float:
	if id!="human" and is_running(id):
		if hunger!=null and hunger.has_method("follow_paused") and hunger.follow_paused(id):return 0.0
		if hunger!=null and hunger.has_method("rushing") and hunger.rushing(id) and not loaded(id):return float(hunger.config.rush_speed)/32.0
		return CARRY_SPEED if loaded(id) else RUN_SPEED
	if loaded(id):return CARRY_SPEED
	if fishing!=null and not fishing.held(id).is_empty():return SPEED
	if hunger!=null and hunger.has_method("rushing") and hunger.rushing(id):return float(hunger.config.rush_speed)/32.0
	if hunger!=null and hunger.has_method("follow_paused") and hunger.follow_paused(id):return 0.0
	if hunger!=null and id!="human" and hunger.rank(id)>=3:return float(hunger.config.presentation.very_slow_speed)/32.0
	if hunger!=null and id!="human" and hunger.rank(id)>=2:return float(hunger.config.slow_speed)/32.0
	return RUN_SPEED if is_running(id) else SPEED

func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0: return
	for actor in actors.values():CarryRetention.clamp_actor(actor)
	auto_stow_idle()
	var motion_before:Dictionary={}
	for id in actors:motion_before[id]={"region":actors[id].region_id,"point":point(actors[id])}
	if resort!=null:resort.ready()
	if hunger!=null and hunger.has_method("advance"):hunger.advance(delta)
	ingredients.advance(delta)
	farms.advance(delta)
	projects.advance(delta)
	homestead.advance(delta)
	var changed := false
	for id in _routes.keys():
		if id=="human" and dark!=null and dark.block_motion(delta):continue
		motion_before[id]["running"]=is_running(id)
		var budget: float = movement_speed(id) * delta
		var point := Vector2(actors[id].position[0], actors[id].position[1])
		while budget > 0 and not _routes[id].is_empty():
			var target: Vector2 = _routes[id][0]
			var direction := target - point
			if direction.length() > 0.01:
				walk_facing(id,direction,minf(delta,direction.length()/maxf(.001,movement_speed(id))))
			var distance := point.distance_to(target)
			if distance <= budget:
				point = target
				budget -= distance
				_routes[id].pop_front()
			else:
				point = point.move_toward(target, budget)
				budget = 0
		actors[id].position = [point.x, point.y]
		changed = true
		if _routes[id].is_empty():
			_routes.erase(id)
			_forced_runs.erase(id)
			_walk_facings.erase(id)
			actors[id].activity = "idle"
	if changed: revision += 1
	if deliveries!=null:deliveries.advance(delta)
	work.advance(delta)
	for barbecue in barbecues.values():barbecue.advance(delta)
	shared_activity.advance(delta)
	if moon!=null:moon.advance(delta)
	# Commit the frame clock before local rules read persisted deadlines.
	forest.advance(delta)
	if scene_speech==null:scene_speech=preload("res://scripts/scene_speech.gd").new(self);scene_speech.reset()
	scene_speech.advance()
	personality.advance()
	intelligence.advance()
	if delta>0:standard.offer_hint()
	if flower_creation!=null:flower_creation.advance(delta)
	director.advance(delta)
	activities.advance(delta)
	fishing.advance(delta)
	gomoku.advance(delta)
	jieqi.advance(delta)
	days.advance()
	weather.advance()
	proposals.advance(delta)
	promises.advance(delta)
	wishes.advance(delta)
	relationships.advance(delta)
	standard.advance(delta)
	if home_island!=null:home_island.advance(delta)
	if their_island!=null:their_island.advance(delta)
	if dark!=null:dark.advance(delta)
	cat.advance(delta)
	lively.advance(delta)
	for actor in actors.values():CarryRetention.clamp_actor(actor)
	_finish_motion(delta,motion_before)

func _error(code: String) -> Dictionary:
	return {"ok": false, "error": code, "snapshot_revision": revision}

func site_size(site: Dictionary) -> Vector2:
	if site.has("blueprint"): return Blueprint.footprint(site.blueprint.structure)
	# Unstarted reserved plots use their authored geometry, not a second fixed size.
	if locations!=null and locations.v3() and catalog._pair(site.get("footprint")):return Vector2(site.footprint[0],site.footprint[1])
	return Vector2(8, 7)

func select_blueprint(target_id: String, blueprint_id: String) -> Dictionary:
	if library == null or not objects.has(target_id) or objects[target_id].kind != "construction_site": return _error("unknown_site")
	var site: Dictionary = objects[target_id]
	if projects.site_locked(target_id): return work.fail("project_locked", LocalText.text("system.world_state.this_house_plan_has_chosen_its_blueprint_cancel"))
	if int(site.get("stage_index", 0)) > 0 or int(site.get("invested", 0)) > 0 or not site.delivered.is_empty() or work.claims.has(target_id): return work.fail("site_locked", LocalText.text("system.world_state.construction_has_begun_the_original_blueprint_cannot_be"))
	var compiled: Dictionary = library.compile_blueprint(blueprint_id)
	if not compiled.ok: return compiled
	var size := Blueprint.footprint(compiled.structure)
	var area := Rect2(point(site) - size / 2, size)
	var valid_zone := false
	for zone in catalog.regions[site.region_id].zones:
		if zone.id == site.zone_id and catalog.rectangle(zone.rect).encloses(area): valid_zone = true
	if not valid_zone: return work.fail("outside_plot", LocalText.text("system.world_state.this_blueprint_extends_beyond_the_home_site"))
	for object in objects.values():
		if object.id != target_id and object.kind=="tree" and area.grow(.8).has_point(point(object)): return work.fail("occupied", LocalText.text("system.world_state.the_house_would_block_existing_objects"))
	site["blueprint"] = compiled.duplicate(true)
	site["required"] = {"wood": compiled.stages[0]}
	_grids.erase(site.region_id); revision += 1
	return {"ok": true, "status": "completed", "wood": compiled.wood, "message": LocalText.text("system.world_state.blueprint_chosen_it_needs_s_wood_in_total") % compiled.wood}

func construction_state(target_id: String) -> Dictionary:
	if not objects.has(target_id) or objects[target_id].kind != "construction_site": return {"ok": false}
	var site: Dictionary = objects[target_id]
	var stage := int(site.get("stage_index", 0))
	var costs: Array = work.stage_costs(site)
	var plan_id: String = site.get("blueprint", {}).get("id", "cottage")
	if not site.has("blueprint") and stage == 0 and site.delivered.is_empty() and library != null:
		costs = Blueprint.quote(library.artworks["cottage"].structure).stages
	var stock:int=int(available_items("human").get("wood",0))
	var delivered := int(site.delivered.get("wood", 0))
	var total := 0
	for amount in costs: total += amount
	return {"ok": true, "id": target_id, "name": site.name, "stage": stage, "costs": costs.duplicate(), "total": total, "invested": int(site.get("invested", 0)), "delivered": delivered, "needed": maxi(0, int(costs[stage]) - delivered) if stage < 5 else 0, "stored": stock, "plan_id": plan_id, "claimed_by": work.claims.get(target_id, ""), "locked": stage > 0 or delivered > 0 or int(site.get("invested", 0)) > 0 or work.claims.has(target_id)}

func region_info(id: String) -> Dictionary:
	return catalog.regions.get(id, interior.rooms().get(id, {}))

var pocket_notice:=""
var pocket_warned:=false
func auto_stow_idle()->void:
	for id in actors:
		var actor:Dictionary=actors[id]
		if actor.get("pocketed",false) or actor.carry.is_empty():continue
		if not actor.carry.keys().any(func(k):return pocket_item(str(k))):continue
		if work.jobs.has(id) or farms.active(id) or projects.active(id) or homestead.active(id) or _routes.has(id):continue
		if not str(actor.get("furniture_id","")).is_empty() or not fishing.held(id).is_empty():continue
		var result:Dictionary=stow_loose(id)
		if id=="human":
			if result.ok:pocket_warned=false
			elif result.get("error")=="backpack_full" and not pocket_warned:pocket_notice=LocalText.text("system.world_state.your_backpack_is_full_loose_items_stay_in");pocket_warned=true
func pocket_item(item:String)->bool:
	return item=="firefly.jar" or item.begins_with("seed.") and farms.crops.has(item.trim_prefix("seed.")) or farms.crops.has(item)
func stow_loose(actor_id:String="human")->Dictionary:
	var actor:Dictionary=actors[actor_id]
	if work.jobs.has(actor_id) or farms.active(actor_id) or projects.active(actor_id) or homestead.active(actor_id):return work.fail("busy",LocalText.text("system.world_state.finish_what_you_are_doing_first"))
	if life.item_count(actor.carry)>=work.CARRY_LIMIT:return work.fail("backpack_full",LocalText.text("system.world_state.your_backpack_is_full_store_something_first"))
	if actor.carry.is_empty() or not actor.carry.keys().any(func(k):return pocket_item(str(k))):return work.fail("nothing_loose",LocalText.text("system.world_state.there_are_no_loose_items_to_put_away"))
	actor["pocketed"]=true;revision+=1
	return {"ok":true,"message":LocalText.text("system.world_state.loose_items_are_in_your_backpack_they_still")}
func loaded(actor_id: String) -> bool:
	var actor:Dictionary=actors[actor_id]
	return actor.carry.keys().any(func(key):return not (actor.get("pocketed",false) and pocket_item(str(key)))) or not str(actor.get("furniture_id", "")).is_empty()

func object_by_id(id: String) -> Dictionary:
	if homestead!=null and id==homestead.config.site.id:return homestead.target()
	return leisure.sites.get(id,farms.plots.get(id, objects.get(id, interior.furniture.get(id, {}))))

func storage_owner(item:Dictionary)->String:
	if item.has("owner_id"):return str(item.owner_id)
	var region:String=str(item.get("region_id",""))
	if region.begins_with("room."):
		return str(objects.get(region.trim_prefix("room."),{}).get("owner_id",""))
	return ""
func storage_objects() -> Array:
	return []

func job_summary(job: Dictionary) -> Dictionary:
	var copy: Dictionary = job.duplicate(true)
	for key in ["candidate", "reservation"]:
		if copy.has(key): copy[key].erase("artwork")
	return copy

# Only UI/host uses this method; model/API calls remain bound to command(actor_id).
func host_command(id: String,args: Dictionary) -> Dictionary:
	if flower_creation!=null and args.get("intent") in flower_creation.ACTIONS:return command(id,args)
	if not actors.has(id):return _error("unknown_resident")
	if not residents.supports(actors[id],str(args.get("intent",""))):return _error("unsupported_capability")
	if shared_activity.contains(id): shared_activity.pause(LocalText.text("system.world_state.the_host_assigned_something_new_the_previous_activity"))
	activities.dismiss(id,false);activities.pause_follow(id);activities.pause_work(id)
	var had_host:bool=host_issuing.has(id);var previous:bool=bool(host_issuing.get(id,false))
	host_issuing[id]=true
	var result:Dictionary=command(id,args)
	if had_host:host_issuing[id]=previous
	else:host_issuing.erase(id)
	return result

func map_anchor(key:String)->Array:
	var entry:Variant=catalog.regions.home.layout.anchors[key]
	if entry is Array:return entry.duplicate()
	if entry.has("anchor"):return map_anchor(str(entry.anchor))
	var object:Dictionary=catalog.objects[entry.object_id]
	return [object.position[0]+entry.offset[0],object.position[1]+entry.offset[1]]

func life_for_target(id:String)->RefCounted:
	if barbecues.has(id):return barbecues[id]
	for barbecue in barbecues.values():
		if barbecue.patches.has(id):return barbecue
	return life
func life_for_job(job:Dictionary)->RefCounted:return barbecues.get(job.get("barbecue_id",job.get("target_id","")),life)
func barbecue_summaries()->Array:
	var result:Array=[]
	for barbecue in barbecues.values():
		var entry:Dictionary=barbecue.station.duplicate(true);entry.erase("artwork");entry["seats"]=barbecue.seats();entry["mushrooms"]=barbecue.patches.values().duplicate(true);result.append(entry)
	return result
func all_mushrooms()->Dictionary:
	var result:Dictionary={}
	for barbecue in barbecues.values():result.merge(barbecue.patches)
	return result

func surface_polygon(id:String)->PackedVector2Array:
	for surface in catalog.regions.home.layout.get("dock_surfaces",[]):
		if surface.get("id")==id:return Layout.points(surface.polygon)
	return PackedVector2Array()

# Resource authority shared by every recipe and building. No routes or callbacks
# occur between validating the complete cost and committing both ledgers.
func available_items(actor_id:String="human")->Dictionary:
	var result:Dictionary=storage.saved().items
	for item in actors[actor_id].carry:result[item]=int(result.get(item,0))+int(actors[actor_id].carry[item])
	return result
func pay_costs(actor_id:String,costs:Dictionary)->Dictionary:
	if not actors.has(actor_id) or not storage.valid_items(costs):return _error("invalid_items")
	var available:Dictionary=available_items(actor_id);var missing:Dictionary={}
	for item in costs:
		if int(costs[item])>int(available.get(item,0)):missing[item]=int(costs[item])-int(available.get(item,0))
	if not missing.is_empty():return {"ok":false,"error":"insufficient_materials","missing":missing}
	var held:Dictionary={};var warehouse:Dictionary={}
	for item in costs:
		var n:int=mini(int(costs[item]),int(actors[actor_id].carry.get(item,0)))
		if n>0:held[item]=n
		if int(costs[item])-n>0:warehouse[item]=int(costs[item])-n
	var paid:Dictionary=storage.take(warehouse)
	if not paid.ok:return paid
	for item in held:
		CarryRetention.consume(actors[actor_id],item,int(held[item]))
		actors[actor_id].carry[item]-=held[item]
		if actors[actor_id].carry[item]==0:actors[actor_id].carry.erase(item)
	revision+=1
	return {"ok":true,"sources":{"backpack":held,"storage":warehouse}}
func deposit_all(actor_id:String="human",preserve_retained:bool=false)->Dictionary:
	if not actors.has(actor_id):return _error("unknown_resident")
	var carry:Dictionary=actors[actor_id].carry
	if not homestead.plans.get(actor_id,{}).get("receipt",{}).is_empty() or actors[actor_id].has("furniture_id"):return _error("inventory_reserved")
	var deposited:Dictionary=CarryRetention.unprotected(actors[actor_id]) if preserve_retained else carry.duplicate(true)
	if deposited.is_empty():return {"ok":true,"items":{}}
	if not storage.add(deposited):return _error("invalid_items")
	if ingredients!=null and recipes!=null:
		for item in deposited:
			if int(deposited[item])>0 and item in recipes.INGREDIENT_IDS:ingredients.note_obtained(item)
	for item in deposited:
		if not preserve_retained:CarryRetention.consume(actors[actor_id],item,int(deposited[item]))
		carry[item]-=int(deposited[item])
		if carry[item]==0:carry.erase(item)
	CarryRetention.clamp_actor(actors[actor_id])
	if carry.is_empty():actors[actor_id].erase("pocketed")
	revision+=1
	return {"ok":true,"items":deposited}
func take_storage_host(item:String,quantity:int)->Dictionary:
	if quantity<1 or work.carry_space("human")<quantity:return _error("backpack_full")
	if work.jobs.has("human") or projects.active("human") or farms.active("human") or homestead.active("human") or actors.human.has("furniture_id"):return _error("inventory_reserved")
	var paid:Dictionary=storage.take({item:quantity})
	if not paid.ok:return paid
	actors.human.carry[item]=int(actors.human.carry.get(item,0))+quantity
	if ingredients!=null and recipes!=null and item in recipes.INGREDIENT_IDS:ingredients.note_obtained(item)
	revision+=1
	return {"ok":true}

func _jieqi_completed(result:Dictionary)->void:
	memories.record_event("jieqi_result",result.id,["human",result.opponent_id],{"opponent_id":result.opponent_id,"winner":result.winner,"seed":result.seed,"moves":result.moves})

# Non-resident pet routes reuse the same AStar/segment validation as residents.
# The temporary path-query proxy never survives this synchronous call or saves.
func route_pet(pet:RefCounted,destination:Vector2)->bool:
	var proxy_id:="__pet_path_query__"
	actors[proxy_id]={"id":proxy_id,"region_id":pet.region,"position":[pet.position.x,pet.position.y],"facing":"down","carry":{},"activity":"idle"}
	var path:Array[Vector2]=find_route(proxy_id,destination)
	actors.erase(proxy_id)
	pet.route=path
	return not path.is_empty()
func advance_pet_route(pet:RefCounted,delta:float)->void:
	var budget:float=delta*SPEED
	while budget>0 and not pet.route.is_empty():
		var target:Vector2=pet.route[0]
		if not walkable(pet.region,target):pet.route.clear();return
		var distance:float=pet.position.distance_to(target)
		if distance>.00001:pet.facing=walking_direction(target-pet.position)
		if distance<=budget:pet.position=target;pet.route.pop_front();budget-=distance
		else:pet.position=pet.position.move_toward(target,budget);budget=0

# Bound provider-neutral actions affect only the bound resident.
func model_social_command(id:String,args:Dictionary)->Dictionary:
	var intent:String=args.intent
	if gomoku.ai_active(id) and intent!="query_state":return _error("chess_match_restricted")
	if id=="human":return _error("host_only")
	if not fishing.held(id).is_empty() and intent!="query_state":return _error("holding_fish")
	if intent=="query_state":
		if args.size()!=1:return _error("invalid_command")
		return {"ok":true,"activity":actors[id].activity,"hunger":hunger.summary(id),"storage":storage.saved()}
	if intent!="query_state" and (work.jobs.has(id) or farms.active(id) or projects.active(id) or homestead.active(id) or shared_activity.holds(id) or activities.members.has(id)):return _error("busy")
	if intent=="gather_at":
		if args.keys().any(func(key):return key not in ["intent","x","y","region_id"]) or not catalog._number(args.get("x")) or not catalog._number(args.get("y")):return _error("invalid_position")
		return activities.gather_selected([id],str(args.get("region_id",actors[id].region_id)),Vector2(args.x,args.y))
	if args.size()!=1:return _error("invalid_command")
	if intent=="hand_over":return {"ok":deliveries.request(id,true,true)}
	var ids:Array=activities.following.keys()
	if intent=="follow" and id not in ids:ids.append(id)
	elif intent=="unfollow":ids.erase(id)
	if work.jobs.has(id) or farms.active(id) or projects.active(id) or homestead.active(id) or shared_activity.holds(id) or activities.members.has(id):return _error("busy")
	return activities.set_followers(ids,[id])
