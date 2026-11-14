extends SceneTree
var failed:=false
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var w:=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");w.residents.provision(w)
	w.library=preload("res://scripts/character_library.gd").new();w.library.configure(OS.get_environment("HABITAT_DATA_DIR"))
	preload("res://scripts/world_opening.gd").apply(w,w.library,"standard");w.intelligence.activate_presets();w.hunger.start();w.director.set_all_enabled(true)
	var b:RefCounted=w.director.brains.codex
	var original:Dictionary=w.storage.saved().duplicate(true)
	for tick in 80:w.advance(.25)
	check(not b.current.is_empty(),"idle has a real selected activity")
	var before:int=b.rng.state
	for tick in 50:w.lively.rng.randf();w.director.routines.codex.rng.randf()
	check(b.rng.state==before,"speech and presentation RNG never consume brain entropy")
	w.activities.set_followers([])
	check(not b.candidates().any(func(c):return c.action=="follow"),"explicit release gives free life before a later social return")
	var choice:String=str(b.current.get("action",""))
	var old_appearance:String=w.actors.codex.appearance_id
	check(w.assign_appearance("codex","ai-claude"),"nondefault editable appearance")
	check(str(b.current.get("action",""))==choice and w.actors.codex.appearance_id!=old_appearance,"identity brain survives appearance change")
	var receiver:RefCounted=w.director.brains["companion-2"]
	receiver.begin_external("command","watch")
	check(not b.invite("companion-2","chat"),"invitation cannot preempt player order")
	receiver.finish("completed")
	receiver.needs.tired=.9
	check(not b.invite("companion-2","chat"),"tired recipient declines social invitation")
	receiver.needs.tired=0
	check(b.invite("companion-2","chat"),"available recipient receives candidate invitation")
	check(receiver.invitation.get("from")=="codex","invitation bound to exact sender")
	w.hunger.ensure("codex");w.hunger.states.codex.elapsed=float(w.hunger.config.thresholds[3])
	check(b.candidates().all(func(c):return c.action=="food"),"very hungry restricts entire candidate set")
	for tick in 100:w.advance(.25)
	check(w.storage.saved()==original,"utility and invitations conserve every warehouse item")
	check(w.work.jobs.values().all(func(job):return not str(job.get("intent","")).contains("chop")),"no unsolicited labor")
	for locale in ["zh","en"]:
		var state:Dictionary=b.summary(locale)
		check(not state.sentence.is_empty() and state.recent.size()<=5,"bilingual bounded mind panel "+locale)
		check(state.needs.values().all(func(word):return word is String),"needs expose words only "+locale)
	var Save=preload("res://scripts/save_store.gd")
	check(Save.save_world(w,OS.get_environment("HABITAT_DATA_DIR")),"save original physical world")
	check(Save.load_world(w,OS.get_environment("HABITAT_DATA_DIR")).get("loaded",false),"reload valid world")
	check(b.current.is_empty() and b.history.is_empty(),"reload does not resume decisions or invent history")
	check(w.storage.saved()==original,"reload conserves real items")
	print("BRAIN_CONTRACT ",checks," failed=",failed);quit(1 if failed else 0)
