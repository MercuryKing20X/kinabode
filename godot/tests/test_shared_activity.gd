# DIRECTION 2026-11-07: 烤蘑菇永久无限供应，不扣任何食材；其它食材守恒断言保留。
extends SceneTree
## Integration — production/evidence/barbecue-v4 — BLOCKING exact jobs, host authority, conservation.
const F=preload("res://tests/cooking_fixture.gd")
const BBQ=preload("res://tests/barbecue_fixture.gd")
const Save=preload("res://scripts/save_store.gd")
var checks:=0
var failed:=false
var directory:String
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:call_deferred("run")
func stock(w:RefCounted)->bool:return F.job(w,"human",{"intent":"gather_wood","tree_count":1,"zone_id":"home.forest"}) and F.mushroom(w)
func checkpoint(w:RefCounted,name:String)->RefCounted:
	check(Save.save_world(w,directory.path_join(name)),"save real stage "+name)
	var loaded:=F.fresh();check(Save.load_world(loaded,directory.path_join(name)).ok,"load real stage "+name)
	check(loaded.work.jobs.is_empty() and loaded.work.claims.is_empty() and loaded._routes.is_empty(),"reload clears all accepted jobs claims and routes "+name)
	check(F.amount(loaded,"wood")==F.amount(w,"wood") and F.amount(loaded,"mushroom")==F.amount(w,"mushroom"),"reload never creates or loses raw resource "+name)
	return loaded
