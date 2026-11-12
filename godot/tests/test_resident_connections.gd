extends SceneTree
const F=preload("res://tests/cooking_fixture.gd")
const B=preload("res://tests/backpack_fixture.gd")
const Preferences=preload("res://scripts/resident_intelligence_preferences.gd")
const Channels=preload("res://scripts/dialogue_channels.gd")
var game: Node
var panel: PanelContainer
var checks:=0
var failed:=false
var output: String
var directory: String
func _initialize() -> void:call_deferred("run")
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failed=true;push_error(label)
func shot(name: String) -> void:
	panel.refresh();await process_frame;await process_frame
	if not output.is_empty():await RenderingServer.frame_post_draw
	var bounds:=root.get_visible_rect()
	check(bounds.encloses(game.resident_connections_button.get_global_rect()),"top right resident entry fits "+name)
	if panel.visible:
		check(bounds.encloses(panel.get_global_rect()),"resident drawer fits "+name)
		check(panel.get_global_rect().encloses(panel.footer.get_global_rect()),"fixed reminder fits "+name)
		check(panel.footer.get_global_rect().position.y>=panel.details_scroll.get_global_rect().end.y,"reminder remains outside scroll "+name)
	if not output.is_empty():root.get_texture().get_image().save_png(output.path_join(name+".png"))
func pair(name: String) -> void:
	root.size=Vector2i(1280,800);await shot(name+"-1280x800")
	root.size=Vector2i(960,640);await shot(name+"-960x640")
