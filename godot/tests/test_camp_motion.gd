extends SceneTree
const Places=preload("res://scripts/map_locations.gd")
const World = preload("res://scripts/world_state.gd")
const Save = preload("res://scripts/save_store.gd")
const Motion = preload("res://scripts/actor_motion.gd")
const Ambience = preload("res://scripts/environment_motion.gd")
const F=preload("res://tests/cooking_fixture.gd")
const BBQ=preload("res://tests/barbecue_fixture.gd")
var checks := 0
var failed := false
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failed = true; push_error(message)
func finish(world: RefCounted, id: String) -> void:
	for i in range(6000):
		if not world.work.jobs.has(id): return
		world.advance(.1)
	check(false, "timeout " + id)
func reach(world: RefCounted, phase: String) -> bool:
	for i in range(6000):
		world.advance(.05)
		if world.work.jobs.get("human", {}).get("phase") == phase and not world._routes.has("human"): return true
	return false
func _initialize() -> void:
	var directory := OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"): quit(1); return
	var world:=F.fresh()
	# Both different timestep partitions traverse the same route at 150px/s.
	var split := World.new()
	for w in [world, split]: w.command("human", {"intent": "move", "x":Places.point("p_57_0_44_0").x,"y":Places.point("p_57_0_44_0").y})
	var start: Vector2 = world.point(world.actors.human)
	world.advance(.1)
	for i in range(10): split.advance(.01)
	check(world.point(world.actors.human).distance_to(start) > .46 and world.point(world.actors.human).distance_to(start) < .48, "normal movement travels 15 pixels in .1 seconds")
	check(world.point(world.actors.human).distance_to(split.point(split.actors.human)) < .0001, "movement independent of timestep")
	world.command("human", {"intent": "stop"})
	world.command("human", {"intent": "chop", "target_id": "home.tree.01"}); finish(world, "human")
	world.command("codex", {"intent": "chop", "target_id": "home.tree.02"})
	for i in range(6000):
		world.advance(.05)
		if not world.actors.codex.carry.is_empty(): break
	world.command("codex", {"intent": "stop"})
	world.command("codex", {"intent": "store"})
	start = world.point(world.actors.codex)
	world.advance(.001)
	check(absf(world.point(world.actors.codex).distance_to(start) * 32 - .125) < .001, "real carried bundle travels at125px/s")
	finish(world, "codex")
	world.command("human", {"intent": "forage", "target_id": "home.mushrooms.1"}); finish(world, "human")
	# C: The earlier explicit stop retains its full 120s quiet period. Advance it
	# before starting the unchanged 30s meal, rather than letting that meal expire.
	var quiet_until:float=maxf(float(world.director.routines.codex.visual_quiet_until),float(world.fishing.life.quiet_until.get("codex",0)))
	while world.director.time<=quiet_until:world.advance(.1)
	check(BBQ.start(world,"single:mushroom",["human","codex"]).ok,"real host fire and exact automatic two-person meal")
	check(reach(world,"fire_eat"),"real sit transition reaches eating")
	var seat_id:String=world.work.jobs.human.seat_id
	var seat:Dictionary=world.life.seats().filter(func(value):return value.id==seat_id)[0]
	check(world.point(world.actors.human).distance_to(world.point(seat))<.001,"resident reaches exact World seat anchor")
	for tick in range(3000):
		if world.life.fireside.jobs.size()==2:break
		world.advance(.05)
	check(world.work.jobs.human.seat_id!=world.work.jobs.codex.seat_id,"two real diners claim distinct seats")
	check(world.observe("codex").shared_life.seats.filter(func(seat):return not seat.occupant_id.is_empty()).size()==2,"AI reads exact real seat occupancy")
	check(BBQ.ate(world,"human") and BBQ.ate(world,"codex"),"two actual automatic eating completions")
	check(world.life.station.meals_eaten==2 and world.life.station.portions==0,"both consumed exactly once")
	world.life.fireside.end_circle("host ends real motion fixture")
	check(world.work.claims.is_empty() and world.work.jobs.is_empty(),"explicit end releases exact seats and jobs")
	var facts:Array=world.read_memories("human",{"kind":"shared_barbecue"}).memories
	check(facts.size()==1 and facts[0].participants.size()==2,"shared memory credits exactly overlapping finished diners")
	for phase in ["fire_travel","fire_eat","fire_sit"]:
		var sample:=F.fresh()
		check(F.job(sample,"human",{"intent":"chop","target_id":"home.tree.01"}) and F.mushroom(sample) and BBQ.start(sample,"single:mushroom",["human","codex"]).ok,"real physical cancellation fixture "+phase)
		var reached:=false
		for tick in range(6000):
			sample.advance(.05)
			if sample.work.jobs.get("human",{}).get("phase")==phase:reached=true;break
		check(reached,"reach actual automatic phase "+phase)
		var eaten:int=sample.life.station.meals_eaten;var raw:int=F.amount(sample,"mushroom")
		sample.command("human",{"intent":"stop"})
		check(sample.work.claims.is_empty() and sample.life.station.portions==0 and sample.life.station.meals_eaten==eaten,"stop releases seats and changes no completed consumption "+phase)
		check(sample.life.fireside.state.current.eaten+sample.life.fireside.state.current.wasted==sample.life.fireside.state.current.total,"canceled food accounted exactly as eaten or wasted "+phase)
		check(Save.save_world(sample,directory.path_join(phase)),"save canceled real motion phase "+phase)
		var restored:=F.fresh()
		check(Save.load_world(restored,directory.path_join(phase)).ok and restored.life.station.meals_eaten==eaten and restored.life.station.portions==0 and F.amount(restored,"mushroom")==raw and restored.work.claims.is_empty(),"reload preserves consumption raw items and no claims "+phase)
	var motion := Motion.new(); motion.advance(.1, world.actors)
	check(Ambience.heat("cold") == 0 and Ambience.heat("cooking") > Ambience.heat("embers"), "cold has no fire, embers reduced")
	check(Ambience.wind(1.0, Places.point("p_20_40")) != Ambience.wind(1.0, Places.point("p_30_45")), "spatial breeze avoids synchronized plants")
	print("Camp motion and speed: %s checks, %s" % [checks, "FAIL" if failed else "PASS"])
	quit(1 if failed else 0)
