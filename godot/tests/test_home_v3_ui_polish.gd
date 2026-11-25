extends SceneTree
class BusyAdapter:
	extends RefCounted
	var _pid:=-1
	func is_busy()->bool:return true
var checks:=0
var failed:=false
var game:Node
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:call_deferred("run")
func card_button(text:String)->Button:
	for node in game.island_hud.card_body.get_child(1).get_children():
		if node is Button and node.text==text:return node
	return null
func run()->void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):quit(1);return
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	game=load("res://scenes/main_v3.tscn").instantiate();game.world=preload("res://tests/main_island_fixture.gd").world();root.add_child(game)
	game.save_enabled=false;game.set_process(false);game.world.director.set_all_enabled(false);game.view.set_process(false);game.view.sound_enabled=false
	var hud:Control=game.island_hud;hud.set_process(false);var human:Dictionary=game.world.actors.human.duplicate(true)
	# Model-only question/proposal fixtures explicitly install the optional controller; identity remains local.
	game.world.director.set_controller("codex","model")

	check(hud.residents_title.text=="居民 · 连接","explicit fixed panel title")
	check(hud.resident_rows.size()==game.world.director.routines.size(),"all residents are dynamic rows")
	var actor:String=game.world.director.routines.keys()[0]
	var click:=InputEventMouseButton.new();click.pressed=true;click.button_index=MOUSE_BUTTON_LEFT;hud.avatar_input(actor,click)
	check(game.view.center==game.world.point(game.world.actors[actor]),"single row click locates only camera")
	click.double_click=true;hud.avatar_input(actor,click)
	check(game.chat.visible and game.chat_actor==actor,"double click opens exact bound direct chat")
	game.chat.hide();hud.resident_menus[actor].pressed.emit()
	check(hud.resident_card.visible and hud.card_id==actor and hud.card_detail.text.contains("心情"),"ellipsis opens relation/personality/mood/activity card")
	card_button("聊聊").pressed.emit();check(game.chat.visible,"card chat uses existing route");game.chat.hide()
	hud.show_card(actor);card_button("交给她").pressed.emit();check(game.assign and game.chat_actor==actor,"assignment route selects exact resident");game.assign=false
	hud.show_card(actor);card_button("叫她过来").pressed.emit();check(game.world.work.jobs.has(actor) or game.world._routes.has(actor),"explicit come-near uses existing engine order")
	card_button("停止").pressed.emit();check(not game.world.work.jobs.has(actor) and not game.world._routes.has(actor),"stop uses original owned cancellation")
	card_button("智能 / 居民连接").pressed.emit();check(game.resident_connections.visible,"intelligence opens full existing connection page");game.resident_connections.close_panel()
	hud.refresh();hud.manage_connections.pressed.emit();check(game.resident_connections.visible,"header management opens existing full page");game.resident_connections.close_panel()
	check(hud.avatar_marks["codex"].texture!=null and not hud.avatar_buttons["codex"].text.contains("Codex") and game._resident_connection_snapshot("codex").origin=="智能小白（本地预设）","idle row omits source; optional model retains local preset identity")
	game.connection_ui_states["codex:direct"]="ready";hud.refresh();check(not hud.resident_status("codex").busy and not hud.avatar_buttons["codex"].text.contains("Codex"),"ready connection does not add a source label")
	game.links["codex"]=BusyAdapter.new();check(hud.resident_status("codex").busy,"busy adapter retains honest thinking flag, zero real process");hud.refresh();check(hud.connection_lights["codex"].text=="●","busy row uses one fixed dot without source or animated syllables");game.links.erase("codex");game.connection_ui_states.erase("codex:direct")
	check(hud.avatar_marks["npc.mira"].texture!=null and not hud.avatar_buttons["npc.mira"].text.contains("Codex") and game._resident_connection_snapshot("npc.mira").origin=="智能小橙（本地预设）","idle resident uses its local preset identity without source on row")
	game.questions[actor]={};hud.refresh();check(hud.resident_badges[actor].text.contains("问"),"question badge comes from exact resident question state");game.questions.erase(actor)
	hud.resident_card.hide();hud.refresh();await process_frame
	if hud.residents_collapsed:
		check(await preload("res://tests/barbecue_ui_fixture.gd").click(self,hud.collapse_residents),"player expands compact residents before testing fold")
	check(await preload("res://tests/barbecue_ui_fixture.gd").click(self,hud.collapse_residents),"player folds the expanded resident panel")
	check(hud.residents_collapsed and not hud.manage_connections.visible and hud.avatar_buttons[actor].visible and not hud.connection_lights[actor].visible and not hud.resident_status(actor).busy,"fold retains portraits; idle resident has no false busy dot")
	var cfg:=ConfigFile.new();hud.save_preference("dismissed",["qa.notice"]);cfg.load(game.data_dir.path_join("local-life.cfg"));check(cfg.get_value(game.world.world_id+"/hud","residents_collapsed",false),"fold remembered in UI preferences, no world schema field")
	hud.toggle_residents();hud.hint_seconds=0;hud.walk_hint_seen=false;game.status.text="点地面走路，点树砍伐。";hud._process(6)
	check(not game.status.visible,"walk hint expires after real UI time advancement")
	game.status.text="真实任务受阻";hud.refresh();check(game.status.visible,"real controller receipt remains visible")
	for size in [Vector2i(1280,800),Vector2i(960,640)]:
		root.size=size;await process_frame;hud.refresh();await process_frame
		check(Rect2(Vector2.ZERO,Vector2(size)).encloses(hud.residents_panel.get_global_rect()),"resident panel fits "+str(size))
		check(not hud.residents_panel.get_global_rect().has_point(Vector2(size)/2),"panel leaves centered actor/target clear "+str(size))
	check(game.world.actors.human==human,"every UI entry leaves human unchanged")
	check(game.world.farms.crops.turnip.name=="萝卜" and hud.stock_button.tooltip_text.contains("仓库") and hud.stock_button.tooltip_text.contains("木材") and hud.stock_button.tooltip_text.contains("蘑菇"),"crop display name consistent without changing ID; warehouse icon has translated stock tooltip")
	check(hud.residents_scroll.vertical_scroll_mode==ScrollContainer.SCROLL_MODE_DISABLED,"up to five residents need no vertical scrolling")
	for i in range(3):check(game.world.add_companion("ui.qa."+str(i),"访客"+str(i),"npc"),"host provision extra QA resident")
	hud.refresh();await process_frame;await process_frame
	check(hud.resident_rows.size()==7 and hud.residents_scroll.vertical_scroll_mode==ScrollContainer.SCROLL_MODE_AUTO,"more than five residents scroll in same bounded panel")
	var proposed:Dictionary=game.world.proposals.create("codex",{"intent":"propose","text":"一起坐坐吧","activity":"sit_together","target_id":"play.gazebo.bench"})
	hud.refresh();check(proposed.ok and hud.resident_badges["codex"].text.contains("议"),"suggestion badge comes from actual validated proposal")
	check(not hud.resident_badges["codex"].text.contains("愿"),"retired daily wishes do not appear in the live island")
	check(game.world.objects.values().filter(func(o):return o.kind=="tree").size()==49,"same real tree count")
	check(game.world.objects.values().filter(func(o):return o.kind=="tree").all(func(tree):return not game.world.Layout.near_road(game.world.catalog.regions.home.layout,game.world.point(tree),.9)),"moved anchors remain outside unchanged road regrowth exclusion")
	check(game.view.ground_config.continuous_ocean,"single continuous ocean; no region-sized water rectangle")
	check(game.world.catalog.regions.home.layout.ground_art.formal_plaza.ring_style=="blocks","well uses separate darker stones")
	for link in game.links.values():check(link._pid<=0,"UI never starts a real model")
	print("Home v3 UI polish: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)
