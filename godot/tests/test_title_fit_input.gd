extends "res://tests/test_simple_connection_input.gd"
func run()->void:
	var fixture:=FileAccess.open(OS.get_environment("HABITAT_DATA_DIR").path_join("island-v2.json"),FileAccess.WRITE);fixture.store_string("{}");fixture.close()
	# Install a fake factory before the title constructs its connection overview.
	var pool:Node=preload("res://scripts/connection_session_pool.gd").obtain(self,OS.get_environment("HABITAT_DATA_DIR"))
	pool.factory=func(_id):return Stub.new()
	var title:Node=load("res://scenes/title.tscn").instantiate();root.add_child(title);current_scene=title
	await frames()
	check(title.version_label.text=="v0.8.0" and preload("res://scripts/game_version.gd").VERSION=="0.8.0","single release version")
	for dimensions in [Vector2i(960,640),Vector2i(1366,768),Vector2i(1920,1080),Vector2i(2560,1440),Vector2i(3840,2160),Vector2i(2560,1080),Vector2i(1440,900)]:
		if OS.get_environment("HABITAT_UI_LARGE_ONLY")=="1" and dimensions not in [Vector2i(2560,1440),Vector2i(3840,2160)]:continue
		root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT;root.content_scale_size=dimensions;root.size=dimensions
		for level in (range(4) if dimensions.x==960 else [2]):
			title.ui_scale.set_level(level,false);await frames()
			title._layout();await frames()
			if DisplayServer.get_name()!="headless":check(root.get_texture().get_image().get_size()==dimensions,"actual rendered pixels equal requested resolution")
			var quit_button:Button=title.menu.get_node("quit")
			check(Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(quit_button.get_global_rect()),"quit visible %s scale %s"%[dimensions,level])
			await shot("title-%sx%s-%s"%[dimensions.x,dimensions.y,level])
			for locale in ["zh","en"]:
				check(await UI.click(self,title.languages.get_node(locale)),"language click "+locale)
				await frames()
				check(title.heading.text==("Kinabode" if locale=="en" else "有栖 · 世界"),"localized title")
				check(await UI.click(self,title.menu.get_node("about")),"about opens by real input")
				await frames();var panel:Node=title.about_panel
				check(panel.visible,"about visible")
				var text:String=panel.body.get_parsed_text()
				check(not text.is_empty(),"single document rendered")
				check("AI" in text and ("MercuryFantasy" in text),"whole repository document loaded")
				check("**" not in text,"markdown bold rendered")
				check(panel.document_path(locale=="en").ends_with("about.en.md" if locale=="en" else "about.md"),"single document path")
				check(Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(panel.panel.get_global_rect()),"about panel fits %s scale %s"%[dimensions,level])
				check(panel.panel.get_global_rect().encloses(panel.close_button.get_global_rect()),"close button fits")
				await shot("about-%s-%sx%s-%s-top"%[locale,dimensions.x,dimensions.y,level])
				var scroll:VScrollBar=panel.body.get_v_scroll_bar()
				scroll.value=scroll.max_value;await frames()
				check(scroll.value>=scroll.max_value-scroll.page-1,"about scroll reaches bottom")
				await shot("about-%s-%sx%s-%s-bottom"%[locale,dimensions.x,dimensions.y,level])
				check(await UI.click(self,panel.close_button),"close real input");check(not panel.visible,"about closed")
	check(pool.links.values().all(func(link):return link is Stub),"connections remain fake")
	title.queue_free();await frames();print("TITLE_FIT ",checks," failed=",failed);quit(1 if failed else 0)
