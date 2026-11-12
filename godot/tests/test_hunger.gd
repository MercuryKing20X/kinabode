# DIRECTION 2026-11-07: 烤蘑菇永久无限供应，不扣任何食材；其它食材守恒断言保留。
extends SceneTree
const World=preload("res://scripts/world_state.gd")
const F=preload("res://tests/cooking_fixture.gd")
const B=preload("res://tests/backpack_fixture.gd")
const Save=preload("res://scripts/save_store.gd")
var checks:=0
var failed:=false
func check(ok:bool,msg:String)->void:
	checks+=1
	if not ok:failed=true;push_error(msg)
func _initialize()->void:call_deferred("run")
func run()->void:
	var dir:=OS.get_environment("HABITAT_DATA_DIR");assert(dir.contains("youqi-test-"))
	var w:=F.fresh();w.residents.provision(w);w.director.set_all_enabled(false);w.hunger.start()
	check(w.hunger.rank("human")==-1 and w.hunger.summary("human").is_empty(),"human never hungry")
	var s:Dictionary=w.hunger.states.codex;s.elapsed=0;s.full_meal=true
	w.advance(float(w.hunger.config.thresholds[1])-.1);check(w.hunger.rank("codex")==0,"before peckish boundary")
	w.advance(.2);check(w.hunger.rank("codex")==1,"real delta crosses peckish boundary")
	s.elapsed=float(w.hunger.config.thresholds[2])-.1;w.advance(.2);check(w.hunger.rank("codex")==2,"hungry boundary")
	check(is_equal_approx(w.movement_speed("codex")*32,125) and not w.is_running("codex"),"hungry empty speed is125 and cannot run")
	var rel:Dictionary=w.relationships.saved();w.advance(20);check(w.relationships.saved()==rel,"hunger never changes relationship scores")
	var save:Dictionary=w.hunger.saved();save.states.codex.elapsed=0;save.states.codex.full_meal=true;save.saved_at=Time.get_unix_time_from_system()-86400
	w.hunger.restore(save);check(w.hunger.states.codex.elapsed==float(w.hunger.config.thresholds[1]) and w.hunger.rank("codex")==1,"offline new advance capped at peckish")
	save.states.codex.elapsed=float(w.hunger.config.thresholds[3])+60;w.hunger.restore(save);check(w.hunger.rank("codex")==3,"offline does not manufacture satiety for already hungry resident")
	check(w.hunger.valid({},w.actors),"old save without hunger valid")
	var work:=F.fresh();check(F.job(work,"codex",{"intent":"chop","target_id":"home.tree.01"}),"real first tree hauled")
	var total:int=B.wood_total(work)
	check(work.command("codex",{"intent":"chop","target_id":"home.tree.02"}).ok,"real second task accepted before hunger")
	work.hunger.start();work.hunger.states.codex.elapsed=float(work.hunger.config.thresholds[3])-.1
	var human:Dictionary=work.actors.human.duplicate(true);work.advance(.2)
	check(not work.work.jobs.has("codex") and work.hunger.statistics.abandoned.size()==1,"very hungry abandons accepted own task")
	check(B.wood_total(work)==total and work.actors.human==human,"abandon preserves materials and never moves human")
	check(Save.save_world(work,dir.path_join("abandon")),"save after hunger abandonment")
	var loaded:=F.fresh();check(Save.load_world(loaded,dir.path_join("abandon")).ok and B.wood_total(loaded)==total and loaded.work.jobs.is_empty(),"reload has no duplicated material or restored jobs")
	var social:=F.fresh();social.residents.provision(social);social.hunger.start();social.director.set_all_enabled(true)
	for id in social.director.routines:social.director.set_held(id,true)
	for i in range(400):social.advance(.1)
	check(social.director.events.all(func(e):return not str(e.context).begins_with("hunger_")),"held blocks hunger speech")
	var routine:RefCounted=social.director.routines.codex;routine.held=false;routine.chatter=false
	for i in range(100):social.advance(.1)
	check(social.director.events.all(func(e):return not str(e.context).begins_with("hunger_")),"chatter off blocks hunger speech")
	var group:=F.fresh();group.residents.provision(group)
	check(F.mushroom(group) and preload("res://tests/barbecue_fixture.gd").start(group,"single:mushroom",["human","codex","companion-2"]).ok,"real host starts explicitly invited barbecue")
	for frame in range(200):
		group.advance(.1)
		if group.life.fireside.jobs.has("codex"):break
	var person:Dictionary=group.actors.human.duplicate(true);var supplies:Dictionary=group.life.station.supplies.duplicate(true)
	group.hunger.start();group.hunger.states.codex.elapsed=float(group.hunger.config.thresholds[3])-.1;group.advance(.2)
	check(group.life.fireside.jobs.has("codex") and group.work.jobs.get("codex",{}).get("intent")=="eat","very hungry never abandons real meal already resolving hunger")
	check(group.life.station.supplies==supplies and group.life.fireside.state.current.receipt.is_empty() and preload("res://tests/barbecue_fixture.gd").ate(group,"codex") and group.hunger.rank("codex")==0,"actual meal resolves hunger without new material or abandoned-task penalty")
	print("Hunger: ",checks," checks, failed=",failed);quit(1 if failed else 0)
