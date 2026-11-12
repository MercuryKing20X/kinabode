extends SceneTree
const F = preload("res://tests/cooking_fixture.gd")
const B = preload("res://tests/backpack_fixture.gd")
const Fish = preload("res://tests/fishing_fixture.gd")
const Save = preload("res://scripts/save_store.gd")
const Library = preload("res://scripts/character_library.gd")
const BBQ=preload("res://tests/barbecue_fixture.gd")
var checks := 0
var failed := false
var directory: String
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failed = true; push_error(label)
func reload_world(world: RefCounted, name: String) -> RefCounted:
	check(Save.save_world(world,directory.path_join(name)), "save " + name)
	var next := F.fresh(); next.library = world.library
	check(Save.load_world(next,directory.path_join(name)).ok, "load " + name)
	next.director.set_all_enabled(false); return next
func run() -> void:
	directory = OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"): quit(1); return
	tree_and_collect(); loads_and_save(); construction(); cooking(); legacy()
	print("Backpack: %s checks, failed=%s" % [checks,failed]); quit(1 if failed else 0)
func tree_and_collect() -> void:
	var world := F.fresh(); var host: Dictionary = world.actors.human.duplicate(true)
	check(world.work.CARRY_LIMIT == 20, "one fixed capacity is twenty")
	check(F.job(world,"codex",{"intent":"chop","target_id":"home.tree.01"}), "real tree chopped and hauled")
	var pickups := 0; var deposits := 0
	for event in world.work.visual_events:
		if event.kind == "pickup": pickups += 1
		if event.kind == "deposit": deposits += 1
	check(pickups == 1 and deposits == 1 and B.wood_total(world) == 3 and world.drops.is_empty(), "three wood reaches storage in exactly one pickup and deposit")
	check(world.actors.human == host, "companion work never controls human")
	check(world.command("codex",{"intent":"chop","target_id":"home.tree.02"}).ok, "second genuine tree starts")
	for tick in range(10000):
		world.advance(.1)
		if not world.drops.is_empty(): break
	world.command("codex",{"intent":"stop"})
	var drop_id: String = world.drops.keys()[0]
	check(B.wood_total(world) == 6 and world.drops[drop_id].wood == 3, "cancel before pickup preserves real drop")
	check(world.command("codex",{"intent":"collect","target_id":drop_id}).ok, "explicit player collects three from ground")
	check(B.held(world,"codex",3) and world.drops.is_empty(), "ground pickup retains exact current tree yield and consumes entire drop")
	world = reload_world(world,"ground-carry")
	check(world.actors.codex.carry.get("wood") == 3 and world.work.jobs.is_empty() and B.wood_total(world) == 6, "reload retains full three and starts no work")
	check(F.job(world,"codex",{"intent":"store"}) and B.wood_total(world) == 6, "explicit storage after reload conserves wood")
