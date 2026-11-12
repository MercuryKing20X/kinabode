extends SceneTree
const F=preload("res://tests/cooking_fixture.gd")
const H=preload("res://tests/homestead_fixture.gd")
const Prefs=preload("res://scripts/resident_intelligence_preferences.gd")
const Scheduler=preload("res://scripts/autonomy_scheduler.gd")
var checks:=0
var failed:=false
var world: RefCounted
var prefs: RefCounted
var scheduler: RefCounted
var directory: String
var serial:=0
var sent:=0
var accept:=true
class Fake extends "res://scripts/companion_link.gd":
	var sent: Array=[]
	var accepts:=true
	func _start() -> bool:return true
	func _send(message: Dictionary) -> bool:sent.append(message.duplicate(true));return accepts
	func complete() -> void:
		_accept_event({"kind":"usage","total_tokens":100,"input_tokens":80,"output_tokens":20,"complete":true})
		_accept_event({"kind":"state","state":"ready","turnComplete":true})
func _initialize() -> void:call_deferred("run")
func check(ok: bool,text: String) -> void:
	checks+=1
	if not ok:failed=true;push_error(text)
func fresh(sender: Callable=Callable()) -> void:
	serial+=1;world=F.fresh();prefs=Prefs.new();sent=0;accept=true
	var path:=directory.path_join(str(serial));DirAccess.make_dir_recursive_absolute(path);prefs.setup(path,world.world_id)
	prefs.runtime_supported.codex=true;prefs.enable_autonomy("codex",true)
	scheduler=Scheduler.new();scheduler.setup(world,prefs,sender if sender.is_valid() else func(_id,_context,_policy,_key):sent+=1;return accept,func(_id):return true)
	scheduler.input_received()
func step(seconds: float) -> void:
	for i in range(int(ceil(seconds))):world.advance(1);scheduler.advance(1)
