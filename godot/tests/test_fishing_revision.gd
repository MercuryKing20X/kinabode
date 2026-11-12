extends SceneTree
const World=preload("res://scripts/world_state.gd")
var checks:=0
var failed:=false
func _initialize() -> void:call_deferred("run")
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failed=true;push_error(label)
func move_to(world: RefCounted,id: String,point: Array) -> bool:
	var result: Dictionary=world.command(id,{"intent":"move","x":point[0],"y":point[1]})
	if not result.ok:return false
	for i in range(2000):
		world.advance(.1)
		if not world._routes.has(id):return true
	return false
func finish(world: RefCounted,id: String) -> bool:
	for i in range(1200):
		world.advance(.1)
		if not world.work.jobs.has(id):return not preload("res://tests/fishing_fixture.gd").unplaced(world,id).is_empty()
	return false
func run() -> void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):quit(1);return
	var world:=World.new();world.director.set_all_enabled(false)
	check(world.error.is_empty(),"revision config loads "+world.error)
	if not world.error.is_empty():quit(1);return
	var position: Array=world.actors.human.position.duplicate()
	check(world.command("human",{"intent":"fish"}).get("error")=="not_near_sea" and world.actors.human.position==position,"inland click only prompts, never auto walks")
	var candidates: Array=world.fishing.nearby_shores("human")
	check(candidates.size()>2,"coast discovery returns natural shore candidates")
	check(move_to(world,"human",candidates[0].position),"real movement reaches ocean coast")
	position=world.actors.human.position.duplicate()
	check(world.command("human",{"intent":"fish"}).ok and not world._routes.has("human") and world.actors.human.position==position,"coastal click casts in place")
	check(finish(world,"human"),"actual sea catch commits")
	check(world.fishing.fish.values().filter(func(f):return f.owner_id=="human" and f.location=="storage")[0].source_id.begins_with("home.sea."),"catch source is sea, not fishery")
	print("Fishing revision: %s checks, %s"%[checks,"FAIL" if failed else "PASS"]);quit(1 if failed else 0)
