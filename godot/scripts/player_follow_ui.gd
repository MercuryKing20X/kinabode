extends Node
const LocalText=preload("res://scripts/localization.gd")
var _locale_static:Dictionary={}
func T(key:String)->String:
	var value:String=LocalText.text(key);_locale_static[value]=key;return value
func _refresh_static(node:Node)->void:
	if node is Label or (node is Button and not node is OptionButton):
		if not node.has_meta("locale_key") and _locale_static.has(node.text):node.set_meta("locale_key",_locale_static[node.text])
		if node.has_meta("locale_key"):node.text=T(str(node.get_meta("locale_key")))
	for child in node.get_children():_refresh_static(child)
## Explicit player selection; session-only. ResidentActivity reuses Hunger/World routes.
var game:Node
var menu:AcceptDialog
var all_box:CheckBox
var checks:Dictionary={}
var follow_note:Label
func setup(host:Node)->void:
	game=host
	if not LocalText.events.changed.is_connected(refresh_locale):LocalText.events.changed.connect(refresh_locale)
func open()->void:
	game.chat.hide();game.chat_input.release_focus()
	if game.resident_connections!=null:game.resident_connections.close_panel()
	if is_instance_valid(menu):menu.hide();menu.queue_free()
	menu=AcceptDialog.new();menu.get_ok_button().set_meta("audio_primary",true);menu.title=T("hud.follow_title");menu.ok_button_text=T("hud.follow_close");game.add_child(menu)
	preload("res://scripts/invitation_common.gd").style_dialog(menu,game.view.font,game.island_hud.pixel_style() if game.island_hud!=null else null,false)
	var body:=VBoxContainer.new();body.custom_minimum_size.x=280;menu.add_child(body)
	all_box=preload("res://scripts/invitation_common.gd").add_all(body);checks.clear()
	var scroll:=ScrollContainer.new();scroll.custom_minimum_size=Vector2(280,mini(320,maxi(80,(game.world.actors.size()-1)*44+8)));body.add_child(scroll)
	var rows:=VBoxContainer.new();rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(rows)
	for id in game.world.actors:
		if id=="human":continue
		var box:=CheckBox.new();box.focus_mode=Control.FOCUS_NONE;box.text=LocalText.resident(game.world,id);box.button_pressed=game.world.activities.following.has(id);box.disabled=not game.world.residents.supports(game.world.actors[id],"move");box.custom_minimum_size.y=40;rows.add_child(box);checks[id]=box
	preload("res://scripts/invitation_common.gd").bind_all(all_box,checks.values())
	all_box.set_pressed_no_signal(not checks.is_empty() and checks.values().filter(func(box):return not box.disabled).all(func(box):return box.button_pressed))
	var note:=Label.new();follow_note=note;note.text=T("hud.follow_hint");body.add_child(note)
	for box in checks.values():box.toggled.connect(func(_value):apply())
	all_box.toggled.connect(func(_value):apply())
	menu.popup_centered()
func apply()->void:
	var ids:Array=checks.keys().filter(func(id):return checks[id].button_pressed)
	for id in checks:
		if id in ids:game.world.activities.default_follow_excluded.erase(id)
		else:game.world.activities.default_follow_excluded[id]=true
	for id in ids:
		if not game.world.activities.following.has(id):game._cancel_resident_turn(id)
	var result:Dictionary=game.world.activities.set_followers(ids)
	game.status.text=LocalText.content(str(result.get("message",result.get("error",""))));game._refresh_gathering()

func refresh_locale()->void:
	if not is_instance_valid(menu):return
	menu.title=T("hud.follow_title");menu.ok_button_text=T("hud.follow_close")
	if is_instance_valid(follow_note):follow_note.text=T("hud.follow_hint")
	for id in checks:
		if is_instance_valid(checks[id]):checks[id].text=LocalText.resident(game.world,id)
