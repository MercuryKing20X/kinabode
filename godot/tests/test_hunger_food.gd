extends SceneTree
const F=preload("res://tests/cooking_fixture.gd")
const B=preload("res://tests/backpack_fixture.gd")
const BBQ=preload("res://tests/barbecue_fixture.gd")
const Save=preload("res://scripts/save_store.gd")
var checks:=0
var failed:=false
func check(ok:bool,msg:String)->void:
	checks+=1
	if not ok:failed=true;push_error(msg)
func _initialize()->void:call_deferred("run")
func near(w:RefCounted,mover:String,target:String)->bool:
	var p:Vector2=w.point(w.actors[target])
	for o in [Vector2(1,0),Vector2(-1,0),Vector2(0,1),Vector2(0,-1)]:
		if w.walkable(w.actors[target].region_id,p+o):return F.job(w,mover,{"intent":"move","x":p.x+o.x,"y":p.y+o.y})
	return false
func run()->void:
	var dir:=OS.get_environment("HABITAT_DATA_DIR");assert(dir.contains("youqi-test-"))
	var w:=F.fresh()
	check(F.harvest(w,"turnip") and F.withdraw(w,"human","turnip"),"real food grown and explicitly withdrawn by human")
	check(near(w,"human","codex"),"human walks to feeding distance")
	w.hunger.start();w.hunger.states.codex.elapsed=float(w.hunger.config.thresholds[3])+60
	var before:int=F.amount(w,"turnip");var receiver:Dictionary=w.actors.codex.carry.duplicate(true);var human_position:Array=w.actors.human.position.duplicate()
	check(not w.command("codex",{"intent":"feed","receiver_id":"human","item_id":"turnip"}).ok,"model interface cannot feed or take human food")
	check(not w.hunger.has_method("feed") and not w.hunger.has_method("pack"),"raw and cooked food feeding/packing API fully removed")
	check(F.amount(w,"turnip")==before and w.actors.codex.carry==receiver and w.actors.human.position==human_position and w.hunger.rank("codex")==3,"rejected removed feeding cannot consume inventory restore fullness or move host")
	check(not w.memories.records.any(func(e):return e.kind=="feeding"),"removed feeding never invents a new memory")
	check(Save.save_world(w,dir.path_join("unfed")),"save unchanged real food")
	var loaded:=F.fresh();check(Save.load_world(loaded,dir.path_join("unfed")).ok and F.amount(loaded,"turnip")==before,"reload retains exact unfed ingredient")
	check(w.memories.valid_saved(w.memories.saved(),w.actors,w.world_id),"canonical memories still validate")
	var meal:=F.fresh();check(F.harvest(meal,"tomato") and F.serve(meal,"tomato-salad"),"real cooked meal served")
	meal.hunger.start();meal.hunger.states.codex.elapsed=float(meal.hunger.config.thresholds[3])+60
	check(F.eat(meal,"codex"),"very hungry resident can finish actual food rather than cancel eating")
	check(meal.hunger.rank("codex")==0 and meal.hunger.statistics.meals==1,"only actual finished portion restores full")
	check(meal.memories.records.any(func(e):return e.kind=="meal_reaction"),"real satisfied reaction recorded")
	var fire:=F.fresh();check(B.wood(fire,1) and F.mushroom(fire) and BBQ.light(fire),"real wood and mushrooms create real cooking fire")
	fire.hunger.start();fire.hunger.states["companion-2"].elapsed=float(fire.hunger.config.thresholds[2])+20;fire.hunger.states.codex.elapsed=float(fire.hunger.config.thresholds[2])+20
	fire.director.routines["companion-2"].set_enabled(true);fire.director.routines.codex.set_enabled(true)
	fire.advance(.1)
	check(not fire.hunger.rushes.has("companion-2"),"hungry glutton does not rush merely because another fire exists")
	check(fire.life.fireside.invite(["companion-2","codex"]).ok and fire.life.fireside.roast_host("single:mushroom").ok,"explicit host invitation and actual food starts meal")
	fire.advance(.1)
	check(fire.hunger.rushes.has("companion-2") and fire.hunger.rushes.has("codex"),"explicit meal triggers all hungry invited residents")
	check(fire._routes.has("companion-2") and fire.movement_speed("companion-2")*32>260,"rush uses real World route and authorised faster speed")
	fire.director.set_held("companion-2",true);var rush_point:Vector2=fire.point(fire.actors["companion-2"])
	fire.advance(.2)
	check(not fire._routes.has("companion-2") and fire.point(fire.actors["companion-2"]).distance_to(rush_point)<.01,"held cancels only owned rush movement and seat")
	var count:int=fire.hunger.statistics.rushes;fire.hunger.clear_rush("companion-2")
	check(not fire.hunger.try_rush("companion-2","home.barbecue") and fire.hunger.statistics.rushes==count,"rush cooldown prevents repeat")
	check(Save.save_world(fire,dir.path_join("rush")),"save real rush state")
	var reloaded:=F.fresh();check(Save.load_world(reloaded,dir.path_join("rush")).ok,"load real rush")
	reloaded.hunger.start();reloaded.director.routines["companion-2"].set_enabled(true)
	check(reloaded.hunger.rushes.is_empty() and reloaded.work.claims.is_empty() and not reloaded.hunger.try_rush("companion-2","home.barbecue"),"reload clears route/reservation and retains rush cooldown")
	var words:=F.fresh();words.hunger.start();words.hunger.states["companion-2"].elapsed=float(words.hunger.config.thresholds[2])+20;words.director.routines["companion-2"].set_enabled(true)
	check(words.hunger.pending_invites.is_empty(),"casual mention does not count")
	words.advance(.1);check(not words.hunger.rushes.has("companion-2"),"chat words cannot replace exact selected fire invitation")
	var not_hungry:=F.fresh();not_hungry.hunger.start();not_hungry.director.routines["companion-2"].set_enabled(true)
	not_hungry.advance(.1);check(not not_hungry.hunger.rushes.has("companion-2"),"peckish glutton does not sprint")
	var fish_world:=F.fresh();fish_world.fishing.rng.seed=101
	var fish_fixture=preload("res://tests/fishing_fixture.gd")
	check(fish_fixture.coast(fish_world,"companion-2") and not fish_fixture.catch_one(fish_world,"companion-2").is_empty(),"glutton really catches and holds a fish")
	fish_world.hunger.start()
	for frame in range(int((float(fish_world.hunger.config.thresholds[2])-float(fish_world.hunger.config.thresholds[1]))/fish_world.intelligence.hunger_multiplier("companion-2")*10)+10):fish_world.advance(.1)
	fish_world.director.routines["companion-2"].set_enabled(true);fish_world.advance(.1)
	check(not fish_world.hunger.rushes.has("companion-2") and not fish_world.is_running("companion-2") and is_equal_approx(fish_world.movement_speed("companion-2")*32,150),"held fish retains ordinary movement and cannot rush or claim a meal seat")
	print("Hunger food: ",checks," checks, failed=",failed);quit(1 if failed else 0)
