extends SceneTree
const Fixture=preload("res://tests/test_barbecue_v2.gd")
var checks:=0
var failed:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func step(w:RefCounted,seconds:float)->void:
	for frame in range(ceili(seconds/.1)):w.advance(.1)
func _initialize()->void:call_deferred("run")
func run()->void:
	var helper:=Fixture.new();var w:RefCounted=helper.fresh(OS.get_environment("HABITAT_DATA_DIR"));var f:RefCounted=w.life.fireside
	check(helper.pickup(w,"wood",4) and helper.pickup(w,"mushroom",5) and helper.approach(w,w.life),"real wood and food brought by human")
	check(f.light_host().ok and f.light_host().ok and f.invite(["codex","companion-2","npc.mira","npc.nora"]).ok and f.roast_host("single:turnip").ok,"actual shared batch with real renewed fuel")
	# B: DIRECTION: “从开烤那一刻起计…烤蘑菇30秒，其他普通料理60秒…到点散场。”
	# Genuine initial ordinary-food stock leaves room to exercise retained dialogue gates.
	for frame in range(300):
		w.advance(.1)
		if f.state.current.eaten==5:break
	check(f.state.current.eaten==5,"real five people finish")
	w.director.set_all_enabled(true)
	for r in w.director.routines.values():r.next_speech=0
	w.director.speech_after=w.director.time+1000
	var serial:int=w.director.serial;var times:Array=[];var max_visible:=0
	for frame in range(300):
		w.advance(.1);max_visible=maxi(max_visible,f.dialogue.visible.size())
		for e in w.director.events:
			if e.serial<=serial:continue
			serial=e.serial
			if str(e.context).begins_with("fireside_"):
				times.append(e.time);check(e.source=="local_rules" and e.actor_id in f.state.attended,"shared outlet has real seated author/source")
	check(times.size()>=4,"mini conversations rotate despite ordinary village gap")
	for i in range(1,times.size()):check(times[i]-times[i-1]>=4.99,"five to eight second intra-conversation pacing never floods")
	check(max_visible<=2,"at most two simultaneous fireside bubbles")
	check(f.dialogue.facts("codex","food").food=="烤萝卜" and f.dialogue.facts("codex","catch").is_empty(),"food comes from own actual eating; absent catch never invented")
	check(f.dialogue.facts("codex","relationship").is_empty(),"no fictional relationship milestone")
	var owned_job:String=str(f.jobs.codex)
	check(w.observe("codex").has("self") and f.jobs.get("codex")==owned_job and not f.circle_closed,"read-only model observation cannot cancel fireside")
	var r:RefCounted=w.director.routines.codex
	r.next_speech=0;r.set_chatter(false)
	check(not w.director.say_fireside("codex","关闭时不说","fireside_test",w.life.station.id),"chatter off gate")
	r.set_chatter(true);r.next_speech=r.time+50
	check(not w.director.say_fireside("codex","冷却中不说","fireside_test",w.life.station.id),"personal cooldown retained")
	r.next_speech=0;w.hunger.quiet_until.codex=w.director.time+120
	check(not w.director.say_fireside("codex","停止后不说","fireside_test",w.life.station.id),"stop quiet retained")
	w.hunger.quiet_until.clear();r.held=true
	check(not w.director.say_fireside("codex","问题中不说","fireside_test",w.life.station.id),"held question gate")
	step(w,.2);check(f.circle_closed and f.jobs.is_empty() and w.work.claims.is_empty(),"held participant ends circle and accurately releases jobs and seats")
	check(f.dialogue.visible.is_empty() and f.dialogue.pending.is_empty(),"interruption clears queued and visible local chat")
	r.held=false;step(w,10);check(f.jobs.is_empty(),"hungry or near actors do not restart interrupted gathering")
	check(not f.has_method("resume_host"),"removed old-batch resume API unavailable")
	check(f.light_host().ok,"host explicitly starts a new consent after ended circle")
	# The initial four actual tomatoes pay these two later two-diner meals (2+2).
	check(f.invite(["codex"]).ok and f.roast_host("single:tomato").ok,"new actual selection starts real invited food")
	for frame in range(1800):
		w.advance(.1)
		if f.jobs.has("codex"):break
	check(f.jobs.has("codex"),"codex actually joins before assembly gate is tested")
	w.activities.members.codex=true;r.next_speech=0
	check(not w.director.say_fireside("codex","集合中不说","fireside_test",w.life.station.id),"assembly gate")
	step(w,.2);check(f.circle_closed,"assembly ends circle")
	w.activities.members.clear();f.light_host();check(f.invite(["codex"]).ok and f.roast_host("single:tomato").ok,"new actual selection starts real invited food")
	for frame in range(1800):
		w.advance(.1)
		if f.jobs.has("codex"):break
	check(f.jobs.has("codex"),"codex actually joins before assembly gate is tested")
	# A real player command leaves consent false. No engine movement of the human follows.
	var p:Vector2=w.point(w.actors.human)
	f.command_received("human");step(w,2)
	check(w.point(w.actors.human)==p and not f.state.consent,"no implicit human move after command")
	check(w.command("human",{"intent":"move","x":p.x,"y":p.y+10}).ok,"human explicitly walks beyond the fire radius")
	step(w,10);check(not f.circle_closed,"walking away has thirty second grace")
	step(w,35);check(f.circle_closed and f.jobs.is_empty(),"host really absent thirty seconds ends circle")
	f.after_load();check(f.dialogue.pending.is_empty() and not f.state.consent and f.jobs.is_empty(),"reload clears presentation and does not resume work")
	helper.free();print("Fireside chat: ",checks," checks, failed=",failed);quit(1 if failed else 0)
