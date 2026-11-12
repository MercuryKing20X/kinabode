extends SceneTree
const F=preload("res://tests/cooking_fixture.gd")
class Fake extends "res://scripts/companion_link.gd":
	var calls:=0
	func _start() -> bool:return true
	func _send(_message: Dictionary) -> bool:calls+=1;return true
var scheduler: RefCounted
var adapter: Fake
var estimated:=0
var estimated_total:=0
var contexts: Array=[]
var checks:=0
var failed:=false
func _initialize() -> void:call_deferred("run")
func check(value: bool,text: String) -> void:
	checks+=1
	if not value:failed=true;push_error(text)
func send(_id: String,context: Dictionary,policy: Dictionary,key: String) -> bool:
	var result: bool=adapter.send_autonomy(context,"ultra",{"tools":int(policy.tools),"turn_tokens":int(policy.turn_tokens)},key)
	# This is an estimate supplied by a fake adapter, never presented as real usage.
	if result:
		contexts.append(context.duplicate(true))
		estimated=preload("res://scripts/autonomy_estimate.gd").tokens(scheduler.config,context)
		estimated_total+=estimated
		scheduler.record_usage("codex",estimated,estimated-256,256);scheduler.finish("codex",true)
		adapter._accept_event({"kind":"assistant","text":"根据真实现状，暂时安静陪伴。"})
		adapter._accept_event({"kind":"state","state":"ready","turnComplete":true})
	return result
func run() -> void:
	var directory:=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(1);return
	var world:=F.fresh();world.actors.codex.position=[-1000,-1000];adapter=Fake.new();adapter.resident_id="codex";root.add_child(adapter)
	var prefs:=preload("res://scripts/resident_intelligence_preferences.gd").new();prefs.setup(directory,world.world_id)
	prefs.choose("codex","ultra");prefs.enable_autonomy("codex",true);prefs.runtime_supported.codex=true
	scheduler=preload("res://tests/autonomy_clock_fixture.gd").new();scheduler.anchor(world);scheduler.setup(world,prefs,send,func(_id):return true)
	var next_input:=0.0
	for frame in range(9000):
		if world.director.time>=next_input:scheduler.input_received();next_input+=60
		world.advance(.2);scheduler.advance(.2)
	var usage: Dictionary=scheduler.usage("codex")
	check(adapter.calls==5,"30 minutes Ultra idle + actual presence every minute yields five settled reflection turns")
	check(usage.calls==5 and usage.tokens==estimated_total,"simulated receipts match five fake turns, full prompt-derived estimated tokens per turn")
	check(usage.reserved==0 and usage.calls<=scheduler.config.levels.ultra.hourly,"within configured hour/day budget")
	check(scheduler.active.is_empty() and world.work.jobs.is_empty(),"fake replies never recursively create inference or engine tasks")
	var evidence: Dictionary={"seconds":1800,"advance_frames":9000,"delta":.2,"level":"ultra","presence":"explicit simulated input every 60 seconds","scenario":"idle, no injected events; natural day rollover included","wake_count":adapter.calls,"contexts":contexts,"estimated_tokens_per_turn":estimated,"estimated_total_tokens":usage.tokens,"configured_worst_case_tokens":adapter.calls*int(scheduler.config.levels.ultra.turn_tokens),"real_model_calls":0,"estimate_not_real_usage":true}
	var path:=OS.get_environment("HABITAT_AUTONOMY_SIMULATION_OUTPUT")
	if not path.is_empty():var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(evidence,"  "))
	adapter.queue_free();scheduler.dispatch=Callable();scheduler.available=Callable()
	print("Autonomy simulation: %s checks, failed=%s; 30min wakes=%d, estimated tokens=%d"%[checks,failed,adapter.calls,usage.tokens]);quit(1 if failed else 0)
