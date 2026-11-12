extends SceneTree
const Talk=preload("res://tests/dialogue_ui_fixture.gd")
const Channels=preload("res://scripts/dialogue_channels.gd")
const F=preload("res://tests/cooking_fixture.gd")
var checks:=0
var failed:=false
var game: Node
var output: String
class Fake extends "res://scripts/companion_link.gd":
	var sent: Array=[]
	func _start() -> bool:return true
	func _send(message: Dictionary) -> bool:sent.append(message.duplicate(true));return true
	func cancel_turn() -> void:
		if _cancelling:return
		_generation+=1;_cancelling=true;_busy=true;_pending_ids.clear();_send({"kind":"cancel"})
	func finish(text: String="",tokens: int=100) -> void:
		if not text.is_empty():_accept_event({"kind":"assistant","text":text})
		_accept_event({"kind":"usage","total_tokens":tokens,"input_tokens":maxi(0,tokens-20),"output_tokens":mini(tokens,20),"complete":true})
		_accept_event({"kind":"state","state":"ready","turnComplete":true})
	func acknowledge() -> void:_accept_event({"kind":"state","state":"cancelled"})
func _initialize() -> void:call_deferred("run")
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failed=true;push_error(label)
func step(seconds: float) -> void:
	var elapsed:float=0
	while elapsed<seconds:
		var delta:float=minf(.5,seconds-elapsed);game._process(delta);elapsed+=delta
func wake(key: String="fixture") -> void:
	game.chat_input.release_focus() # This helper exercises idle wakeups, not the separate focus-block test.
	game.autonomy.player_input();game.autonomy.scheduler.enqueue("codex",key,"house_completed","观察器的事件输入");step(6)
	if not game.autonomy.scheduler.active.has("codex"):print("WAKE_DEBUG ",key," status=",game.autonomy.status("codex")," busy=",game.links.codex.is_busy()," queues=",game.autonomy.scheduler.queues)
func shot(name: String) -> void:
	game.resident_connections.refresh();await process_frame;await process_frame
	if not output.is_empty():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(name+".png"))
	check(root.get_visible_rect().encloses(game.resident_connections.get_global_rect()),"actual resident panel fits "+name)
	check(game.resident_connections.get_global_rect().encloses(game.resident_connections.footer.get_global_rect()),"fixed warning remains visible "+name)