func loads_and_save() -> void:
	var world := F.fresh()
	check(B.wood(world,16) and B.wood_total(world) == 48, "genuine wood for independent resident loads")
	check(F.job(world,"human",{"intent":"take","target_id":"home.chest.01"}), "player takes from actual chest")
	check(world.actors.human.carry.get("wood") == 20 and world.work.carry_space("human") == 0, "chest take fills twenty")
	check(transfer_to_companion(world,20) and world.actors.codex.carry.get("wood") == 20, "second resident independently holds twenty")
	check(not world.command("human",{"intent":"take","target_id":"home.chest.01"}).ok and B.wood_total(world) == 48, "twenty-first item rejected without chest or carry loss")
	var snapshot: Dictionary = world.observe("human")
	check(snapshot.self.carry_limit == 20 and snapshot.residents.all(func(actor):return actor.carry_limit == 20), "all observed resident capacities agree")
	check(not world.actors.human.has("carry_limit"), "capacity is read-only snapshot data, not per-resident state")
	world = reload_world(world,"twenty")
	check(world.actors.human.carry.is_empty() and world.actors.codex.carry.get("wood") == 20 and world.storage.count("wood")==28 and B.wood_total(world) == 48, "schema7 reload normalizes host carry into warehouse and preserves companion full twenty")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("twenty/island-v2.json")))
	check(data.schema_version == 7 and not data.actors.human.has("carry_limit") and not data.has("backpack"), "no schema bump or backpack save fields")
	# Reallocate real stored units in a serialized fixture to check total across item types.
	var mixed: Dictionary = data.duplicate(true)
	mixed.actors.human.carry.wood -= 1; mixed.storage.items.wood += 1
	mixed.storage.items["seed.turnip"] -= 1
	mixed.actors.human.carry["seed.turnip"] = 1
	Fish.write_json(directory.path_join("mixed/island-v2.json"),mixed)
	var mixed_world := F.fresh()
	check(Save.load_world(mixed_world,directory.path_join("mixed")).ok and mixed_world.work.carry_space("human")==20 and mixed_world.actors.human.carry.is_empty() and mixed_world.storage.count("seed.turnip")==world.storage.count("seed.turnip") and B.wood_total(mixed_world)==48, "nineteen wood and one real seed share total twenty capacity")
	mixed.storage.items.wood -= 1; mixed.actors.human.carry.wood += 1
	Fish.write_json(directory.path_join("mixed-overflow/island-v2.json"),mixed)
	check(not Save.load_world(F.fresh(),directory.path_join("mixed-overflow")).ok, "twenty wood plus one seed rejected, not twenty per item type")
	# Move one genuinely stored unit in the invalid save fixture: no material creation.
	data.storage.items.wood -= 1; data.actors.human.carry.wood += 1
	Fish.write_json(directory.path_join("overflow/island-v2.json"),data)
	var rejected: Dictionary = Save.load_world(F.fresh(),directory.path_join("overflow"))
	check(not rejected.ok and FileAccess.file_exists(rejected.get("backup","")), "twenty-one rejected by save validator with recoverable copy")
	check(world.deposit_all("human").ok and world.actors.human.carry.is_empty() and B.wood_total(world)==48,"unlimited warehouse accepts all twenty without partial loss")
	check(world.deposit_all("codex").ok and B.wood_total(world)==48,"second genuine carried load conserved")

func construction() -> void:
	var world := F.fresh(); var library := Library.new(); library.configure(directory); world.library = library
	for batch in range(6):
		if B.wood_total(world)>=129:break
		check(B.wood(world,int(ceil((129-B.wood_total(world))/3.0))),"real remaining construction trees")
		if B.wood_total(world)<129:world.advance(float(world.forest.settings.mature_seconds)+1)
	check(B.wood_total(world)==129,"real building supply129")
	check(world.command("human",{"intent":"select_blueprint","target_id":"home.house.01","blueprint_id":"cottage-large"}).ok, "existing large house supplies a stage above twenty")
	check(world.command("codex",{"intent":"build","target_id":"home.house.01"}).ok,"forty wood construction starts directly from warehouse")
	world.advance(.1);world.command("codex",{"intent":"stop"})
	check(B.wood_total(world)==129 and world.actors.codex.carry.is_empty(),"cancel direct warehouse construction preserves material investments")
	for stage in range(5):
		if world.objects["home.house.01"].stage_index<5:check(F.job(world,"codex",{"intent":"build","target_id":"home.house.01"}),"construct real large house stage")
	check(B.wood_total(world)==129,"large-house warehouse investment conserved")