func run()->void:
	directory=OS.get_environment("HABITAT_DATA_DIR");assert(directory.contains("youqi-test-"))
	local_job_invitation()
	var w:=F.fresh();check(stock(w),"real fuel and forage stock")
	var fire:RefCounted=w.life.fireside;var human:Dictionary=w.actors.human.duplicate(true);var guests:Dictionary=w.actors.duplicate(true)
	check(fire.invite(["codex","companion-2"]).ok,"host selects dynamic resident identities")
	w.advance(.3)
	check(w.actors.human==human and w.actors==guests and w.work.jobs.is_empty(),"invitation alone neither moves human nor starts guests or consumption")
	check(not fire.invite(["codex","codex"]).ok and not fire.invite(["human"]).ok and not fire.invite(["missing"]).ok,"duplicate human and nonexistent invitation rejected atomically")
	var revision:int=w.revision
	for n in range(3,9):w.add_companion("companion-"+str(n),"扩展伙伴"+str(n))
	revision=w.revision
	check(not fire.invite(["codex","companion-2","companion-3","companion-4","companion-5","companion-6","companion-7","companion-8"]).ok and w.revision==revision,"seat capacity rejection has no cancellation mutation or fake consent")
	checkpoint(w,"invitation")
	check(BBQ.light(w) and fire.invite(["codex","companion-2"]).ok,"host alone approaches lights and invites")
	var wood:int=F.amount(w,"wood");var mushroom:int=F.amount(w,"mushroom")
	check(fire.roast_host("single:mushroom").ok and F.amount(w,"mushroom")==mushroom,"three intended mushroom diners cost zero ingredients")
	var loaded:RefCounted=checkpoint(w,"cooking")
	# B: The authorized timed-meal migration (b7b632d) preserves genuine paid food
	# paused on load; clear jobs/claims above still prove it never resumes itself.
	var restored_fire:RefCounted=loaded.life.fireside
	var expected_food:Dictionary=fire.state.current.duplicate(true);expected_food["paused_guests"]=fire.state.invited.duplicate()
	check(restored_fire.state.suspended and not restored_fire.state.consent and loaded.memories._canonical(restored_fire.state.current)==w.memories._canonical(expected_food),"reload retains exact genuine food and timer paused without leftovers or replay")
	var paused_food:Dictionary=restored_fire.state.current.duplicate(true)
	for tick in range(350):loaded.advance(.1)
	check(restored_fire.state.current==paused_food and restored_fire.jobs.is_empty() and loaded.work.claims.is_empty(),"paused food and countdown do not advance or create jobs")
	var resumed_stock:Dictionary=restored_fire.available().duplicate(true)
	check(BBQ.approach(loaded) and restored_fire.resume_meal().ok and restored_fire.available()==resumed_stock,"explicit real return resumes the same meal without paying ingredients twice")
	for tick in range(350):loaded.advance(.1)
	check(restored_fire.state.current.eaten+restored_fire.state.current.wasted==restored_fire.state.current.total and loaded.life.station.portions==0 and restored_fire.jobs.is_empty() and loaded.work.claims.is_empty(),"resumed meal expiry accounts every genuine portion exactly once and releases all work")
	for intent in ["eat","turn_food","cleanup","barbecue"]:
		check(not w.command("npc.nora",{"intent":intent,"target_id":"home.barbecue"}).ok,"old outsider action cannot acquire food: "+intent)
	check(BBQ.ate(w,"human") and BBQ.ate(w,"codex") and BBQ.ate(w,"companion-2"),"all selected people really arrive sit and finish")
	check(fire.state.current.eaters.size()==3 and not fire.state.current.eaters.has("npc.mira") and not fire.state.current.eaters.has("npc.nora"),"nearby bystanders never silently join dinner")
	check(fire.state.current.total==3 and fire.state.current.eaten==3 and fire.state.current.wasted==0 and w.life.station.portions==0,"all cooked output counted once with no leftovers")
	check(F.amount(w,"wood")==wood and F.amount(w,"mushroom")+fire.state.current.receipt.get("mushroom",0)==mushroom,"physical resources and consumed receipt conserve exact source amounts")
	fire.end_circle("host ends completed activity")
	check(w.work.jobs.is_empty() and w.work.claims.is_empty(),"finished gathering releases only its actual jobs and seats")
	var records:Array=w.read_memories("human",{"kind":"shared_barbecue"}).memories
	check(records.size()==1 and records[0].participants==["codex","companion-2","human"],"one canonical event credits only completed eaters")
	fire.end_circle("duplicate end");w.memories.sync()
	check(w.read_memories("human",{"kind":"shared_barbecue"}).total==1,"duplicate end or sync never replays history or food")
	loaded=checkpoint(w,"complete")
	check(loaded.read_memories("human",{"kind":"shared_barbecue"}).total==1,"canonical real gathering persists exactly once")
	# Cancellation targets activity-owned work only, never a newer manual job.
	w=F.fresh();check(stock(w) and BBQ.start(w,"single:mushroom",["human","codex"]).ok,"real second cancellation fixture")
	fire=w.life.fireside
	for tick in range(9000):
		w.advance(.1)
		if fire.jobs.has("codex"):break
	check(fire.jobs.has("codex"),"selected resident has an exact owned arrival/eating job")
	w.command("codex",{"intent":"stop"});var raw:int=F.amount(w,"mushroom")
	check(w.command("codex",{"intent":"chop","target_id":"home.tree.02"}).ok,"explicit player replaces ended gathering with real manual work")
	var manual:String=w.work.jobs.codex.id
	fire.end_circle("stale end after another task")
	check(w.work.jobs.codex.id==manual and w.work.jobs.codex.intent=="chop" and F.amount(w,"mushroom")==raw,"ending old circle cannot stop newer manual job or alter food")
	check(fire.state.current.eaten+fire.state.current.wasted==fire.state.current.total and w.life.station.portions==0,"canceled output accounted without duplication")
	# A busy resident cannot be stolen even by an explicit invitation.
	w=F.fresh();check(stock(w),"real stock before busy guest guard")
	check(w.command("companion-2",{"intent":"chop","target_id":"home.tree.02"}).ok,"unrelated accepted task exists")
	manual=w.work.jobs["companion-2"].id;human=w.actors.human.duplicate(true)
	check(not w.life.fireside.invite(["companion-2"]).ok and w.work.jobs["companion-2"].id==manual and w.actors.human==human,"invitation never steals accepted task or acts as human")
	w=F.fresh();fire=w.life.fireside
	check(BBQ.light(w) and fire.invite(["codex"]).ok,"missing-food fixture uses real fire not free fuel")
	var stock_before:Dictionary=fire.available().duplicate(true)
	check(not fire.roast_host("single:apple").ok and fire.available()==stock_before and w.read_memories("human").total==0,"missing ingredients cannot manufacture food or a completed memory")
	print("Shared activity simplified: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)

func local_job_invitation()->void:
	var w:=F.fresh();w.library=preload("res://scripts/character_library.gd").new();w.library.configure(OS.get_environment("HABITAT_DATA_DIR").path_join("local-facility"));check(stock(w),"real resources before local facility invitation")
	check(F.job(w,"human",{"intent":"gather_wood","tree_count":10,"zone_id":"home.forest"}) and F.job(w,"human",{"intent":"build_facility","target_id":"play.swing"}),"host really builds authored leisure facility")
	check(BBQ.light(w),"host actually lights fire before the local activity invitation")
	check(F.job(w,"codex",{"intent":"move","x":w.point(w.leisure.sites["play.swing"]).x+2,"y":w.point(w.leisure.sites["play.swing"]).y}),"resident really walks near original leisure facility")
	var r:RefCounted=w.director.routines.codex
	check(r._start("facility") and r.owns_job(),"original local routine holds its exact real facility job")
	var local_id:String=r.owned_job_id;var before:Dictionary=w.actors.human.duplicate(true)
	var fire:RefCounted=w.life.fireside
	check(fire.invite(["codex"]).ok and w.work.jobs.get("codex",{}).get("id")==local_id and r.owns_job(),"menu selection accepts own local facility without preempting it before host starts")
	check(BBQ.approach(w) and fire.roast_host("single:mushroom").ok,"explicit actual roast may replace only that exact local facility activity")
	check(not r.owns_job() and w.work.jobs.get("codex",{}).get("id")!=local_id,"confirmed meal releases the precise prior local job rather than an unrelated accepted task")
	check(BBQ.finish(w,["human","codex"]) and fire.state.current.eaters.size()==2,"formerly resting facility user actually joins and eats same genuine meal")
