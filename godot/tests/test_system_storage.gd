extends SceneTree
const Storage = preload("res://scripts/system_storage.gd")
const F = preload("res://tests/cooking_fixture.gd")
const Save = preload("res://scripts/save_store.gd")
var failures := 0
var checks := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var directory := OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"): quit(1); return
	var ledger := Storage.new()
	check(ledger.add({"wood": 200001, "mushroom": 7}), "no old chest capacity limit")
	var before := ledger.saved()
	var rejected := ledger.take({"wood": 2, "mushroom": 8})
	check(not rejected.ok and rejected.missing == {"mushroom": 1} and ledger.saved() == before, "multi-item shortage is atomic and exact")
	check(ledger.take({"wood": 2, "mushroom": 7}).ok and ledger.count("wood") == 199999 and ledger.count("mushroom") == 0, "successful costs are exact")
	before = ledger.saved()
	check(not ledger.add({"wood": 1, "seed.turnip": -1}) and ledger.saved() == before, "invalid additions cannot partially commit")
	check(not ledger.take({"wood": -1}).ok and ledger.saved() == before, "negative costs cannot mint items")
	check(not ledger.add({"wood": 1.5}) and not ledger.add({"wood": true}) and not ledger.add({"wood": INF}), "fractional boolean and nonfinite quantities rejected")
	var detached := ledger.saved(); detached.items.wood = 0
	check(ledger.count("wood") == 199999, "save snapshots cannot mutate ledger")
	check(ledger.restore({"items": {"wood": 4.0}}) and ledger.count("wood") == 4, "JSON integer float equivalence")
	check(not ledger.restore({"items": {"wood": -1}}) and ledger.count("wood") == 4, "invalid restore preserves ledger")
	var world := F.fresh()
	check(world.storage.add({"wood": 33, "mushroom": 2}), "world owns the ledger")
	check(Save.save_world(world, directory), "save optional storage")
	var next := F.fresh()
	check(Save.load_world(next, directory).ok and next.storage.saved() == world.storage.saved(), "save reload conserves each storage quantity")
	var path := directory.path_join("island-v2.json")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	data.erase("storage")
	var file := FileAccess.open(path, FileAccess.WRITE); file.store_string(JSON.stringify(data)); file.close()
	check(Save.load_world(next, directory).ok and next.storage.saved() == {"items": {}}, "legacy absent field starts empty without grants or stale ledger")
	data["storage"] = {"items": {"wood": -1}}
	file = FileAccess.open(path, FileAccess.WRITE); file.store_string(JSON.stringify(data)); file.close()
	check(not Save.load_world(next, directory).ok, "invalid optional storage rejects entire save")
	print("System storage: %s checks, failures=%s" % [checks, failures])
	quit(0 if failures == 0 else 1)
