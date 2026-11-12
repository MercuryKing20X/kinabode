extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
const F=preload("res://tests/cooking_fixture.gd")
var game: Node
var checks:=0
var failed:=false
var output: String
func _initialize() -> void:call_deferred("run")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failed=true;push_error(message)
func capture(prefix: String) -> void:
	for size in [Vector2i(1280,800),Vector2i(960,640)]:
		root.size=size;await process_frame;await process_frame
		if not output.is_empty():
			await RenderingServer.frame_post_draw
			var image:=root.get_texture().get_image();check(image.get_size()==size,"actual navigation viewport "+str(size));image.save_png(output.path_join(prefix+"-%dx%d.png"%[size.x,size.y]))
func route(id: String) -> void:
	var popup: PopupMenu=game.handbook_menu.get_popup()
	for index in range(popup.item_count):
		if popup.get_item_metadata(index)==id:popup.id_pressed.emit(popup.get_item_id(index));return
	check(false,"missing route "+id)
func close_panels() -> void:
	for panel in game.get_children():
		if panel.get_script() in [preload("res://scripts/fireside_panel.gd"),preload("res://scripts/fireside_invitation.gd"),preload("res://scripts/fireside_menu.gd")]:panel.hide();panel.queue_free()
	game.atlas.hide();game.editor.hide();game.memory_panel.hide();game.resident_connections.close_panel();game.farm_panel.hide();game.leisure_panel.hide();game.homestead_panel.hide();game.fishing_panel.hide();game.gomoku_panel.card.hide();game.participant_picker.hide();game.chat.hide();game.action_dock.menu.hide()
func run() -> void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):quit(1);return
	output=OS.get_environment("HABITAT_POLISH_CAPTURE_DIR")
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false);root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
	await process_frame
	game.world.director.set_all_enabled(false);game.view.sound_enabled=false;game.chat.hide();game.chat_input.release_focus()
	if OS.get_environment("HABITAT_POLISH_BEFORE")=="1":
		await capture("before");game.queue_free();await process_frame;print("Navigation before captures: "+str(checks));quit(1 if failed else 0);return
	var top: Container=game.handbook_menu.get_parent();var all_buttons: Array=top.get_children().filter(func(child):return child is BaseButton)
	check(all_buttons.size()<=8 and all_buttons.filter(func(child):return child.visible).size()==7,"top bar seven outdoor entries including storage and at most eight including indoor furniture")
	check(all_buttons.all(func(button):return button.text not in ["地图","回忆","像素工坊","居民连接","主动记录"]),"low-frequency entries no longer occupy independent top buttons")
	var human: Dictionary=game.world.actors.human.duplicate(true)
	await capture("after")
	for entry in ["map","workshop","memories","residents","autonomy_records"]:
		close_panels();route(entry);await process_frame;await process_frame
		match entry:
			"map":check(game.atlas.visible,"map reachable from handbook")
			"workshop":check(game.editor.visible,"workshop reachable with original drafts")
			"memories":check(game.memory_panel.visible,"memories reachable with original filters")
			"residents":check(game.resident_connections.visible,"resident connections reachable")
			"autonomy_records":check(game.resident_connections.visible and game.resident_connections.tabs.current_tab==2 and game.resident_connections.records_host.visible,"proactive records direct entry reaches existing record drawer")
	check(game.world.actors.human==human and game.world.work.jobs.is_empty(),"all handbook navigation is observational, never controls human or starts work")
	close_panels();game.handbook_menu.show_popup();await capture("handbook");game.handbook_menu.get_popup().hide()
	var home: MenuButton=all_buttons.filter(func(button):return button.text=="家园")[0]
	for index in range(3):
		close_panels();home.get_popup().id_pressed.emit(index)
		check([game.farm_panel.visible,game.leisure_panel.visible,game.homestead_panel.visible][index],"original home entry remains reachable "+str(index))
	var activities: MenuButton=all_buttons.filter(func(button):return button.text=="活动")[0]
	for index in range(3):
		close_panels();activities.get_popup().id_pressed.emit(index)
		if index==0:
			await process_frame
			check(game.chess_choice.visible,"chess entry presents explicit game choice")
			var gomoku_choice:BaseButton
			for choice in game.chess_choice.column.get_children():
				if choice is BaseButton and choice.get_meta("chess_key","")=="ui.main.gomoku":gomoku_choice=choice
			check(await UI.click(self,gomoku_choice),"explicit Gomoku choice mouse")
		check([game.gomoku_panel.card.visible,game.fishing_panel.visible,UI.shown(game,"res://scripts/fireside_panel.gd")!=null][index],"remaining activity entry remains reachable "+str(index))
	close_panels();game.dialogue_button.pressed.emit();check(game.chat.visible,"bottom dialogue remains reachable")
	game.actions_button.pressed.emit();check(game.action_dock.menu.visible,"bottom actions remain reachable")
	var settings: MenuButton=all_buttons.filter(func(button):return button.text=="设置")[0]
	check(settings.get_popup().item_count==3 and settings.get_popup().get_item_id(0)==101 and settings.get_popup().get_item_id(1)==0 and settings.get_popup().get_item_id(2)==1 and not settings.flat,"settings entries and opaque menu retained")
	check(not game.gift_panel.visible and not game.proposal_panel.visible,"gift and proposal UI occupy no space when inactive")
	close_panels();check(F.harvest(game.world,"turnip") and F.withdraw(game.world,"human","turnip"),"gift layout uses actual human carried produce")
	game.resident_connections.gift_requested.emit("codex");await process_frame;await process_frame
	check(game.gift_panel.visible and not game.resident_connections.visible,"explicit gift opens only contextual edge composer")
	for size in [Vector2i(1280,800),Vector2i(960,640)]:
		root.size=size;await process_frame;await process_frame
		var rect: Rect2=game.gift_panel.get_global_rect()
		check(root.get_visible_rect().encloses(rect) and rect.position.x>size.x*.5,"gift panel fits screen edge "+str(size))
	await capture("gift-edge");game.gift_panel.hide()
	var proposed: Dictionary=game.world.command("codex",{"intent":"propose","text":"一起看看鱼儿吧","activity":"watch_fishery","target_id":"home.fishery.east"})
	game.proposal_panel.refresh();check(proposed.ok and game.proposal_panel.visible,"only actual proposal creates edge card")
	await capture("proposal-edge")
	var cards: Array=game.world.proposals.snapshot()
	if not cards.is_empty():game.proposal_panel.responded.emit(cards[0].id,false)
	game.proposal_panel.refresh();check(not game.proposal_panel.visible,"resolved proposal returns its screen space")
	check(game.links.values().all(func(link):return link._pid==-1),"UI reorganization never starts models")
	game.queue_free();await process_frame
	print("Polish navigation: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)
