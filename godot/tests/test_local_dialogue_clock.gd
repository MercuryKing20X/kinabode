extends SceneTree
const W=preload("res://scripts/world_state.gd")
const F=preload("res://tests/cooking_fixture.gd")
class NoNeeds extends "res://scripts/resident_needs.gd":
	func choose(_world:RefCounted,_id:String)->Dictionary:return {}
class NoScenes extends "res://scripts/scene_speech.gd":
	func choose(_id:String)->Dictionary:return {}
var checks:=0
var failed:=false
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failed=true;push_error(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"))
	var w:=W.new()
	# Advance real time with the resident disabled; this is a clock-boundary unit,
	# independent from the separate600-second real viewport observation.
	w.advance(90)
	w.activities.default_follow_excluded.codex=true
	w.local_companion.set_enabled(true)
	var dialogue:RefCounted=w.director.local_dialogue
	dialogue.next_check=w.director.time
	var before:int=w.director.serial
	var speech_rng:int=w.local_companion.rng.state
	var action_rng:int=w.local_companion.decision_rng.state
	var scale:float=w.director.moods.interval("codex","speech")*w.personality.speech_scale("codex")
	dialogue.advance(1,false)
	check(dialogue.spoken_ready and dialogue.try_spoken() and w.director.serial==before+1,"one positive tick can deliver one genuinely eligible authored line")
	var gap:float=w.local_companion.next_speech-w.local_companion.time
	check(w.local_companion.rng.state==speech_rng and gap>=float(w.local_companion.config.speech_interval[0])*scale and gap<=float(w.local_companion.config.speech_interval[1])*scale,"actual new spoken line keeps original authored cadence and leaves the old speech RNG untouched")
	check(w.local_companion.decision_rng.state==action_rng,"new presentation cadence cannot consume the original movement RNG")
	var new_cadence:RandomNumberGenerator=dialogue.cadence_rngs.codex.rng
	var new_state:int=new_cadence.state
	var initial_cadence:=RandomNumberGenerator.new();initial_cadence.seed=w.local_companion.rng.seed
	check(new_state!=initial_cadence.state,"actual accepted delivery samples its own original-seed presentation stream")
	speech_rng=w.local_companion.rng.state
	check(not dialogue.spoken_ready and not dialogue.try_spoken() and w.director.serial==before+1,"a consumed spoken opportunity cannot be retried in the same advance")
	check(w.local_companion.rng.state==speech_rng,"consumed opportunity rejects without spending resident speech RNG")
	dialogue.spoken_ready=true
	before=w.director.serial
	dialogue.advance(0,false)
	check(not dialogue.spoken_ready and not dialogue.try_spoken() and w.director.serial==before,"advance zero clears stale opportunity and delivers no new spoken line")
	dialogue.next_check=INF
	dialogue.spoken_opportunity=true
	dialogue.advance(1,false)
	check(not dialogue.spoken_ready and not dialogue.try_spoken() and w.director.serial==before,"original optional-layer next-check isolation suppresses spoken as well as thoughts")
	dialogue.next_check=w.director.time
	dialogue.advance(1,false)
	w.local_companion.set_held(true)
	check(not dialogue.try_spoken() and not dialogue.spoken_ready and not dialogue.try_spoken() and w.director.serial==before,"a rejected held attempt consumes the opportunity without delivery or retry")
	check(not dialogue.spoken_opportunity,"a rejected attempt consumes the retained opportunity rather than retrying every frame")
	check(is_same(dialogue.cadence_rngs.codex.rng,new_cadence) and new_cadence.state==new_state,"all consumed, zero-delta, INF and held rejections leave the presentation RNG undrawn and unreplaced")
	fairness_probe()
	original_turn_probe()
	derived_mood_turn_probe()
	solo_kind_phase_probe()
	print("Local dialogue clock boundaries: ",checks," failed=",failed);quit(1 if failed else 0)
func fairness_probe()->void:
	var w:RefCounted=F.fresh()
	# Actual World routes prepare two stationary listeners and an ordinary
	# speaker. No positions, items, need flags or receipt history are injected.
	var human:Vector2=w.point(w.actors.human)
	for pair in [["codex",Vector2(2,0)],["companion-2",Vector2(3,0)],["npc.mira",Vector2(0,2)]]:
		var reached:=false
		for offset in [pair[1],Vector2(1,0),Vector2(-1,0),Vector2(0,1),Vector2(0,-1)]:
			var at:Vector2=human+offset
			if w.walkable(w.actors[pair[0]].region_id,at) and F.job(w,pair[0],{"intent":"move","x":at.x,"y":at.y}):reached=true;break
		check(reached,"fairness fixture reaches real nearby position "+str(pair[0]))
	w.advance(90)
	baseline_clock_facts(w,["codex","companion-2"])
	for id in ["codex","companion-2"]:
		w.activities.default_follow_excluded[id]=true
		w.director.routines[id].set_enabled(true)
		w.director.routines[id].next_decision=INF
	var d:RefCounted=w.director.local_dialogue
	var before:int=w.director.serial
	d.next_check=w.director.time;d.advance(1,false)
	check(not w.director.try_new_spoken() and w.director.old_spoken_credit==0 and w.director.serial==before,"new exchange cannot borrow before any ordinary delivery")
	# Zero gaps are arguments of this isolated commit-accounting probe, not
	# changes to any authored content parameter or gameplay speech cadence.
	var lines:Array=w.local_companion.config.lines.ambient
	check(w.director.say_local("codex",lines[0],"ordinary_probe",0,0) and w.director.say_local("companion-2",lines[1],"ordinary_probe",0,0),"two genuine ordinary commits are credited")
	d.next_check=w.director.time;d.advance(1,false)
	check(w.director.old_spoken_credit==2 and not w.director.try_new_spoken(),"two ordinary deliveries do not satisfy three-to-one allowance")
	check(w.director.say_local("codex",lines[2],"ordinary_probe",0,0),"third genuine ordinary commit earns village allowance")
	d.next_check=w.director.time;d.advance(1,false)
	before=w.director.serial
	check(w.director.old_spoken_credit==3 and int(w.director.old_spoken_actor.get("codex",0))==2 and not w.director.try_new_spoken() and w.director.serial==before,"village allowance cannot spend another resident's unearned personal speech turn")
	check(w.director.say_local("codex",lines[3],"ordinary_probe",0,float(w.director.moods.config.village_gap)),"actual owner earns third personal allowance while retaining original shared gap")
	d.next_check=w.director.time;d.advance(1,false)
	before=w.director.serial
	check(not w.director.try_new_spoken() and d.spoken_opportunity and w.director.old_spoken_credit==3,"closed shared outlet preserves one earned opportunity without attempting or debiting")
	# Reproduce the independent one-second check phase relative to the shared
	# outlet. This unit timer fixture never changes the authored speech gap.
	d.next_check=w.director.time+.35
	var until:float=w.director.speech_after
	for tick in range(ceili((until-w.director.time)/.1)+2):w.advance(.1)
	var opened:Array=w.director.events.filter(func(e):return e.serial>before)
	if not (opened.size()==1 and opened[0].context=="local_pair" and w.director.old_spoken_credit==0 and d.pending.get("index")==1):
		var actors:Dictionary={}
		for id in ["codex","companion-2"]:
			var r:RefCounted=w.director.routines[id]
			actors[id]={"point":w.actors[id].position,"kind":r.kind,"idle":d.idle(id),"route":w._routes.get(id),"local_route":r.owns_route,"due":r.next_speech,"time":r.time,"actor_credit":w.director.old_spoken_actor.get(id,0),"pair_budget":d.pair_budget(id)}
		print("CLOCK_PAIR_FIXTURE_DIAG opened=",opened," actors=",actors," credit=",w.director.old_spoken_credit," lease=",d.spoken_opportunity," next_check=",d.next_check," pending=",d.pending," pairs=",d.pair_diagnostics," lively_active=",w.lively.active," lively_approaching=",w.lively.approaching)
	check(opened.size()==1 and opened[0].context=="local_pair" and w.director.old_spoken_credit==0 and d.pending.get("index")==1,"retained opportunity delivers exactly one paired first line when original shared gate opens between checks")
	if d.pending.is_empty():return
	var reply:String=d.pending.lines[1].actor_id
	before=w.director.serial
	d.advance(0,false)
	check(not w.director.try_new_spoken() and w.director.serial==before and w.director.old_spoken_credit==0,"zero delta cannot borrow a pending reply turn")
	w.director.routines[reply].set_held(true)
	d.spoken_ready=true
	check(not d.reply_ready() and not w.director.try_new_spoken() and w.director.old_spoken_credit==0,"held reply cannot bypass original barriers or debit allowance")
	w.director.routines[reply].set_held(false)
	# The original ordinary candidate is live throughout these actual frames.
	# At the shared outlet opening, the already-started reply must win first.
	var first_after:int=w.director.serial
	for tick in 300:
		w.advance(.1)
		if d.pending.is_empty():break
	var after:Array=w.director.events.filter(func(e):return e.serial>first_after)
	check(d.delivered.any(func(e):return e.kind=="dialogue_group") and not after.is_empty() and after[0].context=="local_pair","pending reply wins before ordinary speech only once original personal and shared gates open")
	check(w.director.old_spoken_credit==-3,"a genuinely delivered reply records bounded three-credit debt")
	check(int(w.director.old_spoken_actor.get("companion-2",0))==-2 and int(w.director.old_spoken_actor.get("codex",0))==0,"actual reply debits only its own earned credit and bounded personal debt")
	wait_original_speech(w)
	w.director.routines["npc.mira"].set_enabled(true)
	var repayment:Array=w.director.routines["npc.mira"].config.lines.ambient.duplicate()
	repayment.append_array(w.director.routines["npc.mira"].config.lines.near)
	for index in 6:
		check(w.director.say_local("npc.mira",repayment[index],"ordinary_probe",0,0),"actual ordinary delivery repays one credit "+str(index))
		if index<5:
			d.next_check=w.director.time;d.advance(1,false)
			check(not w.director.try_new_spoken(),"unpaid reply debt cannot start another exchange "+str(index))
	check(w.director.old_spoken_credit==3,"six real ordinary deliveries repay debt and earn the next three-to-one turn")
	wait_original_speech(w)
	d.next_check=w.director.time;d.advance(1,false)
	check(w.director.try_new_spoken() and w.director.old_spoken_credit==0,"new authored speech resumes only after actual ordinary repayment")
func wait_original_speech(w:RefCounted)->void:
	var chatter:Dictionary={}
	var until:float=w.director.speech_after
	for id in ["codex","companion-2","npc.mira"]:
		var r:RefCounted=w.director.routines[id]
		chatter[id]=r.chatter;r.set_chatter(false)
		until=maxf(until,r.next_speech)
	# Isolate only this unit's commit-accounting fixture while genuinely
	# advancing through the unchanged personal and shared speech gates.
	for tick in range(ceili(maxf(0,until-w.director.time)/.1)+2):w.advance(.1)
	for id in chatter:w.director.routines[id].set_chatter(chatter[id])
func original_turn_probe()->void:
	# Match the established ordinary due-order unit: real nearby World routes,
	# a NoNeeds fixture and only this optional weather reaction baselined.
	for expected in ["npc.mira","codex"]:
		var w:RefCounted=F.fresh()
		for id in ["codex","npc.mira"]:check(F.job(w,id,{"intent":"come_near"}),"actual nearby original-turn listener "+id)
		w.advance(90)
		baseline_clock_facts(w,["codex","npc.mira"])
		for id in ["codex","npc.mira"]:
			var r:RefCounted=w.director.routines[id]
			w.activities.default_follow_excluded[id]=true
			r.set_enabled(true);r.next_decision=INF;r.was_busy=false;r.needs=NoNeeds.new()
			var earned:Array=r.config.lines.ambient.duplicate();earned.append_array(r.config.lines.near)
			for index in 6:check(w.director.say_local(id,earned[index],"ordinary_probe",0,0),"actual earned personal bank commit "+id+":"+str(index))
			check(int(w.director.old_spoken_actor.get(id,0))==6,"earned bank retains more than three actual deliveries "+id)
		check(w.director.old_spoken_credit==3,"village cap remains three while personal earnings are preserved")
		var d:RefCounted=w.director.local_dialogue
		d.next_pair=INF;d.cursor=0;d.spoken_opportunity=true;d.next_check=w.director.time+1
		for id in ["codex","npc.mira"]:
			# Fixed relative due times are an arbitration fixture, not a changed
			# authored interval. They mirror the existing idle_order regression.
			w.director.routines[id].next_speech=w.director.routines[id].time-(2 if id==expected else 1)
		var before:int=w.director.serial;var positions:Dictionary={}
		var before_gates:Dictionary={}
		for id in ["codex","npc.mira"]:before_gates[id]={"day_defer":w.days.defer_idle(id),"factual":w.personality.factual(id),"due":w.director.routines[id].next_speech,"credit":w.director.old_spoken_actor.get(id,0)}
		for id in w.actors:positions[id]=w.actors[id].position.duplicate()
		w.director.advance(.5)
		var actual:Array=w.director.events.filter(func(e):return e.serial>before)
		if not (actual.size()==1 and actual[0].actor_id==expected and actual[0].context in ["local_host","local_sense"]):
			print("CLOCK_ORIGINAL_ACTOR_DIAG expected=",expected," actual=",actual," before_gates=",before_gates," candidates=",w.director.idle_candidates," lease=",d.spoken_opportunity," credit=",w.director.old_spoken_credit," actors_credit=",w.director.old_spoken_actor)
		check(actual.size()==1 and actual[0].actor_id==expected and actual[0].context in ["local_host","local_sense"],"new single speech replaces only the actual earliest ordinary actor "+expected)
		var other:String="codex" if expected=="npc.mira" else "npc.mira"
		check(int(w.director.old_spoken_actor.get(expected,0))==3 and int(w.director.old_spoken_actor.get(other,0))==6 and w.director.old_spoken_credit==0,"only the actual new speaker spends their own earned bank")
		check(w.actors.keys().all(func(id):return w.actors[id].position==positions[id]) and w.work.jobs.is_empty(),"original-turn selection never moves an actor or starts a task")
func baseline_clock_facts(w:RefCounted,ids:Array)->void:
	# Like idle_priority(), this isolated ordinary-outlet unit baselines only
	# already-due calendar/weather reactions. No gameplay memory or save is made.
	w.days.marked_day=w.days.day()
	if w.days.phase().id not in w.days.spoken:w.days.spoken.append(w.days.phase().id)
	if w.days.small.is_empty():w.days.small={"status":"completed"}
	for id in ids:
		var fact:Dictionary=w.personality.factual(id)
		if fact.get("context","") in ["rain","fog"] and fact.key not in w.personality.reacted:w.personality.reacted.append(fact.key)
func derived_mood_turn_probe()->void:
	var w:RefCounted=F.fresh()
	check(F.job(w,"codex",{"intent":"come_near"}),"actual nearby listener for derived mood outlet")
	w.advance(90)
	baseline_clock_facts(w,["codex"])
	var r:RefCounted=w.director.routines.codex
	w.activities.default_follow_excluded.codex=true
	r.set_enabled(true);r.next_decision=INF;r.was_busy=false;r.needs=NoNeeds.new()
	var earned:Array=r.config.lines.ambient.duplicate();earned.append_array(r.config.lines.near)
	for index in 6:check(w.director.say_local("codex",earned[index],"ordinary_probe",0,0),"actual pre-transition earned speech "+str(index))
	w.director.set_all_enabled(false)
	# Genuine elapsed inactivity changes the derived state. Neither mood time
	# nor old delivery time is assigned by the fixture.
	w.advance(float(w.director.moods.config.inactive_seconds)+1)
	check(w.director.moods.summary("codex").id=="quiet" and float(w.director.moods.changed_at.codex)>float(w.director.old_spoken_at.codex),"actual inactivity creates an unspoken derived mood transition")
	baseline_clock_facts(w,["codex"])
	w.scene_speech=NoScenes.new(w)
	r.set_enabled(true);r.next_decision=INF;r.was_busy=false
	var d:RefCounted=w.director.local_dialogue
	d.next_pair=INF;d.next_check=w.director.time;d.advance(1,false)
	var before:int=w.director.serial
	w.director.advance(.1)
	var actual:Array=w.director.events.filter(func(e):return e.serial>before)
	check(actual.size()==1 and actual[0].text in w.personality.pool("codex","quiet") and actual[0].context not in ["local_host","local_sense","local_pair"],"first original mood-pool feedback survives an otherwise funded new replacement")
	check(int(w.director.old_spoken_actor.codex)==7 and w.director.old_spoken_credit==3,"only the real old mood delivery earns its allowance")
	wait_original_speech(w)
	d.next_check=w.director.time;d.advance(1,false)
	check(w.director.try_new_spoken("codex") and int(w.director.old_spoken_actor.codex)==4 and w.director.old_spoken_credit==0,"new authored speech resumes after actual mood feedback and unchanged personal/shared gates")

func solo_phase_wait(w:RefCounted,ticks:Dictionary,need_solo:bool)->bool:
	var r:RefCounted=w.director.routines.codex
	var d:RefCounted=w.director.local_dialogue
	# As in wait_original_speech(), this component fixture silences automatic
	# delivery only while real time advances through unchanged authored gates.
	r.set_chatter(false)
	while int(ticks.used)<6000:
		w.advance(.1);ticks.used=int(ticks.used)+1
		r.set_chatter(true)
		var ready:bool=d.idle("codex") and w.director.can_say_local("codex","local_host")
		if need_solo:
			ready=ready and w.director.time>=float(d.host_due.get("codex",30+posmod(hash("codex"),30))) and d.spoken_ready and d.cursor%2==1
		if ready:return true
		r.set_chatter(false)
	r.set_chatter(true)
	return false

func solo_kind_phase_probe()->void:
	var w:RefCounted=F.fresh()
	# Fix this new, unadvanced fixture's epoch before any real route. No retained
	# growth, receipts or resources are rewritten, and every wait below advances.
	w.forest.clock=2000000000.0;w.days.origin=2000000000.0
	var coast_ready:=false
	for coast in w.fishing.nearby_shores("human",32):
		var at:=Vector2(coast.position[0],coast.position[1])
		if not F.job(w,"human",{"intent":"move","x":at.x,"y":at.y}):continue
		if not F.job(w,"codex",{"intent":"move","x":at.x,"y":at.y}):continue
		if not w.fishing.shore("codex").is_empty() and not w.fishing.shore("human").is_empty():coast_ready=true;break
	check(coast_ready,"solo-kind fixture reaches a real natural coast through World routes")
	if not coast_ready:return
	baseline_clock_facts(w,["codex"])
	w.scene_speech=NoScenes.new(w)
	var r:RefCounted=w.director.routines.codex
	w.activities.default_follow_excluded.codex=true
	r.rng.seed=420;r.set_enabled(true);r.next_decision=INF;r.was_busy=false;r.needs=NoNeeds.new()
	var d:RefCounted=w.director.local_dialogue
	var ticks:Dictionary={"used":0}
	var rows:Array=[]
	var human:Dictionary=w.actors.human.duplicate(true)
	var all_slots:=true
	for turn in 4:
		# Earn all three personal and village credits from actual old authored
		# deliveries. _speak retains its real RNG/cadence/shared/personality gates.
		for ordinary in 3:
			if not solo_phase_wait(w,ticks,false):all_slots=false;break
			var before:int=w.director.serial
			r._speak("ambient")
			check(w.director.serial==before+1,"phase fixture earns one actual original authored delivery %s:%s"%[turn,ordinary])
			if w.director.serial!=before+1:all_slots=false;break
		if not all_slots:break
		if not solo_phase_wait(w,ticks,true):all_slots=false;break
		var sense:Dictionary=d.choose("codex","sense")
		var host:Dictionary=d.choose("codex","host")
		check(not sense.is_empty() and not host.is_empty() and "sea" in d.contexts("codex"),"both original solo kinds are eligible at the real coast "+str(turn))
		check(w.director.old_spoken_credit==3 and int(w.director.old_spoken_actor.get("codex",0))>=3,"same odd-phase opportunity has three genuinely earned old credits "+str(turn))
		var before:int=w.director.serial
		var cursor:int=d.cursor
		var delivered:bool=w.director.try_new_spoken("codex")
		check(delivered and w.director.serial==before+1,"one real gated solo line is delivered at the odd check phase "+str(turn))
		var commits:Array=d.delivered.filter(func(e):return e.get("actor_id","")=="codex" and e.kind in ["sense","host"])
		rows.append({"turn":turn,"cursor":cursor,"time":w.director.time,"sense_candidate":sense.get("id",""),"host_candidate":host.get("id",""),"actual":commits.back().kind if not commits.is_empty() else "none"})
		if not delivered:all_slots=false;break
	var senses:int=d.delivered.filter(func(e):return e.get("actor_id","")=="codex" and e.kind=="sense").size()
	var hosts:int=d.delivered.filter(func(e):return e.get("actor_id","")=="codex" and e.kind=="host").size()
	print("CLOCK_SOLO_PHASE_DIAG ",JSON.stringify({"rows":rows,"sense":senses,"host":hosts,"advance_ticks":ticks.used,"coast":w.fishing.shore("codex"),"old_credit":w.director.old_spoken_credit}))
	check(all_slots and rows.size()==4 and rows.all(func(row):return int(row.cursor)%2==1),"four original-gated solo opportunities reproduce the same odd timer phase")
	check(senses>0 and hosts>0,"successful solo deliveries serve both content kinds despite one-second check phase")
	check(w.actors.human==human,"solo content arbitration never moves or changes the human")
