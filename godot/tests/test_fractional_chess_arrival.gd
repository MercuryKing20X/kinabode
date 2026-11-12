extends SceneTree
## Integration — production/evidence/barbecue-v4/ — BLOCKING.
## Regression: a walkable coastal endpoint must connect to World's coarse route.
const F=preload("res://tests/cooking_fixture.gd")
var checks:=0
var failed:=false
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failed=true;push_error(message)
func _initialize()->void:call_deferred("run")
func walk(w:RefCounted,id:String,destination:Vector2)->bool:
	if not w.command(id,{"intent":"move","x":destination.x,"y":destination.y}).ok:return false
	var safe:=true
	for tick in range(3000):
		w.advance(.1);safe=safe and w.walkable(w.actors[id].region_id,w.point(w.actors[id]))
		if not w._routes.has(id):return safe and w.point(w.actors[id]).distance_to(destination)<.01
	return false
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"))
	var w:RefCounted=F.fresh();w.library=preload("res://scripts/character_library.gd").new();w.library.configure(OS.get_environment("HABITAT_DATA_DIR"))
	check(F.job(w,"human",{"intent":"gather_wood","tree_count":10,"zone_id":"home.forest"}) and F.job(w,"human",{"intent":"build_facility","target_id":"play.gomoku"}),"actual wood constructs table before arrival regression")
	var start:=Vector2(7.9283390045166,33.5145797729492)
	var connector:=Vector2(8.5,33.5)
	check(w.walkable("home",start) and not w.walkable("home",Vector2(7.5,33.5)) and w.walkable("home",connector),"actual coast is walkable despite blocked coarse centre")
	check(walk(w,"codex",connector) and walk(w,"codex",start),"original World commands reach the real fractional coast through an existing connector")
	var entry:=Vector2(45,78.5)
	var route:Array=w.find_route("codex",entry)
	check(not route.is_empty(),"World connects fractional coastal start to distant chess entry")
	var previous:Vector2=start;var clear:=not route.is_empty()
	for waypoint in route:
		clear=clear and w.segment_clear("home",previous,waypoint);previous=waypoint
	check(clear,"all original World route segments remain walkable without crossing corners or water")
	var before:int=F.amount(w,"wood")
	check(w.gomoku.begin_host("play.gomoku","codex",true,"local","easy").ok,"host starts a real local chess match from the coast")
	var game:Dictionary=w.gomoku.sessions["play.gomoku"];var accepted:Dictionary=game.get("jobs",{}).duplicate(true)
	var silent_removal:=false;var safe_arrivals:=true
	for tick in range(2000):
		w.advance(.1)
		for id in accepted:safe_arrivals=safe_arrivals and w.walkable(w.actors[id].region_id,w.point(w.actors[id]))
		for id in accepted:
			if w.work.jobs.get(id,{}).get("id")==accepted[id]:continue
			if not w.work.events.any(func(event):return event.get("job_id")==accepted[id]):silent_removal=true
		if game.phase!="arriving":break
	check(game.phase=="playing" and accepted.size()==2 and not silent_removal,"both owned arrival jobs survive and reach playing without a silent task interruption")
	check(safe_arrivals,"every actual arrival frame remains on walkable ground")
	if game.phase=="playing":
		var frozen_history:Array=game.history.duplicate(true)
		w.gomoku.pause(game,"QA explicit pause preserves the accepted board")
		check(game.phase=="paused" and accepted.keys().all(func(id):return not w.work.jobs.has(id)) and accepted.values().all(func(job_id):return w.work.events.filter(func(event):return event.get("job_id")==job_id and event.status=="blocked").size()==1),"pause releases only exact owned jobs with one truthful blocked receipt each")
		var receipt_count:int=w.work.events.size();w.gomoku.pause(game,"repeated pause")
		check(w.work.events.size()==receipt_count and game.history==frozen_history and F.amount(w,"wood")==before,"repeated pause is idempotent and preserves board and actual inventory")
		check(w.gomoku.resume_host(game.site_id).ok,"host explicitly resumes original board")
		for tick in range(2000):
			w.advance(.1)
			for id in game.jobs:safe_arrivals=safe_arrivals and w.walkable(w.actors[id].region_id,w.point(w.actors[id]))
			if game.phase!="arriving":break
		check(game.phase=="playing" and safe_arrivals and game.history==frozen_history and game.jobs.values().all(func(job_id):return job_id not in accepted.values()),"resume reaches playing on new exact arrival jobs without changing the retained board")
		check(w.command("human",{"intent":"gomoku_resign","site_id":game.site_id,"match_id":game.id,"revision":game.revision}).ok,"host explicitly ends the real accepted match before return walk")
		var return_route:Array=w.find_route("codex",start);previous=w.point(w.actors.codex);clear=not return_route.is_empty()
		for waypoint in return_route:clear=clear and w.segment_clear("home",previous,waypoint);previous=waypoint
		check(clear and walk(w,"codex",start),"World connects distant route back to fractional coastal destination with every real frame walkable")
	else:check(false,"match must reach playing before return route")
	check(F.amount(w,"wood")==before,"routing and chess arrival never handle resources")
	print("Fractional chess arrival: ",checks," checks, failed=",failed);quit(1 if failed else 0)
