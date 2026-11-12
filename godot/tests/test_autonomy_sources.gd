extends SceneTree
const F=preload("res://tests/cooking_fixture.gd")
const Fish=preload("res://tests/fishing_fixture.gd")
const H=preload("res://tests/homestead_fixture.gd")
var checks:=0
var failed:=false
var world: RefCounted
var scheduler: RefCounted
var prefs: RefCounted
var calls: Array=[]
var fixture:=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,text: String) -> void:
	checks+=1
	if not value:failed=true;push_error(text)
func fresh() -> void:
	fixture+=1;world=F.fresh();calls.clear()
	prefs=preload("res://scripts/resident_intelligence_preferences.gd").new()
	var directory:=OS.get_environment("HABITAT_DATA_DIR").path_join(str(fixture));DirAccess.make_dir_recursive_absolute(directory);prefs.setup(directory,world.world_id)
	for id in ["codex","companion-2"]:prefs.runtime_supported[id]=true;prefs.enable_autonomy(id,true)
	scheduler=preload("res://scripts/autonomy_scheduler.gd").new()
	scheduler.setup(world,prefs,func(id,context,_limits,_key):calls.append({"id":id,"context":context});return true,func(_id):return true)
func step(seconds: float) -> void:
	for tick in range(int(ceil(seconds/.2))):world.advance(.2);scheduler.advance(.2)
func run() -> void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):quit(1);return
	fresh()
	check(F.harvest(world,"turnip") and F.serve(world,"turnip-soup","",["human","codex","companion-2"]) and F.eat(world,"human") and F.eat(world,"codex") and F.eat(world,"companion-2") and F.cleanup(world),"actual harvest, cook, eat and cleanup create canonical meal")
	scheduler.input_received();step(6)
	check(calls.size()==2 and calls.all(func(call):return call.context.events.any(func(event):return event.kind=="shared_barbecue")),"only actual model participants receive real meal trigger")
	check(world.memories.records.any(func(entry):return entry.kind=="shared_barbecue"),"facts retained in original SharedMemories")
	fresh();scheduler.note_model_action("codex")
	check(F.harvest(world,"turnip") and F.serve(world,"turnip-soup","",["human","codex","companion-2"]) and F.eat(world,"human") and F.eat(world,"codex") and F.eat(world,"companion-2") and F.cleanup(world),"same actual meal, model-originated causal barrier")
	scheduler.input_received();step(6)
	check(calls.is_empty(),"model-caused shared memory cannot wake other enabled participants")
	fresh();check(Fish.coast(world,"codex") and not Fish.catch_one(world,"codex").is_empty(),"genuine sea catch")
	scheduler.input_received();step(6)
	check(calls.size()==1 and calls[0].id=="codex" and calls[0].context.events.any(func(event):return event.kind=="fishing_catch"),"canonical catch wakes only actual catcher")
	fresh();check(H.stock(world) and H.deliver(world,"codex") and H.build(world,"codex"),"physical homestead delivery and construction complete")
	scheduler.input_received();step(6)
	check(calls.size()==1 and calls[0].context.events.any(func(event):return event.kind=="homestead_completed"),"real completion source observed once without inventing memory kind")
	scheduler.finish("codex",false);step(6);check(calls.size()==1,"same retained homestead source never repeats")
	# A real schema7 save/reload preserves facts and budgets, never the pending queue.
	scheduler.enqueue("codex","discard-on-reload","house_completed","待发事件")
	var config_dir: String=prefs.path.get_base_dir()
	var save_dir:=OS.get_environment("HABITAT_DATA_DIR").path_join("reload")
	check(preload("res://scripts/save_store.gd").save_world(world,save_dir),"save actual world with existing schema7")
	var loaded:=F.fresh()
	check(preload("res://scripts/save_store.gd").load_world(loaded,save_dir).ok,"reload real schema7 facts without custom autonomy fields")
	world=loaded;prefs=preload("res://scripts/resident_intelligence_preferences.gd").new();prefs.setup(config_dir,world.world_id);prefs.runtime_supported.codex=true
	scheduler=preload("res://scripts/autonomy_scheduler.gd").new();calls.clear()
	scheduler.setup(world,prefs,func(id,context,_limits,_key):calls.append({"id":id,"context":context});return true,func(_id):return true)
	scheduler.input_received();step(6)
	check(calls.is_empty() and scheduler.queues.values().all(func(queue):return queue.is_empty()) and scheduler.usage("codex").calls==1,"new scheduler baselines retained facts and drops old pending events while keeping used budget")
	print("Autonomy sources: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)
