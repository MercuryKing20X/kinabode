extends Control
const LocalText=preload("res://scripts/localization.gd")
var _locale_static:Dictionary={}
func T(key:String)->String:
	var value:String=LocalText.text(key);_locale_static[value]=key;return value
func _refresh_static(node:Node)->void:
	if node is Label or (node is Button and not node is OptionButton):
		if node.get_meta("hud_owned",false) and not node.has_meta("locale_key") and _locale_static.has(node.text):node.set_meta("locale_key",_locale_static[node.text])
		if node.has_meta("locale_key"):node.text=T(str(node.get_meta("locale_key")))
	if node is Control:
		if not node.has_meta("locale_tooltip") and _locale_static.has(node.tooltip_text):node.set_meta("locale_tooltip",_locale_static[node.tooltip_text])
		if node.has_meta("locale_tooltip"):node.tooltip_text=T(str(node.get_meta("locale_tooltip")))
	for child in node.get_children():_refresh_static(child)
## Host presentation shell. Every action delegates to existing validated controllers.
var game:Node
var ui_root:Control
var config:Dictionary
var avatars:BoxContainer
var avatar_buttons:Dictionary={}
var avatar_marks:Dictionary={}
var connection_lights:Dictionary={}
var reasoning_points:Control
var resident_card:PanelContainer
var card_body:VBoxContainer
var card_id:=""
var card_detail:Label
var card_title:Label
var card_close:Button
var card_scroll:ScrollContainer
var stock_button:Button
var stock_detail:PanelContainer
var stock_text:Label
var task:PanelContainer
var task_text:Label
var return_button:Button
var context:HBoxContainer
var context_signature:=""
var primary_actions:HBoxContainer
var chess_button:Button
var utility_actions:HBoxContainer
var notifications:VBoxContainer
var notification_scroll:ScrollContainer
var notification_toggle:Button
var notices_signature:=""
var notices_collapsed:=false
var dismissed:Dictionary={}
var expanded_notice:=""
var deferred_fish:Dictionary={}
var tick:=0.0
var pointer_down:Dictionary={}
var last_click:Dictionary={}
var panel_style:StyleBoxTexture
var icon_cache:Dictionary={}
var portrait_keys:Dictionary={}
var preferences:=ConfigFile.new()
var residents_panel:PanelContainer
var residents_scroll:ScrollContainer
var residents_title:Label
var manage_connections:Button
var collapse_residents:Button
var resident_rows:Dictionary={}
var resident_menus:Dictionary={}
var resident_badges:Dictionary={}
var appearance_buttons:Dictionary={}
var wardrobe:PanelContainer
var ui_size_mode:=LocalText.source("hud.size_standard")
var settings_menu:MenuButton
var show_hunger_hints:=true
var residents_collapsed:=false
var hint_seconds:=0.0
var walk_hint_seen:=false
var upper_status:VBoxContainer
func button(parent:Node,text:String,callback:Callable)->Button:
	var b:=Button.new();b.focus_mode=Control.FOCUS_NONE;b.set_meta("hud_owned",true);b.text=text;b.set_meta("audio_primary",_locale_static.get(text,"") in ["hud.chat","hud.grill","hud.stock_fish","hud.release","hud.later","hud.stock_all"]);b.focus_mode=Control.FOCUS_NONE;parent.add_child(b)
	b.pressed.connect(func():game.autonomy.player_input();callback.call())
	return b
func label(parent:Node,text:String)->Label:
	var l:=Label.new();l.set_meta("hud_owned",true);l.text=text;l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;parent.add_child(l);return l
func pixel_style()->StyleBoxTexture:
	var im:=Image.create(12,12,false,Image.FORMAT_RGBA8);im.fill(Color("324c45"))
	for y in range(12):
		for x in range(12):
			if x<2 or y<2 or x>9 or y>9:im.set_pixel(x,y,Color("543e32"))
			elif x==2 or y==2:im.set_pixel(x,y,Color("aa8a59"))
	var s:=StyleBoxTexture.new();s.texture=ImageTexture.create_from_image(im)
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:s.set_texture_margin(side,4);s.set_content_margin(side,10)
	return s
func icon(kind:String)->Texture2D:
	if icon_cache.has(kind):return icon_cache[kind]
	if kind=="outfit":
		var hanger:=Image.create(20,20,false,Image.FORMAT_RGBA8);hanger.fill(Color.TRANSPARENT)
		var ink:=Color("e8d6aa")
		for p in [Vector2i(9,2),Vector2i(10,2),Vector2i(11,3),Vector2i(11,4),Vector2i(10,5),Vector2i(9,6)]:hanger.fill_rect(Rect2i(p,Vector2i(2,2)),ink)
		for x in range(2,18):
			var y:int=7+int(absf(x-9.5)*.85)
			hanger.fill_rect(Rect2i(x,y,2,2),ink);hanger.fill_rect(Rect2i(x,14,2,2),ink)
		var result:=ImageTexture.create_from_image(hanger);icon_cache[kind]=result;return result
	var im:=Image.create(16,16,false,Image.FORMAT_RGBA8);im.fill(Color.TRANSPARENT)
	var color:=Color("e8d6aa")
	for y in range(2,14):
		for x in range(2,14):
			var ink:=false
			match kind:
				"outfit":ink=(y in [3,4] and x in [6,7,8,9]) or (y in [4,5] and x in [8,9]) or (y in [6,7,8,9,10] and abs(x-8)==y-6) or (y in [10,11] and x in range(3,14))
				"book":ink=x in [2,7,8,13] or y in [3,12] or (y in [6,9] and x in [4,5,10,11])
				"gear":ink=Vector2(x-7.5,y-7.5).length()>3 and Vector2(x-7.5,y-7.5).length()<6
				"sunny":ink=Vector2(x-8,y-8).length()<3 or ((x==8 or y==8) and (x<5 or x>11 or y<5 or y>11))
				"rain":ink=(y in [4,5,6] and x>3 and x<13) or (y>9 and (x+y)%4==0)
				"fog":ink=y in [4,7,10] and x>3 and x<13
				_:ink=y in [5,6,7,8] and x>3 and x<13
			if ink:im.set_pixel(x,y,color)
	var texture:=ImageTexture.create_from_image(im);icon_cache[kind]=texture;return texture
