extends SceneTree
const F=preload("res://tests/cooking_fixture.gd")
const Prefs=preload("res://scripts/resident_intelligence_preferences.gd")
const Scheduler=preload("res://tests/autonomy_clock_fixture.gd")
const Fake=preload("res://tests/test_overnight_autonomy.gd").Fake
var world: RefCounted
var prefs: RefCounted
var scheduler: RefCounted
var calls:=0
var notices:=0
var before_notice:=true
var checks:=0
var failed:=false
func _initialize() -> void:call_deferred("run")
func check(ok: bool,text: String) -> void:
	checks+=1
	if not ok:failed=true;push_error(text)
func send(id: String,_context: Dictionary,_policy: Dictionary,key: String) -> bool:
	before_notice=before_notice and notices>0
	calls+=1;scheduler.records.action(id,key,{"intent":"watch"},{"ok":true,"status":"accepted","job_id":"fake-"+str(calls)})
	scheduler.record_usage(id,100,80,20);scheduler.finish(id,true);return true
func step(seconds: int) -> void:
	for frame in range(seconds):world.advance(1);scheduler.advance(1)
func run() -> void:
	var directory:=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(1);return
	world=F.fresh();prefs=Prefs.new();prefs.setup(directory,world.world_id);prefs.choose("codex","ultra");prefs.runtime_supported.codex=true;prefs.enable_autonomy("codex",true)
	scheduler=Scheduler.new();scheduler.anchor(world);scheduler.setup(world,prefs,send,func(_id):return true)
	scheduler.ultra_notice.connect(func(_id,_hour):notices+=1)
	scheduler.config.levels.ultra.cooldown=30;scheduler.config.levels.ultra.hourly=200;scheduler.config.levels.ultra.daily=200;scheduler.config.levels.ultra.reflection_seconds=100000
	for index in range(21):
		scheduler.input_received();scheduler.enqueue("codex",str(index),"meal","真实来源的适配器测试输入");step(6);step(31)
	var records: Dictionary=scheduler.records.read("codex")
	check(calls==21 and records.turns.size()==20,"last 20 completed autonomous turns retained")
	check(notices==1 and before_notice,"daily Ultra estimate shown before first turn and only once")
	check(records.turns.all(func(turn):return turn.actual_tokens==100 and turn.estimated_tokens>0 and turn.usage_status=="complete" and turn.actions[0].intent=="watch"),"actual and estimated tokens kept distinct, accepted action labelled accurately")
	var ledger: Dictionary=scheduler.usage("codex")
	check(ledger.calls==21 and ledger.tokens==2100 and records.turns.all(func(turn):return ledger.turns.any(func(receipt):return receipt.id==turn.id and receipt.total_tokens==turn.actual_tokens)),"each retained record agrees with ledger")
	var restored:=Prefs.new();restored.setup(directory,world.world_id)
	var store:=preload("res://scripts/autonomy_records.gd").new(restored)
	check(store.read("codex")==records,"reload retains bounded history and daily notice mark")
	records.turns.clear();check(store.read("codex").turns.size()==20,"record reads are deep copies")
	scheduler.enqueue("codex","held","meal","忙碌事件");world.advance(1);scheduler.advance(1,{"codex":true})
	for frame in range(181):world.advance(1);scheduler.advance(1,{"codex":true})
	step(1)
	var gates: Array=scheduler.records.read("codex").gates
	check(gates.any(func(gate):return gate.reason=="busy") and gates.any(func(gate):return gate.reason=="not_present"),"busy and inactive reasons recorded from real advancing gates")
	scheduler.config.levels.ultra.daily=21;scheduler.input_received();scheduler.enqueue("codex","budget","meal","预算事件");step(6)
	check(scheduler.records.read("codex").gates[-1].reason=="budget" and calls==21,"budget block visible without a fake turn")
	world.advance(86401);scheduler.advance(86401);scheduler.input_received();scheduler.enqueue("codex","nextday","meal","翌日");step(6)
	check(notices==2 and calls==22,"new actual date permits one new nonblocking estimate notice")
	# Actual Main wiring and viewport, still fake adapter and disposable world.
	var game: Node=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false);root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
	await process_frame
	game.world.director.set_all_enabled(false);game.view.sound_enabled=false;game.chat.hide();game.chat_input.release_focus();game.dialogue_adapter_factory=func(_id,_scope):return Fake.new()
	for connection in game.links.values():connection.queue_free()
	game.links.clear();game._ensure_link("codex");game.link=game.links.codex
	var p: RefCounted=game.resident_connections.preferences;p.choose("codex","ultra");p.enable_autonomy("codex",true)
	game.autonomy.player_input();game.autonomy.scheduler.enqueue("codex","ui","house_completed","测试事件")
	for frame in range(6):game._process(1)
	check(game.autonomy_notice.visible and game.autonomy_notice.mouse_filter==Control.MOUSE_FILTER_IGNORE and (game.autonomy_notice.text.contains("实测") or game.autonomy_notice.text.contains("估算")),"daily notice is visible and does not intercept controls")
	game.links.codex.complete();game.resident_connections.open("codex");game.resident_connections.tabs.current_tab=2;game.resident_connections.records_host.show();game.resident_connections.refresh()
	check(game.resident_connections.records_text.text.contains("实际100 token") and game.resident_connections.records_text.text.contains("估算"),"resident-page records expose honest actual and estimated usage")
	var output:=OS.get_environment("HABITAT_OVERNIGHT_CAPTURE_DIR")
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	for size in [Vector2i(1280,800),Vector2i(960,640)]:
		root.size=size
		await process_frame;await process_frame
		game.resident_connections.details_scroll.ensure_control_visible(game.resident_connections.records_text)
		await process_frame;await process_frame
		check(game.resident_connections.get_global_rect().encloses(game.resident_connections.footer.get_global_rect()),"record drawer warning stays inside "+str(size))
		check(game.resident_connections.details_scroll.get_global_rect().intersection(game.resident_connections.records_text.get_global_rect()).size.y>=80,"record entries actually visible "+str(size))
		if not output.is_empty():
			await RenderingServer.frame_post_draw
			var image:=root.get_texture().get_image();check(image.get_size()==size,"actual viewport dimensions "+str(size));image.save_png(output.path_join("records-%dx%d.png"%[size.x,size.y]))
	game.queue_free();await process_frame
	print("Autonomy records: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)
