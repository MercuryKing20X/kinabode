extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
const Scale=preload("res://scripts/ui_scale.gd")
const Text=preload("res://scripts/localization.gd")
var game:Node
var manager:Node
var failures:Array=[]
var records:Array=[]
var output:=""
func _initialize()->void:call_deferred("run")
func audit_nodes()->Array:return UI.descendants(game)
func scan(screen:String)->void:
	for i in range(6):
		game.island_hud.refresh();await process_frame
	var bounds:=Rect2(Vector2.ZERO,Vector2(root.size));var errors:Array=[];var count:=0;var leaves:Array=[]
	for window in audit_nodes():
		if window is Window and window.visible and not window is PopupMenu and not bounds.grow(2).encloses(Rect2(Vector2(window.position),Vector2(window.size))):errors.append({"kind":"window_outside","path":str(window.get_path()),"rect":str(Rect2(Vector2(window.position),Vector2(window.size)))})
	for node in audit_nodes():
		if not node is Control or not node.is_visible_in_tree() or node.size.x<1 or node.size.y<1:continue
		if node is Label and node.text.is_empty():continue
		if not (node is BaseButton or node is Label or node is LineEdit or node is TextEdit or node is RichTextLabel):continue
		var rect:Rect2=node.get_global_rect();var clipped:=false;var ancestor:Node=node.get_parent()
		while ancestor!=null and not ancestor is Window:
			if ancestor is Control and (ancestor.clip_contents or ancestor is ScrollContainer) and not ancestor.get_global_rect().encloses(rect):clipped=true
			ancestor=ancestor.get_parent()
		if clipped:continue # Off-scroll/partially-scrolled entries are deliberately clipped, not displayed controls.
		var viewport:Viewport=node.get_viewport();var area:=Rect2(Vector2.ZERO,Vector2(viewport.size)) if viewport is Window else bounds
		count+=1;leaves.append(node)
		if not area.grow(2).encloses(rect):errors.append({"kind":"outside","path":str(node.get_path()),"rect":str(rect),"bounds":str(area)})
		if node is Button and not node is OptionButton and not node.text.is_empty() and node.clip_text:
			var width:float=node.get_theme_font("font").get_string_size(node.text,HORIZONTAL_ALIGNMENT_LEFT,-1,node.get_theme_font_size("font_size")).x
			if width>node.size.x-8:errors.append({"kind":"clipped_text","path":str(node.get_path()),"text":node.text})
	for i in range(leaves.size()):
		for j in range(i+1,leaves.size()):
			var a:Control=leaves[i];var b:Control=leaves[j]
			if a.get_viewport()!=b.get_viewport() or a.is_ancestor_of(b) or b.is_ancestor_of(a):continue
			var intersection:Rect2=a.get_global_rect().intersection(b.get_global_rect())
			if intersection.size.x>8 and intersection.size.y>8:errors.append({"kind":"overlap","a":str(a.get_path()),"b":str(b.get_path()),"intersection":str(intersection)})
	var row:Dictionary={"screen":screen,"locale":TranslationServer.get_locale(),"size":[root.size.x,root.size.y],"level":manager.level,"factor":Scale.factor(),"visible_controls":count,"violations":errors}
	records.append(row);failures.append_array(errors)
	if not output.is_empty() and DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("%s-%s-%dx%d-%d.png"%[screen,TranslationServer.get_locale(),root.size.x,root.size.y,manager.level]))
func tap(button:BaseButton)->void:
	await UI.reveal(self,button)
	var at:Vector2=button.get_global_rect().get_center()
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0;event.position=at;event.global_position=at;root.push_input(event,true);await process_frame
func run()->void:
	var temp:String=OS.get_environment("HABITAT_DATA_DIR");assert(temp.contains("youqi-"))
	output=temp.path_join("ui-scale-screenshots");DirAccess.make_dir_recursive_absolute(output)
	game=UI.init_game(self);await process_frame;await process_frame
	manager=game.get("ui_scale")
	if manager==null:manager=Scale.new();game.add_child(manager);manager.setup(game,game.island_hud.ui_root,temp)
	var zoom:float=game.view.zoom
	for dimensions in [Vector2i(960,640),Vector2i(1280,800)]:
		root.size=dimensions;DisplayServer.window_set_size(dimensions);await process_frame
		for locale in ["zh_CN","en"]:
			Text.ensure();TranslationServer.set_locale(locale);Text.events.changed.emit()
			for index in range(4):
				manager.set_level(index,false);await scan("hud")
				game._open_audio_settings();await scan("settings");game.audio_dialog.hide()
				game.storage_panel.open();await scan("storage");game.storage_panel.hide()
				game.chat.show();await scan("chat");game.chat.hide()
				game.farm_panel.open_farm("farm.home");await scan("farm");game.farm_panel.hide()
				var book:=preload("res://scripts/recipe_book.gd").new();game.add_child(book);book.setup(game.world,game.view.font);await scan("cookbook");book.hide();book.queue_free()
				game.memory_panel.open();await scan("memories");game.memory_panel.hide()
				game.island_hud.refresh();await process_frame
				await tap(game.handbook_menu)
				if not game.handbook_menu.get_popup().visible:failures.append({"kind":"menu_not_open"})
				await scan("handbook-menu");game.handbook_menu.get_popup().hide()
				game.chess_choice.open("play.gomoku");await scan("chess-choice");game.chess_choice.hide()
				game.island_hud.show_card("codex");await scan("resident");game.island_hud.resident_card.hide()
				assert(game.view.zoom==zoom,"UI scaling must not alter camera")
	var file:=FileAccess.open(temp.path_join("ui-scale-audit.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"records":records,"violations":failures},"  "));file=null
	print("UI scale: ",records.size()," screens; violations=",failures.size()," report=",temp.path_join("ui-scale-audit.json"))
	game.game_audio.shutdown();game.queue_free();await process_frame;await create_timer(.1).timeout
	quit(1 if not failures.is_empty() else 0)
