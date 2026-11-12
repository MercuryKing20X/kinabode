extends SceneTree
const World=preload("res://scripts/world_state.gd")
const Library=preload("res://scripts/character_library.gd")
const Opening=preload("res://scripts/world_opening.gd")
class MoonOnly extends "res://scripts/schedule_system.gd":
	func options(id:String)->Array:return super.options(id).filter(func(e):return e.place=="moon")
var checks:=0
var failed:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:
	var directory:=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(1);return
	var w:=World.new("res://content/home-v3/world.json");w.library=Library.new();w.library.configure(directory);w.residents.provision(w);w.director.set_all_enabled(false);assert(Opening.apply(w,w.library).ok)
	while w.days.day()<3 or w.days.phase().id!="night":w.advance(1)
	var candidates:Array=[]
	for id in w.director.routines:
		var options:Array=w.schedules.options(id).filter(func(e):return e.place=="moon")
		if not options.is_empty():candidates.append(id)
	check(candidates.size()==1,"only one resident receives low-weight moon option on eligible night")
	if candidates.is_empty():quit(1);return
	var id:String=candidates[0];var r:RefCounted=w.director.routines[id];var human:Dictionary=w.actors.human.duplicate(true)
	# String pulling now reaches the old starting fixture in 24.1s, before the
	# existing 25.1s probe. Use a real far-east forest cell to exercise >24s.
	# All seven assertions and the original 24/90s runtime rules remain unchanged.
	var forest:Dictionary=w.catalog.regions.home.zones.filter(func(z):return z.id=="home.forest")[0]
	var bounds:Rect2=w.catalog.rectangle(forest.rect);var fixture_start:=Vector2.ZERO
	for x in range(int(bounds.end.x)-1,int(bounds.position.x)-1,-1):
		for y in range(int(bounds.end.y)-1,int(bounds.position.y)-1,-1):
			var p:=Vector2(x+.5,y+.5)
			if w.walkable("home",p):fixture_start=p;break
		if fixture_start!=Vector2.ZERO:break
	assert(fixture_start!=Vector2.ZERO)
	w.actors[id].position=[fixture_start.x,fixture_start.y]
	# This isolated night schedule explicitly selects the existing free-life mode.
	w.activities.default_follow_excluded[id]=true;w.activities.release_follow(id)
	w.schedules=MoonOnly.new(w);w.schedules.config.chance=1.0;r.set_enabled(true)
	check(w.schedules.try_start(r),"real original schedule starts selected moon route")
	check(r.route_timeout>24 and r.route_timeout<=90,"only this distant schedule gets authorized bounded route allowance")
	var arrived:=false;var survived24:=false
	for frame in range(1000):
		w.advance(.1)
		if frame==250:survived24=r.kind=="schedule" and w._routes.has(id)
		if w.schedules.targets.get(id,{}).get("arrived",false):arrived=true;break
	check(survived24 and arrived,"actual advance walks longer than 24 seconds and reaches platform")
	check(w.work.jobs.get(id,{}).get("source")=="local_rules" and r.owns_job(),"arrival uses original owned Leisure seat job, no fake seated flag")
	check(w.actors.human==human,"night preference never moves or acts as human")
	w.command(id,{"intent":"stop"});var before:Array=w.actors[id].position.duplicate()
	for frame in range(600):w.advance(.1)
	check(w.actors[id].position==before and not w.work.jobs.has(id),"explicit stop quiet period interrupts moon route/seat")
	print("Moon schedule: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)
