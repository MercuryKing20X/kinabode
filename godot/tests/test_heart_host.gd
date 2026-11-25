extends SceneTree
## Host callback integration with a preinstalled in-process native-API fake.
## No HTTP, credentials or subprocesses; the host still validates turns and plans.
class TransportStub extends Node:
	func close()->void:pass
class Fake extends "res://scripts/companion_link.gd":
	var sent:Array=[]
	func _ready()->void:
		super._ready();direct_api=TransportStub.new();add_child(direct_api)
	func _start()->bool:return true
	func _send(_value:Dictionary)->bool:return false
	func uses_intents()->bool:return true
	func probe_connection()->bool:handshake_ready=true;return true
	func send_autonomy(context:Dictionary,_level:String,_limits:Dictionary,key:String)->bool:
		if is_busy() or _daily_quota_reached():return false
		turn_kind="autonomy_event";turn_key=key;_generation+=1;_busy=true
		sent.append(context.duplicate(true));return true
var failed:=false
var checks:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("HEART_HOST ",label," ",ok)
	if not ok:failed=true;push_error(label)
func run()->void:
	var dir:String=OS.get_environment("HABITAT_DATA_DIR")
	if not dir.contains("youqi-test-"):quit(1);return
	OS.set_environment("HABITAT_OPENING","standard")
	var pool:Node=preload("res://scripts/connection_session_pool.gd").obtain(self,dir)
	pool.factory=func(_id):return Fake.new()
	var game:Node=load("res://scenes/main_v3.tscn").instantiate()
	game.dialogue_adapter_factory=func(_id,_scope):return Fake.new()
	root.add_child(game);game.save_enabled=false;game.set_process(false)
	await process_frame;await process_frame
	game.memory_life.set_process(false);game.life_archive.set_process(false)
	game.world.director.set_all_enabled(false);game.chat.hide();game.chat_input.release_focus()
	game._ensure_link("codex");game.world.director.set_controller("codex","model")
	game.autonomy.refresh_support();game.autonomy.tick(0)
	var link:Fake=game.links.codex
	var b:RefCounted=game.world.director.brains.codex
	check(game.autonomy.dispatch("codex",{}, {"tools":1},"heart-host-1"),"native host dispatch with exact prebuilt fake")
	check(link.sent.size()==1 and link.sent[0].heart_card.heart_request.available.any(func(row):return row.activity=="daydream" and row.ready),"dispatch contains host-computed real prerequisites")
	check(not game.autonomy.dispatch("codex",{}, {"tools":1},"heart-host-duplicate") and link.sent.size()==1,"one in-flight request without cancellation or resend")
	game.autonomy.scheduler.active["codex"]={"id":"heart-host-1"}
	check(not game._link_holds_body(link,"codex"),"owned autonomous intention does not pause the body during inference")
	check(game._link_holds_body(link,"codex","group"),"non-owned scope has no exemption")
	game.autonomy.scheduler.active.erase("codex")
	var plan:Dictionary={"activity":"daydream","minutes":1,"reason":"Watch the real island for a little while."}
	link._accept_event({"kind":"intent_result","turn_key":"stale","speech":"","intention":plan})
	check(b.intention.pending.is_empty(),"stale result never reaches brain")
	link._accept_event({"kind":"intent_result","turn_key":"heart-host-1","speech":"","intention":plan,"intents":[],"memory":[],"planning":[]})
	check(not b.intention.pending.is_empty(),"bound result reaches only own brain")
	link._accept_event({"kind":"state","state":"ready","turnComplete":true})
	game.world.director.routines.codex.set_enabled(true)
	for tick in 800:
		game.world.advance(.25)
		if b.intention.recent.any(func(row):return row.activity=="daydream" and row.outcome=="completed"):break
	print("HOST_OUTCOMES ",b.intention.recent," current=",b.current," pending=",b.intention.pending," eligible=",b.eligible())
	check(b.intention.recent.any(func(row):return row.activity=="daydream" and row.outcome=="completed"),"accepted plan physically runs to completion")
	check(game.memory_books.list_for("codex","feelings").any(func(row):return row.params.get("kind")=="intention_outcome" and row.params.outcome=="completed"),"real completed outcome enters the same resident memory book")
	check(not game.memory_books.list_for("companion-2","feelings").any(func(row):return row.params.get("kind")=="intention_outcome"),"another resident receives no copied outcome")
	b.finish("interrupted","fixture_cleanup")
	var before_count:int=game.memory_books.list_for("codex","feelings").filter(func(row):return row.params.get("kind")=="intention_outcome").size()
	# DIRECTION v0.8 round four: at most two accepts of the same activity in 15 minutes.
	# The separate same-clock receipt assertion still covers three independent plans.
	for activity in ["daydream","stretch","cloud_watch"]:
		b.intention.card()
		check(b.intention.accept(plan.merged({"activity":activity},true)),"same-clock pending accepted "+activity)
	var same_clock:Array=game.memory_books.list_for("codex","feelings").filter(func(row):return row.params.get("kind")=="intention_outcome")
	check(same_clock.size()==before_count+2,"two replaced pending plans at same clock each retain separate outcome memory")
	var old_world:String=game.world.world_id
	game.world.world_id="other-"+old_world
	b.reset()
	var outcomes:Array=game.memory_books.list_for("codex","feelings").filter(func(row):return row.params.get("kind")=="intention_outcome")
	check(outcomes.size()==before_count+3 and outcomes.all(func(row):return row.world_id==old_world),"cross-world reset settles the pending decision only into its original island memory")
	game.world.world_id=old_world
	var caps:=ConfigFile.new();caps.load(dir.path_join("connection-mode.cfg"));caps.set_value("daily_limit","codex",1);caps.save(dir.path_join("connection-mode.cfg"))
	game.autonomy.event({"kind":"usage","turn_key":"host-paid","input_tokens":1,"output_tokens":1,"total_tokens":2,"complete":true},"codex","direct")
	b.intention.changed()
	check(not game.autonomy.dispatch("codex",{}, {"tools":1},"heart-host-overquota") and link.sent.size()==1,"shared daily quota blocks another native decision before inference")
	var books:RefCounted=game.memory_books
	b.intention.card();check(b.intention.accept(plan),"exit fixture accepts another valid pending plan")
	var before_exit:int=books.list_for("codex","feelings").size()
	game.queue_free()
	for frame in 10:
		if not is_instance_valid(game):break
		await process_frame
	check(books.list_for("codex","feelings").size()==before_exit+1 and books.list_for("codex","feelings").back().params.outcome=="interrupted","ending the session records a real pending interruption")
	print("HEART_HOST ",checks," failed=",failed);quit(1 if failed else 0)
