extends HFlowContainer
const Prefs=preload("res://scripts/resident_intelligence_preferences.gd")
const Text=preload("res://scripts/localization.gd")
var prefs:RefCounted
var actor:=""
var stamp:=""
func setup(base:String,identity:String,id:String)->void:
	var pool:Node=preload("res://scripts/connection_session_pool.gd").obtain(get_tree(),base)
	prefs=pool.shared_preferences
	if prefs==null:prefs=Prefs.new();prefs.setup(base,identity)
	actor=id;refresh()
func _process(_delta:float)->void:
	if not is_visible_in_tree() or prefs==null:return
	prefs.settings.load(prefs.path)
	if stamp!=prefs.preference(actor).level+TranslationServer.get_locale():refresh()
func refresh()->void:
	stamp=prefs.preference(actor).level+TranslationServer.get_locale()

	var names:Array=[Text.text("content.overnight.text.2b81dc69db797a"),Text.text("content.overnight.text.6bea77acefb364"),Text.text("content.overnight.text.e952e0cafb0e8a"),"Ultra",Text.text("content.overnight.text.22c2d7c2ee6997")] if TranslationServer.get_locale().begins_with("zh") else ["Light","Standard","Deep","Ultra","Lifeblood"]
	var button:MenuButton
	if get_child_count()==0:
		button=MenuButton.new();add_child(button);button.flat=false;button.focus_mode=Control.FOCUS_NONE
		button.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
		button.action_mode=BaseButton.ACTION_MODE_BUTTON_RELEASE
		for name_text in names:button.get_popup().add_item(name_text)
		button.get_popup().id_pressed.connect(func(index):choose(Prefs.LEVELS[index]))
	else:button=get_child(0)
	button.text=(Text.text("content.overnight.text.fa173dc0680a2a") if TranslationServer.get_locale().begins_with("zh") else "Level: ")+str(names[maxi(0,Prefs.LEVELS.find(prefs.preference(actor).level))])
	for i in names.size():button.get_popup().set_item_text(i,names[i])
func choose(level:String)->void:
	prefs.settings.load(prefs.path)
	if level!="lifeblood":prefs.choose(actor,level);refresh();return
	var dialog:=ConfirmationDialog.new();add_child(dialog);dialog.title=Text.text("life.level")
	var body:=VBoxContainer.new();dialog.add_child(body)
	var warning:=Label.new();warning.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;warning.custom_minimum_size.x=500
	var estimate:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/autonomy.json")).lifeblood_estimate
	warning.text=Text.text("life.warning")%(float(estimate.tokens_per_turn)*120.0/10000.0);body.add_child(warning)
	var ack:=CheckBox.new();ack.text=Text.text("content.overnight.text.348f1cf1243e74") if TranslationServer.get_locale().begins_with("zh") else "I understand";body.add_child(ack)
	dialog.get_ok_button().disabled=true;ack.toggled.connect(func(on):dialog.get_ok_button().disabled=not on)
	dialog.confirmed.connect(func():
		if ack.button_pressed:prefs.choose(actor,level);prefs.enable_autonomy(actor,true);refresh()
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free);dialog.popup_centered(Vector2i(550,260))