func cooking()->void:
	var world:=F.fresh()
	for n in range(8):check(F.harvest(world,"turnip"),"genuine planted watered matured turnips")
	check(F.amount(world,"turnip")==24,"twenty-four real turnips ready")
	check(world.take_storage_host("turnip",mini(20,world.storage.count("turnip"))).ok and world.actors.human.carry.get("turnip")==20,"real farm pickup uses fixed twenty")
	var human:Dictionary=world.actors.human.duplicate(true)
	check(not world.command("codex",{"intent":"cook","recipe_id":"turnip-soup"}).ok and world.actors.human==human and F.amount(world,"turnip")==24,"removed cooking cannot steal the player's twenty real items")
	world=reload_world(world,"raw-twenty")
	check(world.actors.human.carry.is_empty() and world.storage.count("turnip")==24 and F.amount(world,"turnip")==24 and world.work.jobs.is_empty(),"raw twenty and other four survive reload without inferred servings")
	check(world.deposit_all("human").ok and F.amount(world,"turnip")==24,"explicit return conserves real produce")
	# Valid temporary cost fixture; fixed production recipes and capacity remain unchanged.
	world.recipes.recipes["turnip-soup"].ingredients.turnip=24
	world.recipes.recipe_catalog["turnip-soup"].ingredients.turnip=24
	check(BBQ.start(world,"recipe:turnip-soup",["human","codex"]).ok,"host explicitly authorizes a real twenty-four-item recipe debit")
	check(F.amount(world,"turnip")==0 and world.life.fireside.state.current.receipt.turnip==24 and world.life.item_count(world.actors.human.carry)<=20,"remote authorized debit consumes exact twenty-four without creating an oversized carry")
	check(BBQ.finish(world,["human","codex"]),"actual diners finish the temporary exact-cost recipe")
	check(world.life.fireside.state.current.eaten==2 and world.life.fireside.state.current.wasted==1 and world.life.station.portions==0,"recipe output is exactly eaten plus waste")
	world=F.fresh()
	for n in range(7):check(F.harvest(world,"turnip"),"real race produce")
	check(world.take_storage_host("turnip",mini(20,world.storage.count("turnip"))).ok and world.actors.human.carry.get("turnip")==20,"actual player pickup wins source with twenty")
	var actor:Dictionary=world.actors.human.duplicate(true)
	check(not world.command("codex",{"intent":"cook","recipe_id":"turnip-soup"}).ok and F.amount(world,"turnip")==21 and world.actors.human==actor and world.life.station.portions==0,"removed chef cannot appropriate twenty-one real units or invent a meal")
func legacy() -> void:
	var world := F.fresh()
	for n in range(2): check(F.harvest(world,"turnip"), "real six for legacy fixture")
	check(world.take_storage_host("turnip",mini(20,world.storage.count("turnip"))).ok and world.actors.human.carry.get("turnip") == 6, "legacy six-item carry is genuine")
	check(Save.save_world(world,directory.path_join("legacy")), "save legacy fixture")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("legacy/island-v2.json")))
	for key in ["cooking","journal","day_cycle"]: data.erase(key)
	Fish.write_json(directory.path_join("legacy/island-v2.json"),data)
	var old := F.fresh()
	check(Save.load_world(old,directory.path_join("legacy")).ok and old.actors.human.carry.is_empty() and old.storage.count("turnip")==6 and F.amount(old,"turnip") == 6, "old schema7 missing optional fields loads without migration or gifts")
	check(old.work.carry_space("human") == 20 and old.days.day() == 1 and old.life.fireside.state.is_empty(), "old carry immediately has fixed twenty capacity")
	check(old.deposit_all("human").ok, "store old carry through real action")
	check(B.wood(old,8), "real wood gathered in loaded old world")
	check(old.take_storage_host("wood",20).ok and old.actors.human.carry.get("wood") == 20 and F.amount(old,"wood") == 24 and F.amount(old,"turnip") == 6, "old world takes twenty, keeps four in storage and preserves original six produce")

func transfer_to_companion(world:RefCounted,amount:int)->bool:
	# Serialized fixture reallocates real warehouse units to another independent carry.
	if not world.storage.take({"wood":amount}).ok:return false
	world.actors.codex.carry["wood"]=amount
	return true