func setup(host:Node,source:Control,old_top:Control,settings:MenuButton)->void:
	game=host;ui_root=source;settings_menu=settings;config=JSON.parse_string(FileAccess.get_file_as_string("res://content/home-v3/ui.json"))
	preferences.load(game.data_dir.path_join("local-life.cfg"))
	show_hunger_hints=bool(preferences.get_value("interface","show_hunger",true))
	residents_collapsed=bool(preferences.get_value(game.world.world_id+"/hud","residents_collapsed",false))
	walk_hint_seen=bool(preferences.get_value(game.world.world_id+"/hud","walk_hint_seen",false));hint_seconds=6 if walk_hint_seen else 0
	var remembered:Variant=preferences.get_value(game.world.world_id+"/hud","dismissed",[])
	if remembered is Array:
		for key in remembered.slice(-200):
			if key is String:dismissed[key]=true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);mouse_filter=Control.MOUSE_FILTER_IGNORE;texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	panel_style=pixel_style()
	ui_root.theme.set_stylebox("normal","Button",panel_style);ui_root.theme.set_stylebox("hover","Button",panel_style);ui_root.theme.set_stylebox("pressed","Button",panel_style)
	ui_root.theme.set_stylebox("panel","PanelContainer",panel_style)
	old_top.hide();game.stock.hide()
	# Status remains an honest controller receipt; no resident or task logic is replaced.
	game.status.position=Vector2(18,77);game.status.size=Vector2(300,24);game.status.add_theme_font_size_override("font_size",13)
	for child in ui_root.get_children():
		if child is Label and child.get_meta("ui_role","")=="movement_hint":child.hide()
	var upper:=VBoxContainer.new();upper_status=upper;add_child(upper);upper.position=Vector2(12,10);upper.size=Vector2(420,56)
	game.day_label.reparent(upper,false);game.day_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);game.day_label.position=Vector2.ZERO;game.day_label.size=Vector2.ZERO;game.day_label.show();game.day_label.set_meta("ui_font_base",14);game.day_label.add_theme_font_size_override("font_size",preload("res://scripts/ui_scale.gd").pixels(14))
	var day_style:=StyleBoxFlat.new();day_style.bg_color=Color(.08,.13,.12,.80);day_style.set_content_margin_all(6)
	game.day_label.add_theme_stylebox_override("normal",day_style)
	stock_button=button(upper,T("hud.stock"),func():game.storage_panel.open());stock_button.alignment=HORIZONTAL_ALIGNMENT_LEFT
	stock_button.add_theme_font_size_override("font_size",12);stock_button.expand_icon=true;stock_button.add_theme_constant_override("icon_max_width",24)
	var task_panel:=PanelContainer.new();task_panel.name="TasksPanel";upper.add_child(task_panel);task_panel.add_theme_stylebox_override("panel",pixel_style())
	game.journey.bar.reparent(task_panel,false)
	upper.add_theme_constant_override("separation",8)
	var stock_style:=StyleBoxFlat.new();stock_style.bg_color=Color(.12,.21,.18,.72);stock_style.set_content_margin_all(6);stock_button.add_theme_stylebox_override("normal",stock_style)
	stock_detail=PanelContainer.new();add_child(stock_detail);stock_detail.position=Vector2(16,92);stock_detail.size=Vector2(300,180);stock_text=label(stock_detail,"");stock_detail.hide()
	residents_panel=PanelContainer.new();add_child(residents_panel);residents_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	var resident_body:=VBoxContainer.new();residents_panel.add_child(resident_body)
	var header:=HBoxContainer.new();resident_body.add_child(header)
	residents_title=label(header,T("hud.residents_connections"));residents_title.clip_text=true;residents_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;residents_title.add_theme_font_size_override("font_size",14)
	manage_connections=button(header,T("hud.connections"),func():open_connections(""));manage_connections.add_theme_font_size_override("font_size",12)
	collapse_residents=button(header,"－",toggle_residents)
	residents_scroll=ScrollContainer.new();resident_body.add_child(residents_scroll);residents_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;residents_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	wardrobe=preload("res://scripts/wardrobe.gd").new();ui_root.add_child(wardrobe);wardrobe.setup(game);wardrobe.visibility_changed.connect(func():call_deferred("refresh"))
	avatars=VBoxContainer.new();residents_scroll.add_child(avatars);avatars.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for id in game.world.director.routines:make_avatar(id)
	layout_residents()
	resident_card=PanelContainer.new();add_child(resident_card);resident_card.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT);resident_card.offset_left=-330;resident_card.offset_right=-16;resident_card.offset_top=88;resident_card.offset_bottom=340
	var card_frame:=VBoxContainer.new();resident_card.add_child(card_frame)
	var card_header:=HBoxContainer.new();card_frame.add_child(card_header)
	card_title=label(card_header,T("hud.resident_details"));card_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;card_title.add_theme_font_size_override("font_size",17)
	card_close=button(card_header,"×",resident_card.hide);card_close.tooltip_text=T("hud.close_details");card_close.custom_minimum_size=Vector2(42,42)
	reasoning_points=preload("res://scripts/reasoning_points.gd").new();card_frame.add_child(reasoning_points)
	var heart_button:=button(card_frame,T("gestation.heart"),func():open_connections(card_id);game.resident_connections.tabs.current_tab=3;game.resident_connections.refresh())
	heart_button.name="LifeHeartButton"
	card_scroll=ScrollContainer.new();card_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;card_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;card_frame.add_child(card_scroll)
	card_body=VBoxContainer.new();card_body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;card_scroll.add_child(card_body);card_detail=label(card_body,"")
	var row:=HFlowContainer.new();card_body.add_child(row)
	button(row,T("hud.chat"),func():chat_with(card_id))
	button(row,T("hud.come_here"),func():game._participants_chosen([card_id],{"intent":"come_near","target_id":"human"}))
	button(row,T("hud.delegate"),func():game._select_chat(card_id);game.assign=true;game.status.text=T("hud.delegate_hint");resident_card.hide())
	button(row,T("hud.stop"),func():game._stop_resident(card_id))
	button(row,T("hud.give"),func():resident_card.hide();game.gift_panel.open(card_id))
	button(row,T("hud.rename"),func():rename_resident(card_id))
	button(row,T("hud.appearance"),func():open_appearance(card_id))
	button(row,T("hud.name_preset"),func():rename_intelligence(card_id))
	button(row,T("hud.assign_preset"),func():assign_intelligence(card_id))
	button(row,T("hud.resident_connection"),func():open_connections(card_id))
	button(row,T("hud.close"),resident_card.hide);resident_card.hide()
	var bottom:=HBoxContainer.new();primary_actions=bottom;add_child(bottom);bottom.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM);bottom.offset_left=-228;bottom.offset_right=228;bottom.offset_top=-59;bottom.offset_bottom=-16;bottom.add_theme_constant_override("separation",10)
	for b in [game.dialogue_button,game.actions_button,game.gathering_button]:
		b.reparent(bottom,false);b.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);b.custom_minimum_size=Vector2(104,40)
	game.journey.map_button=button(bottom,T("journey.map"),func():game.journey.toggle_menu())
	chess_button=button(bottom,T("hud.gomoku"),func():game._open_chess());chess_button.custom_minimum_size=Vector2(84,40);chess_button.hide()
	var corner:=HBoxContainer.new();utility_actions=corner;add_child(corner);corner.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT);corner.offset_left=-200;corner.offset_right=-16;corner.offset_top=-59;corner.offset_bottom=-16
	game.handbook_menu.reparent(corner,false);game.handbook_menu.text=T("hud.handbook");game.handbook_menu.icon=icon("book")
	var popup:PopupMenu=game.handbook_menu.get_popup();popup.clear()
	# Keep the existing popup signal, but route the new explicit metadata IDs here.
	for c in popup.id_pressed.get_connections():popup.id_pressed.disconnect(c.callable)
	for entry in config.handbook:
		if entry.id in ["memories","memory","our_days"]:continue
		popup.add_item(LocalText.content(entry.label));popup.set_item_metadata(popup.item_count-1,entry.id)
	popup.add_item(T("memory.notebook"));popup.set_item_metadata(popup.item_count-1,"memory_books")
	popup.add_item(T("hud.relics"));popup.set_item_metadata(popup.item_count-1,"relics")
	popup.add_item(T("hud.wardrobe"));popup.set_item_metadata(popup.item_count-1,"wardrobe")
	if game.world.standard.active():popup.add_item(T("theirs.goals"));popup.set_item_metadata(popup.item_count-1,"opening_board")
	popup.id_pressed.connect(func(index):open_entry(str(popup.get_item_metadata(index))))
	popup.about_to_popup.connect(func():_position_handbook_popup.call_deferred())
	settings.reparent(corner,false);settings.text=T("hud.settings");settings.icon=icon("gear")
	settings.get_popup().about_to_popup.connect(func():_position_settings_popup.call_deferred())
	settings.get_popup().add_item(T("hud.my_appearance"),90)
	settings.get_popup().add_separator(T("hud.interface_size"))
	for item in [[LocalText.source("hud.size_small"),91],[LocalText.source("hud.size_standard"),92],[LocalText.source("hud.size_large"),93],[LocalText.source("ui.scale.extra"),95]]:settings.get_popup().add_radio_check_item(T("hud.interface_prefix")+T({91:"hud.size_small",92:"hud.size_standard",93:"hud.size_large",95:"ui.scale.extra"}[item[1]]),item[1])
	settings.get_popup().add_check_item(T("hud.hunger_hints"),94);settings.get_popup().set_item_checked(settings.get_popup().get_item_index(94),show_hunger_hints)
	ui_size_mode=str(preferences.get_value("interface","size",LocalText.source("hud.size_standard")))
	settings.get_popup().add_item(T("camera.distance.close"),96)
	settings.get_popup().add_item(T("camera.distance.original"),97)
	settings.get_popup().id_pressed.connect(func(id):
		if id in [96,97]:
			game.view.camera_defaults.set_distance(.8 if id==97 else 1.0);game._return_to_player();return
		if id==94:
			set_hunger_hints(not show_hunger_hints);settings.get_popup().set_item_checked(settings.get_popup().get_item_index(94),show_hunger_hints);return
		if id in [91,92,93,95]:set_interface_size({91:LocalText.source("hud.size_small"),92:LocalText.source("hud.size_standard"),93:LocalText.source("hud.size_large"),95:LocalText.source("ui.scale.extra")}[id]);return
		if id==90:
			var confirm:=ConfirmationDialog.new();confirm.title=T("hud.my_appearance");confirm.dialog_text=T("hud.appearance_confirm");confirm.ok_button_text=T("hud.continue");confirm.cancel_button_text=T("hud.cancel");ui_root.add_child(confirm)
			confirm.confirmed.connect(func():wardrobe.open_for("human",true);confirm.queue_free())
			confirm.canceled.connect(confirm.queue_free);confirm.popup_centered())
	task=PanelContainer.new();add_child(task);task.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT);task.offset_left=16;task.offset_right=275;task.offset_top=-160;task.offset_bottom=-95
	var task_row:=HBoxContainer.new();task.add_child(task_row);task_text=label(task_row,"");task_text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	button(task_row,"×",func():game.world.command("human",{"intent":"stop"}))
	return_button=button(self,T("hud.return_to_me"),game._return_to_player);return_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT);return_button.offset_left=16;return_button.offset_right=170;return_button.offset_top=-59;return_button.offset_bottom=-16
	context=HBoxContainer.new();add_child(context);context.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM);context.offset_left=-225;context.offset_right=225;context.offset_top=-111;context.offset_bottom=-70;context.alignment=BoxContainer.ALIGNMENT_CENTER
	notification_toggle=button(self,T("hud.island_news"),func():notices_collapsed=not notices_collapsed;notices_signature="");notification_toggle.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT);notification_toggle.offset_left=-270;notification_toggle.offset_right=-16;notification_toggle.offset_top=90;notification_toggle.offset_bottom=125
	notifications=VBoxContainer.new();add_child(notifications);notifications.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT);notifications.offset_left=-270;notifications.offset_right=-16;notifications.offset_top=134;notifications.offset_bottom=430;notifications.add_theme_constant_override("separation",7)
	# Preserve detailed original card controls on demand; summaries share this one edge.
	game.action_dock.notifications_embedded=true;game.wish_panel.notifications_embedded=true;game.proposal_panel.notifications_embedded=true
	button(game.proposal_panel.get_child(0),T("hud.close"),func():game.proposal_panel.detail_requested=false;game.proposal_panel.hide();expanded_notice="")
	style_panels(ui_root)
	set_interface_size(ui_size_mode,false)
	refresh()
	resized.connect(func():call_deferred("refresh"))
	game.chat.visibility_changed.connect(refresh)
	if not LocalText.events.changed.is_connected(refresh_locale):LocalText.events.changed.connect(refresh_locale)
