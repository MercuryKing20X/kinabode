extends Control
## Input-only view: material commits and routing belong to FlowerCreation.
const L=preload("res://scripts/localization.gd")
signal action_requested(args:Dictionary)
signal placement_requested(args:Dictionary)
var panel:PanelContainer
var color_picker:OptionButton
var quantity:SpinBox
var text_input:LineEdit
var pattern_picker:OptionButton
var trade_button:Button
var arrange_button:Button
var single_button:Button
var pick_button:Button
var close_button:Button
var stock:Label
var message:Label
var actor_label:Label
var colors:=["red","white","yellow","pink"]
var patterns:=["heart","star","smile","sun","flower","arrow"]
var actor_id:="human"
func setup()->void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);mouse_filter=Control.MOUSE_FILTER_STOP
	var shade:=ColorRect.new();shade.color=Color(0,0,0,.3);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);shade.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(shade)
	panel=PanelContainer.new();add_child(panel)
	var margin:=MarginContainer.new();panel.add_child(margin)
	for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,18)
	var body:=VBoxContainer.new();body.add_theme_constant_override("separation",10);margin.add_child(body)
	var head:=HBoxContainer.new();body.add_child(head)
	actor_label=Label.new();actor_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;head.add_child(actor_label)
	close_button=Button.new();close_button.text="×";close_button.custom_minimum_size=Vector2(38,34);head.add_child(close_button);close_button.pressed.connect(hide)
	stock=Label.new();stock.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;body.add_child(stock)
	color_picker=OptionButton.new();body.add_child(color_picker)
	var trade:=HBoxContainer.new();body.add_child(trade)
	quantity=SpinBox.new();quantity.min_value=2;quantity.max_value=800;quantity.step=2;quantity.value=10;quantity.size_flags_horizontal=Control.SIZE_EXPAND_FILL;trade.add_child(quantity)
	trade_button=Button.new();trade.add_child(trade_button);trade_button.pressed.connect(func():action_requested.emit({"intent":"trade_flowers","color":colors[color_picker.selected],"quantity":int(quantity.value)}))
	text_input=LineEdit.new();text_input.max_length=6;body.add_child(text_input)
	pattern_picker=OptionButton.new();body.add_child(pattern_picker)
	arrange_button=Button.new();body.add_child(arrange_button);arrange_button.pressed.connect(func():
		var args:Dictionary={"intent":"arrange_flowers","color":colors[color_picker.selected]}
		if text_input.text.strip_edges().is_empty():args.pattern=patterns[pattern_picker.selected]
		else:args.text=text_input.text.strip_edges().to_upper()
		placement_requested.emit(args);hide())
	var row:=HBoxContainer.new();body.add_child(row)
	single_button=Button.new();single_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(single_button);single_button.pressed.connect(func():placement_requested.emit({"intent":"place_flower","color":colors[color_picker.selected]});hide())
	pick_button=Button.new();pick_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(pick_button);pick_button.pressed.connect(func():placement_requested.emit({"intent":"pick_flower"});hide())
	message=Label.new();message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;body.add_child(message)
	resized.connect(_layout);get_viewport().size_changed.connect(_layout);L.events.changed.connect(refresh);refresh();_layout();hide()
func _layout()->void:
	if panel==null:return
	var extent:=Vector2(minf(520,get_viewport_rect().size.x-32),minf(560,get_viewport_rect().size.y-40))
	panel.position=(get_viewport_rect().size-extent)/2;panel.size=extent
func refresh()->void:
	actor_label.text=L.text("flowers.title");close_button.tooltip_text=L.text("hud.close")
	var c:=color_picker.selected;var p:=pattern_picker.selected;color_picker.clear();pattern_picker.clear()
	for color in colors:color_picker.add_item(L.text("flowers."+color))
	for pattern in patterns:pattern_picker.add_item(L.text("flowers."+pattern))
	color_picker.select(maxi(0,c));pattern_picker.select(maxi(0,p))
	trade_button.text=L.text("flowers.trade");text_input.placeholder_text=L.text("flowers.text_hint");arrange_button.text=L.text("flowers.arrange");single_button.text=L.text("flowers.single");pick_button.text=L.text("flowers.pick");message.text=L.text("flowers.instructions")
func open(who:String,summary:String,can_trade:bool=true)->void:
	actor_id=who;refresh();stock.text=summary;trade_button.visible=can_trade;quantity.visible=can_trade;_layout();show();move_to_front();color_picker.grab_focus()
func _process(_delta:float)->void:
	if visible:_layout()
func _input(event:InputEvent)->void:
	if not visible:return
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:hide();get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT and not panel.get_global_rect().has_point(event.position):hide();get_viewport().set_input_as_handled()
