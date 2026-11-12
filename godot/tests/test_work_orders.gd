extends SceneTree
const World = preload("res://scripts/world_state.gd")
const Library = preload("res://scripts/character_library.gd")
const Save = preload("res://scripts/save_store.gd")
var checks := 0
var failed := false
var world: RefCounted
var directory: String
class BlockedWorld extends World:
	var sealed_ids: Array = []
	func approach_route(actor_id: String, target: Dictionary) -> Array[Vector2]:
		if target.get("id") in sealed_ids: return []
		return super.approach_route(actor_id, target)
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failed = true; push_error(label)
func finish(actor: String) -> void:
	for tick in range(16000):
		if not world.work.jobs.has(actor): return
		world.advance(.2)
	check(false, "task timeout " + str(world.work.jobs.get(actor)))
func run_job(actor: String, args: Dictionary) -> bool:
	var result: Dictionary = world.command(actor, args)
	check(result.ok, "accepted " + str(args) + str(result))
	if result.ok: finish(actor)
	return result.ok
func total_wood() -> int:
	var amount := 0
	for actor in world.actors.values(): amount += int(actor.carry.get("wood", 0))
	for drop in world.drops.values(): amount += int(drop.wood)
	for item in [{"id":"storage","items":world.storage.saved().items,"capacity":9007199254740991,"kind":"storage"}]: amount += int(item.items.get("wood", 0))
	for item in world.objects.values():
		if item.kind == "construction_site": amount += int(item.get("invested", 0)) + int(item.delivered.get("wood", 0))
	return amount