func scale_manager()->Node:
	var manager:Node=game.get("ui_scale")
	return manager if manager!=null else ui_root.get_meta("ui_scale_manager") if ui_root.has_meta("ui_scale_manager") else null
func set_interface_size(mode:String,persist:=true)->void:
	var modes:Array=[LocalText.source("hud.size_small"),LocalText.source("hud.size_standard"),LocalText.source("hud.size_large"),LocalText.source("ui.scale.extra")]
	if mode not in modes:mode=modes[2]
	ui_size_mode=mode
	var manager:Node=scale_manager()
	if manager!=null:manager.set_level(modes.find(mode),persist)
func set_hunger_hints(value:bool)->void:
	show_hunger_hints=value
	var prefs:=ConfigFile.new();prefs.load(game.data_dir.path_join("local-life.cfg"));prefs.set_value("interface","show_hunger",value);prefs.save(game.data_dir.path_join("local-life.cfg"));refresh_card()
func _apply_interface_size(node:Node,_factor:float)->void:
	var manager:Node=scale_manager()
	if manager!=null:manager.apply_branch(node)
func style_panels(node:Node)->void:
	if node is PanelContainer and not node.get_meta("chess_scene_surface",false):node.add_theme_stylebox_override("panel",panel_style)
	for child in node.get_children():style_panels(child)
func save_preference(key:String,value:Variant)->void:
	var latest:=ConfigFile.new();latest.load(game.data_dir.path_join("local-life.cfg"));latest.set_value(game.world.world_id+"/hud",key,value);latest.save(game.data_dir.path_join("local-life.cfg"))
func toggle_residents()->void:
	residents_collapsed=not residents_collapsed;save_preference("residents_collapsed",residents_collapsed);layout_residents();refresh()
