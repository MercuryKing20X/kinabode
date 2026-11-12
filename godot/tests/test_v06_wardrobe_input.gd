extends "res://tests/test_intent_input.gd"
const Catalog=preload("res://scripts/workshop_catalog.gd")
const Text=preload("res://scripts/localization.gd")
func run()->void:
	root.size=Vector2i(960,640)
	OS.set_environment("HABITAT_OPENING","standard")
	game=load("res://scenes/main_v3.tscn").instantiate()
	game.dialogue_adapter_factory=func(_id,_scope):return IntentFake.new()
	root.add_child(game)
	game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.island_hud.set_process(false);game.chat.hide()
	await process_frame;await process_frame
	var before:Dictionary=game.world.storage.saved().duplicate(true)
	var actors:Dictionary=game.world.actors.duplicate(true)
	for locale in ["zh_CN","en"]:
		TranslationServer.set_locale(locale);Text.events.changed.emit()
		check(await UI.click(self,game.island_hud.settings_menu),"native settings opens "+locale)
		var popup:PopupMenu=game.island_hud.settings_menu.get_popup()
		for index in popup.item_count:
			check(popup.get_item_id(index)!=100 and popup.get_item_text(index)!=Text.text("buildall.action"),"no completion menu entry")
		popup.hide()
		check(await UI.click(self,game.island_hud.appearance_buttons.codex),"native wardrobe opens "+locale)
		var panel:Control=game.island_hud.wardrobe
		for level in range(4):
			game.ui_scale.set_level(level,false)
			await process_frame;await process_frame
			var count:=0
			for item in panel.grid.get_children():
				for b in item.get_children():
					if b.has_meta("work_id") and str(b.get_meta("work_id")).begins_with("ai-"):
						var label:String=b.text.to_lower()
						for forbidden in ["gpt","claude","gemini","grok","deepseek","glm","qwen","kimi"]:check(not forbidden in label,"original appearance display name")
					if not b.has_meta("fan_notice"):continue
					count+=1
					check(await UI.click(self,b),"native fan notice "+str(b.get_meta("fan_notice")))
					var notice:AcceptDialog=null
					for node in panel.get_children():
						if node is AcceptDialog and node.visible:notice=node
					check(notice!=null,"notice opens")
					if notice==null:continue
					check(notice.dialog_text==Text.text("wardrobe.fan_notice"),"localized complete disclaimer")
					check(notice.size.x<=root.size.x and notice.size.y<=root.size.y,"notice fits viewport")
					if count==1 and level==2 and DisplayServer.get_name()!="headless":
						RenderingServer.force_draw(false)
						var evidence:String=OS.get_environment("HABITAT_V06_EVIDENCE")
						if not evidence.is_empty():root.get_texture().get_image().save_png(evidence.path_join("wardrobe-notice-"+locale+".png"))
					check(await UI.click(self,notice.get_ok_button()),"native notice closes")
					await process_frame
			check(count==8,"eight appearance info buttons")
		panel.hide()
	check(game.world.storage.saved()==before and game.world.actors==actors,"viewing names and notices never mutates residents or materials")
	game.game_audio.shutdown();game.queue_free();await process_frame
	print("V06_WARDROBE_INPUT ",checks," failed=",failed);quit(1 if failed else 0)
