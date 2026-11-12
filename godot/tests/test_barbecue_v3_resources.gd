extends SceneTree
const H=preload("res://tests/test_barbecue_v2.gd")
const F=preload("res://tests/cooking_fixture.gd")
const Save=preload("res://scripts/save_store.gd")
var checks:=0
var failed:=false
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failed=true;push_error(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	var h:=H.new();var w:RefCounted=h.fresh(OS.get_environment("HABITAT_DATA_DIR"))
	# Original dual-camp test fixture; dark expedition has separate travel/forage tests.
	w.barbecues.erase("dark.barbecue");w.director.set_all_enabled(false)
	for life in w.barbecues.values():
		if life.station.id=="homelands.barbecue":continue # Vacation island has no harvesting.
		if life.station.id=="homelands.barbecue":
			check(F.job(w,"human",{"intent":"move","x":w.home_island.config.arrival[0],"y":w.home_island.config.arrival[1]}),"real continuous bridge route before southern resource check")
		var patches:Array=life.patches.values();patches.sort_custom(func(a,b):return w.point(a).distance_to(w.point(life.station))<w.point(b).distance_to(w.point(life.station)))
		var patch:Dictionary=patches[0];var before:int=int(life.fireside.available().get("mushroom",0))
		check(w.deposit_all("human").ok and F.job(w,"human",{"intent":"forage","target_id":patch.id}),"real mushroom collection via World/Work")
		check(patch.amount==0 and life.fireside.available().get("mushroom",0)==before+4,"patch becomes exactly four real stored mushrooms")
		check(patch.ready_at-Time.get_unix_time_from_system()>21590,"original six-hour regrowth deadline retained")
		w.advance(.1);check(patch.amount==0,"no early regrowth")
		# Deadline fixture: emulate elapsed wall time; actual update still advances world.
		patch.ready_at=Time.get_unix_time_from_system()-1;w.advance(.1)
		check(patch.amount==4 and patch.ready_at==0,"original expired deadline regrows one batch")
	if w.home_island.here():
		check(F.job(w,"human",{"intent":"move","x":w.home_island.config.home_dock[0],"y":w.home_island.config.home_dock[1]}),"real bridge return retains original mainland fixture")
	var moon:RefCounted=w.barbecues["moon.barbecue"]
	var previous:Dictionary={"station":moon.station.duplicate(true),"patches":moon.patches.duplicate(true),"memories":[]}
	previous.patches["moon.mushrooms.1"].position=[-40,86]
	check(Save._valid_life(w,previous,w.actors,moon),"exact old legal mushroom coordinate accepted without relaxing quantities")
	previous.patches["moon.mushrooms.1"].amount=5
	check(not Save._valid_life(w,previous,w.actors,moon),"invalid old quantity still rejected")
	var life:RefCounted=w.life
	check(h.approach(w,life) and life.fireside.light_host().ok and life.fireside.invite(w.standard.config.companions).ok and life.fireside.roast_host("single:mushroom").ok,"explicit five-person circle")
	for i in range(1000):
		w.advance(.1)
		if life.fireside.state.current.eaten==5:break
	check(life.fireside.seats.size()==5 and life.fireside.state.current.eaten==5,"five distinct actual arrivals finish")
	var all:Array=life.seats();var angular:Array=[]
	for i in range(all.size()):
		check(w.walkable("home",w.point(all[i])),"all eight seats walkable")
		check(absf(w.point(all[i]).distance_to(w.point(life.station))-3)<.05,"all eight seats equal radius")
	for id in life.fireside.seats:
		var toward:Vector2=w.point(life.station)-w.point(w.actors[id])
		check(w.actors[id].facing==w.walking_direction(toward),"actual seated actor faces pit")
		angular.append(atan2(toward.y,toward.x))
	angular.sort();var gap:=0.0
	for i in range(angular.size()):gap=maxf(gap,fposmod(angular[(i+1)%angular.size()]-angular[i],TAU))
	check(gap<=PI/2+.01,"first five arrivals distributed across circle")
	h.free();print("Barbecue v3 resources: ",checks," checks, failed=",failed);quit(1 if failed else 0)
