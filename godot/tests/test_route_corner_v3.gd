extends SceneTree
const World=preload("res://scripts/world_state.gd")
const Helper=preload("res://tests/test_resident_director.gd")
var checks:=0
var failed:=false
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failed=true;push_error(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	var h:=Helper.new();var w:=World.new();w.residents.provision(w);w.library=preload("res://scripts/character_library.gd").new();w.library.configure(OS.get_environment("HABITAT_DATA_DIR"));w.director.set_all_enabled(false)
	check(h.run_job(w,{"intent":"gather_wood","tree_count":12}) and h.run_job(w,{"intent":"build_facility","target_id":"play.gazebo"}),"real gazebo construction before geometry check")
	var start:=Vector2(39.60,67.764);var finish:=Vector2(39.20,68.164)
	check(w.walkable("home",start) and w.walkable("home",finish),"regression endpoints outside actual post")
	check(not w.segment_clear("home",start,finish),"continuous rectangle check rejects tiny corner crossing missed by .15 samples")
	check(w.segment_clear("home",start,start+Vector2(0,-1)),"safe route remains accepted")
	check(w.command("codex",{"intent":"move","x":start.x,"y":start.y}).ok,"original World route to regression start")
	for i in range(5000):
		w.advance(.03)
		if not w._routes.has("codex"):break
	check(w.command("codex",{"intent":"move","x":finish.x,"y":finish.y}).ok,"route repaired around actual post")
	var safe:=true
	for i in range(5000):
		w.advance(.003);safe=safe and w.walkable("home",w.point(w.actors.codex))
		if not w._routes.has("codex"):break
	check(safe and w.point(w.actors.codex).distance_to(finish)<.001,"actual fine-grained movement never enters obstacle and arrives")
	# Seed21's accepted swing approach grazed the existing southern farm fence.
	# Both endpoints are legal; a .15 sample interval can miss its tiny incursion.
	var interior_point:=Vector2(39.6329803466797,48.0688629150391)
	check(w.terrain_surface("home",interior_point),"observed isolated interior point remains real land")
	check(not w.terrain_surface("home",Vector2(8,8)),"polygon verification never expands the coastline to nearby sea")
	var farm_start:=Vector2(43.7695808410645,59.9251899719238)
	var farm_finish:=Vector2(42.0,59.9779739380)
	check(w.walkable("home",farm_start) and w.walkable("home",farm_finish),"farm grazing regression endpoints stay outside the original fence radius")
	check(not w.segment_clear("home",farm_start,farm_finish),"continuous original farm fence radius rejects a grazing route")
	check(w.segment_clear("home",farm_start,farm_start+Vector2(0,1)),"route away from the farm fence stays valid")
	check(w.command("codex",{"intent":"move","x":farm_start.x,"y":farm_start.y}).ok,"common World route to farm regression start")
	for i in range(5000):
		w.advance(.03)
		if not w._routes.has("codex"):break
	check(w.command("codex",{"intent":"move","x":farm_finish.x,"y":farm_finish.y}).ok,"common World repairs the farm grazing route")
	safe=true
	for i in range(5000):
		w.advance(.003);safe=safe and w.walkable("home",w.point(w.actors.codex))
		if not w._routes.has("codex"):break
	check(safe and w.point(w.actors.codex).distance_to(farm_finish)<.001,"actual farm corner detour stays walkable through settled arrival")
	h.free();print("Route corner v3: ",checks," checks, failed=",failed);quit(1 if failed else 0)
