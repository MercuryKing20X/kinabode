extends "res://tests/test_ui_scale.gd"
## Only the three requested additions to the existing 160-screen audit.
var opening_checks:Array=[]
func deep_nodes(node:Node)->Array:
	var found:Array=[]
	for child in node.get_children(true):found.append(child);found.append_array(deep_nodes(child))
	return found
func audit_nodes()->Array:return deep_nodes(game)
func verify(ok:bool,label:String)->bool:
	opening_checks.append({"passed":ok,"label":label})
	if not ok:failures.append({"kind":"native_open","label":label});push_error(label)
	return ok
func mouse(at:Vector2)->void:
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.position=at;event.global_position=at;event.button_index=MOUSE_BUTTON_LEFT;event.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0;event.pressed=down;root.push_input(event,true);await process_frame
func tick()->void:game._process(.1);game.view._process(.1)
func say(text:String)->void:
	if not game.chat.visible:verify(await UI.click(self,game.dialogue_button),"native chat entry")
	await process_frame
	await mouse(game.chat_input.get_global_rect().get_center())
	for index in text.length():
		for down in [true,false]:
			var event:=InputEventKey.new();event.unicode=text.unicode_at(index);event.pressed=down;root.push_input(event,true);await process_frame
	verify(game.chat_input.text==text,"native actual Unicode draft")
	for down in [true,false]:
		var event:=InputEventKey.new();event.keycode=KEY_ENTER;event.pressed=down;root.push_input(event,true);await process_frame
func board_button(node:Node,key:String)->BaseButton:
	if node is BaseButton and node.get_meta("chess_key","")==key:return node
	for child in node.get_children():
		var found:BaseButton=board_button(child,key)
		if found!=null:return found
	return null
func scroll_last_group_row()->void:
	var card:Node=game.local_host_commands.card;var scroll:ScrollContainer=null
	for node in UI.descendants(card):
		if node is ScrollContainer:scroll=node;break
	if not verify(scroll!=null,"group preview has a real scroll viewport"):return
	var at:Vector2=scroll.get_global_rect().get_center();var viewport:Viewport=scroll.get_viewport()
	if viewport is Window and viewport.is_embedded():at+=Vector2(viewport.position);viewport=root
	for step in range(8):
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_WHEEL_DOWN;event.pressed=true;event.position=at;event.global_position=at;event.factor=4;viewport.push_input(event,true);await process_frame
	var keys:Array=card.boxes.keys();var last:Control=card.boxes[keys.back()]
	verify(scroll.get_global_rect().grow(1).encloses(last.get_global_rect()),"native wheel reaches the fourth resident name")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("group-last-%s-%dx%d-%d.png"%[TranslationServer.get_locale(),root.size.x,root.size.y,manager.level]))
func variations(kind:String)->void:
	for dimensions in [Vector2i(960,640),Vector2i(1280,800)]:
		root.size=dimensions;DisplayServer.window_set_size(dimensions);await process_frame
		for locale in ["zh_CN","en"]:
			Text.ensure();TranslationServer.set_locale(locale);Text.events.changed.emit()
			for index in range(4):
				manager.set_level(index,false)
				if kind=="group-card":
					await say("大家去种土豆")
					if not verify(is_instance_valid(game.local_host_commands.card) and game.local_host_commands.card.visible,"native four-resident group preview"):return
					verify(game.local_host_commands.pending.rows.size()==4,"four actual residents listed")
					await scan(kind)
					await scroll_last_group_row()
					verify(await UI.click(self,game.local_host_commands.card.get_cancel_button()),"native group preview cancel")
				elif kind=="barbecue-menu":
					game.chat.hide();game.island_hud.refresh()
					var center:Vector2=game.world.point(game.world.life.station);game.view.center=center;game.view.follow_player=false
					await mouse(game.view.screen(center))
					for step in range(10000):
						if UI.shown(game,"res://scripts/fireside_panel.gd")!=null:break
						tick()
					var panel:Node=UI.shown(game,"res://scripts/fireside_panel.gd")
					if not verify(panel!=null,"native camp approach reaches actual fire panel"):return
					verify(await UI.click(self,panel.roast_button),"native barbecue entry")
					var invite:Node=UI.shown(game,"res://scripts/fireside_invitation.gd")
					if not verify(invite!=null,"native invitation exists"):return
					verify(await UI.click(self,invite.all_box),"native invite all")
					verify(await UI.click(self,invite.get_ok_button()),"native invitation next")
					var menu:Node=UI.shown(game,"res://scripts/fireside_menu.gd")
					if not verify(menu!=null,"native real barbecue menu"):return
					await scan(kind);menu.hide();menu.queue_free();await process_frame
				else:
					await scan(kind)
func run()->void:
	var temp:String=OS.get_environment("HABITAT_DATA_DIR");assert(temp.contains("youqi-"))
	output=temp.path_join("ui-scale-screenshots");DirAccess.make_dir_recursive_absolute(output)
	game=UI.init_game(self);await process_frame;await process_frame;manager=game.ui_scale
	# Genuine harvested empty plots expose potato seed deficits; never fabricate stock.
	await say("大家去收菜")
	if not verify(is_instance_valid(game.local_host_commands.card),"real group harvest plan"):await finish(temp);return
	verify(await UI.click(self,game.local_host_commands.card.get_ok_button()),"native group harvest confirmation")
	for step in range(20000):
		tick()
		if not game.world.farms.orders.is_empty() and game.world.farms.orders.values().all(func(order):return order.status=="completed"):break
	verify(game.world.farms.orders.values().all(func(order):return order.status=="completed"),"four real harvests create genuinely empty annual plots")
	await variations("group-card")
	game.chat.hide();await process_frame;game.island_hud.refresh()
	await variations("barbecue-menu")
	# Real table click, real World approach, explicit local preset game. No model calls.
	var site:Dictionary=game.world.leisure.sites["play.gomoku"];game.view.center=game.world.point(site);game.view.follow_player=false
	var rect:Rect2=game.view.leisure_renderer.rect(game.view,site)
	await mouse(rect.position+Vector2(rect.size.x*.5,rect.size.y*.25))
	for step in range(10000):
		if game.chess_choice.visible:break
		tick()
	if verify(game.chess_choice.visible,"native table opens actual chess choice"):
		tick();await process_frame;game.island_hud.refresh()
		if not verify(await UI.click(self,board_button(game.chess_choice,"jieqi.title")),"native actual chess selection"):await finish(temp);return
		if not verify(await UI.click(self,board_button(game.chess_choice,"chess.standard")),"native standard mode"):await finish(temp);return
		if not verify(await UI.click(self,game.jieqi_panel.start_button),"native local chess start"):await finish(temp);return
		for step in range(10000):
			tick()
			if game.world.jieqi.phase=="playing":break
		verify(not game.world.jieqi.game.is_empty(),"actual initialized chess board retained")
		await variations("chess-board")
	await finish(temp)
func finish(temp:String)->void:
	var file:=FileAccess.open(temp.path_join("ui-scale-additional-audit.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"records":records,"violations":failures,"native_opening":opening_checks},"  "));file=null
	print("UI scale additions: ",records.size()," screens; violations=",failures.size()," report=",temp.path_join("ui-scale-additional-audit.json"))
	game.game_audio.shutdown();game.queue_free();await process_frame;await create_timer(.1).timeout;quit(1 if not failures.is_empty() else 0)
