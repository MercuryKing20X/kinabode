extends SceneTree
const World=preload("res://scripts/world_state.gd")
const Library=preload("res://scripts/character_library.gd")
const Opening=preload("res://scripts/world_opening.gd")
const Motion=preload("res://scripts/actor_motion.gd")
var checks:=0
var failed:=false
var moving_frames:=0
var violations:Array=[]
var motion:=Motion.new()
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failed=true;push_error(message)
func _initialize()->void:call_deferred("run")
func fresh(suffix:String)->RefCounted:
	var w:=World.new("res://content/home-v3/world.json");w.residents.provision(w);w.library=Library.new();w.library.configure(OS.get_environment("HABITAT_DATA_DIR").path_join(suffix));assert(Opening.apply(w,w.library).ok);w.intelligence.activate_presets();w.director.set_all_enabled(false);return w
func frame(w:RefCounted,delta:float=.05)->void:
	var before:Dictionary={}
	for id in w.actors:before[id]={"point":w.point(w.actors[id]),"region":w.actors[id].region_id}
	w.advance(delta);motion.advance(delta,w.actors)
	for id in w.actors:
		if before[id].region!=w.actors[id].region_id:continue
		var shift:Vector2=w.point(w.actors[id])-Vector2(before[id].point)
		if shift.length()<=.00001:continue
		moving_frames+=1
		var expected:String=w.walking_direction(shift)
		var pose:Dictionary=motion.pose(w.actors[id],w.work.jobs.get(id,{}),w.actors,{"motion":w.motion_state(id)})
		if (w.actors[id].facing!=expected or pose.facing!=expected or not (pose.frame.begins_with(expected+"_") or pose.frame.begins_with("carry_"+expected))) and violations.size()<10:violations.append({"id":id,"activity":w.actors[id].activity,"job":w.work.jobs.get(id,{}).get("intent",""),"expected":expected,"actual":pose.frame,"shift":shift})
func finish(w:RefCounted,id:String,limit:int=2400)->void:
	for i in range(limit):
		if not w.work.jobs.has(id) and not w._routes.has(id):return
		frame(w)
	check(false,"actual route/job timed out "+id)
