# DIRECTION 2026-11-07: 烤蘑菇永久无限供应，不扣任何食材；其它食材守恒断言保留。
extends SceneTree
const World = preload("res://scripts/world_state.gd")
const Library = preload("res://scripts/character_library.gd")
const Save = preload("res://scripts/save_store.gd")
const BBQ=preload("res://tests/barbecue_fixture.gd")
var failed := false
var checks := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failed = true; push_error(message)
func finish(world: RefCounted, actor: String) -> void:
	for i in range(6000):
		if not world.work.jobs.has(actor) and not world.deliveries.active(actor): return
		world.advance(.1)
	check(false, "job timeout")
func _initialize() -> void:
	var directory := OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"): quit(1); return
	var library := Library.new(); library.configure(directory)
	var world := World.new(); world.library = library
	for id in ["cottage", "cottage-large", "camp-grill"]: check(library.valid(library.artworks[id]), "valid shared editable work")
	var small: Dictionary = library.compile_blueprint("cottage")
	var large: Dictionary = library.compile_blueprint("cottage-large")
	check(small.wood == 60 and large.wood > small.wood, "structural cost differs")
	check(world.select_blueprint("home.house.01", "cottage").ok, "select saved plan")
	var pinned: int = world.objects["home.house.01"].blueprint.revision
	var draft: Dictionary = library.artworks.cottage.duplicate(true)
	draft.frames.stage_4[0].pixels[0] = 1
	check(library.publish(draft, int(draft.revision)).ok, "paint building")
	check(library.compile_blueprint("cottage").wood == small.wood, "color does not affect wood")
	check(world.objects["home.house.01"].blueprint.revision == pinned, "placed plan pinned")
	check(library.patch("cottage", {"base_revision": library.artworks.cottage.revision, "structure": {"width": 10, "depth": 8, "floors": 2, "porch": 1}}).ok, "AI can edit structure")
	check(library.compile_blueprint("cottage").wood > small.wood, "structure change updates quote")
	check(not world.observe("codex", {"object_id": "home.house.01"}).objects[0].blueprint.has("artwork"), "observation omits huge pixel payload")
	check(world.command("human", {"intent": "chop", "target_id": "home.tree.01"}).ok, "real harvest")
	finish(world, "human")
	check(world.deposit_all("human").ok,"host explicitly stores the real three wood in global warehouse")
	check(world.command("codex", {"intent": "forage", "target_id": "home.mushrooms.1"}).ok, "real forage")
	check(not world.command("human", {"intent": "forage", "target_id": "home.mushrooms.1"}).ok, "forage claim")
	finish(world, "codex")
	check({"id":"storage","items":world.storage._items,"capacity":9007199254740991,"kind":"storage","region_id":"home","position":world.actors.human.position}.items.mushroom == 4, "forage physically stored")
	var human:Dictionary=world.actors.human.duplicate(true)
	for intent in ["barbecue","turn_food","eat","cleanup"]:
		check(not world.command("codex",{"intent":intent,"target_id":"home.barbecue"}).ok,"removed manual preparation/eating is rejected: "+intent)
	check(world.actors.human==human and world.work.jobs.is_empty(),"removed local preparation never controls host")
	check(BBQ.approach(world),"host approaches real fire before inviting companion")
	check(world.command("codex",{"intent":"come_near"}).ok,"companion explicitly approaches host before shared eating timing")
	finish(world,"codex")
	check(world.life.fireside.light_host().ok,"host explicitly walks close and consumes real fuel")
	check({"id":"storage","items":world.storage._items,"capacity":9007199254740991,"kind":"storage","region_id":"home","position":world.actors.human.position}.items.wood==1 and world.life.station.fuel_used==2,"exactly two actual wood consumed and accounted")
	check(world.life.fireside.invite(["codex"]).ok and world.life.fireside.roast_host("single:mushroom").ok,"host selects actual ingredients and exact invited diner")
	check({"id":"storage","items":world.storage._items,"capacity":9007199254740991,"kind":"storage","region_id":"home","position":world.actors.human.position}.items.mushroom==4,"unlimited grilled mushrooms leave all four harvested ingredients untouched")
	check(not world.life.fireside.has_method("pack_host") and not world.life.fireside.has_method("resume_host"),"removed packing and old-batch resume APIs absent")
	var both:=false
	for tick in range(6000):
		world.advance(.1)
		if world.actors.human.activity=="fire_eat" and world.actors.codex.activity=="fire_eat":both=true
		if world.life.fireside.state.current.eaten==2:break
	check(both,"both actual diners share eating animation")
	check(world.life.station.meals_eaten==2 and world.life.station.portions==0,"each real diner consumes once")
	check(world.life.fireside.state.current.eaten+world.life.fireside.state.current.wasted==world.life.fireside.state.current.total,"cooked output conserved without leftovers")
	world.life.fireside.end_circle("host explicitly ends shared-life QA circle")
	check(world.work.jobs.is_empty() and world.work.claims.is_empty(),"ending circle releases exact activity jobs and seats")
	check(world.read_memories("human",{"kind":"shared_barbecue"}).total==1,"one actual completed gathering fact")
	check(Save.save_world(world,directory),"save completed outing")
	var again:=World.new();again.library=library
	check(Save.load_world(again,directory).ok and again.read_memories("human",{"kind":"shared_barbecue"}).total==1,"true completed gathering survives reopening")
	# A v2 save remains loadable, with new feature defaults instead of a world reset.
	var path := directory.path_join("island-v2.json")
	var legacy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	legacy.schema_version = 2; legacy.erase("shared_life")
	var file := FileAccess.open(path, FileAccess.WRITE); file.store_string(JSON.stringify(legacy)); file.close()
	var old := World.new(); old.library = library
	check(Save.load_world(old, directory).ok and old.world_id == world.world_id, "v2 migration preserves world")
	check({"id":"storage","items":old.storage._items,"capacity":9007199254740991,"kind":"storage","region_id":"home","position":old.actors.human.position}.items.wood == 1, "v2 migration preserves resources")
	print("Shared life: %s checks, %s" % [checks, "FAIL" if failed else "PASS"])
	quit(1 if failed else 0)
