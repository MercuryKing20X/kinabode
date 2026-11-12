extends SceneTree
const F=preload("res://tests/cooking_fixture.gd")
const H=preload("res://tests/homestead_fixture.gd")
const Fish=preload("res://tests/fishing_fixture.gd")
var game: Node
var started:=0
var label_now:="setup"
var rows: Array=[]
var scenarios: Array=[]
var output: String
var failed:=false
class RecordingLink extends "res://scripts/companion_link.gd":
	var owner_probe: SceneTree
	var real_autonomy:=0
	func _init() -> void:
		helper_filename="polish_live_probe.py";bridge_files.append(helper_filename)
	func _send(message: Dictionary) -> bool:
		if message.kind in ["chat","autonomy_event"] and Time.get_unix_time_from_system()>=float(OS.get_environment("HABITAT_LIVE_DEADLINE")):return false
		if message.kind in ["chat","autonomy_event"] and Time.get_ticks_msec()-owner_probe.started>=1190000:return false
		if message.kind=="autonomy_event":
			if real_autonomy+int(OS.get_environment("HABITAT_LIVE_PREVIOUS_ROUNDS"))>=6 or Time.get_ticks_msec()-owner_probe.started>=1200000:return false
			real_autonomy+=1
		owner_probe.record("outbound",message)
		return super._send(message)
func _initialize() -> void:
	if OS.get_environment("HABITAT_LIVE_TEST")!="1" or not OS.get_environment("HABITAT_DATA_DIR").contains("habitat-live-test-"):quit(1);return
	call_deferred("run")
func record(kind: String,data: Dictionary) -> void:
	rows.append({"at":Time.get_unix_time_from_system(),"elapsed_seconds":float(Time.get_ticks_msec()-started)/1000,"scenario":label_now,"kind":kind,"data":data.duplicate(true)})
	var file:=FileAccess.open(output.path_join("live-events.json"),FileAccess.WRITE);file.store_string(JSON.stringify(rows,"  "));file.close()
func check(ok: bool,message: String) -> void:
	record("assertion",{"ok":ok,"message":message})
	if not ok:failed=true;push_error(message)
func click() -> void:
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true;game._input(event)
func tick(delta: float=.1) -> void:
	game._process(delta)
func advance(seconds: float) -> void:
	for frame in range(int(ceil(seconds/.2))):game.world.advance(.2)
func baseline(name: String) -> void:
	label_now=name;game.autonomy.scheduler.reset();game.chat.hide();game.chat_input.release_focus();click()
func receive(event: Dictionary) -> void:record("inbound",event)
func await_turn() -> void:
	var limit:=Time.get_ticks_msec()+180000
	while Time.get_ticks_msec()<limit and Time.get_ticks_msec()-started<1190000:
		tick(.1);await create_timer(.1).timeout
		if not game.links.codex.is_busy() and not game.autonomy.scheduler.active.has("codex"):return
	check(false,"real turn did not settle before bounded deadline");game.links.codex.cancel_turn()
func fire() -> void:
	for frame in range(31):tick(.2)
	await await_turn()
	scenarios.append({"name":label_now,"calls":game.links.codex.real_autonomy,"usage":game.autonomy.scheduler.usage("codex"),"records":game.autonomy.scheduler.records.read("codex")})
func idle_work() -> void:
	for frame in range(30000):
		if game.world.work.jobs.is_empty() and game.world._routes.is_empty() and not game.world.projects.active("codex") and not game.world.homestead.active("codex"):break
		game.world.advance(.2)
