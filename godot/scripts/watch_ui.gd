extends Node
const Text=preload("res://scripts/localization.gd")
var game:Node
var recent:RichTextLabel
var age:=0.0
var signature:=""
var toggle:Button
var bar:HBoxContainer
var menu_column:VBoxContainer
var menu_scroll:ScrollContainer
func setup(source:Node)->void:
	game=source
	if game.island_hud==null:return
	bar=game.island_hud.primary_actions
	game.gathering_button.reparent(bar,false);game.gathering_button.show();game.gathering_button.focus_mode=Control.FOCUS_NONE
	game.dialogue_button.reparent(bar,false);bar.move_child(game.dialogue_button,0)
	game.dialogue_button.custom_minimum_size=Vector2(120,40);game.dialogue_button.set_meta("ui_scale_min",Vector2(120,40));game.dialogue_button.set_meta("main_locale_text","watch.dialogue_commands")
	game.actions_button.hide();game.actions_button.reparent(game.island_hud,false)
	game.journey.map_button.reparent(bar,false);bar.move_child(game.journey.map_button,1)
	toggle=Button.new();bar.add_child(toggle);bar.move_child(game.gathering_button,bar.get_child_count()-1);toggle.focus_mode=Control.FOCUS_NONE;bar.alignment=BoxContainer.ALIGNMENT_CENTER;toggle.custom_minimum_size=Vector2(78,40);toggle.set_meta("ui_scale_min",Vector2(78,40));toggle.pressed.connect(game.steward.choose)
	game.journey.map_button.pressed.connect(func():game.chat.hide();game.chat_input.release_focus())
	recent=RichTextLabel.new();game.island_hud.add_child(recent);recent.mouse_filter=Control.MOUSE_FILTER_IGNORE;recent.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT);recent.offset_left=-470;recent.offset_right=-20;recent.offset_top=-145;recent.offset_bottom=-65
	rebuild_menu()
	# The tall handbook popup opens above this bottom panel. Open on release so
	# the same click cannot immediately select an overlapping popup item.
	game.handbook_menu.action_mode=BaseButton.ACTION_MODE_BUTTON_RELEASE
	game.handbook_menu.get_popup().id_pressed.connect(func(_id):game.action_dock.menu.hide())
	var tools:=HBoxContainer.new();menu_column.add_child(tools)
	for item in game.island_hud.utility_actions.get_children():item.reparent(tools,false)
	game.island_hud.utility_actions.hide()
	var settings:MenuButton=game.island_hud.settings_menu
	settings.reparent(game.island_hud,false);settings.show();settings.flat=false
	settings.focus_mode=Control.FOCUS_NONE;settings.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	settings.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	settings.offset_left=-100;settings.offset_right=-16;settings.offset_top=-54;settings.offset_bottom=-14
	menu_scroll=ScrollContainer.new();menu_scroll.name="CommandSections";menu_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	menu_scroll.custom_minimum_size=Vector2(0,180);menu_scroll.set_meta("ui_scale_min",Vector2(0,180))
	var chat_column:Node=game.chat.get_child(0);chat_column.add_child(menu_scroll);chat_column.move_child(menu_scroll,0)
	menu_column.reparent(menu_scroll,false);menu_column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var previous_menu:PanelContainer=game.action_dock.menu
	for control in menu_column.find_children("*","BaseButton",true,false):
		for connection in control.get_signal_connection_list("pressed"):
			var callback:Callable=connection.callable
			if callback.get_object()==previous_menu and callback.get_method()=="hide":
				control.pressed.disconnect(callback);control.pressed.connect(game.chat.hide)
	previous_menu.queue_free();game.action_dock.menu=game.chat
	# Compatibility references resolve to the single visible dialogue entry.
	game.actions_button=game.dialogue_button
	game.chat.visibility_changed.connect(func():
		if game.chat.visible:game.chat.move_to_front())
	game.chat.hide();refresh_locale()
	Text.events.changed.connect(refresh_locale)
