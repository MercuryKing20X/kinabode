extends SceneTree
const W=preload("res://scripts/world_state.gd")
const Library=preload("res://scripts/character_library.gd")
const Opening=preload("res://scripts/world_opening.gd")
const Save=preload("res://scripts/save_store.gd")
const BBQ=preload("res://tests/barbecue_fixture.gd")
var checks:=0
var failed:=false
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failed=true;push_error(message)
func fresh()->RefCounted:
	var w:=W.new("res://content/home-v3/world.json");w.residents.provision(w);w.library=Library.new();w.library.configure(OS.get_environment("HABITAT_DATA_DIR"))
	assert(Opening.apply(w,w.library,"showcase").ok);w.intelligence.activate_presets();w.hunger.start();w.director.set_all_enabled(true);return w
func advance(w:RefCounted,seconds:float)->void:
	for tick in range(ceili(seconds/.1)):w.advance(.1)
func _initialize()->void:call_deferred("run")
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"))
	var w:=fresh();var human:Array=w.actors.human.position.duplicate();var stock:Dictionary=w.life.fireside.available().duplicate(true)
	check(w.activities.set_followers(["codex","npc.mira"]).ok,"host selects exact two")
	advance(w,95)
	check(w.activities.following.size()==2 and not w.activities.following.has("companion-2"),"selected two persist beyond old60-second limit")
	check(w.actors.human.position==human,"following never moves human")
	for id in ["codex","npc.mira"]:check(w.point(w.actors[id]).distance_to(w.point(w.actors.human))<7,"selected resident stays nearby "+id)
	check(w.life.fireside.available()==stock,"idle follow never consumes or auto-stores resources")
	var goal:=Vector2.INF
	for offset in [Vector2(18,0),Vector2(-18,0),Vector2(0,18),Vector2(0,-18)]:
		var at:Vector2=w.point(w.actors.human)+offset
		if w.walkable("home",at) and not w.find_route("human",at).is_empty():goal=at;break
	check(goal.is_finite() and w.command("human",{"intent":"move","x":goal.x,"y":goal.y}).ok,"actual host route moves human")
	advance(w,55)
	for id in ["codex","npc.mira"]:check(w.point(w.actors[id]).distance_to(w.point(w.actors.human))<7,"follower catches new position "+id)
	w.director.set_held("codex",true);advance(w,2);var held:Array=w.actors.codex.position.duplicate();advance(w,5)
	check(w.actors.codex.position==held and w.activities.following.has("codex"),"held pauses movement while retaining selection")
	w.director.set_held("codex",false);advance(w,5)
	check(not w.command("codex",{"intent":"move","x":goal.x,"y":goal.y}).ok and w.activities.following.has("codex"),"model/general command cannot replace explicit follow")
	check(BBQ.start(w,"single:mushroom",["npc.mira"]).ok and BBQ.ate(w,"npc.mira"),"selected follower may actually join and eat invited real meal")
	BBQ.end(w);advance(w,5);check(w.activities.following.has("npc.mira"),"follow selection survives real meal")
	check(w.host_command("codex",{"intent":"move","x":goal.x,"y":goal.y}).ok and w.activities.following.has("codex") and w.activities.following.has("npc.mira") and not w.hunger.owned_routes.has("codex"),"explicit new host order pauses only selected follow route and retains return preference")
	var order_route:Variant=w._routes.get("codex")
	w.advance(.1)
	check((not w._routes.has("codex") or is_same(w._routes.codex,order_route)) and not w.hunger.owned_routes.has("codex") and w.activities.following.has("npc.mira"),"real explicit route keeps ownership until arrival without touching other follower")
	advance(w,10)
	check(w.activities.following.has("codex") and w.activities.following.has("npc.mira"),"completed host movement retains exact follow selection")
	var directory:String=OS.get_environment("HABITAT_DATA_DIR").path_join("follow-save")
	check(Save.save_world(w,directory),"normal save succeeds")
	var loaded:=fresh();check(Save.load_world(loaded,directory).ok and loaded.activities.following.is_empty(),"reload never automatically resumes temporary follow")
	check(w.activities.set_followers([]).ok and w.activities.following.is_empty(),"unchecking ends follow without restarting previous work")
	check_crossing()
	print("Player persistent follow: %d checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)

func check_crossing()->void:
	var w:=fresh();w.director.set_all_enabled(false)
	var edge:Vector2=w.dark.p(w.dark.config.walking_connection.home_end)
	check(w.command("human",{"intent":"move","x":edge.x,"y":edge.y}).ok,"host genuinely starts bridge approach")
	for tick in range(1800):
		w.advance(.1)
		if not w._routes.has("human"):break
	check(w.dark.travel([],true).ok,"host alone crosses actual seam")
	var camp:Vector2=w.dark.p(w.dark.config.arrival)
	check(w.command("human",{"intent":"move","x":camp.x,"y":camp.y}).ok,"host walks from seam to actual camp")
	for tick in range(900):
		w.advance(.1)
		if not w._routes.has("human"):break
	var host_at:Array=w.actors.human.position.duplicate()
	check(w.activities.set_followers(["codex"]).ok and w.actors.codex.region_id=="home" and w._routes.has("codex"),"selecting from other island immediately creates real bridge route without teleport")
	var stopped:Array=w.actors.codex.position.duplicate()
	w.activities.set_followers([]);advance(w,1)
	check(not w._routes.has("codex") and w.actors.codex.position==stopped,"unticking while approaching bridge cancels exact owned crossing route")
	w.activities.set_followers(["codex"])
	for tick in range(1800):
		w.advance(.1)
		if w.actors.codex.region_id=="dark" and w.point(w.actors.codex).distance_to(w.point(w.actors.human))<4.5:break
	check(w.actors.codex.region_id=="dark" and w.point(w.actors.codex).distance_to(w.point(w.actors.human))<4.5,"resident arrives from another island by real World bridge route")
	check(w.actors.human.position==host_at,"remote companion following never moves human")
	check("codex" in w.dark.party,"actual arriving companion becomes real party participant")
