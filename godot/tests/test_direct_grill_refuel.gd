extends SceneTree
## Deterministic real-advance regression for the paid warm-fire refuel branch.
const Fish=preload("res://tests/fishing_fixture.gd")
const BBQ=preload("res://tests/barbecue_fixture.gd")
const World=preload("res://scripts/world_state.gd")
var checks:=0
var failed:=false
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failed=true;push_error(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	var dir:String=OS.get_environment("HABITAT_DATA_DIR");assert(dir.contains("youqi-test-"))
	var original_hash:String=FileAccess.get_sha256("res://content/barbecue-v2.json")
	var w:=World.new("res://content/home-v3/world.json");w.residents.provision(w)
	w.library=preload("res://scripts/character_library.gd").new();w.library.configure(dir)
	check(preload("res://scripts/world_opening.gd").apply(w,w.library,"showcase").ok,"real showcase opening, no supplied inventory")
	w.hunger.start();w.director.set_all_enabled(false)
	check(Fish.coast(w,"human"),"World route to validated natural coast")
	check(w.command("human",{"intent":"fish"}).ok,"real fishing starts")
	for i in range(1200):
		w.advance(.1)
		if not w.work.jobs.has("human"):break
	var stored:Array=w.fishing.fish.values().filter(func(f):return f.owner_id=="human" and f.location=="storage")
	var fish:Dictionary=stored[0].duplicate(true) if not stored.is_empty() else {}
	check(not fish.is_empty(),"real unique catch before lighting")
	if fish.is_empty():quit(1);return
	check(BBQ.approach(w),"actual host route carrying same pending fish to camp")
	var fire:RefCounted=w.life.fireside;var center:Vector2=w.point(w.life.station)
	var arrived:=false
	for offset in [Vector2(5,0),Vector2(-5,0),Vector2(0,5),Vector2(0,-5)]:
		var goal:Vector2=center+offset
		if w.walkable("home",goal) and Fish.walk(w,"codex",[goal.x,goal.y]):arrived=true;break
	check(arrived,"companion reaches nearby camp via original World route")
	var config:Dictionary=fire.config.duplicate(true)
	check(fire.light_host().ok,"explicit host lighting consumes original real wood")
	var interval:float=float(fire.config.fire_seconds)
	for frame in range(1790):w.advance(.1)
	check(fire.burning() and absf(float(fire.state.remaining)-1.0)<.00001,"actual179seconds leaves exactly one second of original180second fire")
	var before:float=float(fire.state.remaining);var wood:int=int(fire.available().get("wood",0));var fuel:int=w.life.station.fuel_used
	var result:Dictionary=fire.direct_grill(fish.id)
	check(result.get("ok",false),"explicit warm direct-grill accepted with one-second fire")
	if not result.get("ok",false):quit(1);return
	check(int(fire.available().get("wood",0))==wood-int(config.charcoal_wood) and int(config.charcoal_wood)==1,"one existing charcoal wood paid exactly once")
	check(is_equal_approx(float(fire.state.remaining),before+interval) and interval==180.0,"paid warm refuel adds existing180second interval without tuning")
	check(w.life.station.fuel_used==fuel+1,"fuel audit includes exactly the paid wood")
	check(not w.fishing.fish.has(fish.id) and fire.state.current.fish.id==fish.id,"same fish moves atomically to fire without duplicate")
	var stock_after:int=int(fire.available().get("wood",0));var remaining_after:float=float(fire.state.remaining)
	check(not fire.direct_grill(fish.id).ok and int(fire.available().get("wood",0))==stock_after and float(fire.state.remaining)==remaining_after,"spent fish cannot refuel or debit again")
	w.director.routines.codex.set_enabled(true)
	check(fire.invite_direct(["codex"]).ok,"host explicitly invites real companion")
	for frame in range(600):
		w.advance(.1)
		if fire.state.current.eaters.has("codex"):break
	check(fire.burning() and fire.state.current.eaters==["codex"] and not fire.state.current.eaters.has("human"),"renewed real fire lasts through cooking arrival and actual companion consumption")
	check(fire.state.current.eaten==1 and w.hunger.rank("codex")==0,"actual completed meal consumes one portion and restores only diner hunger")
	check(fire.config==config and FileAccess.get_sha256("res://content/barbecue-v2.json")==original_hash,"all existing duration cost and content parameters byte-identical")
	print("Direct grill paid refuel: ",checks," checks; failed=",failed,"; real routes/catch/advance, temporary engine fixture");quit(1 if failed else 0)