func refresh_locale()->void:
	if game==null:return
	if menu_column!=null:game.action_dock._refresh_static(menu_column)
	for index in range(4):game.action_dock.action_tabs.set_tab_title(index,Text.text(["watch.common","watch.everyone","watch.myself","watch.ask"][index]))
	game.dialogue_button.text=Text.text("watch.dialogue_commands")
	game.command_page.rebuild_targets();game.command_page.rebuild()
func rebuild_menu()->void:
	if game.command_page.selected.is_empty():game.command_page.selected=game.command_page.actors()
	game.command_page.rebuild_targets()
	var menu:Control=game.action_dock.menu
	menu.set_meta("watch_menu",true)
	var old:TabContainer=game.action_dock.action_tabs
	var column:Node=old.get_parent();menu_column=column
	if column.get_parent()!=menu:
		var wrapper:Node=column.get_parent();column.reparent(menu,false);wrapper.queue_free()
	game.command_page.targets.reparent(column,false);column.move_child(game.command_page.targets,0)
	for control in game.command_page.targets.get_children():
		if control is Button:control.expand_icon=true;control.add_theme_constant_override("icon_max_width",22)
	game.command_page.sending.reparent(column,false);column.move_child(game.command_page.sending,1)
	var tabs:=TabContainer.new();game.action_dock.action_tabs=tabs;tabs.set_meta("watch_tabs",true);column.add_child(tabs);column.move_child(tabs,2)
	var common:=VBoxContainer.new();common.name=Text.text("watch.common");tabs.add_child(common)
	game.command_page.body.reparent(common,false);game.command_page.body.show();game.command_page.body.get_child(0).hide();game.command_page.category=0;game.command_page.rebuild()
	var everyone:=VBoxContainer.new();everyone.name=Text.text("watch.everyone");tabs.add_child(everyone)
	bar.move_child(game.gathering_button,bar.get_child_count()-1);game.gathering_button.text=Text.text("watch.follow_options");game.gathering_button.set_meta("main_locale_text","watch.follow_options")
	for row in [["watch.chop","content.steward.command.chop"],["watch.harvest","content.steward.command.harvest"],["watch.gather","content.steward.command.assemble"],["watch.follow","content.steward.command.follow"],["watch.unfollow","content.steward.command.unfollow"]]:
		var entry:Array=row
		game.action_dock.button(everyone,Text.text(entry[0]),func():game.chat.hide();game._send(preset_command(entry[1]))).set_meta("locale_key",entry[0])
	game.action_dock.button(everyone,Text.text("play.choose"),choose_game).set_meta("locale_key","play.choose")
	var own:=VBoxContainer.new();own.name=Text.text("watch.myself");tabs.add_child(own)
	for page in old.get_children():
		for control in page.get_children():control.reparent(everyone if control is Button and control.text==Text.text("storage.ask_wood") else own,false)
	old.hide()
	var ask:=VBoxContainer.new();ask.name=Text.text("watch.ask");tabs.add_child(ask)
	for row in [["watch.doing","content.steward.command.doing"],["watch.hungry","content.steward.command.hungry"],["watch.stock","content.steward.command.stock"]]:
		var entry:Array=row
		game.action_dock.button(ask,Text.text(entry[0]),func():game.chat.hide();game._send(preset_command(entry[1]))).set_meta("locale_key",entry[0])
	for page in tabs.get_children():
		var index:int=page.get_index();var caption:String=page.name
		var scroll:=ScrollContainer.new();tabs.add_child(scroll);tabs.move_child(scroll,index);page.reparent(scroll,false);page.show();scroll.name=caption;page.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.custom_minimum_size.y=200;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	tabs.custom_minimum_size.y=230
	menu.offset_left=-minf(360,game.get_viewport_rect().size.x/2-18);menu.offset_right=-menu.offset_left;menu.offset_top=-430
