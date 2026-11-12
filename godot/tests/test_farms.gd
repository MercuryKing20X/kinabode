extends SceneTree
const World = preload("res://scripts/world_state.gd")
const Save = preload("res://scripts/save_store.gd")
const Library = preload("res://scripts/character_library.gd")
var checks := 0
var failed := false
var world: RefCounted
var directory := ""
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failed = true; push_error(label)
func job(actor: String, args: Dictionary) -> bool:
	var result: Dictionary = world.command(actor,args)
	check(result.ok,"accept "+str(args)+str(result))
	if not result.ok: return false
	for tick in range(12000):
		if not world.work.jobs.has(actor): return true
		world.advance(.1)
	check(false,"job timeout "+str(args)); return false
func finish_order(actor: String) -> void:
	for tick in range(24000):
		if not world.farms.active(actor): return
		world.advance(.2)
	check(false,"order timeout "+str(world.farms.orders[actor]))
func total(item: String) -> int:
	var count := 0
	count += world.storage.count(item)
	for actor in world.actors.values(): count += int(actor.carry.get(item,0))
	return count
func run() -> void:
	directory=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"): quit(1); return
	world=World.new(); var library:=Library.new(); library.configure(directory); world.library=library
	check(world.error.is_empty(),"catalog loads with eastern coast extension")
	check(world.farms.farms.size()==4 and world.farms.plots.size()==48,"four working farms, forty-eight fixed plots")
	for plot in world.farms.plots.values(): check(world.can_approach("human",plot),"reachable plot "+plot.id)
	for chest in world.farms.containers.values(): check(world.can_approach("human",chest),"reachable chest "+chest.id)
	check(world.observe("codex").farming.farms.size()==4,"AI observes farm IDs, permissions, crop stages, real boxes")
	check(world.observe("codex",{"object_id":"farm.home.plot.01"}).objects[0].kind=="farm_plot","inspect stable plot")
	check(not world.command("codex",{"intent":"plant","target_id":"farm.east.plot.01","crop_id":"turnip"}).ok,"manager cannot plant another farm")
	check(not world.command("codex",{"intent":"assign_farm","farm_id":"farm.east","manager_id":"codex"}).ok,"model cannot self-assign land")
	check(not world.command("human",{"intent":"plant","target_id":"home.tree.01","farm_id":"farm.home","crop_id":"turnip"}).ok,"arbitrary land cannot be planted")
	var seed_before:=total("seed.turnip")
	job("human",{"intent":"plant","target_id":"farm.home.plot.01","crop_id":"turnip"})
	check(total("seed.turnip")==seed_before-1,"plant consumes exactly one physical seed")
	world.advance(4000)
	check(world.farms.stage(world.farms.plots["farm.home.plot.01"])=="dry","initial watering required; dry planted seed preserved")
	job("human",{"intent":"water","target_id":"farm.home.plot.01"})
	world.advance(600)
	check(world.farms.stage(world.farms.plots["farm.home.plot.01"])=="growing","growth uses crop-specific real seconds")
	world.advance(601)
	check(world.farms.stage(world.farms.plots["farm.home.plot.01"])=="mature","reaches maturity")
	var take: Dictionary=world.command("codex",{"intent":"harvest","target_id":"farm.home.plot.01"})
	check(take.ok and not world.command("human",{"intent":"harvest","target_id":"farm.home.plot.01"}).ok,"atomic claim prevents double harvesting")
	for tick in range(12000):
		world.advance(.1)
		if not world.work.jobs.has("codex") and not world.deliveries.active("codex"): break
	check(total("turnip")==3 and total("seed.turnip")==seed_before,"harvest yields three produce and one returned seed")
	check(world.actors.codex.carry.is_empty() and world.storage.count("turnip")==3,"actual harvest hauled into assigned output chest")
	check(not world.command("codex",{"intent":"farm_take","target_id":"farm.lake.seed","item_id":"seed.daisy"}).ok,"private container isolation")
	check(world.farms.containers.is_empty(),"legacy containers cannot bypass warehouse-only storage")
	check(not world.command("human",{"intent":"farm_meal","farm_id":"farm.home","item_id":"turnip"}).ok,"retired farm meal cannot bypass barbecue-only food")
	check(total("turnip")==3 and world.farms.memories.is_empty(),"removed farm meal consumes no actual harvest and invents no memory")
	# Stop between seed pickup and sowing; reload must retain the seed in hand.
	var before:=total("seed.tomato")
	check(world.command("human",{"intent":"plant","target_id":"farm.home.plot.02","crop_id":"tomato"}).ok,"start interruptible sowing")
	world.advance(.05)
	world.command("human",{"intent":"stop"})
	check(total("seed.tomato")==before and world.actors.human.carry.is_empty(),"stop never loses or duplicates picked seed")
	check(Save.save_world(world,directory),"save crop inventory")
	var restored:=World.new()
	check(Save.load_world(restored,directory).ok and restored.actors.human.carry.is_empty() and restored.storage.count("seed.tomato")==before,"schema six restores crop inventory and releases jobs")
	check(world.deposit_all("human").ok,"warehouse deposit replaces seed-box store")
	# Independent managers execute concurrently with no model polling.
	world.add_companion("companion-2","阿澄")
	job("human",{"intent":"assign_farm","farm_id":"farm.east","manager_id":"companion-2"})
	check(world.command("codex",{"intent":"manage_farm","farm_id":"farm.home","crop_id":"turnip","mode":"once"}).ok,"whole-farm order accepted")
	check(world.command("companion-2",{"intent":"manage_farm","farm_id":"farm.east","crop_id":"turnip","mode":"once"}).ok,"second identity starts its own farm")
	for tick in range(5000): world.advance(.2)
	check(world.farms.farm_plots("farm.home").all(func(p):return p.watered) and world.farms.farm_plots("farm.east").all(func(p):return p.watered),"both managers plant and water every plot")
	check(world.farms.orders.codex.status=="waiting" and world.work.jobs.is_empty(),"growth wait creates no job or model request")
	check(Save.save_world(world,directory),"save waiting orders")
	restored=World.new(); var loaded: Dictionary=Save.load_world(restored,directory)
	check(loaded.ok and restored.farms.orders.codex.status=="paused" and restored.work.jobs.is_empty(),"restart pauses persistent farm orders")
	world.advance(1300); finish_order("codex"); finish_order("companion-2")
	check(world.farms.orders.codex.status=="completed" and world.farms.orders["companion-2"].status=="completed","once stops after all harvest is stored")
	check(world.farms.farms["farm.east"].harvested==36,"twelve plots produce independently into eastern box")
	check(world.actors.human.carry.is_empty(),"AI never commandeers human carry")
	# Farm lifecycle, repeating crops, offline growth, full storage, and corrupt save.
	job("human",{"intent":"plant","target_id":"farm.hill.plot.01","crop_id":"apple"})
	job("human",{"intent":"water","target_id":"farm.hill.plot.01"})
	world.advance(86401)
	job("human",{"intent":"harvest","target_id":"farm.hill.plot.01"})
	check(world.farms.plots["farm.hill.plot.01"].crop_id=="apple" and world.farms.stage(world.farms.plots["farm.hill.plot.01"])!="mature","fruit tree remains and starts next batch only after harvest")
	var saved: Dictionary=world.farms.saved().duplicate(true)
	saved.clock=Time.get_unix_time_from_system()-90000
	for plot in saved.plots.values(): plot.planted_at=minf(float(plot.planted_at),saved.clock)
	restored.farms.restore(saved)
	check(restored.farms.stage(restored.farms.plots["farm.hill.plot.01"])=="mature","offline clock ripens already planted batch")
	var fruit_count:int=restored.storage.count("apple")
	for tick in range(5): restored.advance(90000)
	check(restored.storage.count("apple")==fruit_count,"offline time does not fabricate harvested fruit")
	var bad: Dictionary=world.farms.saved().duplicate(true);bad["containers"]={"legacy":{"items":{"seed.turnip":-1}}}
	check(not world.farms.valid_saved(bad,world.actors),"reject negative seed amounts")
	bad=world.farms.saved().duplicate(true);bad.plots["farm.home.plot.01"].crop_id="unknown"
	check(not world.farms.valid_saved(bad,world.actors),"reject corrupt crop IDs")
	for id in ["crop-turnip","crop-tomato","crop-pumpkin","crop-daisy","crop-blueberry","crop-apple"]: check(library.valid(library.artworks[id]),"editable growth work "+id)
	# Unlimited storage retains exact harvest and independent carry limits.
	world=World.new()
	job("human",{"intent":"plant","target_id":"farm.home.plot.01","crop_id":"turnip"})
	job("human",{"intent":"water","target_id":"farm.home.plot.01"})
	world.advance(1201)
	job("codex",{"intent":"harvest","target_id":"farm.home.plot.01"})
	for tick in range(12000):
		world.advance(.1)
		if not world.deliveries.active("codex"):break
	check(world.storage.count("turnip")==3,"warehouse accepts real harvested batch")
	check(total("turnip")==3 and world.actors.codex.carry.is_empty(),"warehouse batch conserved with no box capacity")
	check(world.life.item_count(world.actors.codex.carry)<=world.work.CARRY_LIMIT and world.work.claims.is_empty(),"bundle cap and claims survive storage")
	# Repeat reuses physical returned seeds after the starter seed box is exhausted.
	world=World.new()
	world.farms.farms["farm.home"].grid=[1,1]
	for id in world.farms.plots.keys():
		if world.farms.plots[id].farm_id=="farm.home" and id!="farm.home.plot.01": world.farms.plots.erase(id)
	world.storage.take({"seed.turnip":world.storage.count("seed.turnip")});world.storage.add({"seed.turnip":1})
	check(world.command("codex",{"intent":"manage_farm","farm_id":"farm.home","crop_id":"turnip","mode":"repeat"}).ok,"explicit continuous scope accepted")
	for tick in range(14000):
		world.advance(.2)
		if int(world.farms.plots["farm.home.plot.01"].harvests)>=2 and world.actors.codex.carry.is_empty(): break
	check(world.farms.plots["farm.home.plot.01"].harvests>=2 and total("turnip")==6,"continuous farming replants returned seed without model turns")
	world.command("codex",{"intent":"stop"})
	check(not world.farms.active("codex") and world.work.jobs.is_empty(),"stop cancels whole repeating plan")
	# Reassignment interrupts sowing without taking the seed away from the previous manager.
	world=World.new(); world.add_companion("companion-2","阿澄")
	world.command("codex",{"intent":"plant","target_id":"farm.home.plot.01","crop_id":"turnip"})
	for tick in range(4000):
		world.advance(.05)
		if world.work.jobs.has("codex"): break
	var seed_total:=total("seed.turnip")
	job("human",{"intent":"assign_farm","farm_id":"farm.home","manager_id":"companion-2"})
	check(total("seed.turnip")==seed_total and world.actors.codex.carry.is_empty() and not world.work.jobs.has("codex"),"manager reassignment stops old work without losing held seed")
	# Host reset archives only progress, retaining the editable artwork directory.
	check(Save.save_world(world,directory),"save before authorized new-world operation")
	var art: Dictionary=library.artworks["white-haired-girl"].duplicate(true)
	check(library.publish(art,int(art.revision)).ok,"persist original companion artwork")
	check(Save.archive_progress(directory),"host reset archives progress")
	var fresh:=World.new();check(not Save.load_world(fresh,directory).loaded and fresh.drops.is_empty(),"reset produces fresh actual world")
	var after:=Library.new();after.configure(directory)
	check(after.artworks["white-haired-girl"].revision==library.artworks["white-haired-girl"].revision,"reset preserves both character work storage")
	print("Farming: %s checks, %s"%[checks,"FAIL" if failed else "PASS"]); quit(1 if failed else 0)