func run() -> void:
	started=Time.get_ticks_msec();output=OS.get_environment("HABITAT_POLISH_EVIDENCE");DirAccess.make_dir_recursive_absolute(output)
	game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false)
	await process_frame
	game.world.director.set_all_enabled(false);game.view.sound_enabled=false;game.chat.hide();game.chat_input.release_focus()
	for id in game.world.actors:
		if id not in ["human","codex"]:game.world.director.set_controller(id,"local")
	game.dialogue_adapter_factory=func(_id,_scope):var connection:=RecordingLink.new();connection.owner_probe=self;return connection
	for connection in game.links.values():connection.queue_free()
	game.links.clear();game._ensure_link("codex");game.link=game.links.codex;game.links.codex.event_received.connect(receive)
	var prefs: RefCounted=game.resident_connections.preferences;prefs.choose("codex","medium");prefs.enable_autonomy("codex",true)
	check(H.stock(game.world) and H.deliver(game.world,"codex"),"physical homestead materials prepared with real wood and harvested crops")
	baseline("homestead_completed");check(H.build(game.world,"codex"),"real homestead construction completes")
	await fire()
	if OS.get_environment("HABITAT_POLISH_RETEST")=="1":
		var result: Dictionary={"status":"observed" if not failed else "needs_review","elapsed_seconds":float(Time.get_ticks_msec()-started)/1000,"autonomous_calls":game.links.codex.real_autonomy,"level":"medium","reason":"necessary single retest after observed token-budget cancellation","scenarios":scenarios,"usage":game.autonomy.scheduler.usage("codex"),"history":game.dialogue.histories.get("direct:codex",[])}
		var file:=FileAccess.open(output.path_join("live-summary.json"),FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
		game.links.codex.shutdown();game.queue_free();await process_frame;print("Polish live retest complete");quit(1 if failed else 0);return
	idle_work();advance(610)
	# Actual RNG draws/catches, never injected fish instances or resources.
	label_now="fishing_setup";check(Fish.coast(game.world,"codex"),"resident walks through World to real sea")
	game.world.fishing.rng.seed=23
	var big: Dictionary={}
	for attempt in range(12):
		baseline("large_fish");var fish: Dictionary=Fish.catch_one(game.world,"codex")
		if not fish.is_empty() and fish.scale>=2:big=fish;break
		if not fish.is_empty():game.world.command("codex",{"intent":"release_fish","fish_id":fish.id})
	check(not big.is_empty(),"genuine catch at least two resident heights")
	await fire();idle_work()
	var held: Dictionary=game.world.fishing.held("codex")
	if not held.is_empty():game.world.command("codex",{"intent":"stock_fish","fish_id":held.id,"pen_id":"home.fishery.east"})
	advance(610);baseline("day_changed");var before: int=game.links.codex.real_autonomy
	advance(game.world.days.day_seconds-game.world.days.within_day()+.1);click();await fire()
	check(game.links.codex.real_autonomy==before,"medium day score alone does not force a call")
	baseline("player_returned");var last_input: float=game.autonomy.scheduler.last_input
	var absence_end:=Time.get_ticks_msec()+181000
	while Time.get_ticks_msec()<absence_end:
		tick(.1);await create_timer(.1).timeout
	check(game.autonomy.scheduler.last_input==last_input,"actual 181 wall seconds without input do not count presence")
	click();await fire();check(game.links.codex.real_autonomy==before,"returned score alone respects threshold")
	baseline("ordinary_dialogue");game._select_chat("codex");game._send("今天在岛上一起待着真好，先随便聊一句，不用安排任务。");game.chat_input.release_focus();await await_turn()
	check(game.autonomy.scheduler.now()-float(game.autonomy.scheduler.usage("codex").last_at)<3,"ordinary real dialogue restarts autonomy cooldown")
	for frame in range(61):tick(.2)
	check(game.links.codex.real_autonomy==before,"ordinary dialogue cooldown remains quiet")
	check(game.links.codex.real_autonomy<=6 and Time.get_ticks_msec()-started<1200000,"one resident, at most six autonomous rounds and under 20 wall minutes")
	var result: Dictionary={"status":"observed" if not failed else "needs_review","elapsed_seconds":float(Time.get_ticks_msec()-started)/1000,"autonomous_calls":game.links.codex.real_autonomy,"level":"medium","model_residents":["codex"],"scenarios":scenarios,"usage":game.autonomy.scheduler.usage("codex"),"history":game.dialogue.histories.get("direct:codex",[])}
	var file:=FileAccess.open(output.path_join("live-summary.json"),FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
	game.links.codex.shutdown();game.queue_free();await process_frame
	print("Polish live: "+JSON.stringify(result));quit(1 if failed else 0)