func layout_residents()->void:
	var english:bool=LocalText.revision().begins_with("en")
	var f:float=preload("res://scripts/ui_scale.gd").factor()
	var width:float=(92 if residents_collapsed else 330)*f
	if english:width=(132 if residents_collapsed else 380)*f
	width=minf(width,get_viewport_rect().size.x*.57)
	width=minf(width,get_viewport_rect().size.x-36-upper_status.get_combined_minimum_size().x)
	var left_width:float=minf(420,get_viewport_rect().size.x-width-36)
	upper_status.size=Vector2(left_width,0)
	game.day_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	stock_button.clip_text=true
	residents_panel.offset_left=-width-12;residents_panel.offset_right=-12;residents_panel.offset_top=10
	residents_panel.offset_bottom=minf(get_viewport_rect().size.y-180,(76+game.world.director.routines.size()*52)*f)
	residents_scroll.custom_minimum_size.y=0
	residents_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED if (76+game.world.director.routines.size()*52)*f<=get_viewport_rect().size.y-180 else ScrollContainer.SCROLL_MODE_AUTO
	residents_title.text=T("hud.residents") if residents_collapsed else T("hud.residents_connections");manage_connections.visible=not residents_collapsed;collapse_residents.text="＋" if residents_collapsed else "－"
	for id in resident_rows:
		var appetite:Dictionary=game.world.hunger.summary(id)
		avatar_buttons[id].text="" if residents_collapsed else LocalText.resident(game.world,id)+(("\n" if preload("res://scripts/ui_scale.gd").factor()>=1.1 and get_viewport_rect().size.x<1100 else " · ")+appetite_label(id) if show_hunger_hints and not appetite.is_empty() else "")
		avatar_buttons[id].custom_minimum_size=Vector2((34 if residents_collapsed else (180 if english else 150))*f,48*f)
		avatar_marks[id].custom_minimum_size=Vector2(10,0)
		resident_menus[id].visible=not residents_collapsed;resident_badges[id].visible=not residents_collapsed;appearance_buttons[id].visible=not residents_collapsed
	if is_instance_valid(notification_toggle):
		var fish_pending:bool=game.world.fishing.fish.values().any(func(entry):return entry.location=="pending")
		if fish_pending:
			notification_toggle.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);notification_toggle.offset_left=12;notification_toggle.offset_right=266;notification_toggle.offset_top=90;notification_toggle.offset_bottom=124
			notifications.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);notifications.offset_left=12;notifications.offset_right=minf(612,get_viewport_rect().size.x-20);notifications.offset_top=130;notifications.offset_bottom=get_viewport_rect().size.y-70
		else:
			notification_toggle.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT);notification_toggle.offset_left=-270;notification_toggle.offset_right=-16
			notifications.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT);notifications.offset_left=-270;notifications.offset_right=-16
			var bottom:float=residents_panel.offset_bottom+6;notification_toggle.offset_top=bottom;notification_toggle.offset_bottom=bottom+34;notifications.offset_top=bottom+40;notifications.offset_bottom=minf(get_viewport_rect().size.y-130,bottom+250)
		if english:
			if notification_scroll==null:
				notification_scroll=ScrollContainer.new();notification_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;add_child(notification_scroll)
			if notifications.get_parent()!=notification_scroll:notifications.reparent(notification_scroll,false)
			notification_scroll.position=Vector2(notification_toggle.position.x,notification_toggle.position.y+notification_toggle.size.y+6)
			notification_scroll.size=Vector2(254,maxf(40,get_viewport_rect().size.y-80-notification_scroll.position.y))
			notifications.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);notifications.position=Vector2.ZERO;notifications.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		elif notification_scroll!=null:
			if notifications.get_parent()==notification_scroll:notifications.reparent(self,false);call_deferred("layout_residents")
			notification_scroll.hide()
func make_avatar(id:String)->void:
	var row:=HBoxContainer.new();avatars.add_child(row);row.mouse_filter=Control.MOUSE_FILTER_STOP;resident_rows[id]=row
	row.gui_input.connect(func(event):avatar_input(id,event);row.accept_event())
	var b:=Button.new();b.focus_mode=Control.FOCUS_NONE;var row_style:StyleBoxTexture=panel_style.duplicate();row_style.set_content_margin_all(4);b.add_theme_stylebox_override("normal",row_style);b.add_theme_stylebox_override("hover",row_style);b.size_flags_horizontal=Control.SIZE_EXPAND_FILL;b.clip_text=false;b.alignment=HORIZONTAL_ALIGNMENT_LEFT;b.add_theme_font_size_override("font_size",13);row.add_child(b);avatar_buttons[id]=b
	b.gui_input.connect(func(event):avatar_input(id,event);b.accept_event())
	update_portrait(id)
	var lamp:=Label.new();lamp.add_theme_font_size_override("font_size",12);lamp.mouse_filter=Control.MOUSE_FILTER_STOP;row.add_child(lamp);connection_lights[id]=lamp
	var mark:=Label.new();mark.add_theme_font_size_override("font_size",12);mark.mouse_filter=Control.MOUSE_FILTER_IGNORE;row.add_child(mark);avatar_marks[id]=mark
	var badges:=Label.new();badges.add_theme_font_size_override("font_size",10);badges.position=Vector2(2,1);badges.mouse_filter=Control.MOUSE_FILTER_IGNORE;b.add_child(badges);resident_badges[id]=badges
	appearance_buttons[id]=button(row,"",func():open_appearance(id));appearance_buttons[id].icon=icon("outfit");appearance_buttons[id].tooltip_text=T("hud.appearance_tooltip");appearance_buttons[id].custom_minimum_size.x=68
	var outfit_text:=Label.new();outfit_text.set_meta("hud_owned",true);outfit_text.text=T("hud.outfit");outfit_text.mouse_filter=Control.MOUSE_FILTER_IGNORE;outfit_text.add_theme_font_size_override("font_size",13);outfit_text.position=Vector2(30,9);appearance_buttons[id].add_child(outfit_text)
	resident_menus[id]=button(row,"⋯",func():show_card(id));resident_menus[id].add_theme_font_size_override("font_size",14)
func resident_status(id:String)->Dictionary:
	var state:Dictionary=game._connection_light(id)
	return {"text":state.provider,"color":state.color,"busy":(game._valid_link(game.links,id) and game.links[id].is_busy()) or (game._valid_link(game.group_links,id) and game.group_links[id].is_busy()),"tooltip":state.provider+" · "+T("memory.state."+state.state)+" · "+T("memory.today_tokens")+": "+str(state.tokens)}
func update_portrait(id:String)->void:
	var actor:Dictionary=game.world.actors[id];var visual_id:String=game.library.visual_appearance(actor);var art:Dictionary=game.library.artworks.get(visual_id,{})
	var key:String=visual_id+":"+str(art.get("revision",0))
	if portrait_keys.get(id)==key:return
	portrait_keys[id]=key
	if not art.is_empty():
		var frame:String="idle_down" if art.frames.has("idle_down") else art.frames.keys()[0]
		var im:Image=game.library.render(art,frame);var rect:Rect2i=im.get_used_rect();var crop:=im.get_region(Rect2i(maxi(0,rect.get_center().x-20),rect.position.y,40,40))
		avatar_buttons[id].icon=ImageTexture.create_from_image(crop);avatar_buttons[id].expand_icon=false
func avatar_input(id:String,event:InputEvent)->void:
	if event is InputEventMouseButton:
		if event.pressed:
			game.autonomy.player_input()
			if event.button_index==MOUSE_BUTTON_RIGHT:show_card(id);return
			if event.button_index==MOUSE_BUTTON_LEFT:
				if event.double_click:chat_with(id)
				else:locate(id)
				pointer_down={"id":id,"at":Time.get_ticks_msec()}
		else:pointer_down.clear()
	elif event is InputEventScreenTouch:
		if event.pressed:pointer_down={"id":id,"at":Time.get_ticks_msec()};locate(id)
		else:
			if last_click.get("id")==id and Time.get_ticks_msec()-int(last_click.get("at",0))<350:chat_with(id)
			last_click={"id":id,"at":Time.get_ticks_msec()};pointer_down.clear()
