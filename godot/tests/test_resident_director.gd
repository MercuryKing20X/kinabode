extends SceneTree
const Places=preload("res://scripts/map_locations.gd")
const World=preload("res://scripts/world_state.gd")
const Library=preload("res://scripts/character_library.gd")
const Save=preload("res://scripts/save_store.gd")
var checks:=0
var failed:=false
var diagnostic_seed:String=OS.get_environment("HABITAT_DIRECTOR_DIAGNOSTIC_SEED")
func diagnostic_actor(world:RefCounted,id:String,tick:int,previous:Dictionary)->Dictionary:
	var actor:Dictionary=world.actors[id]
	var at:Vector2=world.point(actor)
	var nearby:Array=[]
	for object in world.objects.values():
		if object.region_id==actor.region_id and world.point(object).distance_to(at)<=10:
			nearby.append({"id":object.id,"kind":object.kind,"position":object.position.duplicate(),"distance":world.point(object).distance_to(at),"status":object.get("status",""),"stage":object.get("stage_index",0)})
	var facilities:Array=[]
	for site in world.leisure.sites.values():
		if site.region_id!=actor.region_id:continue
		var boxes:Array=[]
		for box in world.leisure.art(site).get("recreation",{}).get("obstacles",[]):
			var rect:=Rect2(world.point(site)+Vector2(box[0],box[1]),Vector2(box[2],box[3]))
			if rect.grow(2).has_point(at):boxes.append({"rect":str(rect),"inside":rect.has_point(at)})
		if not boxes.is_empty():facilities.append({"id":site.id,"complete":site.complete,"boxes":boxes})
	var fences:Array=[]
	for farm in world.farms.farms.values():
		for fence in world.farms.fences(farm):
			var distance:float=at.distance_to(Geometry2D.get_closest_point_to_segment(at,fence[0],fence[1]))
			if distance<2:fences.append({"farm_id":farm.id,"start":str(fence[0]),"end":str(fence[1]),"distance":distance,"blocked_radius":.55})
	return {"nearby_farm_fences":fences,"homestead_blocked":world.homestead.blocks(actor.region_id,at),"actor":id,"tick":tick,"position":actor.position.duplicate(),"region":actor.region_id,"activity":actor.activity,"kind":world.director.routines[id].kind,"route":str(world._routes.get(id,[])),"job":world.work.jobs.get(id,{}).duplicate(true),"previous":previous.duplicate(true),"terrain_walkable":world._terrain_walkable(actor.region_id,at),"leisure_blocked":world.leisure.blocked(actor.region_id,at),"nearby_objects":nearby,"nearby_facility_boxes":facilities,"forest_clock":world.forest.clock,"weather":world.weather.summary()}

