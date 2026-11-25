extends SceneTree
const World=preload("res://scripts/world_state.gd")
var checks:=0
var failed:=false
func check(ok:bool,msg:String)->void:
	checks+=1
	if not ok:failed=true;push_error(msg)
func _initialize()->void:call_deferred("run")
func run()->void:
	var dir:=OS.get_environment("HABITAT_DATA_DIR");assert(dir.contains("youqi-test-"))
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	var game:Node=load("res://scenes/main_v3.tscn").instantiate();game.world=World.new("res://content/home-v3/world.json");root.add_child(game)
	game.save_enabled=false;game.view.sound_enabled=false;game.set_process(false);game.chat.hide();await process_frame;await process_frame
	var hud:Control=game.island_hud;var smart:RefCounted=game.world.intelligence
	hud.refresh();await process_frame
	if hud.residents_collapsed:
		check(await preload("res://tests/barbecue_ui_fixture.gd").click(self,hud.collapse_residents),"player expands the compact resident panel")
	check(smart.rename_preset("resident-blue","智能小蓝测试"),"host renames intelligence preset")
	var fresh:RefCounted=preload("res://scripts/intelligence_system.gd").new(game.world);fresh.setup(dir.path_join("intelligence-preferences.cfg"))
	check(fresh.summary("companion-2").name=="智能小蓝测试","name preference survives reload")
	game.world.hunger.states["companion-2"].elapsed=float(game.world.hunger.config.thresholds[2])+20
	hud.show_card("companion-2");check(hud.card_detail.text.contains("智能小蓝测试") and hud.card_detail.text.contains("当前状态 · 饿了"),"card uses true preset and appetite state")
	hud.refresh();check(hud.avatar_buttons["companion-2"].text.contains("饿了"),"actual resident row shows hunger word")
	check(hud.avatar_marks["companion-2"].texture!=null and not hud.resident_status("companion-2").busy and not hud.avatar_buttons["companion-2"].text.contains("Codex") and game._resident_connection_snapshot("companion-2").origin=="智能小蓝测试（本地预设）","idle row has a mood icon, omits source and uses the actual local preset")
	game.world.director.set_controller("companion-2","local");hud.refresh_card()
	check(hud.card_detail.text.begins_with("智能小蓝测试（本地预设）"),"card starts with actual intelligence preset title")
	hud.set_hunger_hints(false);check(not hud.card_detail.text.contains("当前状态"),"display toggle only hides status line")
	hud.refresh();check(not hud.avatar_buttons["companion-2"].text.contains("饿了"),"same preference hides hunger on actual resident row")
	check(game.world.hunger.rank("companion-2")==2,"display toggle does not change state")
	var prefs:=ConfigFile.new();prefs.load(dir.path_join("local-life.cfg"));check(prefs.get_value("interface","show_hunger",true)==false,"toggle saved outside world")
	hud.set_hunger_hints(true)
	hud.assign_intelligence("companion-2");await process_frame
	var dialogs:Array=hud.ui_root.get_children().filter(func(n):return n is ConfirmationDialog and n.title=="分配智能预设")
	check(dialogs.size()==1 and dialogs[0].get_child_count()>0,"preset assignment has a reachable host dialog")
	for dialog in dialogs:dialog.hide();dialog.queue_free()
	await process_frame
	hud.rename_intelligence("companion-2");await process_frame
	dialogs=hud.ui_root.get_children().filter(func(n):return n is ConfirmationDialog and n.title=="智能预设显示名")
	check(dialogs.size()==1,"preset rename has a reachable host dialog")
	for dialog in dialogs:dialog.hide();dialog.queue_free()
	await process_frame
	for size in [Vector2i(1280,800),Vector2i(960,640)]:
		root.size=size;root.content_scale_size=Vector2i.ZERO
		for mode in ["小","标准","大"]:
			hud.set_interface_size(mode);hud.show_card("companion-2");await process_frame;await process_frame
			check(Rect2(Vector2.ZERO,Vector2(size)).encloses(hud.resident_card.get_global_rect()),"card fits "+str(size)+mode)
	game.queue_free();await process_frame;await create_timer(.3).timeout
	print("Intelligence UI: ",checks," checks, failed=",failed);quit(1 if failed else 0)