func _initialize() -> void: call_deferred("run")
func run() -> void:
	directory = OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"): quit(1); return
	world = World.new(); world.residents.provision(world);world.director.set_all_enabled(false); var library := Library.new(); library.configure(directory); world.library = library
	# Small valid blueprints isolate exact partial contributions. Each current three-tree batch yields9;
	# keep one genuine surplus in a third independent backpack, leaving8 for the original1/2/9/10 scenario.
	for plan in [["cottage", 5, 5], ["cottage-blue", 5, 8]]:
		var art: Dictionary = library.artworks[plan[0]].duplicate(true)
		art.structure.width = plan[1]; art.structure.depth = plan[2]
		check(library.publish(art, int(art.revision)).ok, "publish real blueprint")
	run_job("human", {"intent": "select_blueprint", "target_id": "home.house.01", "blueprint_id": "cottage"})
	run_job("human", {"intent": "select_blueprint", "target_id": "home.house.02", "blueprint_id": "cottage-blue"})
	run_job("codex", {"intent":"gather_wood","tree_count":3,"zone_id":"home.forest"})
	check(world.storage.take({"wood":1}).ok,"reserve one genuinely harvested surplus wood")
	world.actors["companion-2"].carry["wood"]=int(world.actors["companion-2"].carry.get("wood",0))+1
	run_job("human", {"intent": "build", "target_id": "home.house.01"})
	run_job("human", {"intent":"take"})
	check(world.actors.human.carry == {"wood": 1}, "harvest minus seven-wood foundation leaves one real wood")
	if not run_job("human", {"intent": "build", "target_id": "home.house.02"}):
		print("Reproduced partial-delivery rejection"); quit(1); return
	check(world.objects["home.house.02"].delivered == {"wood": 1}, "one wood physically delivered without requiring all ten")
	run_job("codex", {"intent":"gather_wood","tree_count":3,"zone_id":"home.forest"})
	check(world.storage.take({"wood":1}).ok,"reserve one genuinely harvested surplus wood")
	world.actors["companion-2"].carry["wood"]=int(world.actors["companion-2"].carry.get("wood",0))+1
	# Reallocate the same harvested eight units into independent carry fixtures;
	# warehouse supply no longer has a cancellable load route.
	check(world.storage.take({"wood":8}).ok,"allocate only genuinely harvested warehouse wood")
	world.actors.human.carry={"wood":7};world.actors.codex.carry={"wood":1}
	check(world.actors.codex.carry == {"wood": 1}, "second resident holds one real independent wood")
	check(world.command("codex", {"intent": "build", "target_id": "home.house.02"}).ok,"direct contribution accepted")
	check(int(world.objects["home.house.02"].delivered.get("wood",0))==2,"acceptance commits the exact one carried wood")
	world.command("codex", {"intent": "stop"})
	check(world.actors.codex.carry.is_empty() and world.work.claims.is_empty(),"cancel keeps exact site investment and releases plot")
	var site: Dictionary = world.objects["home.house.02"]
	check(site.delivered == {"wood": 2} and site.stage_index == 0 and world.actors.codex.carry.is_empty(), "1/10 plus one delivered becomes2/10; no premature construction")
	check(world.objects["home.house.02"].stage_index==0,"partial investment does not finish house")
	check(total_wood() == 18, "partial delivery conserves all harvested wood")
	check(Save.save_world(world, directory), "save partial investment")
	var restored := World.new(); restored.library = library
	check(Save.load_world(restored, directory).ok, "reload partial investment")
	world = restored; site = world.objects["home.house.02"]
	check(int(site.delivered.get("wood", 0)) == 2 and world.work.jobs.is_empty() and total_wood() == 18, "reload preserves exact contribution and held wood")
	run_job("human", {"intent": "build", "target_id": "home.house.02"})
	check(site.delivered == {"wood": 9} and site.stage_index == 0, "second contribution reaches9/10 and waits")
	run_job("codex", {"intent":"gather_wood","tree_count":3,"zone_id":"home.forest"})
	check(world.storage.take({"wood":1}).ok,"reserve one genuinely harvested surplus wood")
	world.actors["companion-2"].carry["wood"]=int(world.actors["companion-2"].carry.get("wood",0))+1
	run_job("human", {"intent":"take"})
	var expected_surplus:int=int(world.actors.human.carry.get("wood",0))-(10-int(site.delivered.get("wood",0)))
	run_job("human", {"intent": "build", "target_id": "home.house.02"})
	check(site.stage_index == 1 and site.invested == 10 and site.delivered.is_empty(), "last needed wood completes only the funded stage")
	check(world.actors.human.carry == {"wood": expected_surplus} and total_wood() == 27, "surplus held wood is preserved")
	world = World.new()
	var start: Dictionary = world.command("codex", {"intent": "gather_wood", "target_id": "home.tree.01", "tree_count": 3})
	check(start.ok, "multi-tree order accepted")
	if not start.ok: print("Reproduced missing multi-tree order"); quit(1); return
	finish("codex")
	check(world.objects.values().filter(func(o): return o.kind == "tree" and o.status in ["stump", "sapling"]).size() == 3 and total_wood() == 9, "one job physically harvests and stores three trees")
	check(world.drops.is_empty() and world.actors.codex.carry.is_empty(), "all three trees hauled completely")
	check(world.work.events[-1].job_id == start.job_id and world.work.events[-1].progress.trees_completed == 3, "all trees share one accepted job and accurate completion")
	check(world.work.events.filter(func(event): return event.status == "progress" and event.get("progress",{}).has("trees_completed")).size() == 3, "progress follows completed hauling")
	for object in world.objects.values():
		if object.kind == "tree" and object.status in ["stump", "sapling"]: check(object.zone_id == "home.forest", "default order stays within starting resource zone")
	world = World.new()
	for args in [{"intent":"gather_wood", "tree_count":0}, {"intent":"gather_wood", "tree_count":1.5}, {"intent":"gather_wood", "tree_count":NAN}, {"intent":"gather_wood", "tree_count":101}, {"intent":"gather_wood", "actor_id":"human"}, {"intent":"gather_wood", "zone_id":"moon.forest"}, {"intent":"gather_wood", "target_id":"home.tree.01", "zone_id":"home.north_grove"}]:
		check(not world.command("codex", args).ok and world.work.jobs.is_empty(), "invalid order has no job " + str(args))
	var human_start: Array = world.actors.human.position.duplicate()
	check(world.command("codex", {"intent":"gather_wood", "target_id":"home.tree.01"}).ok, "unbounded order starts")
	var second_started := false
	for tick in range(16000):
		world.advance(.15)
		if world.work.jobs.has("codex") and world.work.jobs.codex.trees_completed >= 2 and world.work.jobs.codex.phase == "chop": second_started = true; break
	check(second_started and world.actors.human.position == human_start, "default order continues beyond one tree without controlling human")
	var before_stop := total_wood()
	world.command("codex", {"intent":"stop"})
	for tick in range(100): world.advance(.2)
	check(not world.work.jobs.has("codex") and world.work.claims.is_empty() and total_wood() == before_stop, "stop cancels future tree selection immediately")
	check(world.work.events[-1].status == "cancelled", "continuous stop is visible")
	world = World.new()
	check(world.command("codex", {"intent":"gather_wood", "target_id":"home.tree.01", "tree_count":3}).ok, "cancellable transport order starts")
	for tick in range(16000):
		world.advance(.1)
		if int(world.actors.codex.carry.get("wood",0)) == int(world.forest.settings.normal_wood): break
	check(total_wood() == 3 and world.drops.is_empty(), "whole tree in hands before interruption")
	world.command("codex", {"intent":"stop"})
	check(Save.save_world(world, directory.path_join("gather")), "save stopped harvesting")
	var resumed := World.new()
	check(Save.load_world(resumed, directory.path_join("gather")).ok, "reload stopped harvesting")
	world = resumed
	check(world.work.jobs.is_empty() and world.work.claims.is_empty() and total_wood() == 3, "reload never restarts an order or loses carried materials")
	run_job("codex", {"intent":"gather_wood", "zone_id":"home.forest", "tree_count":1})
	check(total_wood() == 6 and world.drops.is_empty() and world.actors.codex.carry.is_empty(), "new order stores held wood and reclaims old drop before harvesting another tree")
	world = World.new()
	check(world.command("codex", {"intent":"gather_wood", "tree_count":2, "zone_id":"home.forest"}).ok, "first resident order")
	check(world.command("human", {"intent":"gather_wood", "tree_count":2, "zone_id":"home.forest"}).ok, "second independent resident order")
	world.advance(.1)
	check(world.work.jobs.codex.target_id != world.work.jobs.human.target_id and world.work.claims.size() == 2, "simultaneous residents reserve different current trees")
	finish("codex"); finish("human")
	check(total_wood() == 12 and world.work.claims.is_empty(), "concurrent orders each fully haul two trees")
	# Capacity-only fixtures use real harvested wood, never injected inventory.
	world = World.new()
	check(not world.storage.saved().has("capacity"),"system warehouse has no capacity field")
	run_job("codex", {"intent":"gather_wood", "zone_id":"home.forest","tree_count":2})
	check(total_wood() == 6 and world.drops.is_empty() and world.actors.codex.carry.is_empty(), "unlimited system warehouse stores both actual three-wood trees")
	check(world.work.events[-1].status == "completed", "full storage reports actual reason")
	world = World.new()
	check(not world.storage.saved().has("capacity"),"single unlimited warehouse replaces split chest capacity")
	run_job("codex", {"intent":"gather_wood", "tree_count":1, "target_id":"home.tree.01"})
	check(total_wood() == 3 and world.drops.is_empty() and world.actors.codex.carry.is_empty(), "one actual three-wood bundle enters the single unlimited warehouse")
	var blocked := BlockedWorld.new(); world = blocked
	blocked.sealed_ids = ["home.tree.01"]
	run_job("codex", {"intent":"gather_wood", "tree_count":1, "target_id":"home.tree.01"})
	check(world.objects["home.tree.01"].status == "mature" and total_wood() == 3, "skip inaccessible tree and choose another in same zone")
	world = BlockedWorld.new()
	for tree in world.objects.values():
		if tree.kind == "tree": world.sealed_ids.append(tree.id)
	run_job("codex", {"intent":"gather_wood", "zone_id":"home.forest"})
	check(total_wood() == 0 and world.work.events[-1].status == "blocked" and world.work.events[-1].message.contains("走不到"), "no accessible targets stops without fabricating work")
	world = World.new()
	run_job("codex", {"intent":"gather_wood", "zone_id":"home.garden"})
	check(world.work.events[-1].message.contains("没有可砍的树") and total_wood() == 0, "empty zone ends explicitly")
	world = World.new(); world.library = library
	run_job("codex", {"intent":"gather_wood", "tree_count":14, "zone_id":"home.forest"})
	for i in range(5): run_job("codex", {"intent":"build", "target_id":"home.house.01"})
	run_job("codex", {"intent":"enter", "target_id":"home.house.01"})
	check(world.actors.codex.region_id == "room.home.house.01", "resident actually inside before forestry request")
	run_job("codex", {"intent":"gather_wood", "tree_count":1, "zone_id":"home.forest"})
	check(world.actors.codex.region_id == "home" and total_wood() == 45, "one forestry order exits house and harvests without a second model request")
	var game: Node = load("res://scenes/main.tscn").instantiate(); root.add_child(game)
	game.save_enabled = false; game.set_process(false); game.view.sound_enabled = false
	game.world.local_companion.set_enabled(false)
	game.house_panel.open_site("home.house.02")
	check(game.house_panel.materials.text.contains("2 / 10") and game.house_panel.build_button.text == "交料 / 建造", "actual house panel displays persisted partial-stage progress")
	check(game.world.command("codex", {"intent":"gather_wood", "zone_id":"home.forest", "tree_count":2}).ok, "actual main controller has a continuous order")
	game.world.advance(.1); game._update_order_bar()
	check(game.order_bar.visible and game.order_label.text.contains("0 / 2"), "HUD displays authoritative order progress")
	game.order_bar.get_child(1).pressed.emit()
	check(not game.world.work.jobs.has("codex") and game.world.work.claims.is_empty() and not game.order_bar.visible and game.link._pid == -1, "visible stop button cancels work without starting a model")
	game.queue_free(); await process_frame
	print("Work orders: %s checks, %s" % [checks, "FAIL" if failed else "PASS"])
	quit(1 if failed else 0)