func locate(id:String)->void:
	game._toggle_atlas(false);game.view.show_region(game.world.actors[id].region_id);game.view.center=game.world.point(game.world.actors[id]);game.view.follow_player=false
func chat_with(id:String)->void:
	resident_card.hide();game.resident_connections.close_panel();game._select_chat(id);game.chat.show();game.chat_input.grab_focus()
func show_card(id:String)->void:
	card_id=id;game.resident_connections.close_panel();resident_card.offset_top=residents_panel.offset_bottom+6;resident_card.offset_bottom=minf(get_viewport_rect().size.y-maxf(150,150*preload("res://scripts/ui_scale.gd").factor()),resident_card.offset_top+290);resident_card.show();refresh_card()
func refresh_card()->void:
	if card_id.is_empty():return
	reasoning_points.setup(game.data_dir,game.world.world_id,card_id)
	card_title.text=str(LocalText.resident(game.world,card_id))+T("hud.resident_details_suffix")
	var state:Dictionary=game._resident_connection_snapshot(card_id);var rel:Dictionary=game.world.relationships.summary(card_id)
	card_detail.text="%s · %s\n%s\n%s\n%s\n%s"%[LocalText.resident(game.world,card_id),LocalText.content(rel.name),LocalText.content(str(game.world.personality.summary(card_id).get("name",""))),LocalText.content(state.origin),LocalText.content(state.connection),LocalText.content(state.activity)+T("hud.mood_prefix")+LocalText.content(str(game.world.director.moods.summary(card_id).name))]
	var intelligence:Dictionary=game.world.intelligence.summary(card_id)
	if not intelligence.is_empty():card_detail.text=game.world.intelligence.display_name(card_id)+T("hud.local_preset_suffix")+card_detail.text
	var appetite:Dictionary=game.world.hunger.summary(card_id)
	if show_hunger_hints and not appetite.is_empty():card_detail.text+=T("hud.state_prefix")+LocalText.content(appetite.state)
	if game.steward!=null:card_detail.text+="\n"+LocalText.text("watch.reason")+game.steward.reason_for(card_id)
func rename_intelligence(id:String)->void:
	var preset_id:String=game.world.intelligence.preset_id(id)
	if preset_id.is_empty():return
	var dialog:=ConfirmationDialog.new();dialog.title=T("hud.preset_name");ui_root.add_child(dialog)
	var body:=VBoxContainer.new();dialog.add_child(body)
	label(body,T("hud.preset_name_hint")).autowrap_mode=TextServer.AUTOWRAP_OFF
	var field:=LineEdit.new();field.text=game.world.intelligence.summary(id).name;field.max_length=24;body.add_child(field)
	dialog.confirmed.connect(func():game.world.intelligence.rename_preset(preset_id,field.text);refresh_card();dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free);size_intelligence_dialog(dialog);dialog.popup_centered(Vector2i(400,170))
func assign_intelligence(id:String)->void:
	var dialog:=ConfirmationDialog.new();dialog.title=T("hud.assign_title");ui_root.add_child(dialog)
	var body:=VBoxContainer.new();dialog.add_child(body)
	label(body,T("hud.assign_hint")).autowrap_mode=TextServer.AUTOWRAP_OFF
	var picker:=OptionButton.new();picker.focus_mode=Control.FOCUS_NONE;body.add_child(picker)
	for pid in game.world.intelligence.catalog.presets:
		picker.add_item(LocalText.content(game.world.intelligence.catalog.presets[pid].name));picker.set_item_metadata(picker.item_count-1,pid)
		if pid==game.world.intelligence.preset_id(id):picker.select(picker.item_count-1)
	dialog.confirmed.connect(func():game.world.intelligence.assign(id,picker.get_item_metadata(picker.selected));refresh_card();dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free);size_intelligence_dialog(dialog);dialog.popup_centered(Vector2i(460,190))
func size_intelligence_dialog(dialog:ConfirmationDialog)->void:
	_apply_interface_size(dialog,preload("res://scripts/ui_scale.gd").factor())
func rename_resident(id:String)->void:
	if not game.world.actors.has(id) or game.world.actors[id].role=="human":return
	var dialog:=ConfirmationDialog.new();dialog.title=T("hud.rename_title");ui_root.add_child(dialog)
	var field:=LineEdit.new();field.text=game.world.actors[id].name;field.max_length=24;dialog.add_child(field)
	dialog.confirmed.connect(func():
		var result:Dictionary=game.world.residents.rename(game.world,id,field.text)
		game.status.text=T("hud.renamed") if result.ok else T("hud.invalid_name")
		refresh_card();dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free);dialog.popup_centered(Vector2i(340,130))
func open_appearance(id:String)->void:
	if not game.world.actors.has(id):return
	resident_card.hide()
	wardrobe.open_for(id)
func open_connections(id:String)->void:
	resident_card.hide()
	if not game.resident_connections.visible:game._toggle_resident_connections()
	if not id.is_empty():game.resident_connections.select_resident(id)
func open_entry(id:String)->void:
	if id=="relics":game.dark_ui.relics();return
	game.autonomy.player_input();resident_card.hide()
	match id:
		"wardrobe":
			for actor_id in game.world.actors:
				if game.world.actors[actor_id].role!="human":wardrobe.open_for(actor_id);break
		"journal":game.journal_panel.open()
		"homestead":game._open_homestead()
		"farms":game.farm_panel.show()
		"facilities":game.leisure_panel.rebuild()
		"fisheries":game._open_fishing()
		_:game._handbook_selected(id)
func notification_data()->Array:
	var rows:Array=[]
	var pending:Array=[]
	for fish in game.world.fishing.fish.values():
		if fish.location=="pending" or (fish.location=="storage" and fish.owner_id=="human"):pending.append(fish)
	pending.sort_custom(func(a,b):return float(a.caught_at)<float(b.caught_at))
	for fish in pending:
		if not deferred_fish.has(fish.id):rows.append({"key":"fish:"+fish.id,"kind":"fish","id":fish.owner_id,"fish_id":fish.id,"text":T("hud.new_fish") % LocalText.resident(game.world,fish.owner_id)})
	for card in game.world.proposals.snapshot():rows.append({"key":"proposal:"+card.id,"kind":"proposal","id":card.id,"text":LocalText.resident(game.world,card.actor_id)+"："+(LocalText.content(card.text) if card.get("source","")=="local_rules" else str(card.text))})
	for id in game.world.director.routines:
		var wish:Dictionary=game.world.wishes.summary(id)
		if wish.active and wish.announced and game.wish_panel.dismissed.get(id,"")!=wish.id:rows.append({"key":"wish:"+wish.id,"kind":"wish","id":id,"text":LocalText.resident(game.world,id)+"："+LocalText.content(wish.text)+"\n"+game.world.wishes.hint(game.world.wishes.template(game.world.wishes.active(id).template_id),true)})
	for record in game.world.memories.records:
		if record.kind in ["gift","house_completed"]:rows.append({"key":"memory:"+record.id,"kind":"memory","id":record.id,"text":game.world.memories._describe(record).summary})
	var completed:Dictionary=game.world.homestead.site.completion
	var completion_id:String=str(completed.get("id",""))
	if not completion_id.is_empty() and not game.world.homestead.site.has("host_completion_source"):rows.append({"key":completion_id,"kind":"homestead","id":completion_id,"text":T("hud.homestead_complete")})
	return rows.filter(func(row):return row.kind=="fish" or not dismissed.has(row.key))
