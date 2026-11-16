extends Control
const LocalText=preload("res://scripts/localization.gd")
signal deposit_all_requested
signal take_requested(item:String,quantity:int)
signal grill_requested(fish_id:String)
var world:RefCounted
var panel:PanelContainer
var carry_label:Label
var title:Label
var stock_title:Label
var rows:VBoxContainer
var deposit_button:Button
var close_button:Button
var refresh_revision:=-1
var inventory_signature:=0
func _process(_delta:float)->void:
	if visible and world!=null:
		var signature:int=hash([world.actors.human.carry,world.storage.saved(),world.fishing.fish])
		if signature!=inventory_signature:refresh()
var quantities:Dictionary={}
func setup(source:RefCounted)->void:
	world=source;set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);mouse_filter=Control.MOUSE_FILTER_STOP
	var shade:=ColorRect.new();shade.color=Color(0,0,0,.3);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);shade.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(shade)
	panel=PanelContainer.new();add_child(panel)
	var margin:=MarginContainer.new();for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,16)
	panel.add_child(margin);var body:=VBoxContainer.new();body.add_theme_constant_override("separation",10);margin.add_child(body)
	var header:=HBoxContainer.new();body.add_child(header);title=Label.new();title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(title)
	close_button=Button.new();close_button.text="×";close_button.custom_minimum_size=Vector2(40,36);close_button.pressed.connect(hide);header.add_child(close_button)
	carry_label=Label.new();carry_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;body.add_child(carry_label)
	deposit_button=Button.new();deposit_button.pressed.connect(func():deposit_all_requested.emit();refresh());body.add_child(deposit_button)
	stock_title=Label.new();body.add_child(stock_title)
	var scroll:=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;body.add_child(scroll)
	rows=VBoxContainer.new();rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(rows)
	resized.connect(_layout);get_viewport().size_changed.connect(_layout);LocalText.events.changed.connect(refresh);_layout();hide()
func _layout()->void:
	if panel==null:return
	var viewport_size:=get_viewport_rect().size
	var extent:=Vector2(minf(560,viewport_size.x-32),minf(580,viewport_size.y-40))
	panel.position=(viewport_size-extent)/2;panel.size=extent
func open()->void:
	refresh();_layout();show();move_to_front();deposit_button.grab_focus()
func _input(event:InputEvent)->void:
	if not visible:return
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
		hide();get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT and not panel.get_global_rect().has_point(event.position):
		hide();get_viewport().set_input_as_handled()
static func item_name(source:RefCounted,item:String)->String:
	if item in ["rose_red","rose_white","rose_yellow","rose_pink"]:return LocalText.text("flowers."+item.trim_prefix("rose_"))
	if item=="wood":return LocalText.text("hud.wood")
	if item=="mushroom":return LocalText.text("hud.mushroom")
	if item=="firefly.jar":return LocalText.text("storage.firefly_jar")
	var crop:String=item.trim_prefix("seed.")
	var name:String=LocalText.content(str(source.farms.crops.get(crop,{}).get("name",crop)))
	return LocalText.text("storage.seed_name")%name if item.begins_with("seed.") else name
func refresh()->void:
	if world==null or rows==null:return
	inventory_signature=hash([world.actors.human.carry,world.storage.saved(),world.fishing.fish])
	title.text=LocalText.text("storage.title");stock_title.text=LocalText.text("storage.stock");close_button.tooltip_text=LocalText.text("hud.close")
	var carried:Array=[];var carry:Dictionary=world.actors.human.carry
	var amount:=0
	for item in carry:
		amount+=int(carry[item]);carried.append(item_name(world,item)+" ×"+str(int(carry[item])))
	carry_label.text=LocalText.text("storage.carry")%[amount,world.work.CARRY_LIMIT]+"\n"+(" · ".join(carried) if not carried.is_empty() else LocalText.text("storage.empty"))
	deposit_button.text=LocalText.text("storage.deposit_all");deposit_button.disabled=amount==0
	for child in rows.get_children():rows.remove_child(child);child.queue_free()
	var items:Dictionary=world.storage.saved().items;var keys:=items.keys();keys.sort()
	var fish:Array=world.fishing.fish.values().filter(func(entry):return entry.owner_id=="human" and entry.location=="storage")
	if keys.is_empty() and fish.is_empty():var empty:=Label.new();empty.text=LocalText.text("storage.empty");rows.add_child(empty)
	for item in keys:
		if int(items[item])<=0:continue
		var row:=HBoxContainer.new();rows.add_child(row)
		var name:=Label.new();name.text=item_name(world,item)+" ×"+str(int(items[item]));name.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(name)
		var quantity:=SpinBox.new();quantity.min_value=1;quantity.max_value=maxi(1,mini(int(items[item]),world.work.carry_space("human")));quantity.value=mini(int(quantities.get(item,1)),int(quantity.max_value));quantity.custom_minimum_size.x=100;row.add_child(quantity)
		quantity.value_changed.connect(func(value):quantities[item]=int(value))
		var take:=Button.new();take.focus_mode=Control.FOCUS_NONE;take.text=LocalText.text("storage.take_out");take.disabled=world.work.carry_space("human")<=0;take.pressed.connect(func():take_requested.emit(item,int(quantity.value));refresh());row.add_child(take)
	for entry in fish:
		var row:=HBoxContainer.new();rows.add_child(row)
		var name:=Label.new();name.text=LocalText.content(world.fishing.describe(entry).species_name)+" ×1";name.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(name)
		var grill:=Button.new();grill.focus_mode=Control.FOCUS_NONE;grill.text=LocalText.text("hud.grill");grill.pressed.connect(_grill_fish.bind(str(entry.id)));row.add_child(grill)
func _grill_fish(id:String)->void:
	hide();grill_requested.emit(id)
