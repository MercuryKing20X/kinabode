extends SceneTree
const F=preload("res://tests/cooking_fixture.gd")
const Prefs=preload("res://scripts/resident_intelligence_preferences.gd")
const Scheduler=preload("res://scripts/autonomy_scheduler.gd")
var checks:=0
var failed:=false
var directory: String
var world: RefCounted
var prefs: RefCounted
var scheduler: RefCounted
var sent: Array=[]
var fixture:=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failed=true;push_error(label)
func fresh(level: String="medium") -> void:
	fixture+=1;world=F.fresh();prefs=Prefs.new()
	# Same-day reservation probes must not straddle the operator's real midnight.
	# Keep one advancing ForestSystem clock, and preserve the game-day phase.
	var bias:float=Time.get_time_zone_from_system().bias*60.0
	var midday:float=ceil((Time.get_unix_time_from_system()+bias)/86400.0)*86400.0+43200-bias
	world.days.origin+=midday-world.forest.clock;world.forest.clock=midday
	var path:=directory.path_join(str(fixture));DirAccess.make_dir_recursive_absolute(path);prefs.setup(path,world.world_id)
	prefs.choose("codex",level);prefs.enable_autonomy("codex",level!="low");prefs.runtime_supported.codex=true
	sent.clear();scheduler=Scheduler.new();scheduler.setup(world,prefs,send,func(_id):return true);scheduler.input_received()
func send(id: String,context: Dictionary,policy: Dictionary,token: String) -> bool:
	sent.append({"id":id,"context":context.duplicate(true),"policy":policy.duplicate(),"token":token});return true
func step(seconds: float,held: Dictionary={}) -> void:
	for frame in range(int(ceil(seconds/.2))):world.advance(.2);scheduler.advance(.2,held)
func event(key: String="a",id: String="codex") -> void:scheduler.enqueue(id,key,"house_completed","真实来源观察器事件的单元输入")
func complete() -> void:
	scheduler.record_usage("codex",120,100,20);scheduler.finish("codex")
func run() -> void:
	directory=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(1);return
	fresh("low");event();step(10)
	check(sent.is_empty() and scheduler.queues.is_empty(),"low never wakes on any event")
	fresh();prefs.enable_autonomy("codex",false);event();step(10)
	check(sent.is_empty(),"old medium selection without explicit opt-in never wakes")
	fresh();check(scheduler.error.is_empty(),"validated content policy loaded")
	event();step(4);event("b");step(2)
	check(sent.size()==1 and sent[0].context.events.size()==2,"settling merges two events into exactly one turn")
	check(scheduler.usage("codex").calls==1 and scheduler.usage("codex").reserved==scheduler.config.levels.medium.turn_tokens,"count and token reservation charged before dispatch")
	check(scheduler.record_usage("codex",120,100,20) and scheduler.record_usage("codex",120,100,20),"duplicate cumulative actual usage accepted idempotently")
	check(scheduler.usage("codex").tokens==120 and not scheduler.record_usage("codex",110,90,20),"usage never double counts or decreases")
	scheduler.finish("codex");check(scheduler.usage("codex").reserved==0,"known completed turn releases unused reservation")
	event("c");step(10);check(sent.size()==1,"cooldown blocks next event")
	step(190);scheduler.input_received();step(410)
	check(sent.size()==1 and scheduler.queues.codex.is_empty(),"expired events discarded, no catch-up after cooldown")
	fresh();event();step(6);complete();scheduler.config.levels.medium.daily=1;event("budget");scheduler.input_received();step(610)
	check(sent.size()==1,"daily count exhaustion blocks further calls")
	fresh();scheduler.config.levels.medium.hourly=1;event();step(6);complete();step(605);scheduler.input_received();event("hour");step(6)
	check(sent.size()==1,"rolling hourly count enforced")
	# DIRECTION 2026-11-09: 默认“不限”，连接页可手动设回。Exercise the explicit cap, retaining unknown reservation assertions.
	fresh()
	var caps:=ConfigFile.new();caps.set_value("daily_limit","codex",scheduler.config.levels.medium.turn_tokens);caps.save(scheduler.preferences.path.get_base_dir().path_join("connection-mode.cfg"))
	event();step(6);scheduler.finish("codex",false);step(605);scheduler.input_received();event("unknown");step(6)
	check(sent.size()==1 and scheduler.usage("codex").reserved==scheduler.config.levels.medium.turn_tokens and scheduler.usage("codex").unknown_turns==1,"unknown usage remains reserved conservatively")
	fresh();step(121);event();step(6);check(sent.is_empty(),"inactive human never wakes model")
	scheduler.input_received();step(6);check(sent.size()==1,"real new input makes live event eligible")
	fresh();event();step(10,{"codex":true});check(sent.is_empty(),"shared Main held gate covers chat/questions")
	step(1);check(sent.size()==1,"eligible event can dispatch after held releases")
	fresh();world.activities.members.codex={};event();step(10);check(sent.is_empty(),"assembly prevents inference")
	fresh();scheduler.note_model_action("codex");event();event("other","companion-2");step(6)
	check(sent.is_empty(),"model-originated action does not wake itself or unenabled others")
	fresh();event();step(2);scheduler.reset();step(10);check(sent.is_empty() and scheduler.queues.codex.is_empty(),"reload/reset clears unissued queued events")
	fresh();world.actors.codex.position=[-1000,-1000];prefs.choose("codex","ultra");scheduler.input_received();step(110);scheduler.input_received();step(110);scheduler.input_received();step(90)
	check(sent.size()==1 and sent[0].context.events[0].kind=="reflection","only Ultra can start a configured idle reflection")
	complete();var before: Dictionary=scheduler.usage("codex");world.advance(86400);scheduler.advance(86400)
	check(before.tokens==120 and scheduler.usage("codex").tokens==0 and scheduler.usage("codex").calls==0,"real clock advancement resets date budgets and token usage")
	# Real Work event source, not an invented SharedMemories record.
	fresh();scheduler.config.event_scores.work_completed=6
	check(world.command("codex",{"intent":"chop","target_id":"home.tree.01"}).ok,"real physical work accepted")
	for frame in range(500):
		step(.2)
		if not sent.is_empty():break
	check(sent.size()==1 and sent[0].context.events[0].kind=="work_completed","real advancing Work completion observed exactly once")
	complete();step(3);check(sent.size()==1,"retained source is not reprocessed")
	# Genuine long-running model work stays suppressed through its completion.
	fresh();scheduler.config.event_scores.work_completed=6;scheduler.note_model_action("codex")
	world.command("codex",{"intent":"chop","target_id":"home.tree.01"})
	step(60);check(sent.is_empty() and not scheduler.causal.has("codex"),"model completion observed under provenance barrier before it clears")
	fresh();var invalid: Dictionary=scheduler.config.duplicate(true);invalid.levels.ultra.tools=99
	check(not scheduler.valid_config(invalid),"invalid tool budget disables configuration")
	print("Autonomy scheduler: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)