func open_notice(row:Dictionary)->void:
	expanded_notice=row.kind
	match row.kind:
		"fish":game.fishing_panel.open("",row.id);refresh()
		"wish":game.wish_panel.detail_requested=true;game.wish_panel.refresh();game.wish_panel.show()
		"proposal":game.proposal_panel.detail_requested=true;game.proposal_panel.refresh();game.proposal_panel.show()
		"homestead":game._open_homestead()
		_:game._toggle_memories()
func notice_limit()->int:
	return int(config.notification_limit)
func refresh_notifications()->void:
	var rows:=notification_data();var pending:Array=game.world.fishing.fish.values().filter(func(f):return f.location=="pending" or (f.owner_id=="human" and f.location=="storage"))
	var sig:=JSON.stringify(rows)+str(notices_collapsed)+JSON.stringify(deferred_fish)
	notification_toggle.text=T("hud.news_count")%[rows.size()," ＋" if notices_collapsed else " －"]
	notification_toggle.visible=(not rows.is_empty() or not pending.is_empty()) and not resident_card.visible and not game.resident_connections.visible and not game.chat.visible and not game.editor.visible and not game.atlas.visible
	notifications.visible=notification_toggle.visible and not notices_collapsed and expanded_notice.is_empty() and not game.gift_panel.visible and not game.fishing_panel.visible
	if notification_scroll!=null:notification_scroll.visible=LocalText.revision().begins_with("en") and notifications.visible
	if sig==notices_signature:return
	notices_signature=sig
	for child in notifications.get_children():notifications.remove_child(child);child.queue_free()
	for row in rows.slice(0,notice_limit()):
		var box:=PanelContainer.new();box.add_theme_stylebox_override("panel",panel_style);notifications.add_child(box)
		var body:=VBoxContainer.new();box.add_child(body)
		if row.kind=="fish":
			var entry:Dictionary=game.world.fishing.fish.get(row.fish_id,{})
			if entry.is_empty():continue
			var top:=HBoxContainer.new();body.add_child(top)
			var icon_view:=TextureRect.new();icon_view.custom_minimum_size=Vector2(48,38);icon_view.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon_view.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;icon_view.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;icon_view.texture=game.view.fishing_renderer.texture(entry.species_id,entry.color_id,game.world.fishing.rules);top.add_child(icon_view)
			var info:Dictionary=game.world.fishing.describe(entry)
			var title:Button=button(top,T("hud.catch_card") % [LocalText.resident(game.world,entry.owner_id),LocalText.content(str(info.species_name)),LocalText.content(str(info.sizes_name))],func():open_notice(row));title.clip_text=true;title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;title.add_theme_font_size_override("font_size",13)
			var fish_grid:=GridContainer.new();fish_grid.columns=4;body.add_child(fish_grid)
			var fish_actions:=fish_grid
			button(fish_actions,T("hud.grill"),func():game.choose_direct_grill(row.fish_id))
			button(fish_actions,T("hud.stock_fish"),func():fish_action(row.fish_id,"stock"))
			button(fish_actions,T("hud.release"),func():fish_action(row.fish_id,"release"))
			button(fish_actions,T("hud.later"),func():deferred_fish[row.fish_id]=true;notices_signature="";refresh_notifications())
			for action_button in fish_actions.get_children():
				var compact:=StyleBoxFlat.new();compact.bg_color=Color("344c41");compact.set_content_margin(SIDE_TOP,2);compact.set_content_margin(SIDE_BOTTOM,2);compact.set_content_margin(SIDE_LEFT,4);compact.set_content_margin(SIDE_RIGHT,4)
				action_button.add_theme_stylebox_override("normal",compact);action_button.add_theme_stylebox_override("hover",compact);action_button.add_theme_stylebox_override("pressed",compact)
				action_button.add_theme_font_size_override("font_size",13)
			continue
		label(body,row.text).add_theme_font_size_override("font_size",13)
		var actions:=HBoxContainer.new();body.add_child(actions)
		button(actions,T("hud.view"),func():open_notice(row))
		button(actions,T("hud.dismiss"),func():
			dismissed[row.key]=true;notices_signature=""
			save_preference("dismissed",dismissed.keys().slice(-200)))
	if pending.size()>=2:button(notifications,T("hud.stock_all"),stock_all_pending)
	var visible_fish:int=rows.slice(0,notice_limit()).filter(func(row):return row.kind=="fish").size()
	var hidden:int=pending.size()-visible_fish
	if hidden>0:button(notifications,T("hud.more_fish")%hidden,func():
		for row in rows.slice(0,notice_limit()):
			if row.kind=="fish":deferred_fish[row.fish_id]=true
		for entry in pending:
			if deferred_fish.has(entry.id) and not rows.any(func(r):return r.get("fish_id")==entry.id):deferred_fish.erase(entry.id)
		notices_signature="";refresh_notifications())

func fish_action(id:String,action:String)->void:
	var result:Dictionary=game.world.fishing.host_stock_nearest(id) if action=="stock" else game.world.fishing.host_pending_action(id,"release_fish")
	game.status.text=LocalText.content(str(result.get("message",result.get("error",""))))
	if result.get("ok",false):deferred_fish.erase(id)
	notices_signature="";game.action_dock.refresh();refresh_notifications()

func stock_all_pending()->void:
	var pending:Array=game.world.fishing.fish.values().filter(func(f):return f.location=="pending" or (f.owner_id=="human" and f.location=="storage"))
	pending.sort_custom(func(a,b):return float(a.caught_at)<float(b.caught_at))
	var placed:=0
	for entry in pending:
		var result:Dictionary=game.world.fishing.host_stock_nearest(entry.id)
		if result.get("ok",false):placed+=1;deferred_fish.erase(entry.id)
	game.status.text=T("hud.stock_result")%[placed,pending.size()-placed]
	notices_signature="";game.action_dock.refresh();refresh_notifications()
func nearby_chess_site()->String:
	var human:Dictionary=game.world.actors.human
	var closest:=float(config.context_radius);var chosen:=""
	for site in game.world.leisure.sites.values():
		if site.region_id!=human.region_id or not site.complete or game.world.gomoku.table(str(site.id)).is_empty():continue
		var distance:float=game.world.point(site).distance_to(game.world.point(human))
		if distance<=closest:closest=distance;chosen=str(site.id)
	return chosen

