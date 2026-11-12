extends SceneTree
const Talk=preload("res://tests/dialogue_ui_fixture.gd")
var checks := 0
var failed := false
class FakeLink extends Node:
	var replies: Array = []
	var answers: Array = []
	var sent: Array = []
	var cancelled := false
	func reply(id: String, value: Dictionary) -> void: replies.append({"id":id,"value":value})
	func answer(id: String, value: Dictionary) -> void: answers.append({"id":id,"value":value})
	func send_message(text: String, snapshot: Dictionary) -> void: sent.append({"text":text,"snapshot":snapshot})
	func cancel_turn() -> void: cancelled = true
	func is_busy() -> bool: return false
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks+=1
	if not value: failed=true; push_error(label)
func run() -> void:
	var directory := OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"): quit(1); return
	var game: Node = load("res://scenes/main.tscn").instantiate(); root.add_child(game)
	game.save_enabled=false; game.set_process(false); game.view.sound_enabled=false; game.world.local_companion.set_enabled(false)
	await process_frame
	Talk.open(game,"codex")
	check(game.links.size()==2 and game.links.values().all(func(link): return link._pid==-1),"two independent connections, no automatic model startup")
	check(game.links.codex.resident_id=="codex" and game.links["companion-2"].resident_id=="companion-2","separate bound resident IDs")
	check(game.links.codex.world_id==game.world.world_id,"sessions scoped to actual world")
	var codex:=FakeLink.new(); var other:=FakeLink.new(); game.add_child(codex); game.add_child(other)
	game.links={"codex":codex,"companion-2":other}; game.link=codex
	game._select_chat("companion-2"); Talk.send(game,"照顾你的果园")
	check(other.sent.size()==1 and codex.sent.is_empty() and other.sent[0].snapshot.self.id=="companion-2","chat uses selected actor snapshot and session")
	var human: Array=game.world.actors.human.position.duplicate()
	game._bound_companion_event({"kind":"action","id":"other-act","command":{"intent":"manage_farm","farm_id":"farm.hill","crop_id":"apple","mode":"once"}},"companion-2")
	check(other.replies[-1].value.ok and game.world.farms.active("companion-2") and not game.world.farms.active("codex"),"model event starts only its own permitted farm")
	game._bound_companion_event({"kind":"action","id":"cross","command":{"intent":"manage_farm","farm_id":"farm.home","crop_id":"turnip","mode":"once"}},"companion-2")
	check(not other.replies[-1].value.ok,"other model cannot claim Codex farm")
	game._bound_companion_event({"kind":"question","id":"q-other","text":"苹果还是蓝莓？","choices":["苹果","蓝莓"]},"companion-2")
	game._bound_companion_event({"kind":"question","id":"q-codex","text":"要种番茄吗？","choices":["种番茄"]},"codex")
	check(game.pending_question=="q-other" and game.questions.size()==2,"concurrent questions never steal selected answer target")
	check(game.world.farms.orders["companion-2"].status=="paused","question pauses farm order")
	Talk.send(game,"苹果")
	check(other.answers.size()==1 and other.answers[0].id=="q-other" and codex.answers.is_empty(),"answer routed only to chosen question")
	check(game.questions.has("codex") and not game.questions.has("companion-2"),"other unanswered question remains pending")
	game._select_chat("codex"); game._stop_companion()
	check(codex.cancelled and not other.cancelled and game.questions.is_empty(),"stop cancels only selected model")
	game._bound_companion_event({"kind":"assistant","text":"果园留给我。"},"companion-2")
	check(game.view.speech_actor=="companion-2","speech bubble follows speaking resident")
	check(game.world.actors.human.position==human,"both model event paths leave human control independent")
	game.farm_panel.open_farm("farm.east","farm.east.plot.01")
	game.farm_panel.focus_requested.emit("farm.east")
	check(game.farm_panel.visible and game.view.center==game.world.catalog.rectangle(game.world.farms.farms["farm.east"].rect).get_center(),"farm selector focuses map without hiding controls")
	check(game.farm_panel.plot_button.text=="播种到这块田" and not game.farm_panel.plot_button.disabled,"clickable fixed plot opens actual action")
	game.editor.open_art("crop-tomato")
	check(game.editor.category=="plant" and game.editor.work_picker.item_count==6 and game.editor.frame_picker.item_count==3,"workshop separates plants and three growth stages")
	check(not game.editor.structure_toggle.visible,"pixel plant editing cannot alter yield or rules")

	game._gather_residents()
	check(codex.cancelled and other.cancelled and game.world.activities.members.size()==4,"gather cancels both links and includes all four")
	game._bound_companion_event({"kind":"action","id":"stale","command":{"intent":"dance"}},"codex")
	check(not codex.replies[-1].value.ok and game.world.work.jobs.codex.intent=="gather_residents","queued model action cannot replace formation")
	game._participants_chosen(["npc.mira","npc.nora"],{"intent":"dance"})
	check(game.world.work.jobs["npc.mira"].intent=="dance" and game.world.work.jobs["npc.nora"].intent=="dance","same picker dispatches both NPCs without model inference")
	for actor_id in game.world.actors:game.world.command(actor_id,{"intent":"stop"})
	game.participant_picker.open_for({"intent":"use_facility","target_id":"play.gazebo"},"npc.nora")
	check(game.participant_picker.toggles.keys().size()==game.world.actors.size()-1 and not game.participant_picker.toggles.has("human") and game.participant_picker.toggles.values().all(func(toggle):return not toggle.disabled),"all residents eligible for recreation")
	game.participant_picker.hide()
	game._select_chat("npc.nora");var model_count:int=codex.sent.size()+other.sent.size();Talk.send(game,"你好")
	check(model_count==codex.sent.size()+other.sent.size() and game.local_host_commands.unknown(["npc.nora"]).examples.all(func(example):return game.status.text.contains(example)) and game.dialogue.histories.get("direct:npc.nora",[]).any(func(entry):return entry.sender_id=="npc.nora" and entry.kind=="local"),"unconnected NPC gives an authored local reply and examples without any model dialogue")
	game.editor.open_art("black-scarf-girl");game.editor.resident_name.text="墨墨";game.editor._rename_resident()
	check(game.world.actors["npc.nora"].name=="墨墨" and game.chat_picker.get_item_text(game.chat_picker.selected)=="墨墨","workshop rename updates selected dialogue identity")
	game._gather_residents()
	game._select_chat("companion-2");game._stop_companion()
	check(not game.world.activities.members.has("companion-2") and game.world.activities.members.has("codex"),"selected stop never releases another resident")
	game.world.activities.dismiss();game.editor.hide();game.chat_input.release_focus();game.questions.clear();game.pending_question=""
	game.world.director.set_all_enabled(true)
	game._select_chat("codex");game.pending_question="isolated-question";game._process(.1)
	check(game.world.director.routines.codex.held and not game.world.director.routines["companion-2"].held and not game.world.director.routines["npc.mira"].held,"one conversation holds only its bound resident")
	game.pending_question="";game._process(.1)
	game._select_chat("npc.mira")
	game.activity_toggle.button_pressed=false;game.chatter_toggle.button_pressed=false
	check(not game.world.director.routines["npc.mira"].enabled and game.world.director.routines["companion-2"].enabled,"daily toggle controls only selected resident")
	var settings:=ConfigFile.new();settings.load(directory.path_join("local-life.cfg"))
	check(settings.get_value("resident:npc.mira","enabled",true)==false and settings.get_value("resident:companion-2","enabled",false)==true,"per-resident daily preferences persisted independently")
	var identity: Dictionary=game.world.actors["npc.mira"].duplicate(true)
	game._change_controller(0)
	check(game.links.has("npc.mira") and game.links["npc.mira"]._pid==-1 and game.links["npc.mira"].resident_id=="npc.mira","switching NPC to Codex prepares its own lazy connection without inference")
	check(game.world.actors["npc.mira"].id==identity.id and game.world.actors["npc.mira"].appearance_id==identity.appearance_id and game.world.actors["npc.mira"].carry==identity.carry,"source switch preserves appearance identity and items")
	var token: String="";var untouched: String=""
	for candidate in game.endpoint.bindings:
		if game.endpoint.bindings[candidate]=="npc.mira":token=candidate
		if game.endpoint.bindings[candidate]=="companion-2":untouched=candidate
	check(not token.is_empty(),"model source receives individual external binding")
	var request: Dictionary={"session":game.endpoint.session,"token":token,"expires":Time.get_unix_time_from_system()+5,"operation":"act","request_id":"npc-social","query":{"intent":"dance"}}
	check(game.endpoint.handle(request).ok,"new model binding controls the existing NPC through common rules")
	game._change_controller(1)
	request.request_id="late-command"
	check(not game.endpoint.handle(request).ok and game.endpoint.bindings.has(untouched),"source switch revokes old token without invalidating other residents")
	game._bound_companion_event({"kind":"assistant","text":"stale model text"},"npc.mira")
	check(not game.chat_log.get_parsed_text().contains("stale model text") and not game.world.work.jobs.has("npc.mira"),"local mode rejects stale dialogue and stops old task")
	game._change_controller(0)
	check(game.links["npc.mira"]._pid==-1 and not game.endpoint.bindings.has(token),"switching back creates a new token and never restarts inference by itself")
	game.queue_free(); await process_frame
	print("Farm controller: %s checks, %s"%[checks,"FAIL" if failed else "PASS"]);quit(1 if failed else 0)