var meal_countdown:Label
func _process(delta:float)->void:
	if game==null or game.island_hud==null:return
	if meal_countdown==null:
		meal_countdown=Label.new();meal_countdown.name="MealCountdown";meal_countdown.mouse_filter=Control.MOUSE_FILTER_IGNORE;game.island_hud.add_child(meal_countdown)
	var lines:Array[String]=[]
	for life in game.world.barbecues.values():
		var fire:RefCounted=life.fireside
		if not fire.active() or fire.circle_closed and not fire.state.suspended:continue
		var meal:Dictionary=fire.state.current
		if float(meal.get("meal_remaining",0))<=0:continue
		var seconds:int=ceili(float(meal.meal_remaining))
		lines.append(LocalTextName(meal)+" · %02d:%02d"%[seconds/60,seconds%60]+(" · "+Text.text("meal.timer.paused") if fire.state.suspended else ""))
	if game.playground!=null and not game.playground.kind.is_empty():
		var seconds:int=maxi(0,ceili(120-game.playground.duration))
		lines.append(Text.text("play."+game.playground.kind)+" %02d:%02d"%[seconds/60,seconds%60])
	meal_countdown.text=" / ".join(lines);meal_countdown.visible=not lines.is_empty()
	meal_countdown.position=Vector2(bar.global_position.x,bar.global_position.y-30)
	if game.chat.visible:
		var viewport_size:Vector2=game.get_viewport_rect().size
		var extent:=Vector2(minf(720,viewport_size.x-24),minf(580,bar.global_position.y-24))
		game.chat.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		game.chat.size=extent;game.chat.position=Vector2((viewport_size.x-extent.x)/2,maxf(12,bar.global_position.y-extent.y-12))
	game.island_hud.return_button.hide();game.island_hud.utility_actions.hide()
	var ids:Array=game.steward.candidates()
	toggle.text=Text.text("repair.running")%Text.resident(game.world,game.steward.manager) if game.steward.active else Text.text("watch.manage");toggle.disabled=false;toggle.tooltip_text=""
	var rows:Array=game.dialogue.histories.get(game._chat_channel(),[]).slice(-3)
	var current:String=JSON.stringify(rows)
	if current!=signature:
		signature=current;age=0;recent.clear()
		for row in rows:recent.add_text((Text.resident(game.world,row.sender_id)+": " if game.world.actors.has(row.sender_id) else "")+str(row.text).replace("\n"," ").left(60)+"\n")
	else:age+=delta
	recent.modulate.a=clampf((6-age)/2,0,.8);recent.visible=not game.chat.visible

func preset_command(key:String)->String:
	var chinese:String=Text.source(key).trim_prefix(Text.source("content.steward.everyone_prefix"))
	var english:String=str(Text.entries.get(key,{}).get("en",key)).trim_prefix("Everyone ")
	return game.command_page.preset_text({"zh":chinese,"en":english})

func choose_game()->void:
	var card:=AcceptDialog.new();card.title=Text.text("play.choose");card.set_meta("play_selector",true);game.add_child(card)
	var column:=VBoxContainer.new();card.add_child(column)
	var join:=CheckButton.new();join.focus_mode=Control.FOCUS_NONE;join.text=Text.text("play.join");join.set_meta("play_join",true);column.add_child(join)
	var watch:=Label.new();watch.text=Text.text("play.watch");column.add_child(watch)
	for kind in ["eagle","handkerchief","hide","fireflies","circle","shuttlecock","rope"]:
		var key:String=kind
		var button:=Button.new();button.focus_mode=Control.FOCUS_NONE;button.text=Text.text("play."+key);button.set_meta("play_kind",key);column.add_child(button)
		button.pressed.connect(func():
			var result:Dictionary=game.playground.start(key,join.button_pressed)
			if not result.get("ok",false):game.status.text=Text.text("play.unavailable")
			card.queue_free())
	card.confirmed.connect(card.queue_free);card.close_requested.connect(card.queue_free);card.popup_centered(Vector2i(320,300))

func LocalTextName(meal:Dictionary)->String:return Text.content(str(meal.get("name","")))