func refresh_context()->void:
	chess_button.visible=not nearby_chess_site().is_empty()
	var choices:Array=[];var human:Dictionary=game.world.actors.human;var p:Vector2=game.world.point(human);var radius:float=config.context_radius
	var fire_choices:Array=[];var fire_distance:=INF
	if str(human.region_id).begins_with("room."):choices.append({"id":"interior","label":T("hud.arrange_room")})
	else:
		for barbecue in game.world.barbecues.values():
			if barbecue.station.region_id!=human.region_id:continue
			var distance:float=p.distance_to(game.world.point(barbecue.station))
			if distance<=radius and distance<fire_distance:
				if not game.world.standard.ready(barbecue.station.id):
					continue
				fire_distance=distance
				fire_choices=[{"id":"light:"+str(barbecue.station.id),"label":T("hud.refuel") if barbecue.fireside.burning() else T("hud.light_fire")},{"id":"roast:"+str(barbecue.station.id),"label":T("hud.barbecue")}]
		for site in game.world.leisure.sites.values():
			if site.region_id!=human.region_id:continue
			var nearby:bool=p.distance_to(game.world.point(site))<=(6.0 if game.world.standard.active() and not site.complete else radius)
			if game.world.standard.active() and not site.complete and (nearby or game.view.hover_id==site.id):
				choices.push_front({"id":site.id,"label":T("hud.construction")%[LocalText.content(site.name),site.invested,game.world.leisure.cost(site)]})
			elif nearby and site.complete and game.world.gomoku.table(str(site.id)).is_empty() and not game.world.barbecues.has(str(game.world.standard.sites.get(site.id,{}).get("target",site.id))):choices.append({"id":site.id,"label":T("hud.gomoku") if not game.world.gomoku.table(site.id).is_empty() else LocalText.content(site.name)})

		if human.region_id=="home" and game.world.standard.active() and p.distance_to(Vector2(game.world.map_anchor("notice")[0],game.world.map_anchor("notice")[1]))<=radius:choices.push_front({"id":"opening.board","label":T("hud.noticeboard")})
		if not game.world.fishing.shore("human").is_empty():choices.append({"id":"fish","label":T("hud.shore_fishing")})
		for site in game.world.objects.values():
			if site.region_id==human.region_id and site.kind=="construction_site" and p.distance_to(game.world.point(site)+Vector2(0,game.world.site_size(site).y/2+1))<=radius:choices.append({"id":site.id,"label":T("hud.enter_home") if int(site.stage_index)==5 else T("hud.build")});break
		if human.region_id==game.world.homestead.config.site.region_id and p.distance_to(game.world.homestead.area().get_center())<=radius:choices.append({"id":"homestead","label":T("hud.homestead")})
	# Fireside interaction stays two actions even from a seat beside another site.
	# Other facilities keep their direct map and handbook entry points.
	if not fire_choices.is_empty():choices=fire_choices
	var sig:=JSON.stringify(choices)
	if sig==context_signature:return
	context_signature=sig
	for child in context.get_children():context.remove_child(child);child.queue_free()
	for entry in choices.slice(0,3):button(context,entry.label,func():activate_context(entry.id))
func activate_context(id:String)->void:
	if id=="opening.board":game._show_opening_board();return
	if game.world.leisure.sites.has(id) and not game.world.leisure.sites[id].complete:game.leisure_panel.open_site(id);return
	if id.begins_with("light:"):
		var station_id:String=id.trim_prefix("light:")
		if not game.world.barbecues.has(station_id):return
		game._camp_action(station_id,"light");context_signature="";refresh_context();return
	if id.begins_with("roast:"):
		game._camp_action(id.trim_prefix("roast:"),"roast");return
	match id:
		"barbecue":game._show_barbecue_menu()
		"fish":game.action_dock.open_invite(true)
		"interior":game.interior_panel.show()
		"homestead":game._open_homestead()
		_:
			if game.world.barbecues.has(id):game._show_barbecue_menu(id)
			elif game.world.objects.has(id):game.house_panel.open_site(id)
			elif not game.world.gomoku.table(id).is_empty():game._open_chess(id)
			else:game.leisure_panel.rebuild()
func layout_primary_actions()->void:
	var f:float=preload("res://scripts/ui_scale.gd").factor()
	var bottom_height:float=maxf(44,42*f)
	var english:bool=LocalText.revision().begins_with("en")
	# Two distinct rows at narrow sizes prevent the action and utility groups overlapping.
	primary_actions.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	var compact:Control=primary_actions.get_node_or_null("CompactDialogue")
	if compact!=null:
		var others:float=0
		for child in primary_actions.get_children():
			if child!=compact and child is Control and child.visible:others+=child.get_combined_minimum_size().x
		compact.custom_minimum_size.x=maxf(220,minf(420*f,get_viewport_rect().size.x-48-others-primary_actions.get_theme_constant("separation")*3))
	var bar_width:float=minf(get_viewport_rect().size.x-24, primary_actions.get_combined_minimum_size().x)
	primary_actions.offset_left=-bar_width/2;primary_actions.offset_right=bar_width/2
	primary_actions.offset_top=-bottom_height-12;primary_actions.offset_bottom=-12
	primary_actions.alignment=BoxContainer.ALIGNMENT_CENTER
	utility_actions.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	utility_actions.offset_left=-minf(get_viewport_rect().size.x-24,(300 if english else 220)*f);utility_actions.offset_right=-12
	utility_actions.offset_top=-bottom_height*2-20;utility_actions.offset_bottom=-bottom_height-20
	utility_actions.alignment=BoxContainer.ALIGNMENT_END
	return_button.offset_top=-bottom_height*2-20;return_button.offset_bottom=-bottom_height-20
	return_button.offset_right=minf(get_viewport_rect().size.x*.45,12+250*f)
	context.offset_top=-bottom_height*3-28;context.offset_bottom=-bottom_height*2-28
	game.status.position=Vector2(16,get_viewport_rect().size.y*.42);game.status.size=Vector2(minf(260*f,get_viewport_rect().size.x*.42),44*f)
