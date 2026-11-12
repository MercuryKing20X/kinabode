extends SceneTree
const Talk=preload("res://tests/dialogue_ui_fixture.gd")

const Channels = preload("res://scripts/dialogue_channels.gd")
const BBQ_UI=preload("res://tests/barbecue_ui_fixture.gd")
var checks := 0
var failed := false

class FakeAdapter extends "res://scripts/companion_link.gd":
	var sent: Array = []
	func _start() -> bool: return true
	func _send(message: Dictionary) -> bool:
		sent.append(message.duplicate(true)); return true

func _initialize() -> void: call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failed = true; push_error(label)

func run() -> void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"): quit(1); return
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game); game.save_enabled = false; game.set_process(false); game.view.sound_enabled = false
	await process_frame
	Talk.open(game,"codex")
	game.world.director.set_all_enabled(false)
	check(game.links.values().all(func(connection): return connection._pid == -1), "startup never launches inference")
	for connection in game.links.values(): connection.queue_free()
	game.links.clear()
	game.dialogue_adapter_factory = func(_id, _scope): return FakeAdapter.new()
	game._ensure_link("codex"); game._ensure_link("companion-2"); game.link = game.links.codex
	# C: Fake adapters created by acquire skip the connect-button observer wiring.
	# Attach the same existing diagnostic observer as connect_ai, without a probe.
	for id in ["codex","companion-2"]:
		var connection:Node=game.links[id]
		if not connection.has_meta("pool_observed"):
			connection.set_meta("pool_observed",true)
			connection.event_received.connect(func(event):game.connection_pool.receive(id,event))
	game._select_chat("codex")
	game._bound_companion_event({"kind":"state", "message":"白色状态"}, "codex")
	check(game.status.text.contains("白色状态"), "selected connection shows its status")
	game._select_chat("companion-2")
	check(not game.status.text.contains("白色状态"), "switching residents removes the previous connection status")
	game._bound_companion_event({"kind":"state", "message":"蓝色状态"}, "companion-2")
	game._bound_companion_event({"kind":"queue", "count":2}, "codex")
	check(game.status.text.contains("蓝色状态"), "background queue cannot overwrite selected status")
	var previous_channel_status:String=game.dialogue.statuses[Channels.direct("codex")]
	game.links.codex._accept_event({"kind":"error", "message":"白色连接中断"})
	check(game.status.text.contains("蓝色状态"), "background error cannot overwrite selected status")
	game._select_chat("codex")
	# B: DIRECTION396: “连接只是一盏小灯，不弹错误”。
	check(game.status.text==previous_channel_status and not game.status.text.contains("白色连接中断"), "returning preserves the original channel while transport diagnostics stay out of chat")
	check(game.connection_pool.states.get("codex",{}).get("state")=="error" and game.connection_pool.states.get("companion-2",{}).get("state")!="error", "error lamp remains bound only to the failed resident connection")
	game.links.codex._accept_event({"kind":"question", "id":"q1", "text":"先去海边吗？", "choices":["去"]})
	check(game.chat_log.get_parsed_text().count("等你回答") == 1, "only pending question is marked waiting")
	Talk.send(game,"去")
	check(game.links.codex.sent[-1].kind == "tool_result" and game.links.codex.sent[-1].id == "q1", "direct answer actually reaches exact pending adapter request")
	check(not game.chat_log.get_parsed_text().contains("等你回答"), "answered question no longer claims to be waiting")
	game.links.codex._accept_event({"kind":"question", "id":"q2", "text":"再去田边吗？", "choices":["去田边"]})
	check(game.chat_log.get_parsed_text().count("等你回答") == 1, "older question cannot masquerade as the current pending question")
	Talk.send(game,"去田边")
	game.links.codex._accept_event({"kind":"state", "state":"ready", "turnComplete":true})
	game.links.codex._accept_event({"kind":"question", "id":"q1", "text":"新一轮复用请求编号", "choices":["继续"]})
	check(game.chat_log.get_parsed_text().count("等你回答") == 1, "reused request ID cannot reactivate an old history entry")
	game.links.codex._accept_event({"kind":"state", "state":"disconnected", "message":"已断开"})
	check(not game.chat_log.get_parsed_text().contains("等你回答") and game.choices.get_child_count() == 0, "disconnection removes waiting label and answer controls")
	game._select_chat(Channels.ALL)
	game._ensure_group_link("companion-2")
	game.group_links["companion-2"]._accept_event({"kind":"question", "id":"g1", "text":"一起去吗？", "choices":["好"]})
	game._answer_group("companion-2", "g1", "好")
	check(game.group_links["companion-2"].sent[-1].id == "g1", "group answer reaches only exact group adapter request")
	check(not game.chat_log.get_parsed_text().contains("等你回答"), "group answer also clears historical waiting label")
	game._show_barbecue_menu()
	var camp:Node=BBQ_UI.shown(game,"res://scripts/fireside_panel.gd")
	check(camp!=null and BBQ_UI.descendants(camp.body).filter(func(n):return n is Button).size()==2 and camp.roast_button.text=="烧烤" and game.choices.get_child_count()==0,"two explicit camp actions have an independent activity panel")
	game.links.codex._accept_event({"kind":"question","id":"q3","text":"等你决定","choices":["继续"]})
	check(is_instance_valid(camp) and camp.visible and BBQ_UI.descendants(camp.body).filter(func(n):return n is Button).size()==2 and game.choices.get_child_count()==0,"background direct question cannot replace visible activity buttons")
	game._select_chat("codex")
	check(game.activity_choices.get_child_count() == 0 and game.choices.get_child_count() == 1, "switching channel restores answers and removes stale activity controls")
	game._show_barbecue_menu()
	check(game.choices.get_child_count() == 1 and game.activity_choices.get_child_count() == 0, "barbecue cannot hide a current decision")
	game._stop_companion()
	check(not game.questions.has("codex") and not game.chat_log.get_parsed_text().contains("等你回答"), "stop retires pending question while preserving historical text")
	game.links.codex._accept_event({"kind":"state", "state":"ready", "turnComplete":true})
	game.group_links["companion-2"]._accept_event({"kind":"state", "state":"ready", "turnComplete":true})
	game.links.codex._accept_event({"kind":"action", "id":"wood", "command":{"intent":"chop", "target_id":"home.tree.01"}})
	check(game.world.work.jobs.has("codex") and game.world.work.claims.get("home.tree.01") == "codex", "accepted task reserves only the actual resident's target")
	var job: Dictionary = game.world.work.jobs.codex.duplicate(true)
	game.links["companion-2"]._accept_event({"kind":"action", "id":"same-tree", "command":{"intent":"chop", "target_id":"home.tree.01"}})
	check(not game.world.work.jobs.has("companion-2") and game.world.work.jobs.codex == job, "another resident cannot steal accepted tree work")
	var actors: Dictionary = game.world.actors.duplicate(true)
	var revision: int = game.world.revision
	game._focus_companion()
	check(game.view.region_id == game.world.actors.codex.region_id and game.view.center == game.world.point(game.world.actors.codex), "find partner centers camera on actual resident")
	check(game.world.actors == actors and game.world.work.jobs.codex == job and game.world.revision == revision, "finding a working partner never moves anyone or changes work and resources")
	game._select_chat("companion-2")
	game._bound_companion_event({"kind":"state", "message":"正在听你说"}, "companion-2")
	# Synthetic UI event; the underlying work remains unfinished in this disposable world.
	game.world.work.record_event("codex", job, "progress", "验收用后台进度")
	game._process(.21)
	check(game.status.text.contains("正在听你说"), "background task progress cannot overwrite selected conversation status")
	game._select_chat("codex")
	check(game.status.text.contains("验收用后台进度"), "task progress remains available in its original channel")
	game._stop_companion()
	check(not game.world.work.jobs.has("codex") and not game.world.work.claims.has("home.tree.01"), "selected stop releases actual task and reservation")
	game._select_chat(Channels.ALL)
	check(not game.find_partner_button.visible, "group chat never implies there is one selected partner to locate")
	var camera: Vector2 = game.view.center
	game._focus_companion()
	check(game.view.center == camera, "group find is a no-op")
	# The camera's completed-room fixture is prepared independently of hunger;
	# still build it from real wood, then restore the live subsystem unchanged.
	var hunger_enabled:bool=game.world.hunger.enabled
	game.world.hunger.enabled=false
	game.chat.hide();game.chat_input.release_focus();game._process(0)
	game._house_scenario()
	game.world.hunger.enabled=hunger_enabled
	game._qa_job("codex", {"intent":"enter", "target_id":"home.house.01"})
	game._select_chat("codex")
	actors = game.world.actors.duplicate(true); revision = game.world.revision
	game._focus_companion()
	check(game.view.region_id.begins_with("room.") and game.view.center == game.world.point(game.world.actors.codex), "find partner also uses actual independent room coordinates")
	check(game.world.actors == actors and game.world.revision == revision, "indoor find preserves world and human location")
	game._return_to_player()
	check(game.view.region_id == game.world.actors.human.region_id, "return to my view restores the human region")
	var capture_dir: String = OS.get_environment("HABITAT_LIFE_CAPTURE_DIR")
	if not capture_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(capture_dir)
		game.chat.show(); game._select_chat("companion-2"); game._focus_companion()
		game.links["companion-2"]._accept_event({"kind":"question", "id":"capture-q", "text":"这是界面验收用的模拟提问：先去田边还是海边？", "choices":["去田边", "去海边"]})
		await shot(game, capture_dir.path_join("waiting.png"))
		Talk.send(game,"去田边")
		await shot(game, capture_dir.path_join("answered.png"))
		game._show_barbecue_menu()
		await shot(game, capture_dir.path_join("barbecue.png"))
		root.size = Vector2i(960, 640)
		await shot(game, capture_dir.path_join("small.png"))
	game.queue_free(); await process_frame
	print("Life acceptance: %s checks, %s" % [checks, "FAIL" if failed else "PASS"])
	quit(1 if failed else 0)

func shot(game: Node, path: String) -> void:
	await process_frame; await process_frame; await RenderingServer.frame_post_draw
	var viewport_size: Vector2 = root.get_visible_rect().size
	for control in [game.chat_input, game.find_partner_button, game.activity_choices, game.choices]:
		check(Rect2(Vector2.ZERO, viewport_size).encloses(control.get_global_rect()), "visible control fits actual viewport: " + control.name)
	check(game.chat.get_global_rect().end.y + 8 <= game.dialogue_button.get_global_rect().position.y, "chat panel leaves bottom dialogue and gathering buttons unobstructed")
	root.get_texture().get_image().save_png(path)