func event(key: String="test") -> void:scheduler.enqueue("codex",key,"house_completed","真实事件的测试输入")
func run() -> void:
	directory=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(1);return
	# Each item advances the real world. Dispatch is definitely rejected before inference.
	fresh();accept=false;event();step(6)
	check(scheduler.usage("codex").calls==0 and scheduler.usage("codex").reserved==0 and scheduler.usage("codex").times.is_empty(),"S0.2 rejected dispatch burns neither calls nor reserved")
	for i in range(2):step(610);scheduler.input_received();event(str(i));step(6)
	check(not prefs.preference("codex").runtime_active,"S0.2 three identical preflight failures quarantine runtime")
	fresh();world.advance(2);scheduler.input_received()
	check(absf(scheduler.last_input-scheduler.now())<1,"S0.6 presence and budgets share epoch clock")
	event();world.advance(6);scheduler.advance(0)
	check(sent==0,"S0.6 paused tick cannot dispatch")
	scheduler.advance(.1);scheduler.finish("codex");step(3601)
	check(sent<=1 and scheduler.usage("codex").times.is_empty(),"S0.6 long stalled advance expires presence and hourly window together")
	fresh();check(H.stock(world) and H.deliver(world,"codex") and H.build(world,"codex"),"S0.5 genuine physical homestead completion fixture")
	scheduler.note_model_action("companion-2");scheduler.input_received();step(6)
	check(sent==1,"S0.5 unrelated causal resident must not block actual non-causal contributor")
	# Real Main with never-started fake links, pure mouse movement and dialogue completion.
	var game: Node=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false)
	await process_frame
	game.world.director.set_all_enabled(false);game.view.sound_enabled=false;game.chat.hide();game.chat_input.release_focus()
	check(game.links.has("codex") and game.links.has("companion-2") and game.links.values().all(func(connection):return connection._pid==-1),"S0.1 Main provisions lazy unstarted link objects before any chat")
	game.dialogue_adapter_factory=func(_id,_scope):return Fake.new()
	for link in game.links.values():link.queue_free()
	game.links.clear();game._ensure_link("codex");game._ensure_link("companion-2");game.link=game.links.codex
	var link: Fake=game.links.codex;var p: RefCounted=game.resident_connections.preferences;var s: RefCounted=game.autonomy.scheduler
	for level in ["medium","high","ultra"]:
		p.choose("codex",level);p.enable_autonomy("codex",true);s.reset();game.autonomy.player_input();s.enqueue("codex",level,"house_completed","尚未聊过天的事件")
		for frame in range(6):game._process(1)
		check(s.active.has("codex") and link._pid==-1,"S0.1 never-chatted "+level+" dispatches lazily through an unstarted link")
		link.complete();s.reset();p.save_accounting("codex",{})
	p.choose("codex","ultra");s.reset();var before: int=link.sent.size()
	for frame in range(180):
		var motion:=InputEventMouseMotion.new();motion.relative=Vector2(1,1);game._input(motion);game._process(10)
	check(link.sent.size()==before and not s.input_seen,"S0.3 mouse-only 30 minutes never counts presence or wakes")
	p.choose("codex","medium");p.save_accounting("codex",{});s.reset()
	game._select_chat("codex");preload("res://tests/dialogue_ui_fixture.gd").send(game,"普通对话测试");link.complete();game.chat_input.release_focus()
	for frame in range(2):game._process(1)
	check(s.now()-float(s.usage("codex").last_at)<3 and float(s.reflection_after.get("codex",0))>=float(s.usage("codex").last_at),"S0.4 direct completion starts autonomous cooldown and reflection delay")
	game._select_chat("group:all");preload("res://tests/dialogue_ui_fixture.gd").send(game,"普通群聊测试")
	var group: Fake=game.group_links.codex;group.complete();game.chat_input.release_focus()
	for frame in range(2):game._process(1)
	check(s.now()-float(s.usage("codex").last_at)<3,"S0.4 group completion starts same resident cooldown")
	p.save_accounting("codex",{});s.reset();p.enable_autonomy("codex",true);link.accepts=false
	for attempt in range(3):
		game.autonomy.player_input();s.enqueue("codex","send-false-"+str(attempt),"house_completed","未发送")
		for frame in range(6):game._process(1)
		check(s.usage("codex").calls==0 and s.usage("codex").reserved==0,"S0.2 send_autonomy false does not burn attempt "+str(attempt))
	check(not p.preference("codex").runtime_active,"S0.2 three send failures stop runtime")
	link.accepts=true
	p.save_accounting("codex",{});s.reset();p.enable_autonomy("codex",true)
	for attempt in range(3):
		game.autonomy.player_input();s.enqueue("codex","unsupported-"+str(attempt),"house_completed","拒绝前置能力")
		for frame in range(6):game._process(1)
		link._accept_event({"kind":"error","code":"autonomy_unsupported","message":"测试模型不支持"})
		check(s.usage("codex").calls==0 and s.usage("codex").reserved==0,"S0.2 unsupported rejection refunds attempt "+str(attempt))
	check(not p.preference("codex").runtime_active and game.autonomy.status("codex").reason.contains("autonomy_unsupported"),"S0.2 quarantine retains truthful reason in UI")
	p.enable_autonomy("codex",false);p.enable_autonomy("codex",true)
	check(p.preference("codex").runtime_active,"S0.2 explicit reopen clears quarantine")
	p.runtime_supported.codex=false
	check(not game.autonomy.can_send("codex"),"S0.2 can_send explicitly checks runtime_supported")
	# Rejection before dispatch, including malformed context, is not a billable turn.
	p.runtime_supported.codex=true;var use: Dictionary=s.usage("codex")
	check(not game.autonomy.dispatch("codex",{"padding":"汉".repeat(5000)},s.config.levels.medium,"oversized"),"S0.2 >4KB rejected before inference")
	check(s.usage("codex").calls==use.calls and s.usage("codex").reserved==use.reserved,"S0.2 invalid context does not burn budget")
	var export_path:=OS.get_environment("HABITAT_OVERNIGHT_PROMPT_CONTEXT")
	if not export_path.is_empty():
		var ctx:=FileAccess.open(export_path,FileAccess.WRITE);ctx.store_string(JSON.stringify(game.world.autonomy_context("codex")));ctx.close()
	game.queue_free();await process_frame
	print("Overnight autonomy: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)