func run() -> void:
	directory=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(1);return
	output=OS.get_environment("HABITAT_RESIDENT_CONNECTIONS_CAPTURE_DIR")
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false);root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
	await process_frame
	game.world.director.set_all_enabled(false);game.view.sound_enabled=false;game.chat.hide();game.chat_input.release_focus()
	var menus: Array=game.resident_connections_button.get_parent().get_children().filter(func(child):return child is MenuButton)
	check(menus.size()==4 and menus.all(func(menu):return not menu.flat),"home/activity/handbook/settings menus retain opaque Button backgrounds")
	panel=game.resident_connections
	await pair("home-layout")
	game._select_chat("codex");game.chat_input.text="保留给小白的草稿"
	game._handbook_selected("residents");panel.select_resident("companion-2")
	check(not game.action_dock.visible,"drawer hides contextual action strip without stopping activity")
	check(game.chat_actor=="codex" and game.chat_input.text=="保留给小白的草稿","browsing residents does not change direct recipient or draft")
	check(panel.resident_ids.size()==game.world.actors.size()-1 and panel.resident_ids.has("npc.mira"),"list includes all configured residents, excluding human")
	check(game.controller_picker.get_parent()==panel.controls_host and game.daily_controls.get_parent()==panel.life_host,"original control widgets moved out of chat without duplicate settings")
	check(game.gathering_button.get_parent()==panel.actions_host and game.find_partner_button.get_parent()==panel.actions_host,"gather and camera focus now live in resident drawer")
	check(game.order_bar.get_parent()==panel.life_host and game.project_panel.get_parent()==panel.life_host,"task progress and construction plan also live in resident drawer")
	check(panel.origin.text=="智能小蓝（本地预设）\n已配置 · 尚未启动","optional model keeps local preset identity without claiming startup")
	await pair("cloud-configured")
	panel.select_resident("npc.mira");panel.tabs.current_tab=1
	check(panel.origin.text=="智能小橙（本地预设）\n可选加装：未开启" and not panel.intelligence.visible and panel.external_button.disabled,"local preset identity retains truthful optional extension controls")
	await pair("local-resident")
	panel.select_resident("codex");panel.tabs.current_tab=2
	var actors: String=game.world.memories._canonical(game.world.actors)
	var jobs: String=game.world.memories._canonical(game.world.work.jobs)
	panel.level_picker.item_selected.emit(3)
	check(panel.ultra_dialog.visible and panel.ultra_dialog.dialog_text.contains("小白") and panel.ultra_dialog.dialog_text.contains("费用") and panel.ultra_dialog.dialog_text.contains("不会开始调用"),"Ultra opens real actor-bound expense confirmation")
	check(panel.preferences.preference("codex").level=="medium","selection is not saved before confirmation")
	await pair("ultra-confirmation")
	panel.ultra_dialog.canceled.emit();panel.ultra_dialog.hide()
	check(panel.preferences.preference("codex").level=="medium" and panel.level_picker.selected==1,"cancel preserves prior level and resets dropdown")
	panel.level_picker.item_selected.emit(3);panel.select_resident("companion-2");panel._confirm_ultra()
	check(panel.preferences.preference("codex").level=="medium" and panel.preferences.preference("companion-2").level=="medium","switching residents invalidates pending confirmation")
	panel.select_resident("codex");panel.tabs.current_tab=2;panel.level_picker.item_selected.emit(3);panel.ultra_dialog.confirmed.emit();panel.ultra_dialog.hide()
	check(panel.preferences.preference("codex").level=="ultra" and panel.preferences.preference("companion-2").level=="medium","confirmed Ultra is independent per resident")
	check(panel.footer.text.contains("尚未开启实际调用") and panel.footer.text.contains("费用"),"persistent footer truthfully warns without claiming activation")
	check(not panel.preferences.preference("codex").runtime_active,"reserved preference never activates runtime")
	panel.details_scroll.scroll_vertical=10000
	await pair("ultra-selected")
	check(game.world.memories._canonical(game.world.actors)==actors and game.world.memories._canonical(game.world.work.jobs)==jobs,"browsing and intelligence preferences do not mutate actors, tasks or inventory")
	var restored:=Preferences.new();restored.setup(directory,game.world.world_id)
	check(restored.preference("codex").level=="ultra" and not restored.preference("codex").runtime_active,"frontend preference reloads without active inference")
	var other_world:=Preferences.new();other_world.setup(directory,"other-world")
	check(other_world.preference("codex").level=="medium" and not restored.choose("codex","unsupported"),"preferences are world scoped and unknown levels rejected")
	panel.level_picker.item_selected.emit(0)
	check(panel.preferences.preference("codex").level=="low" and not panel.ultra_dialog.visible,"lowering level needs no extra confirmation")
	# The selected resident remains independent of a visible group channel.
	game._select_chat(Channels.ALL);panel.select_resident("companion-2");game._refresh_control_ui()
	game._change_controller(1)
	check(game.group_chat and game.world.actors["companion-2"].controller=="local" and game.world.actors.codex.controller=="model","source changes affect selected profile, not retained chat recipient")
	game._change_controller(0)
	check(game.group_chat and game.world.actors["companion-2"].controller=="model","model selection keeps group draft and starts no inference")
	panel.select_resident("codex");panel.level_picker.item_selected.emit(3);game._change_controller(1);panel.refresh();panel._confirm_ultra()
	check(panel.preferences.preference("codex").level=="low" and not panel.ultra_dialog.visible,"switching to local invalidates pending Ultra confirmation")
	game._change_controller(0)
	game.external_residents["companion-2"]=true
	var external: Dictionary=game._resident_connection_snapshot("companion-2")
	check(external.origin=="智能小蓝（本地预设）" and external.connection.contains("尚未确认"),"external extension keeps local preset identity without inventing a successful connection")
	game.external_residents.erase("companion-2")
	# Honest connection states from received events, while selecting another profile.
	game._bound_companion_event({"kind":"state","state":"error","message":"测试连接异常"},"companion-2")
	check(game._resident_connection_snapshot("companion-2").connection=="连接异常" and game._resident_connection_snapshot("codex").connection!="连接异常","received connection errors stay actor bound")
	check(game.world.add_companion("qa.extra","临时新居民"),"registered resident can be added without fixed roster")
	panel.refresh();check(panel.resident_ids.has("qa.extra"),"drawer refresh discovers extra resident")
	# Real time, inventory, and exact stop ownership through the moved controls.
	var before_wood:int=B.wood_total(game.world)
	var yield_wood:int=int(game.world.forest.settings.large_wood if int(game.world.objects["home.tree.01"].wood_yield)>8 else game.world.forest.settings.normal_wood)
	check(game.world.command("codex",{"intent":"chop","target_id":"home.tree.01"}).ok and B.held(game.world,"codex",yield_wood),"real engine job reaches loaded carry")
	panel.tabs.current_tab=1;panel.refresh()
	await pair("resident-task")
	panel.select_resident("companion-2");panel.stop_requested.emit(panel.selected_id)
	check(game.world.work.jobs.has("codex") and B.wood_total(game.world)==before_wood+yield_wood,"stopping different selected resident never steals another task")
	panel.select_resident("codex");panel.stop_requested.emit(panel.selected_id)
	check(not game.world.work.jobs.has("codex") and int(game.world.actors.codex.carry.get("wood",0))==yield_wood and B.wood_total(game.world)==before_wood+yield_wood,"selected resident stop preserves real carried wood")
	game._bound_companion_event({"kind":"question","id":"resident-ui-question","text":"测试问题：先停一下吗？","choices":["等等"]},"codex")
	check(not panel.visible and game.chat.visible and game.questions.has("codex") and game.action_dock.visible,"real question takes priority over drawer and restores contextual actions")
	check(game.links.values().all(func(connection):return connection._pid==-1) and game.group_links.is_empty(),"opening, source selection, confirmation and reload launch no model processes")
	game.queue_free();await process_frame
	print("Resident connections: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)