func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failed=true;push_error(label)
func run_job(world: RefCounted,args: Dictionary) -> bool:
	if not world.command("codex",args).ok:return false
	for tick in range(18000):
		world.advance(.1)
		if not world.work.jobs.has("codex") and not world._routes.has("codex"):return true
	return false
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var directory:=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(1);return
	if not diagnostic_seed.is_empty():seed(int(diagnostic_seed))
	var world:=World.new();world.residents.provision(world)
	if not diagnostic_seed.is_empty():
		world.world_id="director-diagnostic-%d"%int(diagnostic_seed)
		world.weather.weather_seed=int(diagnostic_seed)
		world.forest.clock=2000000000.0
		world.days.origin=world.forest.clock
		world.fishing.rng.seed=int(diagnostic_seed)
		world.gomoku.rng.seed=int(diagnostic_seed)
	print("DIRECTOR_BASELINE ",JSON.stringify({"seed":diagnostic_seed,"world_id":world.world_id,"weather_seed":world.weather.weather_seed,"forest_clock":world.forest.clock,"days_origin":world.days.origin}))
	var library:=Library.new();library.configure(directory);world.library=library
	check(world.director.routines.size()==4 and not world.director.routines.has("human"),"one identical routine per non-human identity")
	check(world.director.routines["companion-2"].preferences.facilities.dance>world.director.routines.codex.preferences.facilities.dance,"preferences belong to resident data")
	check(run_job(world,{"intent":"gather_wood","tree_count":12}),"prepare real leisure materials")
	for id in world.leisure.sites:check(run_job(world,{"intent":"build_facility","target_id":id}),"build actual facility "+id)
	# Faster valid routes finish preparation before the last stumps sprout.
	# Settle that existing natural transition with real advance before taking the
	# unchanged strict conservation snapshot. Never rewrite trees or resources.
	for tick in range(ceili((float(world.forest.settings.sprout_seconds)+float(world.forest.settings.scan_seconds))/.1)):world.advance(.1)
	var objects: Dictionary=world.objects.duplicate(true);var farming: Dictionary=world.farms.saved().duplicate(true);farming.erase("clock")
	var leisure: Dictionary=world.leisure.saved().duplicate(true);var human: Dictionary=world.actors.human.duplicate(true)
	var first_invalid:Dictionary={};var previous:Dictionary={}
	var starts: Dictionary={};var moved: Dictionary={};var behaviors: Dictionary={};var visited: Dictionary={};var walkable:=true;var collisions:=false;var observed_lines: Array=[];var seen:=0
	# C: exercise the existing opt-in free-idle module, independently of default following.
	for id in world.director.routines:
		world.activities.default_follow_excluded[id]=true
		world.director.routines[id].rng.seed=420+starts.size()+(int(diagnostic_seed)*17 if not diagnostic_seed.is_empty() else 0)
		world.director.routines[id].set_enabled(true);starts[id]=world.actors[id].position.duplicate();behaviors[id]={}
	for tick in range(6000):
		for id in starts:previous[id]={"position":world.actors[id].position.duplicate(),"activity":world.actors[id].activity,"route":str(world._routes.get(id,[])),"kind":world.director.routines[id].kind}
		world.advance(.1)
		for id in starts:
			if world.actors[id].position!=starts[id]:moved[id]=true
			behaviors[id][world.director.routines[id].kind]=true
			var valid_position:bool=world.walkable(world.actors[id].region_id,world.point(world.actors[id]))
			if not valid_position and first_invalid.is_empty():first_invalid=diagnostic_actor(world,id,tick,previous[id])
			walkable=walkable and valid_position
			if world.actors[id].activity in ["swinging","seated","dancing"]:visited[id]=true
		var reserved: Array=[]
		for job in world.work.jobs.values():
			if job.intent!="use_facility":continue
			var key: String=job.target_id+":"+str(job.slot)
			if key in reserved:collisions=true
			reserved.append(key)
		for line in world.director.events:
			if line.serial>seen:observed_lines.append(line);seen=line.serial
	if moved.size()!=4 or not walkable:
		var unmoved:Array=[]
		for id in starts:
			if not moved.has(id):unmoved.append(diagnostic_actor(world,id,5999,previous[id]))
		print("DIRECTOR_DIAGNOSTIC ",JSON.stringify({"seed":diagnostic_seed,"world_id":world.world_id,"weather_seed":world.weather.weather_seed,"moved_ids":moved.keys(),"moved_condition":moved.size()==4,"walkable_condition":walkable,"unmoved":unmoved,"first_invalid":first_invalid}))
	check(moved.size()==4 and walkable,"all four wander along valid world routes")
	check(behaviors.values().all(func(kinds):return kinds.size()>=4),"all four choose varied behaviors during ten minutes")
	check(visited.size()==4,"every resident naturally uses a completed facility")
	check(not collisions,"autonomous facility use never double-books a slot")
	check(world.actors.human==human,"local simulation never moves or controls player")
	var after_farm: Dictionary=world.farms.saved().duplicate(true);after_farm.erase("clock")
	check(world.objects==objects and after_farm==farming and world.leisure.saved()==leisure,"ten-minute local life preserves all materials crops and construction")
	var spaced:=true
	for i in range(1,observed_lines.size()):spaced=spaced and float(observed_lines[i].time)-float(observed_lines[i-1].time)>=float(world.director.moods.config.village_gap)-.1
	check(observed_lines.size()>0 and spaced and observed_lines.all(func(line):return line.source=="local_rules" and line.actor_id in starts),"all voices identified and globally rate limited")
	world.director.interrupt_all(0);world.director.set_all_enabled(false)
	for id in starts:
		check(world.command(id,{"intent":"move","x":33+starts.keys().find(id)*2,"y":65}).ok,"host positioning uses common movement "+id)
	for tick in range(1000):world.advance(.1)
	world.director.set_all_enabled(true)
	var routine: RefCounted=world.director.routines["npc.mira"]
	check(routine._start("facility") and routine.owns_job(),"local facility marks only its own job")
	check(world.host_command("npc.mira",{"intent":"dance"}).ok and not routine.owns_job() and world.work.jobs["npc.mira"].intent=="dance","manual invitation preempts only local facility job")
	routine.set_enabled(false)
	check(world.work.jobs["npc.mira"].intent=="dance","disabling ambient leaves explicit activity running")
	world.director.set_all_enabled(false) # Freeze idle scheduling while positioning the isolated start fixture.
	world.host_command("codex",{"intent":"move","x":Places.point("p_35_0_63_0").x,"y":Places.point("p_35_0_63_0").y})
	for tick in range(300):world.advance(.1)
	var white: RefCounted=world.director.routines.codex
	white.set_enabled(true)
	check(white._start("facility"),"model resident starts local leisure without inference")
	check(world.command("codex",{"intent":"gather_wood","tree_count":1}).ok and not white.owns_job() and world.work.jobs.codex.intent=="gather_wood","model task preempts local facility before busy validation")
	var job_id: String=world.work.jobs.codex.id
	white.set_held(true);world.advance(.1)
	check(world.work.jobs.codex.id==job_id,"conversation hold never cancels an explicit accepted task")
	world.command("codex",{"intent":"stop"});white.set_held(false)
	var still: Array=world.actors.codex.position.duplicate()
	for tick in range(1000):world.advance(.1)
	check(world.actors.codex.position==still and white.kind.is_empty(),"manual stop quiet period survives model hold changes")
	world.activities.gather()
	for tick in range(1200):
		world.advance(.1)
		if world.activities.gathering.get("phase")=="holding":break
	check(world.activities.members.size()==4 and world.activities.members.values().all(func(m):return m.arrived),"all autonomous residents yield to assembly")
	var line_positions: Dictionary={}
	for id in starts:line_positions[id]=world.actors[id].position.duplicate()
	for tick in range(590):world.advance(.1)
	check(starts.keys().all(func(id):return world.actors[id].position==line_positions[id]),"all four stay still throughout assembly hold")
	world.activities.dismiss();world.director.set_all_enabled(false)
	# Source switch affects control only; identity, memories, capabilities and belongings stay.
	var saved_actor: Dictionary=world.actors["npc.mira"].duplicate(true)
	var capabilities:Array=world.residents.capabilities(world.actors["npc.mira"]).duplicate()
	check(world.director.set_controller("npc.mira","model").ok and world.actors["npc.mira"].id==saved_actor.id and world.actors["npc.mira"].appearance_id==saved_actor.appearance_id,"NPC can use model source without changing identity or artwork")
	check(world.residents.capabilities(world.actors["npc.mira"])==capabilities and world.residents.supports(world.actors["npc.mira"],"chop") and world.residents.supports(world.actors["npc.mira"],"dance"),"controller switch never silently grants work capabilities")
	check(world.director.set_controller("codex","local").ok and world.residents.supports(world.actors.codex,"chop"),"worker retains capability with local control")
	check(not world.director.set_controller("human","model").ok,"human is never available for model takeover")
	check(Save.save_world(world,directory),"save explicit source preferences")
	var restored:=World.new();restored.library=library
	check(Save.load_world(restored,directory).ok and restored.actors["npc.mira"].controller=="model" and restored.actors.codex.controller=="local","load source choices without rewriting identity")
	check(restored.work.jobs.is_empty() and restored.work.claims.is_empty() and restored.director.routines.values().all(func(r):return r.kind.is_empty()),"restart restores no old leisure jobs routes or reservations")
	print("Unified resident life: %s checks, %s"%[checks,"FAIL" if failed else "PASS"]);quit(1 if failed else 0)
