extends SceneTree
const Click=preload("res://tests/barbecue_ui_fixture.gd")
class TransportStub extends Node:
	func close()->void:pass
class Fake extends "res://scripts/companion_link.gd":
	var sent:Array=[]
	func _ready()->void:
		super._ready();direct_api=TransportStub.new();add_child(direct_api)
	func _start()->bool:return false
	func _send(_value:Dictionary)->bool:return false
	func uses_intents()->bool:return true
	func probe_connection()->bool:handshake_ready=true;return true
	func send_autonomy(context:Dictionary,_level:String,_limits:Dictionary,key:String)->bool:
		if is_busy():return false
		turn_kind="autonomy_event";turn_key=key;_generation+=1;_busy=true
		sent.append(context.duplicate(true));return true
var game:Node
var w:RefCounted
var meet:RefCounted
var daily:RefCounted
var failures:=0
var checks:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	print("MEETING %s %s"%[label,ok])
	if not ok:failures+=1
func step(seconds:float)->void:
	for i in int(seconds*10):
		w.advance(.1);meet.tick();daily.advance(.1)
func plan(id:String,activity:String,extra:Dictionary={})->bool:
	var b:RefCounted=w.director.brains[id]
	b.intention.card()
	return b.intention.accept({"activity":activity,"reason":"I think this would be nice today."}.merged(extra))
func receipt(event:String,who:String="",value:String="")->bool:
	return meet.records.any(func(row):return row.event==event and (who.is_empty() or row.recipient==who) and (value.is_empty() or row.get("decision","")==value))
