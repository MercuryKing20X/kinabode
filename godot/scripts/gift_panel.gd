extends PanelContainer
const LocalText=preload("res://scripts/localization.gd")
var _locale_static:Dictionary={}
func T(key:String)->String:
	var value:String=LocalText.text(key);_locale_static[value]=key;return value
func _refresh_static(node:Node)->void:
	if node is Label or (node is Button and not node is OptionButton):
		if not node.has_meta("locale_key") and _locale_static.has(node.text):node.set_meta("locale_key",_locale_static[node.text])
		if node.has_meta("locale_key"):node.text=T(str(node.get_meta("locale_key")))
	for child in node.get_children():_refresh_static(child)
var world: RefCounted
var receiver_id:=""
var picker: OptionButton
var quantity: SpinBox
var note: Label
var title: Label
var submitted: Callable
func setup(source: RefCounted,send: Callable) -> void:
	world=source;submitted=send;set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT);offset_left=-354;offset_right=-20;offset_top=-410;offset_bottom=-98
	var body:=VBoxContainer.new();body.add_theme_constant_override("separation",10);add_child(body)
	title=Label.new();title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;body.add_child(title)
	var caption:=Label.new();caption.text=T("hud.gift_hint");caption.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;body.add_child(caption)
	picker=OptionButton.new();picker.item_selected.connect(func(_index):refresh_quantity());body.add_child(picker)
	quantity=SpinBox.new();quantity.min_value=1;quantity.step=1;quantity.value=1;body.add_child(quantity)
	note=Label.new();note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;body.add_child(note)
	var row:=HBoxContainer.new();body.add_child(row)
	for action_id in ["send","close"]:
		var text:String=T("hud.send" if action_id=="send" else "hud.close")
		var button:=Button.new();button.focus_mode=Control.FOCUS_NONE;button.text=text;button.focus_mode=Control.FOCUS_NONE;row.add_child(button)
		if action_id=="close":button.pressed.connect(hide)
		else:button.pressed.connect(send_gift)
	hide()
	if not LocalText.events.changed.is_connected(refresh_locale):LocalText.events.changed.connect(refresh_locale)
func open(id: String) -> void:
	receiver_id=id;title.text=T("hud.gift_title") % LocalText.resident(world,id);picker.clear()
	for item in world.actors.human.carry:
		var name: String=str(world.farms.crops.get(item,{}).get("name",{"wood":T("hud.wood"),"mushroom":T("hud.mushroom")}.get(item,item)))
		picker.add_item(LocalText.content(name)+" ×"+str(int(world.actors.human.carry[item])));picker.set_item_metadata(picker.item_count-1,item)
	note.text=T("hud.empty_carry") if picker.item_count==0 else T("hud.gift_range")
	refresh_quantity();show()
func refresh_quantity() -> void:
	quantity.max_value=int(world.actors.human.carry.get(str(picker.get_item_metadata(picker.selected)),0)) if picker.item_count>0 else 1
func send_gift() -> void:
	if picker.item_count==0:return
	var result: Dictionary=submitted.call({"intent":"give","receiver_id":receiver_id,"item_id":str(picker.get_item_metadata(picker.selected)),"quantity":int(quantity.value)})
	note.text=LocalText.content(str(result.get("message",result.get("error",""))))
	if result.get("ok",false):hide()

func refresh_locale()->void:
	_refresh_static(self)
	if receiver_id.is_empty():return
	title.text=T("hud.gift_title") % LocalText.resident(world,receiver_id)
	for index in range(picker.item_count):
		var item:String=str(picker.get_item_metadata(index))
		var name:String=LocalText.content(str(world.farms.crops.get(item,{}).get("name",{"wood":LocalText.source("hud.wood"),"mushroom":LocalText.source("hud.mushroom")}.get(item,item))))
		picker.set_item_text(index,name+" ×"+str(int(world.actors.human.carry.get(item,0))))
