extends SceneTree
const Places=preload("res://scripts/map_locations.gd")
const World=preload("res://scripts/world_state.gd")
const Fixture=preload("res://tests/fishing_fixture.gd")
const Save=preload("res://scripts/save_store.gd")
var checks:=0
var failed:=false
func _initialize() -> void:call_deferred("run")
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failed=true;push_error(label)
func run() -> void:
	var directory:=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(1);return
	var world:=World.new();world.residents.provision(world);world.director.set_all_enabled(false)
	check(world.error.is_empty(),"revised fishing config valid "+world.error)
	if not world.error.is_empty():quit(1);return
	check(world.fishing.pens.size()==4 and world.fishing.seas.size()==4,"separate fisheries and wild ocean catalogs")
	check(world.fishing.pens.values().all(func(pen):return not pen.has("spots") and not pen.has("stock_capacity")),"fisheries never contain fishing positions or wild stocks")
	var positions: Dictionary=world.actors.duplicate(true)
	check(world.command("human",{"intent":"fish"}).get("error")=="not_near_sea" and world.actors==positions and world._routes.is_empty(),"inland action prompts without moving")
	for id in world.fishing.pens:check(world.command("human",{"intent":"fish","target_id":id}).get("error")=="sea_only","fishery cannot be used as fishing target")
	check(world.residents.supports(world.actors["npc.mira"],"fish") and world.command("npc.mira",{"intent":"fish"}).get("error")=="not_near_sea" and world.actors==positions and world._routes.is_empty(),"all four working companions still require their own actual coast and never auto-walk")
	check(not world.command("npc.mira",{"intent":"fish","actor_id":"human"}).ok and world.actors.human==positions.human,"work capability never permits overriding the bound actor to control human")
	var unauthorized_plot:Dictionary=world.farms.farm_plots("farm.home")[0]
	check(not world.command("npc.mira",{"intent":"plant","target_id":unauthorized_plot.id,"crop_id":"turnip"}).ok and world.work.jobs.is_empty() and world.farms.host_grants.is_empty(),"work capability never grants unauthorized farm management or host orders")
	check(Fixture.coast(world,"human"),"player physically walks to natural coast")
	var shore: Dictionary=world.fishing.shore("human")
	check(not shore.is_empty() and world.fishing._ocean("home",Vector2(shore.hook[0],shore.hook[1])),"hook is natural ocean outside all enclosures")
	positions=world.actors.duplicate(true)
	var before: int=world.fishing.waters[shore.water_id].available
	check(world.command("human",{"intent":"fish"}).status=="accepted" and world.actors==positions and not world._routes.has("human"),"coastal action casts exactly where resident stands")
	world.command("human",{"intent":"stop"})
	check(world.fishing.waters[shore.water_id].available==before and world.fishing.fish.is_empty() and world.work.claims.is_empty(),"cancel before actual catch consumes no resource")
	var fish: Dictionary=Fixture.catch_one(world,"human")
	check(not fish.is_empty(),"actual engine catch creates one owned instance")
	if fish.is_empty():quit(1);return
	check(fish.scale>=1 and fish.scale<=8 and fish.source_id.begins_with("home.sea."),"fish size and natural ocean provenance")
	check(world.fishing.held("human").is_empty() and fish.location=="storage" and world.command("human",{"intent":"fish"}).ok,"stored catch allows an actual next fishing task")
	world.command("human",{"intent":"stop"})
	check(world.shared_activity.validate_invitation(["codex"]).ok,"stored catch does not block a valid barbecue invitation")
	check(not world.loaded("human") and world.actors.human.carry.is_empty() and world.command("human",{"intent":"chop","target_id":"home.tree.01"}).ok,"stored fish allows actual tool work without backpack load")
	world.command("human",{"intent":"stop"})
	var id: String=fish.id
	check(Fixture.walk(world,"human",[shore.position[0]+1,shore.position[1]+1]),"held fish can move through authoritative router")
	check(world.fishing.fish[id].location=="storage" and world.fishing.fish.size()==1,"movement retains same held instance")
	check(world.command("codex",{"intent":"stock_fish","fish_id":id,"pen_id":"home.fishery.east"}).get("error")=="fish_not_owned","bound resident cannot take another catch")
	check(Save.save_world(world,directory.path_join("pending")),"held catch saves")
	var restored:=World.new()
	check(Save.load_world(restored,directory.path_join("pending")).ok and restored.fishing.fish[id].location=="storage","reload retains pending/held fish with no new catch")
	check(restored.work.jobs.is_empty() and restored.work.claims.is_empty() and restored._routes.is_empty(),"reload restores no fishing tasks")
	positions=world.actors.duplicate(true)
	check(world.command("human",{"intent":"stock_fish","fish_id":id,"pen_id":"home.fishery.east"}).ok and world.actors==positions,"instant fish transfer still never moves residents")
	check(not world.command("human",{"intent":"stock_fish","fish_id":id,"pen_id":"home.fishery.east"}).ok and world.fishing.fish.size()==1,"repeat transfer never duplicates")
	check(world.read_memories("human",{"kind":"fishing_catch"}).total==1 and world.read_memories("codex",{"kind":"fishing_catch"}).total==0,"real catch memory never credits nearby noncatcher")
	check(Save.save_world(world,directory.path_join("placed")),"placed catch saves")
	var second:=World.new();check(Save.load_world(second,directory.path_join("placed")).ok and second.fishing.fish[id].location=="home.fishery.east","placed metadata survives load")
	# Genuine event fixture encoded as the previous format; never player data.
	var legacy: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("placed/island-v2.json")))
	legacy.erase("shared_memories");legacy.fishing.version=1
	var old_waters: Dictionary={}
	for sea in world.fishing.seas.values():old_waters[sea.legacy_id]=legacy.fishing.waters[sea.id]
	legacy.fishing.waters=old_waters
	var sea: Dictionary=world.fishing.seas[fish.source_id]
	legacy.fishing.fish[id].source_id=sea.legacy_id;legacy.fishing.fish[id].spot_id=sea.legacy_spots[0].id
	legacy.fishing.memories[0].water_id=sea.legacy_id
	Fixture.write_json(directory.path_join("legacy/island-v2.json"),legacy)
	var migrated:=World.new();check(Save.load_world(migrated,directory.path_join("legacy")).ok,"previous fishing format migrates")
	check(migrated.fishing.fish[id].source_id==sea.legacy_id and migrated.fishing.fish[id].spot_id==sea.legacy_spots[0].id,"historical fish sources are preserved")
	check(migrated.fishing.waters[sea.id].available==legacy.fishing.waters[sea.legacy_id].available,"migration maps resource counts without refill")
	check(is_equal_approx(float(migrated.fishing.fish[id].scale),float(fish.scale)) and migrated.fishing.fish[id].owner_id==fish.owner_id and migrated.fishing.fish[id].location=="home.fishery.east","migration preserves actual individual appearance and ownership")
	check(Save.save_world(migrated,directory.path_join("migrated")),"migrated state saves as version2")
	var repeat:=World.new();check(Save.load_world(repeat,directory.path_join("migrated")).ok and repeat.fishing.fish[id]==migrated.fishing.fish[id],"migration is idempotent on subsequent reload")
	var bad: Dictionary=legacy.duplicate(true);bad.fishing.fish[id].scale=.5
	Fixture.write_json(directory.path_join("bad/island-v2.json"),bad)
	var rejected: Dictionary=Save.load_world(World.new(),directory.path_join("bad"))
	check(not rejected.ok and FileAccess.file_exists(rejected.get("backup","")),"invalid old fish retains recoverable copy")
	var older: Dictionary=legacy.duplicate(true);older.erase("fishing")
	Fixture.write_json(directory.path_join("older/island-v2.json"),older)
	var old_world:=World.new();check(Save.load_world(old_world,directory.path_join("older")).ok and old_world.fishing.fish.is_empty(),"pre-fishing save invents no catches")
	var jobs: Array=[]
	for number in range(2,9):
		var actor_id: String="companion-%s"%number
		if not world.actors.has(actor_id):world.add_companion(actor_id,actor_id)
		jobs.append(actor_id)
	jobs.append("codex")
	world.director.set_all_enabled(false)
	# Move player to a broad north coast for an actual multi-resident invitation.
	var options: Array=world.fishing.coast_points.duplicate()
	options.sort_custom(func(a,b):return Vector2(a.position[0],a.position[1]).distance_squared_to(Places.point("p_52_10"))<Vector2(b.position[0],b.position[1]).distance_squared_to(Places.point("p_52_10")))
	check(Fixture.walk(world,"human",options[0].position),"host reaches a natural social coastline")
	var invited: Dictionary=world.fishing.invite_host(jobs)
	check(invited.accepted.size()>=6,"more than five AI residents can reserve independent natural shore positions "+str(invited))
	for tick in range(2500):
		world.advance(.1)
		if not invited.accepted.any(func(actor_id):return world.work.jobs.has(actor_id)):break
	check(invited.accepted.all(func(actor_id):return not world.fishing.held(actor_id).is_empty()),"invited residents each finish their own real catch")
	check(world.fishing.held("human").is_empty(),"invitation never fishes as or moves host automatically")
	var actor_id: String=invited.accepted[0]
	var owned: Dictionary=world.fishing.held(actor_id)
	var water_stock: int=world.fishing.waters[world.fishing.sea_id(owned.source_id)].available
	check(world.command(actor_id,{"intent":"release_fish","fish_id":owned.id}).ok and not world.fishing.fish.has(owned.id),"owner releases exact held instance")
	check(not world.command(actor_id,{"intent":"release_fish","fish_id":owned.id}).ok and world.fishing.waters[world.fishing.sea_id(owned.source_id)].available==water_stock,"repeat release does not refund resource")
	check(world.command(actor_id,{"intent":"fish"}).ok,"AI already at sea casts without travel")
	world.director.set_controller(actor_id,"local")
	check(not world.work.jobs.has(actor_id),"source takeover stops only exact fishing")
	var other: String=invited.accepted[1]
	check(not world.fishing.held(other).is_empty(),"takeover retains another resident's actual fish")
	print("Fishing: %s checks, %s"%[checks,"FAIL" if failed else "PASS"]);quit(1 if failed else 0)
