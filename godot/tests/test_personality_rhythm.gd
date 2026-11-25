extends SceneTree
const F=preload("res://tests/cooking_fixture.gd")
var checks:=0
var failed:=false
func _initialize() -> void:call_deferred("run")
func check(ok: bool,text: String) -> void:
	checks+=1
	if not ok:failed=true;push_error(text)
func run() -> void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):quit(1);return
	var w:=F.fresh();var counts: Dictionary={};var serial:=0
	# C: Measure the original personality idle cadence, independently of the
	# separately covered authored pair/host/sense conversation scheduler.
	w.director.local_dialogue.next_check=INF
	w.personality.config.fact_events_enabled=false
	w.days.config.greeting_after=w.days.day_seconds+1;w.days.config.small_after=w.days.day_seconds+1
	for id in w.director.routines:
		w.activities.default_follow_excluded[id]=true
		check(F.job(w,id,{"intent":"come_near"}),"explicit QA places companion in same nearby scene")
		var r: RefCounted=w.director.routines[id];r.rng.seed=27;r.set_enabled(true);r.set_chatter(true);r.next_decision=INF
		for key in r.preferences.weights:r.preferences.weights[key]=0
		counts[id]=0
	var human:=JSON.stringify(w.actors.human);var items:=F.amount(w,"wood")
	for frame in range(7200):
		w.advance(.5)
		for e in w.director.events:
			if e.serial>serial:counts[e.actor_id]+=1;serial=e.serial
	check(counts["npc.mira"]>counts["companion-2"] and counts["companion-2"]>=counts.codex and counts.codex>counts["npc.nora"],"same-position real one-hour delivered speech follows lively/curious/gentle/quiet")
	for id in counts:
		check(counts[id]>0,"each companion still has real visible lines")
		check(w.personality.spoken.get(id,{}).values().all(func(times):return times.size()<=2),"same line at most twice per genuine hour")
	check(JSON.stringify(w.actors.human)==human and F.amount(w,"wood")==items,"cadence never moves human or alters physical inventory")
	check(w.personality.speech_scale("npc.mira")<w.personality.speech_scale("npc.nora"),"personality configuration controls idle cadence only")
	check(F.job(w,"codex",{"intent":"chop","target_id":"home.tree.01"}),"explicit real task still completes with idle cadence layer")
	print("Personality rhythm: %s checks, failed=%s counts=%s"%[checks,failed,counts]);quit(1 if failed else 0)
