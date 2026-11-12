extends RefCounted
const Places=preload("res://scripts/map_locations.gd")
## Disposable QA fixture: every resource and event comes from validated jobs.
static func job(world: RefCounted, actor: String, args: Dictionary) -> bool:
	if actor=="human" and args.get("intent")=="sit" and not world.actors.human.carry.is_empty():
		if not world.deposit_all("human").ok:return false
	var response: Dictionary=world.command(actor,args)
	if not response.ok:push_error("Memory fixture rejected: "+str(args)+str(response));return false
	for i in range(4800):
		if not world.work.jobs.has(actor) or world.work.jobs[actor].get("step")=="seated":return true
		world.advance(.5)
	push_error("Memory fixture timed out: "+str(args));return false

static func phase(world: RefCounted, wanted: String) -> bool:
	for i in range(2000):
		if world.shared_activity.session.get("phase")==wanted and world.shared_activity.active():return true
		if world.shared_activity.session.get("status")=="paused":break
		world.advance(.1)
	push_error("Memory fixture phase: "+wanted+str(world.shared_activity.session));return false

static func populate(world: RefCounted, directory: String) -> bool:
	world.residents.provision(world);world.director.set_all_enabled(false)
	if world.library==null:
		world.library=preload("res://scripts/character_library.gd").new();world.library.configure(directory.path_join("fixture-art"))
	for tree in ["home.tree.01","home.tree.02"]:
		if not job(world,"human",{"intent":"chop","target_id":tree}) or not world.deposit_all("human").ok:return false
	if not job(world,"human",{"intent":"build","target_id":"home.house.01"}):return false
	if not world.command("codex",{"intent":"build_house","target_id":"home.house.01"}).ok:return false
	for i in range(4800):
		world.advance(.5)
		if world.projects.plans.codex.status=="completed":break
	if world.projects.plans.codex.status!="completed":return false
	# Two chairs and fire retain their real costs; three current trees supply nine wood.
	if not job(world,"human",{"intent":"gather_wood","zone_id":"home.forest","tree_count":3}) or not world.deposit_all("human").ok:return false
	for placement in [["human",11.5],["codex",15.5]]:
		if not job(world,placement[0],{"intent":"furnish","target_id":"home.house.01","recipe_id":"chair","x":placement[1],"y":6.5}):return false
	var chairs: Array=world.interior.furniture.keys()
	if not job(world,"human",{"intent":"sit","target_id":chairs[0]}):return false
	if not job(world,"codex",{"intent":"sit","target_id":chairs[1]}):return false
	world.command("human",{"intent":"stop"});world.command("codex",{"intent":"stop"})
	if not job(world,"human",{"intent":"exit"}):return false
	if not job(world,"human",{"intent":"forage","target_id":"home.mushrooms.1"}):return false
	# Respect the real 120-second stop gate before starting the shorter timed meal.
	var quiet_until:float=maxf(float(world.director.routines.codex.visual_quiet_until),float(world.director.routines["companion-2"].visual_quiet_until))
	if world.director.time<=quiet_until:world.advance(quiet_until-world.director.time+.1)
	return preload("res://tests/barbecue_fixture.gd").meal(world,"single:mushroom",["human","codex","companion-2"])
