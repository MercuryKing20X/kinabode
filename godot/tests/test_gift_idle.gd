extends SceneTree
const Places=preload("res://scripts/map_locations.gd")
const F=preload("res://tests/cooking_fixture.gd")
const Save=preload("res://scripts/save_store.gd")
const B=preload("res://tests/backpack_fixture.gd")
var checks:=0
var failed:=false
func _initialize() -> void:call_deferred("run")
func check(ok: bool,text: String) -> void:
	checks+=1
	if not ok:failed=true;push_error(text)
func step(w: RefCounted,seconds: float) -> void:
	for frame in range(int(ceil(seconds/.5))):w.advance(.5)
func near(w: RefCounted,mover: String,other: String) -> bool:
	var p: Vector2=w.point(w.actors[other])
	for offset in [Vector2(1,0),Vector2(-1,0),Vector2(0,1),Vector2(0,-1)]:
		if w.walkable(w.actors[other].region_id,p+offset) and F.job(w,mover,{"intent":"move","x":p.x+offset.x,"y":p.y+offset.y}):return true
	return false
func configuration(w: RefCounted) -> void:
	# This arm compares the original free-idle state machine, not default following.
	w.activities.release_follow("npc.mira");w.activities.default_follow_excluded["npc.mira"]=true
	w.director.local_dialogue.next_check=INF
	w.days.config.greeting_after=w.days.day_seconds+1;w.days.config.small_after=w.days.day_seconds+1
	w.wishes.config.first_after=86400;w.relationships.config.stage_events_enabled=false;w.personality.config.fact_events_enabled=false
	var r: RefCounted=w.director.routines["npc.mira"];r.set_enabled(true);r.set_chatter(true);r.rng.seed=1027
func simulate(w: RefCounted) -> Dictionary:
	configuration(w)
	var result: Dictionary={"active":0.0,"moving":0.0,"behaviors":{},"speech":0};var serial: int=w.director.serial
	for frame in range(7200):
		w.advance(.5)
		var r: RefCounted=w.director.routines["npc.mira"]
		var k: String=r.kind if not r.kind.is_empty() else "idle"
		result.behaviors[k]=float(result.behaviors.get(k,0))+.5
		if k!="idle":result.active+=.5
		if r.owns_route:result.moving+=.5
		for e in w.director.events:
			if e.serial<=serial:continue
			serial=e.serial
			if e.actor_id=="npc.mira":result.speech+=1
	return result
func run() -> void:
	var root_dir:=OS.get_environment("HABITAT_DATA_DIR")
	if not root_dir.contains("youqi-test-"):quit(1);return
	var w:=F.fresh()
	check(F.harvest(w,"turnip") and F.withdraw(w,"human","turnip"),"real harvest and player-owned pickup")
	check(near(w,"human","npc.mira") and w.command("human",{"intent":"give","receiver_id":"npc.mira","item_id":"turnip","quantity":1}).ok,"explicit human gift of one real crop")
	check(F.job(w,"human",{"intent":"store"}) and F.job(w,"human",{"intent":"move","x":Places.point("p_51_44").x,"y":Places.point("p_51_44").y}),"player independently stores surplus and returns")
	check(Save.save_world(w,root_dir.path_join("gift")),"save legitimate gift without new provenance field")
	var empty:=F.fresh();check(Save.load_world(empty,root_dir.path_join("gift")).ok,"clone baseline by valid temporary reload")
	empty.deliveries.cancel("npc.mira") # Isolate idle-gift behavior from explicitly authorized load handoff.
	check(near(empty,"human","npc.mira") and empty.command("npc.mira",{"intent":"give","receiver_id":"human","item_id":"turnip","quantity":1}).ok,"explicit host returns real gift in empty-handed control")
	check(F.job(empty,"human",{"intent":"store"}) and F.job(empty,"human",{"intent":"move","x":Places.point("p_51_44").x,"y":Places.point("p_51_44").y}),"empty control uses real storage")
	var human: Dictionary=w.actors.human.duplicate(true);var total:=F.amount(w,"turnip")
	configuration(w)
	check(not w.director.routines["npc.mira"].blocked(),"held gift alone must not suppress all local life")
	var gift_stats:=simulate(w);var empty_stats:=simulate(empty)
	check(gift_stats.active>0 and absf(gift_stats.active-empty_stats.active)/maxf(1,empty_stats.active)<.2,"gift and empty active time remain within twenty percent")
	check(gift_stats.moving>0 and gift_stats.behaviors.size()>=3,"gift companion still wanders and chooses varied idle behaviors")
	check(w.actors["npc.mira"].carry.get("turnip")==1 and F.amount(w,"turnip")==total,"no automatic take/store/consume, gift remains exactly one")
	check(w.actors.human==human,"gift local behavior cannot move or act for human")
	w.command("npc.mira",{"intent":"stop"});check(Save.save_world(w,root_dir.path_join("after")),"stop and save actual held gift")
	var loaded:=F.fresh();check(Save.load_world(loaded,root_dir.path_join("after")).ok and loaded.actors["npc.mira"].carry.get("turnip")==1 and F.amount(loaded,"turnip")==total,"reload preserves gift and total without tasks")
	loaded.deliveries.cancel("npc.mira");configuration(loaded);step(loaded,130);check(not loaded.director.routines["npc.mira"].blocked(),"valid reloaded gift can resume idle only after quiet period")
	var work:=F.fresh();check(B.wood(work,1),"real tree stock for engineering transport")
	check(work.command("codex",{"intent":"homestead_start","site_id":work.homestead.config.site.id}).ok,"real engineering material withdrawal starts")
	work.advance(.1)
	check(work.homestead.plans.codex.receipt.is_empty() and work.homestead.site.delivered.get("wood")==3,"warehouse material committed exactly once without transport receipt")
	work.command("codex",{"intent":"stop"});var deposited:Dictionary=work.homestead.site.delivered.duplicate(true)
	work.director.routines.codex.set_enabled(true);step(work,150)
	check(work.homestead.site.delivered==deposited and B.wood_total(work)+int(deposited.wood)==3,"paused warehouse engineering investment stays protected and cannot be spent by idle life")
	var output:=OS.get_environment("HABITAT_GIFT_IDLE_OUTPUT")
	if not output.is_empty():
		var f:=FileAccess.open(output,FileAccess.WRITE);f.store_string(JSON.stringify({"seconds_per_arm":3600,"gift":gift_stats,"empty":empty_stats,"retained_gift":w.actors["npc.mira"].carry,"total_before":total,"total_after":F.amount(w,"turnip")},"  "));f.close()
	print("Gift idle: %s checks, failed=%s gift=%s empty=%s"%[checks,failed,gift_stats,empty_stats]);quit(1 if failed else 0)
