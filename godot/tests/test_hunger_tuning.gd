extends SceneTree
## Integration — production/evidence/barbecue-v4 — BLOCKING hunger consumption / speech barriers.
const F=preload("res://tests/cooking_fixture.gd")
const BBQ=preload("res://tests/barbecue_fixture.gd")
const Save=preload("res://scripts/save_store.gd")
var checks:=0
var failed:=false
func check(ok:bool,msg:String)->void:
	checks+=1
	if not ok:failed=true;push_error(msg)
func _initialize()->void:call_deferred("run")
func run()->void:
	var dir:String=OS.get_environment("HABITAT_DATA_DIR");assert(dir.contains("youqi-test-"))
	var w:=F.fresh();check(not w.hunger.has_method("pack") and not w.hunger.has_method("feed") and not w.life.fireside.has_method("pack_host"),"all raw/cooked feeding and packing APIs absent")
	check(F.harvest(w,"tomato"),"actual produce for hungry reaction")
	w.hunger.start();w.hunger.states.codex.elapsed=float(w.hunger.config.thresholds[3])+float(w.hunger.config.presentation.reaction_long_seconds)+20
	for frame in range(int(w.hunger.config.presentation.reaction_long_seconds*10)+1):w.advance(.1)
	var before:int=F.amount(w,"tomato");var pos:Array=w.actors.human.position.duplicate();var carry:Dictionary=w.actors.codex.carry.duplicate(true)
	for intent in ["feed","pack","eat"]:check(not w.command("human",{"intent":intent,"target_id":"home.barbecue","receiver_id":"codex","item_id":"tomato"}).ok,"removed route rejected without secret consumption: "+intent)
	check(F.amount(w,"tomato")==before and w.hunger.rank("codex")==3 and w.actors.human.position==pos and w.actors.codex.carry==carry,"removed food routes cannot consume restore fullness move human or gift local inventory")
	check(F.serve(w,"tomato-salad") and F.eat(w,"codex"),"only real invited barbecue eater restores fullness")
	check(w.hunger.rank("codex")==0 and w.hunger.statistics.meals==1 and F.amount(w,"tomato")==before-2,"actual recipe cost and one finished resident meal counted exactly once")
	check(w.hunger.reactions.codex.tier==3,"actual prolonged-hunger meal retains authored strongest reaction")
	# C: A reaction-only idle fixture explicitly opts out of default following.
	w.activities.default_follow_excluded.codex=true
	w.life.fireside.end_circle("host ends reaction fixture");w.director.routines.codex.set_enabled(true);w.advance(.1)
	check(not w.hunger.reaction("codex").is_empty(),"satisfied motion shown at real idle opportunity")
	w.director.set_held("codex",true);w.advance(.1)
	check(w.hunger.reaction("codex").is_empty() and w.hunger.rank("codex")==0,"held hides reaction without changing actual fullness")
	check(Save.save_world(w,dir.path_join("fed-by-fire")),"save actual meal")
	var loaded:=F.fresh();check(Save.load_world(loaded,dir.path_join("fed-by-fire")).ok and F.amount(loaded,"tomato")==before-2 and loaded.actors.human.carry.keys().all(func(k):return not str(k).begins_with("meal")),"reload preserves consumed ingredients without creating portable cooked food")
	check(loaded.work.jobs.is_empty() and loaded.work.claims.is_empty() and loaded.life.station.portions==0,"reload never restores meal jobs claims or leftovers")
	var neglect:=F.fresh();neglect.hunger.start()
	for frame in range(int(neglect.hunger.config.thresholds[3]*10)+20):neglect.advance(.1)
	check(neglect.hunger.rank("codex")==3 and neglect.hunger.rank("human")==-1,"unchanged actual hunger thresholds reach very hungry while human stays exempt")
	var fire:=F.fresh();check(F.mushroom(fire) and BBQ.light(fire),"real forage and real wood light a host fire")
	fire.hunger.start();var id:String="companion-2";fire.hunger.states[id].elapsed=float(fire.hunger.config.thresholds[2])+20
	fire.director.routines[id].set_enabled(true);fire.director.routines[id].next_speech=1e10;fire.director.speech_after=1e10
	fire.advance(.1);check(not fire.hunger.rushing(id),"mere burning fire never attracts uninvited glutton")
	check(fire.life.fireside.invite([id]).ok and fire.life.fireside.roast_host("single:mushroom").ok,"explicit selected resident plus actual roast starts invitation")
	fire.advance(.1)
	check(fire.hunger.rushing(id) and not fire.hunger.visible_cue(id).is_empty(),"invited hungry rush cue survives ordinary speech spacing")
	check(fire.director.events.any(func(e):return e.actor_id==id and e.context=="hunger_rush" and e.source=="local_rules"),"rush cue delivered by real Director gate without model")
	var cues:int=fire.director.events.filter(func(e):return e.context=="hunger_rush").size()
	for frame in range(5):fire.advance(.1)
	check(fire.director.events.filter(func(e):return e.context=="hunger_rush").size()==cues,"persistent come-here cue does not flood repeated utterances")
	fire.director.routines[id].chatter=false;check(fire.hunger.visible_cue(id).is_empty(),"chatter switch still hides rush cue")
	fire.director.routines[id].chatter=true;fire.director.set_held(id,true);fire.advance(.1)
	check(fire.hunger.visible_cue(id).is_empty() and not fire.hunger.rushing(id),"held cancels rush and hides bubble")
	check(not fire.hunger.try_rush(id,"home.barbecue"),"original rush cooldown survives cancellation")
	var happy:=F.fresh();check(F.mushroom(happy) and BBQ.light(happy),"not-hungry real fire fixture")
	happy.hunger.start();happy.director.routines[id].set_enabled(true)
	check(happy.life.fireside.invite([id]).ok and happy.life.fireside.roast_host("single:mushroom").ok,"peckish glutton can be explicitly invited")
	happy.advance(.1);check(not happy.hunger.rushing(id),"invitation alone does not override hunger threshold")
	print("Hunger tuning v4: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)