func run() -> void:
	var directory:=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(1);return
	output=OS.get_environment("HABITAT_AUTONOMY_CAPTURE_DIR")
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false);root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
	await process_frame
	Talk.open(game,"codex")
	# Keep this same-day accounting fixture away from the real local midnight.
	# The actual ForestSystem clock still advances; its day origin moves equally.
	var bias:float=Time.get_time_zone_from_system().bias*60.0
	var midday:float=ceil((Time.get_unix_time_from_system()+bias)/86400.0)*86400.0+43200-bias
	var shift:float=midday-game.world.forest.clock
	game.world.forest.clock=midday;game.world.days.origin+=shift;game.autonomy.scheduler.reset()
	game.world.director.set_all_enabled(false);game.view.sound_enabled=false;game.chat.hide();game.chat_input.release_focus()
	game.dialogue_adapter_factory=func(_id,_scope):return Fake.new()
	for connection in game.links.values():connection.queue_free()
	game.links.clear();game._ensure_link("codex");game._ensure_link("companion-2");game.link=game.links.codex
	var white: Fake=game.links.codex;var blue: Fake=game.links["companion-2"]
	var prefs: RefCounted=game.resident_connections.preferences;var schedule: RefCounted=game.autonomy.scheduler
	game.autonomy.refresh_support()
	check(not prefs.preference("codex").runtime_active,"migrated medium disabled even with native-capable adapter")
	prefs.enable_autonomy("codex",true)
	check(prefs.preference("codex").runtime_active and not prefs.preference("companion-2").runtime_active,"explicit per-resident opt-in")
	check(game.controller_picker.get_item_text(0).contains("主动事件"),"connection source label acknowledges enabled autonomous events")
	wake();check(white.sent.size()==1 and white.sent[0].kind=="autonomy_event" and blue.sent.is_empty(),"host sends one actual autonomy envelope to exact resident only")
	check(game._resident_connection_snapshot("codex").activity.contains("主动思考"),"resident activity truthfully distinguishes an active autonomous round")
	white._accept_event({"kind":"question","id":"auto-question","text":"先做什么？"})
	step(.2)
	check(game.questions.is_empty() and not white._cancelling and white.sent[-1].kind=="tool_result" and white.sent[-1].result.error=="autonomy_cannot_open_question","autonomy explicitly rejects blocking question without opening a disappearing UI")
	check(JSON.stringify(white.sent[0].world).to_utf8_buffer().size()<=4096 and not JSON.stringify(white.sent[0].world).contains("pixels"),"session uses bounded context")
	white.finish("我在这里，陪你看看。",150)
	var history: Array=game.dialogue.histories[Channels.direct("codex")]
	check(history[-1].kind=="autonomy" and history[-1].sender_id=="codex" and not game.dialogue.histories.has(Channels.direct("companion-2")),"autonomous output recorded in matching private history")
	game._render_chat();check(game.chat_log.get_parsed_text().contains("主动 · 小白"),"player can distinguish proactive model text")
	check(game.view.speech_by_actor.codex.source=="autonomy","viewport speech carries proactive marker")
	check(schedule.usage("codex").tokens==150 and schedule.usage("codex").calls==1 and schedule.usage("codex").reserved==0,"actual usage displayed and unused reservation released")
	step(10);check(white.sent.filter(func(message):return message.kind=="autonomy_event").size()==1 and blue.sent.is_empty(),"reply does not chain to self or other resident")
	# DIRECTION 2026-11-09: typing queues, never cancels an active connection.
	step(600);wake("second");check(schedule.active.has("codex"),"new major event after cooldown can wake")
	var old_key: String=white.turn_key;var human: Dictionary=game.world.actors.human.duplicate(true)
	var active_generation:int=white._generation;var sent_before_queue:int=white.sent.size()
	var calls_before_queue:int=int(schedule.usage("codex").calls)
	game._select_chat("codex");Talk.send(game,"先和我聊聊")
	check(not white._cancelling and white.turn_key==old_key and white._generation==active_generation,"typing preserves the exact active autonomous turn and generation")
	check(game.autonomy.pending.size()==1 and game.autonomy.pending[0].scope=="direct" and game.autonomy.pending[0].targets==["codex"] and game.autonomy.pending[0].text=="先和我聊聊","player message is queued with exact original actor and scope")
	check(white.sent.size()==sent_before_queue and int(schedule.usage("codex").calls)==calls_before_queue and blue.sent.is_empty(),"queued typing starts no extra inference or cancellation")
	white._accept_event({"kind":"assistant","turn_key":old_key,"text":"当前自主回应"})
	check(JSON.stringify(game.dialogue.histories).contains("当前自主回应") and white.turn_key==old_key,"current autonomous response continues while player input waits")
	game._select_chat("companion-2");game.autonomy.flush_pending()
	check(game.autonomy.pending.size()==1 and white.sent.size()==sent_before_queue and blue.sent.is_empty(),"changing selected resident cannot flush a busy turn or reroute queued input")
	# The fake's zero-token completion is an explicit known fixture receipt, not
	# an unknown real call treated as free. The original 150+220 accounting
	# assertion below stays unchanged and still exercises actual accumulation.
	white.finish("",0);await process_frame;await process_frame
	check(white.sent[-1].kind=="chat" and white.sent[-1].text=="先和我聊聊" and blue.sent.is_empty(),"queued player message stays bound after selecting another resident")
	check(white.sent.filter(func(message):return message.kind=="chat" and message.get("text","")=="先和我聊聊").size()==1 and not schedule.active.has("codex"),"completed autonomy flushes the queued player message exactly once before another wakeup")
	check(white.sent[-1].level=="medium","ordinary chat also uses actual selected reasoning level")
	white._accept_event({"kind":"assistant","turn_key":old_key,"text":"过期自主文本"})
	check(not JSON.stringify(game.dialogue.histories).contains("过期自主文本"),"old turn token cannot cross new player turn")
	white.finish("在呢。",220)
	check(schedule.usage("codex").tokens==370,"player and proactive actual token use accumulates")
	check(game.world.actors.human==human,"no human movement or operations")
	# All Main held cases advance the real world.
	step(600);game.autonomy.player_input();schedule.enqueue("codex","held","house_completed","真实事件")
	game.questions.codex={"id":"q","text":"pending"};step(10)
	check(not schedule.active.has("codex"),"pending question blocks autonomous turn")
	game.questions.clear();game._refresh_question_controls()
	game.world.activities.members.codex={};step(10);check(not schedule.active.has("codex"),"assembly blocks autonomous turn")
	game.world.activities.members.clear()
	game._select_chat("codex");game.chat_input.grab_focus();step(10);check(not schedule.active.has("codex"),"chat focus blocks autonomous turn")
	game.chat_input.release_focus();step(6);check(schedule.active.has("codex"),"release held allows unexpired event")
	game._stop_resident("codex")
	white._accept_event({"kind":"assistant","text":"迟到回复"})
	white._accept_event({"kind":"action","id":"late","command":{"intent":"chop","target_id":"home.tree.01"}})
	check(not game.world.work.jobs.has("codex") and not JSON.stringify(game.dialogue.histories).contains("迟到回复"),"late text and actions rejected during cancellation")
	white.acknowledge();step(10)
	check(not schedule.active.has("codex") and game.autonomy.pending.is_empty(),"explicit stop cancels and clears deferred messages")
	# Runtime adapter rejection stays honest and never starts a helper.
	game.external_residents["companion-2"]=true
	blue.queue_free();game.links.erase("companion-2");game._ensure_link("companion-2")
	game.autonomy.refresh_support();check(not game.autonomy.status("companion-2").supported,"external adapter is not falsely claimed to support autonomy")
	game.external_residents.erase("companion-2")
	# Actual UI: Ultra confirmation and explicit activation are separate.
	var panel: PanelContainer=game.resident_connections
	panel.open("codex");panel.tabs.current_tab=2;panel._level_selected(3)
	check(panel.ultra_dialog.visible and panel.ultra_dialog.dialog_text.contains("token") and panel.ultra_dialog.dialog_text.contains("费用"),"Ultra warning states real token/cost consequences")
	panel._confirm_ultra();panel.ultra_dialog.hide()
	prefs.enable_autonomy("codex",false);panel._toggle_autonomy(true)
	check(panel.ultra_dialog.visible and not prefs.preference("codex").autonomy_enabled,"previous Ultra selection cannot bypass new activation warning")
	panel._confirm_ultra();panel.ultra_dialog.hide();panel.refresh()
	check(prefs.preference("codex").runtime_active and panel.usage_label.text.contains("370 token") and panel.footer.text.contains("token"),"UI reports actual status and accumulated usage")
	for size in [Vector2i(1280,800),Vector2i(960,640)]:root.size=size;await shot("ultra-"+str(size.x)+"x"+str(size.y))
	# Review regression: three queued inputs must wait for each actual preceding turn.
	prefs.choose("codex","medium");game.autonomy.quiet_until.clear();step(610);wake("three-inputs")
	game._select_chat("codex")
	for text in ["第一条","第二条","第三条"]:Talk.send(game,text)
	check(game.autonomy.pending.size()==3,"three player inputs retained while active autonomy continues")
	white.finish("",0);await process_frame;await process_frame
	check(white.sent[-1].get("text")=="第一条" and game.autonomy.pending.size()==2,"first queued input starts, remaining inputs retained while busy")
	white.finish("一",100);await process_frame;await process_frame
	check(white.sent[-1].get("text")=="第二条" and game.autonomy.pending.size()==1,"second input waits for first actual completion")
	white.finish("二",100);await process_frame;await process_frame
	check(white.sent[-1].get("text")=="第三条" and game.autonomy.pending.is_empty(),"third input sent exactly once after second completes")
	white.finish("三",100);await process_frame
	# Review regression: actual link polling notices a vanished owned helper.
	step(610);wake("helper-exit");Talk.send(game,"连接恢复后发给你")
	white._session_dir=directory.path_join("fake-session");DirAccess.make_dir_recursive_absolute(white._session_dir.path_join("outbox"))
	white._pid=OS.create_process("/bin/sh",PackedStringArray(["-c","exit 0"]))
	await create_timer(.1).timeout
	white._process(.2);await process_frame;await process_frame
	check(not schedule.active.has("codex") and white.sent[-1].get("text")=="连接恢复后发给你","helper exit releases active and flushes player input after isolation")
	white.finish("连接恢复",100)
	# Review regression: heartbeat timeout has a terminal event, with unknown usage retained.
	step(3610);wake("heartbeat-timeout")
	check(schedule.active.has("codex"),"heartbeat fixture starts a real fake-adapter turn after the hourly budget window")
	white._pid=OS.create_process("/bin/sh",PackedStringArray(["-c","exec sleep 10"]));white._started_at=Time.get_ticks_msec()-61000
	white._process(.2)
	check(not schedule.active.has("codex") and schedule.usage("codex").unknown_turns>0,"heartbeat timeout terminates autonomy without pretending usage is zero")
	OS.kill(white._pid);white._pid=-1;white._shutting_down=false;white.set_process(false)
	# Replacing an active link revokes the source, even if its cancel acknowledgement never arrives.
	game.autonomy.quiet_until.clear();step(610);wake("source-replacement")
	check(schedule.active.has("codex"),"source switch fixture is genuinely in flight")
	game._bind_external_ai("codex",true,false)
	check(not schedule.active.has("codex") and not prefs.preference("codex").autonomy_enabled,"replacing active source clears scheduler state and explicit opt-in")
	game._bind_external_ai("codex",false,false);white=game.links.codex
	# A capability error disables autonomy, but must never silently turn high player chat into low.
	prefs.choose("codex","high");white.capability_error="测试：当前模型未公布high";game.autonomy.refresh_support()
	check(not game.autonomy.status("codex").supported,"capability error is honestly reported")
	game._send_direct("codex","保持所选档位，失败就明确报告")
	check(white.sent[-1].level=="high","unsupported selected level is still sent to explicit validator, never silently downgraded")
	white.finish("假适配器结束",100);prefs.choose("codex","medium")
	check(game.autonomy.status("codex").supported,"explicit new preference can recover capability validation")
	var final_tokens: int=int(schedule.usage("codex").tokens)
	# Retained source baseline, plus real elapsed clock and restored budget prefs.
	var queues: int=schedule.queues.size();schedule.reset();step(6)
	check(schedule.active.is_empty() and schedule.queues.values().all(func(items):return items.is_empty()),"reload baseline no work replay")
	var restored:=preload("res://scripts/resident_intelligence_preferences.gd").new();restored.setup(directory,game.world.world_id)
	check(not restored.preference("codex").autonomy_enabled and restored.accounting("codex").tokens==final_tokens,"preferences and actual usage survive reload outside schema7")
	game.world.advance(86400);schedule.advance(86400)
	check(schedule.usage("codex").tokens==0 and schedule.usage("codex").calls==0,"cross-calendar day usage reset")
	check(white._pid==-1 and game.links["companion-2"]._pid==-1,"entire integration uses fake adapters, zero model processes")
	game.queue_free();await process_frame
	print("Autonomy controller: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)