func refresh()->void:
	visible=not ((scale_manager()!=null and scale_manager().full_modal_open()) or (game.jieqi_panel!=null and game.jieqi_panel.visible) or (game.gomoku_panel!=null and game.gomoku_panel.card.visible) or (game.chess_choice!=null and game.chess_choice.visible))
	layout_primary_actions()
	residents_panel.visible=not resident_card.visible and not game.resident_connections.visible and not game.editor.visible and not game.fishing_panel.visible
	upper_status.visible=not game.editor.visible
	game.status.visible=not game.editor.visible and visible
	game.day_label.text=LocalText.text("title.name")+" · "+T("hud.day_weather")%[game.world.days.day(),LocalText.content(game.world.days.phase().name),LocalText.content(game.world.weather.current().name)]
	var nearby_fire:RefCounted=game.world.nearest_barbecue("human")
	var stock:Dictionary=game.world.storage.saved().items
	var names:Dictionary={"wood":T("hud.wood"),"mushroom":T("hud.mushroom")}
	var parts:Array=[]
	for item in ["wood","mushroom"]:parts.append(names[item]+" "+str(stock.get(item,0)))
	stock_button.text=T("storage.title")+" · "+" · ".join(parts);stock_button.icon=game.view.textures.get("chest",icon("book"))

	for id in game.world.director.routines:
		if not resident_rows.has(id):make_avatar(id);layout_residents()
	for id in avatar_marks:
		update_portrait(id);avatar_buttons[id].tooltip_text=LocalText.resident(game.world,id)
		var state:Dictionary=resident_status(id)
		avatar_marks[id].text="●" if state.busy else ""
		avatar_marks[id].add_theme_color_override("font_color",Color("8ac5f0"))
		connection_lights[id].text="●";connection_lights[id].tooltip_text=state.tooltip
		connection_lights[id].add_theme_color_override("font_color",state.color)
		var appetite:Dictionary=game.world.hunger.summary(id)
		avatar_buttons[id].text="" if residents_collapsed else LocalText.resident(game.world,id)+(("\n" if preload("res://scripts/ui_scale.gd").factor()>=1.1 and get_viewport_rect().size.x<1100 else " · ")+appetite_label(id) if show_hunger_hints and not appetite.is_empty() else "")
		var flags:Array=[]
		if game.world.wishes.summary(id).active:flags.append(T("hud.wish_flag"))
		if game.questions.has(id) or game.group_questions.has(id):flags.append(T("hud.question_flag"))
		if game.world.proposals.snapshot().any(func(card):return card.actor_id==id):flags.append(T("hud.proposal_flag"))
		resident_badges[id].text="/".join(flags);resident_badges[id].tooltip_text=T("hud.flags_tooltip")
	if game.status.text.is_empty() or (game.status.get_meta("ui_message_key","")=="ui.main.movement_hint" and game.status.text==LocalText.text("ui.main.movement_hint")):
		game.status.modulate.a=clampf((5-hint_seconds)/2,0,1);game.status.visible=hint_seconds<5
	else:game.status.modulate.a=1;game.status.show()
	layout_residents()
	var job:Dictionary=game.world.work.jobs.get("human",{})
	task.visible=not job.is_empty() or game.world._routes.has("human") or game.world.farms.active("human") or game.world.projects.active("human")
	var intent:String=str(job.get("intent","manage_farm" if game.world.farms.active("human") else "build_house" if game.world.projects.active("human") else "move"))
	var phase:String=str(job.get("phase",game.world.farms.orders.get("human",{}).get("status","")))
	task_text.text=T("hud.task_status") % [LocalText.content(str(config.task_names.get(intent,T("hud.working")))),LocalText.content(str(config.phase_names.get(phase,"")))]
	return_button.visible=not game.view.follow_player and not game.atlas.visible
	game.furniture_button.hide()
	if not game.action_dock.feedback.is_empty():game.status.text=game.action_dock.feedback
	if game.wish_panel.visible and expanded_notice!="wish":game.wish_panel.hide()
	if game.proposal_panel.visible and expanded_notice!="proposal":game.proposal_panel.hide()
	if expanded_notice=="wish" and not game.wish_panel.visible:expanded_notice=""
	if expanded_notice=="proposal" and not game.proposal_panel.visible:expanded_notice=""
	if expanded_notice=="fish" and not game.fishing_panel.visible:expanded_notice=""
	game.action_dock.strip.visible=game.action_dock.strip.visible and expanded_notice=="fish"
	game.action_dock.reopen_button.hide()
	refresh_card();refresh_context();refresh_notifications()
	context.visible=not game.chat.visible and not game.editor.visible and not game.atlas.visible and not game.resident_connections.visible and not game.participant_picker.visible
	# Chat is a focused surface: keep the bottom toggle available, never overlay its input.
	if not visible:game.status.hide()
	utility_actions.visible=not game.chat.visible
	if game.chat.visible:
		residents_panel.hide();notifications.hide();notification_toggle.hide();game.status.hide();context.hide();task.hide();return_button.hide()

func _process(delta:float)->void:
	hint_seconds+=delta
	if hint_seconds>=5 and not walk_hint_seen:walk_hint_seen=true;save_preference("walk_hint_seen",true)
	if not pointer_down.is_empty() and Time.get_ticks_msec()-int(pointer_down.at)>=600:show_card(pointer_down.id);pointer_down.clear()
	tick+=delta
	if tick>=.2:tick=0;refresh()
func _unhandled_input(event:InputEvent)->void:
	if event is InputEventKey and event.pressed and event.keycode==KEY_SPACE and game._camera_keys_allowed():game._return_to_player();get_viewport().set_input_as_handled()

func appetite_label(id:String)->String:
	var rank:int=game.world.hunger.rank(id)
	return "" if rank<0 else T(["hud.hunger_full","hud.hunger_peckish","hud.hunger_hungry","hud.hunger_very"][rank])
func refresh_locale()->void:
	_refresh_static(self)
	# Dialog inputs retain raw custom names and drafts. Only registered static text changes.
	for child in ui_root.get_children():
		if child is Window:
			_refresh_static(child)
			if not child.has_meta("locale_title") and _locale_static.has(child.title):child.set_meta("locale_title",_locale_static[child.title])
			if child.has_meta("locale_title"):child.title=T(str(child.get_meta("locale_title")))
	game.handbook_menu.text=T("hud.handbook");settings_menu.text=T("hud.settings")
	var popup:PopupMenu=game.handbook_menu.get_popup()
	for index in range(popup.item_count):
		var id:String=str(popup.get_item_metadata(index))
		if id=="relics":popup.set_item_text(index,T("hud.relics"))
		elif id=="wardrobe":popup.set_item_text(index,T("hud.wardrobe"))
		elif id=="opening_board":popup.set_item_text(index,T("theirs.goals"))
		else:
			for entry in config.handbook:
				if entry.id==id:popup.set_item_text(index,LocalText.content(entry.label))
	var settings:PopupMenu=settings_menu.get_popup()
	for index in range(settings.item_count):
		var id:int=settings.get_item_id(index)
		if _locale_static.has(settings.get_item_text(index)):settings.set_item_text(index,T(str(_locale_static[settings.get_item_text(index)])))
		if id==0:settings.set_item_text(index,T("ui.main.fullscreen_window"))
		elif id==1:settings.set_item_text(index,T("ui.main.sound_backups"))
		elif id==99:settings.set_item_text(index,T("ui.main.new_game_archive_and_restart"))
		elif id==90:settings.set_item_text(index,T("hud.my_appearance"))
		elif id==94:settings.set_item_text(index,T("hud.hunger_hints"))
		elif id in [96,97]:settings.set_item_text(index,T("camera.distance.original" if id==97 else "camera.distance.close"))
		elif id in [91,92,93]:settings.set_item_text(index,T("hud.interface_prefix")+T({91:"hud.size_small",92:"hud.size_standard",93:"hud.size_large"}[id]))
	context_signature="";notices_signature="";layout_residents();refresh()

func _position_handbook_popup()->void:
	var popup:PopupMenu=game.handbook_menu.get_popup()
	if not popup.visible:return
	var rect:Rect2=game.handbook_menu.get_global_rect()
	if rect.end.y+popup.size.y>get_viewport_rect().size.y:
		popup.position.y=roundi(maxf(0,rect.position.y-popup.size.y-4))

func _position_settings_popup()->void:
	var popup:PopupMenu=settings_menu.get_popup()
	if not popup.visible:return
	var rect:Rect2=settings_menu.get_global_rect()
	# Keep the releasing click over its opener, outside the menu's item area.
	if rect.end.y+popup.size.y>get_viewport_rect().size.y:
		popup.position.y=roundi(maxf(0,rect.position.y-popup.size.y-4))