func move(w:RefCounted,id:String,to:Vector2)->bool:
	var result:Dictionary=w.command(id,{"intent":"move","x":to.x,"y":to.y})
	if not result.ok:return false
	finish(w,id);return w.point(w.actors[id]).distance_to(to)<.01
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"))
	var w:=fresh("axes")
	var center:Array=w.map_anchor("plaza.center");var p:=Vector2(center[0],center[1])
	for id in w.actors:
		check(move(w,id,p+Vector2(0,4)),"all residents use real route to open plaza "+id)
		for offset in [Vector2(2,0),Vector2(0,2),Vector2(-2,0),Vector2(0,-2),Vector2(2,1.8),Vector2(-2,-1.8)]:check(move(w,id,w.point(w.actors[id])+offset),"real move and turn "+id)
	check(violations.is_empty(),"every resident faces real motion across all turn frames: "+str(violations))
	check(move(w,"human",w.point(w.actors.human)+Vector2(1,0)),"actual final player step establishes the settlement boundary")
	var human:Dictionary=w.actors.human;var last:String=w.motion_state("human").facing
	human.facing="up" if last!="up" else "down";frame(w,.1)
	check(human.facing==last,"requested look cannot replace movement direction within first settled .1 seconds")
	frame(w,.1);check(human.facing==last,"direction remains locked before .3 seconds")
	frame(w,.11);human.facing="left";var pose:Dictionary=motion.pose(human,{},w.actors,{"motion":w.motion_state("human")})
	check(pose.facing=="left","settled body may look elsewhere after .3 seconds")
	for id in w.actors:
		var plots:Array=w.catalog.regions.home.layout.residential.filter(func(plot):return plot.owner_id==id)
		if plots.is_empty():continue
		check(w.command(id,{"intent":"enter","target_id":plots[0].site_id}).ok,"real route home through owned house door "+id);finish(w,id)
		check(w.actors[id].region_id.begins_with("room."),"actual home arrival "+id)
		check(w.command(id,{"intent":"exit"}).ok,"real exit route "+id);finish(w,id)
	# Explicit free-life fixture: authored schedule/wander movement stays testable.
	for id in w.director.routines:w.activities.default_follow_excluded[id]=true
	w.director.set_all_enabled(true)
	var schedules_seen:=false;var wander_seen:=false
	for i in range(4000):
		frame(w,.1)
		for r in w.director.routines.values():
			if r.kind=="schedule":schedules_seen=true
			if r.kind=="wander":wander_seen=true
	check(schedules_seen and wander_seen,"actual authored schedules and idle wandering traversed World routes")
	w.director.set_all_enabled(false)
	var rush_world:=fresh("invited-rush");rush_world.hunger.start();rush_world.advance(700)
	check(rush_world.command("human",{"intent":"forage","target_id":rush_world.life.patches.keys()[0]}).ok,"actual host forages food for the invited meal");finish(rush_world,"human")
	var camp:Vector2=rush_world.point(rush_world.life.station)
	check(move(rush_world,"human",camp+Vector2(2.5,0)) and rush_world.life.fireside.light_host().ok,"actual host reaches and lights camp for invited sprint")
	rush_world.director.routines["companion-2"].set_enabled(true)
	check(not rush_world.hunger.try_rush("companion-2",rush_world.life.station.id),"an uninvited hungry glutton cannot sprint toward fire")
	check(rush_world.life.fireside.invite(["companion-2"]).ok,"host explicitly invites the hungry glutton")
	check(rush_world.life.fireside.roast_host("single:mushroom").ok,"actual roast commits invitation and triggers hungry sprint")
	var sprint_seen:=false
	for i in range(1200):
		frame(rush_world)
		if rush_world.hunger.rushing("companion-2"):sprint_seen=true
		if rush_world.hunger.rushes.get("companion-2",{}).get("arrived",false):break
	check(sprint_seen,"invited hungry glutton traverses real high-speed World route")
	var f:=fresh("follow");check(move(f,"human",p+Vector2(5,6)),"explicit player reaches follow scene")
	f.hunger.start();f.advance(1600);f.director.set_all_enabled(true)
	for i in range(2600):frame(f)
	check(f.hunger.follow_targets.size()==4,"four genuinely hungry companions form a real routed queue")
	var count:int=f.hunger.statistics.follow_routes;var origin:Vector2=f.point(f.actors.human)
	check(move(f,"human",origin+Vector2(.25,0)) and move(f,"human",origin),"small real player steps")
	for i in range(80):frame(f)
	check(int(f.hunger.statistics.follow_routes)-count<=2,"small player movements stay inside the queue's dead zone")
	var side_seen:=false
	for turn in range(3):
		var nearest:String=""
		for id in f.hunger.follow_targets:
			if nearest.is_empty() or f.point(f.actors[id]).distance_to(f.point(f.actors.human))<f.point(f.actors[nearest]).distance_to(f.point(f.actors.human)):nearest=id
		var towards:Vector2=(f.point(f.actors[nearest])-f.point(f.actors.human)).normalized();var end:Vector2=f.point(f.actors[nearest])+towards*3
		if not f.command("human",{"intent":"move","x":end.x,"y":end.y}).ok:continue
		for i in range(180):
			frame(f)
			if f.hunger.follow_targets.values().any(func(t):return t.get("yielding",false)):side_seen=true
			if not f._routes.has("human"):break
		finish(f,"human")
	check(side_seen,"companions yield sideways when player turns and crosses queue")
	check(violations.is_empty(),"follow/yield frames obey same hard facing rule: "+str(violations))
	var before:Dictionary=f.actors.human.duplicate(true);var id:String=f.hunger.follow_targets.keys()[0];f.command(id,{"intent":"stop"});var at:Vector2=f.point(f.actors[id])
	for i in range(100):frame(f)
	check(f.point(f.actors[id]).distance_to(at)<.01 and f.actors.human==before,"stop quiet gate and human control remain intact")
	print("Motion v4: ",checks," checks, failed=",failed,"; moving_frames=",moving_frames,"; violations=",violations);quit(1 if failed else 0)
