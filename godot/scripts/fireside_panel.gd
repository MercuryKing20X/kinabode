extends AcceptDialog
const LocalText=preload("res://scripts/localization.gd")
## Exactly two explicit host actions for the selected fire.
var host:WeakRef
var life:RefCounted
var body:VBoxContainer
var feedback:Label
var light_button:Button
var roast_button:Button
var invite_button:Button
var last_result:Dictionary={}
var feedback_until:=0
func setup(game:Node,station_id:String)->void:
	LocalText.events.changed.connect(refresh_locale)
	host=weakref(game);life=game.world.barbecues[station_id]
	title=(T("ui.bbq.home") if station_id=="home.barbecue" else T("ui.bbq.moon") if station_id=="moon.barbecue" else LocalText.content(str(life.station.get("name",T("ui.bbq.campfire")))))+T("ui.bbq.title_suffix");dialog_hide_on_ok=false
	theme=Theme.new();theme.default_font=game.view.font;theme.default_font_size=16
	if game.island_hud!=null:add_theme_stylebox_override("panel",game.island_hud.pixel_style())
	if life.fireside.state.get("suspended",false) and float(life.fireside.state.get("current",{}).get("meal_remaining",0))>0:
		var resume:=Button.new();resume.text=T("meal.timer.resume");resume.pressed.connect(func():show_result(life.fireside.resume_meal());if last_result.get("ok",false):resume.hide());resume.set_meta("resume_meal",true);add_child(resume)
	body=VBoxContainer.new();body.add_theme_constant_override("separation",14);add_child(body)
	for child in get_children():
		if child is Button and child.get_meta("resume_meal",false):child.reparent(body,false)
	feedback=Label.new();feedback.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;feedback.custom_minimum_size=Vector2(430,54);feedback.text=T("ui.bbq.intro");body.add_child(feedback)
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",12);body.add_child(row)
	light_button=Button.new();light_button.custom_minimum_size=Vector2(208,44);row.add_child(light_button)
	light_button.pressed.connect(func():game._camp_action(life.station.id,"light"))
	roast_button=Button.new();roast_button.text=T("ui.bbq.barbecue");roast_button.custom_minimum_size=Vector2(208,44);row.add_child(roast_button)
	roast_button.pressed.connect(func():hide();game._camp_action(life.station.id,"roast");queue_free())
	get_ok_button().hide();canceled.connect(queue_free);close_requested.connect(queue_free);refresh()
func _process(_delta:float)->void:
	if life!=null:refresh()
	if feedback_until>0 and Time.get_ticks_msec()>=feedback_until:
		feedback.text="";feedback_until=0
func refresh()->void:
	light_button.text=T("ui.bbq.refuel") if life.fireside.burning() else T("ui.bbq.light")
	var current:Dictionary=life.fireside.state.get("current",{})
	var needed:bool=life.fireside.waiting_meal()
	if needed and invite_button==null:
		invite_button=Button.new();invite_button.custom_minimum_size.y=44;body.add_child(invite_button)
		invite_button.pressed.connect(func():
			var game:Node=host.get_ref()
			if game!=null:hide();game._invite_barbecue(life.station.id);queue_free())
	elif not needed and invite_button!=null:
		body.remove_child(invite_button);invite_button.queue_free();invite_button=null
	if invite_button!=null:invite_button.text=T("ui.bbq.invite_cooling") if current.get("ready",false) and float(current.get("wait_elapsed",0))>=float(life.fireside.config.get("serve_wait_seconds",90))-15 else T("ui.bbq.invite")
func show_result(result:Dictionary)->void:
	feedback_until=Time.get_ticks_msec()+4000
	last_result=result.duplicate(true)
	feedback.text=str(result.get("message",result.get("error",T("ui.bbq.done"))))
	var game:Node=host.get_ref()
	if game!=null:game.status.text=feedback.text

var locale_labels:Dictionary={}
func T(key:String)->String:
	var result:=LocalText.text(key);locale_labels[LocalText.source(key)]=key;locale_labels[result]=key;locale_labels[str(LocalText.entries.get(key,{}).get("en",result))]=key;return result
func refresh_locale()->void:
	_refresh_locale_nodes(self)
	var station_id:String=life.station.id
	title=(T("ui.bbq.home") if station_id=="home.barbecue" else T("ui.bbq.moon") if station_id=="moon.barbecue" else LocalText.content(str(life.station.get("name",T("ui.bbq.campfire")))))+T("ui.bbq.title_suffix")
	refresh()
func _refresh_locale_nodes(node:Node)->void:
	for property in ["text","title","ok_button_text"]:
		if not node.get_property_list().any(func(p):return p.name==property):continue
		var value:Variant=node.get(property)
		if value is String and locale_labels.has(value):node.set(property,LocalText.text(locale_labels[value]))
	for child in node.get_children():_refresh_locale_nodes(child)