func run()->void:
	var dir:String=OS.get_environment("HABITAT_DATA_DIR")
	if not dir.contains("youqi-test-"):quit(2);return
	OS.set_environment("HABITAT_OPENING","standard")
	var pool:Node=preload("res://scripts/connection_session_pool.gd").obtain(self,dir)
	pool.factory=func(_id):return Fake.new()
	game=load("res://scenes/main_v3.tscn").instantiate()
	game.dialogue_adapter_factory=func(_id,_scope):return Fake.new()
	root.add_child(game);game.save_enabled=false;game.set_process(false)
	await process_frame;await process_frame
	game.memory_life.set_process(false);game.life_archive.set_process(false)
	w=game.world;meet=game.autonomy.meetings;daily=game.life_archive.daily
	game.autonomy.tick(0)
	var white:RefCounted=w.director.brains.codex
	var blue:RefCounted=w.director.brains["companion-2"]
	var human:Array=w.actors.human.position.duplicate()
	var stock:Dictionary=w.storage.saved()
	for id in ["codex","companion-2"]:
		game._ensure_link(id);w.director.set_controller(id,"model")
		game.resident_connections.preferences.choose(id,"lifeblood")
		game.resident_connections.preferences.enable_autonomy(id,true)
	w.advance(.1)
	game.autonomy.tick(0)
	game.autonomy.refresh_support()
	check(plan("codex","watch_sea",{"place":"sea","with":"companion-2"}),"a connected partner appears on the ready list")
	step(1)
	if not receipt("heart_peer_delivered","companion-2"):print("PEER_DIAGNOSTIC ",white.current," ",white.intention.pending," ",white.intention.feedback_rows," ",white.intention.outings.meetings==meet)
	check(receipt("heart_peer_delivered","companion-2"),"one recipient receives the real invitation")
	var host_id:String=white.current.get("ai_plan",{}).get("host_id","missing")
	white.intention.changed()
	check(game.autonomy.dispatch("codex",{},{"tools":1},"white-thinking"),"white can think while walking or waiting")
	check(game.autonomy.dispatch("companion-2",{},{"tools":1},"blue-answer"),"blue has a separate simultaneous request")
	var link:Fake=game.links["companion-2"]
	check(link.sent.size()==1 and link.sent[0].heart_card.get("peer_request",{}).get("id")==host_id,"only the exact invitation enters blue's own turn")
	var reply:Dictionary={"id":host_id,"decision":"accept","reason":"Let's go! I want to hear the waves."}
	meet.answer("codex",host_id,"blue-answer",reply);meet.answer("companion-2",host_id,"stale",reply)
	check(not receipt("heart_peer_decided","companion-2"),"wrong actor and revoked turn cannot start either body")
	meet.answer("companion-2",host_id,"blue-answer",reply)
	check(receipt("heart_peer_decided","companion-2","accepted"),"model's own answer includes a reason")
	# Let the fake turn release its existing link lease.
	link._accept_event({"kind":"state","state":"ready","turnComplete":true})
	game.links.codex._accept_event({"kind":"state","state":"ready","turnComplete":true})
	step(70)
	if not receipt("heart_peer_together","companion-2"):print("ARRIVAL_DIAGNOSTIC ",meet.records," ",blue.current," ",w.actors["companion-2"].position," ",w.actors.codex.position)
	check(receipt("heart_peer_together","companion-2"),"two original World routes reach the same outing")
	check(white.intention.recent.any(func(row):return row.id==host_id and row.outcome=="completed"),"shared outing completes instead of disappearing")
	check(meet.records.filter(func(row):return row.invitation_id==host_id and row.event=="heart_peer_spoken").size()<=4,"one capped dialogue; original speech gap remains")
	check(w.actors.human.position==human and w.storage.saved()==stock,"partner invitation never moves or charges the player")
	var orange:RefCounted=w.director.brains["npc.mira"]
	check(plan("npc.mira","visit",{"place":"plaza","with":"companion-2"}),"a new pair can ask separately during the first pair's cooldown")
	step(1)
	var refused:String=orange.current.get("ai_plan",{}).get("host_id","")
	check(game.autonomy.dispatch("companion-2",{},{"tools":1},"blue-refusal"),"the invitee can consider a different invitation")
	game.autonomy.scheduler.active["companion-2"]={"id":"blue-refusal"}
	link._accept_event({"kind":"intent_result","turn_key":"blue-refusal","speech":"","peer_reply":{"id":refused,"decision":"decline","reason":"I need a little time on my own."}})
	game.autonomy.scheduler.active.erase("companion-2")
	link._accept_event({"kind":"state","state":"ready","turnComplete":true})
	step(1)
	check(meet.records.any(func(row):return row.invitation_id==refused and row.event=="heart_peer_decided" and row.decision=="declined" and row.source=="model"),"actual bound refusal reaches the inviter with the model reason")
	check(not blue.current.has("heart_guest") and not meet.records.any(func(row):return row.invitation_id==refused and row.event=="heart_peer_departed"),"declining never orders the invitee's body")
	check(orange.current.get("outing_job",{}).get("phase")=="walk","inviter continues on her own World route")
	# Keep the player in the same real world; use existing World positions.
	check(plan("codex","visit_flowers",{"place":"flower_isle","for_player":"invite","player_card":{"question":"See the roses with me?","options":[{"id":"yes","text":"Yes"},{"id":"later","text":"Maybe later"}]}}),"AI authors a bounded card for a real destination")
	for i in 200:
		step(.1)
		if daily.cards.has("codex"):break
	await process_frame;daily.advance(.1);await process_frame
	check(daily.cards.has("codex"),"the card really appears beside the player")
	if daily.cards.has("codex"):
		var button:Button=daily.cards.codex.panel.get_node("body/answer_yes")
		check(await Click.click(self,button),"actual mouse clicks the exact yes button")
		check(w._routes.has("human"),"only yes issues a human World route")
	step(75)
	check(daily.invitation_trace.any(func(row):return row.event=="heart_player_resolved" and row.result=="yes"),"host records real player acceptance")
	check(plan("codex","visit_flowers",{"place":"flower_isle","for_player":"invite"}),"second same activity still available")
	step(18)
	var before:Array=w.actors.human.position.duplicate()
	step(25)
	check(daily.invitation_trace.any(func(row):return row.event=="heart_player_resolved" and row.result=="timeout"),"15 seconds without a click really expires")
	check(w.actors.human.position==before and not w._routes.has("human"),"timeout never routes the player")
	check(not plan("codex","visit_flowers",{"place":"flower_isle"}),"third accept inside 15 minutes rejected by host")
	check(white.intention.card().feedback.any(func(row):return row.reason=="repeat_limit"),"next real card explains repetition")
	check(blue.intention.card().today_counts.is_empty(),"per-resident intention counts are isolated")
	var quotas:=ConfigFile.new()
	quotas.load(dir.path_join("connection-mode.cfg"))
	quotas.set_value("daily_limit","companion-2",1);quotas.set_value("enabled","companion-2",true)
	quotas.save(dir.path_join("connection-mode.cfg"))
	pool.settings.load(dir.path_join("connection-mode.cfg"))
	game.autonomy.event({"kind":"usage","turn_key":"paid-blue","input_tokens":1,"output_tokens":1,"total_tokens":2,"complete":true},"companion-2","direct")
	check(pool.quota_reached("companion-2") and not pool.quota_reached("codex"),"named quota bills only the receiving resident")
	pool._quota_local("companion-2")
	check(not w.director.model_controlled("companion-2") and w.director.model_controlled("codex"),"quota fallback leaves the other source connected")
	var mira:RefCounted=w.director.brains["npc.mira"]
	w.hunger.states["npc.mira"].elapsed=float(w.hunger.config.thresholds[3])+1
	check(meet.gate("npc.mira")=="refuse_hunger","a real very-hungry state refuses leisure")
	mira.begin_external("command","move")
	w.hunger.states["npc.mira"].elapsed=0.0
	check(meet.gate("npc.mira")=="refuse_command","an owned host command wins over an invitation")
	game.queue_free();await process_frame
	print("MEETINGS ",checks," failures=",failures);quit(1 if failures else 0)
