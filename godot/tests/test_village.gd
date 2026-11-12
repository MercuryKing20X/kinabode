extends SceneTree
const World = preload("res://scripts/world_state.gd")
const Farms = preload("res://scripts/farm_system.gd")
const Save = preload("res://scripts/save_store.gd")
const Library = preload("res://scripts/character_library.gd")
var checks := 0
var failed := false
func check(value: bool, label: String) -> void:
	checks+=1
	if not value: failed=true; push_error(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var directory := OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"): quit(1); return
	var world:=World.new()
	var old:=Farms.new(world,"res://content/farms-v1.json")
	world.farms=old
	# Exercise a genuine v1 planted crop and then migrate its save to compact v2.
	var seed_before:int=world.storage.count("seed.turnip")
	check(world.command("codex",{"intent":"plant","target_id":"farm.home.plot.01","crop_id":"turnip"}).ok,"legacy crop planted by actual action")
	for tick in range(1000):
		world.advance(.1)
		if not world.work.jobs.has("codex"): break
	check(Save.save_world(world,directory),"legacy progress saved")
	var migrated:=World.new()
	check(Save.load_world(migrated,directory).ok,"v1 layout upgrades without invalidating save")
	check(migrated.farms.plots.size()==48 and migrated.farms.plots["farm.home.plot.01"].crop_id=="turnip","upgrade retains living crop and opens eighteen empty plots")
	check({"id":"storage","items":migrated.storage._items,"capacity":9007199254740991,"kind":"storage","region_id":"home","position":migrated.actors.human.position}.items["seed.turnip"]==seed_before-1,"layout upgrade never refills stock")
	var farm=migrated.farms.farms["farm.east"]
	check(farm.grid==[4.0,3.0] and farm.spacing==[2.8,2.4],"all farms use compact four-by-three geometry")
	var once: Dictionary=migrated.farms.saved().duplicate(true);migrated.farms.restore(once)
	check(migrated.farms.saved().plots==once.plots and migrated.storage.count("seed.turnip")==seed_before-1,"repeat load keeps same stock and plot identities")
	world=World.new();world.village.provision();world.village.enabled=true;world.village.rng.seed=20
	# The legacy patrol probe must seed the actual director, not its retired RNG.
	world.world_id="00000000-0000-4000-8000-000000000020";world.weather.weather_seed=1027
	for id in world.village.ids(): world.director.routines[id].rng.seed=20+world.village.ids().find(id)
	check(world.actors.size()==4 and world.village.ids().size()==2,"two ambient villagers added separately from model companions")
	var starts: Dictionary={}
	for id in world.village.ids(): starts[id]=world.actors[id].position.duplicate()
	var human: Array=world.actors.human.position.duplicate()
	var walked: Dictionary={};var dry:=true
	for tick in range(700):
		world.advance(.1)
		for id in world.village.ids():
			if world.actors[id].position != starts[id]: walked[id]=true
			dry=dry and world.walkable("home",world.point(world.actors[id]))
	check(walked.size()==2 and dry,"every villager uses real valid routes around farms")
	check(world.actors.human.position==human and world.work.jobs.is_empty(),"ambient villagers never take human control or create jobs")
	check(world.command("npc.mira",{"intent":"chop","target_id":"home.tree.01"}).ok and world.work.jobs.has("npc.mira"),"explicit command authorizes existing resident work capability")
	world.command("npc.mira",{"intent":"stop"})
	check(world.command("human",{"intent":"assign_farm","farm_id":"farm.home","manager_id":"npc.mira"}).ok and world.farms.farms["farm.home"].manager_id=="npc.mira","host explicitly assigns farm to an existing work-capable resident")
	for i in range(2,6): check(world.add_companion("companion-%s"%i,"伙伴"),"ambient crowd does not consume model slots")
	check(Save.save_world(world,directory),"save all residents")
	var restored:=World.new();check(Save.load_world(restored,directory).ok and restored.actors.size()==8,"five model slots plus two NPCs survive load")
	var endpoint: Node=load("res://scripts/read_endpoint.gd").new();root.add_child(endpoint);endpoint.configure(world,directory)
	check(endpoint.bindings.size()==5 and endpoint.bindings.values().all(func(id):return world.actors[id].role=="companion"),"only model residents receive API connections")
	endpoint.queue_free();await process_frame
	# White-haired companion starts walking promptly, even while her crops are waiting.
	world=World.new();world.activities.default_follow_excluded["codex"]=true;world.local_companion.rng.seed=42;world.local_companion.set_enabled(true)
	world.local_companion.set_chatter(false)
	var initial: Array=world.actors.codex.position.duplicate();var movements:=0
	var walk_diag:Dictionary={}
	var last: Array=initial
	for tick in range(400):
		world.advance(.1)
		var key:String=world.local_companion.kind+":"+str(world.actors.codex.activity)
		walk_diag[key]=int(walk_diag.get(key,0))+1
		if world.actors.codex.position!=last: movements+=1
		last=world.actors.codex.position.duplicate()
	if movements<=30:print("VILLAGE_WALK_DIAG movements=",movements," frames=",walk_diag," point=",world.actors.codex.position," initial=",initial," routine=",world.local_companion.state()," kind=",world.local_companion.kind," elapsed=",world.local_companion.elapsed," duration=",world.local_companion.duration," next=",world.local_companion.next_decision," time=",world.local_companion.time," route=",world._routes.get("codex")," preferences=",world.local_companion.preferences," recent=",world.local_companion.recent_behaviors," blocked=",world.local_companion.blocked()," follows=",world.activities.following," commanded=",world.activities.commanded("codex")," speed=",world.movement_speed("codex")," weather=",world.weather.current())
	check(movements>30,"Codex visibly walks during a forty-second idle period")
	world.local_companion.set_held(true);initial=world.actors.codex.position.duplicate()
	for tick in range(60):world.advance(.1)
	check(world.actors.codex.position==initial,"real conversation holds ambient walking")
	world.local_companion.set_held(false)
	world.command("codex",{"intent":"stop"});initial=world.actors.codex.position.duplicate()
	for tick in range(300):world.advance(.1)
	check(world.actors.codex.position==initial,"explicit stop still wins over idle behavior")
	# Filling is a bounded task, so grown plants stay visible instead of being harvested away.
	world=World.new()
	check(world.command("codex",{"intent":"manage_farm","farm_id":"farm.home","crop_id":"mixed","mode":"plant"}).ok,"mixed planting-only task accepted")
	for tick in range(8000):
		world.advance(.1)
		if not world.farms.active("codex"):break
	check(world.farms.orders.codex.status=="completed" and world.farms.farm_plots("farm.home").all(func(p):return not p.crop_id.is_empty() and p.watered),"fills all twelve plots and stops after watering")
	world.advance(90000)
	check(world.farms.farm_plots("farm.home").all(func(p):return world.farms.stage(p)=="mature") and world.farms.farms["farm.home"].harvested==0,"plant-only never auto-harvests the full field")
	var library:=Library.new();library.configure(directory)
	var silhouettes: Array=[]
	for id in ["blue-haired-girl","orange-haired-girl","black-scarf-girl"]:
		check(library.valid(library.artworks[id]),"unique editable resident artwork "+id)
		var art: Dictionary=library.artworks[id]
		var mask: Array=art.frames.down_0[0].pixels.map(func(pixel):return 0 if pixel==0 else 1)
		check(mask not in silhouettes,"distinct silhouette rather than palette-only duplicate "+id);silhouettes.append(mask)
		check(art.frames.left_1[0].pixels!=art.frames.left_2[0].pixels,"real alternating walking frames "+id)
	print("Village and compact farms: %s checks, %s"%[checks,"FAIL" if failed else "PASS"]);quit(1 if failed else 0)
