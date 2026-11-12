extends SceneTree
const World=preload("res://scripts/world_state.gd")
const Library=preload("res://scripts/character_library.gd")
const Save=preload("res://scripts/save_store.gd")
var checks:=0
var failed:=false
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failed=true;push_error(label)
func run_job(world: RefCounted,id: String,args: Dictionary) -> bool:
	var result: Dictionary=world.command(id,args)
	if not result.ok:print(result);return false
	for tick in range(18000):
		world.advance(.1)
		if not world.work.jobs.has(id) and not world._routes.has(id):return true
	return false
func timber(world: RefCounted) -> int:
	var total:=0
	for chest in [{"id":"storage","items":world.storage.saved().items,"capacity":9007199254740991,"kind":"storage"}]:total+=int(chest.items.get("wood",0))
	for actor in world.actors.values():total+=int(actor.carry.get("wood",0))
	for drop in world.drops.values():total+=int(drop.wood)
	for site in world.leisure.sites.values():total+=int(site.invested)
	return total
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var directory:=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(1);return
	var world:=World.new();world.residents.provision(world)
	var library:=Library.new();library.configure(directory);world.library=library;library.resident_world=world
	check(world.actors.size()==5 and [world.actors.codex.name,world.actors["companion-2"].name,world.actors["npc.mira"].name,world.actors["npc.nora"].name]==["小白","小蓝","小橙","阿黑"],"four distinct resident names")
	for site in world.leisure.sites.values():
		var art: Dictionary=world.leisure.art(site)
		check(library.valid(art),"valid editable recreation "+site.id)
		var config: Dictionary=art.recreation
		for p in config.slots+[config.entry]:check(world.walkable("home",world.point(site)+Vector2(p[0],p[1])),"slot and entrance walkable "+site.id)
	world.local_companion.set_enabled(true);world.village.enabled=true
	var human: Array=world.actors.human.position.duplicate()
	world.activities.gather()
	for tick in range(900):
		world.advance(.1)
		if world.activities.gathering.get("phase")=="holding":break
	check(world.activities.members.size()==4 and world.activities.members.values().all(func(m):return m.arrived),"all four arrive in formation")
	var positions: Dictionary={}
	for id in world.activities.members:positions[id]=world.actors[id].position.duplicate()
	for tick in range(590):world.advance(.1)
	check(not world.activities.gathering.is_empty() and world.activities.members.keys().all(func(id):return world.actors[id].position==positions[id]),"hold all four for full minute with ambient movement enabled")
	check(world.actors.human.position==human,"gather never moves human")
	check(not world.command("codex",{"intent":"dance"}).ok,"external actions cannot break assembly")
	for tick in range(12):world.advance(.1)
	check(world.activities.gathering.is_empty() and world.work.jobs.is_empty(),"automatically dismiss after sixty seconds without resuming labor")
	world.activities.gather();world.host_command("npc.nora",{"intent":"dance"})
	check(not world.activities.members.has("npc.nora") and world.activities.members.size()==3,"explicit host action releases only selected resident")
	world.activities.dismiss();world.work.stop("npc.nora");world.local_companion.set_enabled(false);world.village.enabled=false
	check(run_job(world,"codex",{"intent":"gather_wood","tree_count":11}),"collect actual wood for construction")
	var initial:=timber(world)
	check(initial==33,"eleven real normal trees supply exactly33 wood")
	check(world.command("codex",{"intent":"build_facility","target_id":"play.swing"}).ok,"start hauling swing materials")
	for tick in range(5000):
		world.advance(.1)
		if world.leisure.sites["play.swing"].invested>0:break
	world.command("codex",{"intent":"stop"})
	check(world.leisure.sites["play.swing"].invested>0 and timber(world)==initial,"cancel after partial delivery conserves timber")
	check(Save.save_world(world,directory),"save with partial facility")
	var restored:=World.new();restored.library=library
	check(Save.load_world(restored,directory).ok and timber(restored)==initial and restored.work.jobs.is_empty(),"reload conserves contributions without restarting")
	world=restored;world.residents.provision(world);library.resident_world=world
	check(run_job(world,"codex",{"intent":"build_facility","target_id":"play.swing"}) and world.leisure.sites["play.swing"].complete,"complete swing through real hauling")
	check(timber(world)==initial,"construction never invents or loses wood")
	for id in ["codex","companion-2","npc.mira","npc.nora"]:
		check(world.host_command(id,{"intent":"use_facility","target_id":"play.swing"}).ok,"any resident can swing "+id)
		for tick in range(1200):
			world.advance(.1)
			if world.actors[id].activity=="swinging":break
		check(world.actors[id].activity=="swinging","arrives at actual swing slot "+id)
		world.command(id,{"intent":"stop"})
	check(world.host_command("npc.mira",{"intent":"use_facility","target_id":"play.swing"}).ok and world.host_command("npc.nora",{"intent":"use_facility","target_id":"play.swing"}).ok,"two simultaneous reservations")
	check(not world.host_command("codex",{"intent":"use_facility","target_id":"play.swing"}).ok,"full facility rejects third occupant")
	check(world.work.jobs["npc.mira"].slot!=world.work.jobs["npc.nora"].slot,"reservations are unique")
	world.activities.gather();check(world.work.claims.is_empty() and timber(world)==initial,"gather releases facility slots without losing resources")
	world.activities.dismiss()
	var identity: String=world.actors.codex.id;var manager: String=world.farms.farms["farm.home"].manager_id
	check(world.residents.rename(world,"codex","小雪").ok and world.actors.codex.id==identity and world.farms.farms["farm.home"].manager_id==manager,"rename preserves identity and farm ownership")
	var custom: Dictionary=library.create_work(library.artworks["play-stage"])
	check(custom.ok,"clone new editable recreation")
	var exported:=directory.path_join("facility.json");check(library.export_work(library.artworks[custom.id],exported) and library.import_work(exported).ok,"export and import reusable template")
	check(not world.leisure.place(custom.id,Vector2(-10,-10)).ok,"outside-island foundation rejected")
	check(not world.leisure.place(custom.id,world.point(world.leisure.sites["play.stage"])).ok,"overlapping foundation rejected")
	var placed: Dictionary={}
	for y in range(35,100,5):
		for x in range(15,100,5):
			placed=world.leisure.place(custom.id,Vector2(x,y))
			if placed.ok:break
		if placed.ok:break
	check(placed.get("ok",false) and world.leisure.sites[placed.site_id].invested==0,"custom facility places on validated free land without free wood")
	var unsafe: Dictionary=library.artworks[custom.id].recreation.duplicate(true)
	unsafe.slots=[[0,0]];unsafe.obstacles=[[-1,-1,2,.5],[-1,.5,2,.5],[-1,-1,.5,2],[.5,-1,.5,2]]
	check(not world.leisure.Rules.valid(unsafe),"editor rejects enclosed unreachable seat")
	var loaded_library:=Library.new();loaded_library.configure(directory)
	check(loaded_library.artworks.has(custom.id),"custom template persists across library reload")
	var extra={"id":"npc.guest","name":"访客","role":"npc","appearance_id":"orange-haired-girl","position":[52,47]}
	world.residents.definitions[extra.id]=extra;world.residents.provision(world)
	check(world.actors.has(extra.id) and world.host_command(extra.id,{"intent":"dance"}).ok,"fifth resident works from data without identity branches")
	Save.save_world(world,directory);restored=World.new();restored.residents.definitions[extra.id]=extra;restored.library=loaded_library
	check(Save.load_world(restored,directory).ok and restored.actors.codex.name=="小雪" and restored.actors.has(extra.id),"custom name and data-defined resident survive restart")
	# Isolated room fixture checks door traversal independently of already-tested house construction.
	var room_world:=World.new();room_world.residents.provision(room_world)
	room_world.objects["home.house.01"].stage_index=5
	check(run_job(room_world,"human",{"intent":"enter","target_id":"home.house.01"}),"host enters room fixture")
	room_world.activities.gather()
	for tick in range(1800):
		room_world.advance(.1)
		if room_world.activities.gathering.get("phase")=="holding":break
	check(room_world.activities.members.size()==4 and room_world.activities.members.values().all(func(m):return m.arrived),"gather finds alternate rows when host stands at indoor entrance")
	check(room_world.actors.values().all(func(a):return a.region_id==room_world.actors.human.region_id),"all residents use normal house door to join indoor gathering")
	print("Recreation and assembly: %s checks, %s"%[checks,"FAIL" if failed else "PASS"]);quit(1 if failed else 0)
