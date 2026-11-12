extends "res://tests/probe_empowered_live.gd"
func run()->void:
	await fresh()
	game.world.director.set_controller("codex","model")
	var panel:Node=game.resident_connections
	panel.open("codex");await ready_frames()
	await UI.reveal(self,panel.tabs);await mouse_at(panel.tabs.global_position+panel.tabs.get_tab_rect(2).get_center());await ready_frames()
	await UI.click(self,panel.level_picker);await key_press(KEY_HOME)
	for step in range(5):await key_press(KEY_DOWN)
	await key_press(KEY_ENTER);await ready_frames()
	check(panel.life_dialog.visible,"warning visible via viewport input")
	check(panel.life_dialog.get_ok_button().disabled,"unchecked confirmation disabled")
	check(panel.life_warning.text.contains("token"),"warning includes token estimate")
	await picture("lifeblood-warning-final")
	await UI.click(self,panel.life_ack);await UI.click(self,panel.life_dialog.get_ok_button());await ready_frames()
	check(panel.preferences.preference("codex").level=="lifeblood","checked confirmation applies")
	await picture("lifeblood-enabled-final")
	await UI.click(self,panel.downgrade);check(panel.preferences.preference("codex").level=="ultra","downgrade via viewport input")
	for language in ["en","zh"]:
		game.LocalText.select(game.data_dir,language);await ready_frames()
		check(panel.level_picker.get_item_text(4)==panel.T("life.level"),"fifth level translates without indexing a four-item array")
	panel.close_panel();game.world.director.set_controller("codex","local")
	var count:int=game.world.director.events.size()
	for tick in range(1800):game.world.advance(1);game.memory_life.speak("codex")
	check(not game.world.director.events.slice(count).any(func(e):return e.get("context","")=="memory_reminder"),"30 game minutes local produces zero memory speech")
	var menu:PopupMenu=game.handbook_menu.get_popup();var entries:=0
	for i in range(menu.item_count):
		if str(menu.get_item_metadata(i)) in ["memories","memory_books"]:entries+=1
	check(entries==1,"one handbook memory entry")
	print("LIFEBLOOD_INPUT ",checks," ",failed)
	game.queue_free();await ready_frames();quit(1 if failed else 0)
