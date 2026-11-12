extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
## Shared visual and selection component; it never starts a task itself.
static func style_dialog(dialog:Window,font:Font,panel:StyleBox,large:bool)->void:
	var theme:=Theme.new();theme.default_font=font;theme.default_font_size=18 if large else 16;dialog.theme=theme
	if panel!=null:dialog.add_theme_stylebox_override("panel",panel)
static func add_all(parent:Node)->CheckBox:
	var box:=CheckBox.new();box.focus_mode=Control.FOCUS_NONE;box.text=LocalText.text("hud.all");box.custom_minimum_size.y=42;parent.add_child(box)
	var callback:Callable=func():
		if is_instance_valid(box):box.text=LocalText.text("hud.all")
	LocalText.events.changed.connect(callback)
	box.tree_exiting.connect(func():
		if LocalText.events.changed.is_connected(callback):LocalText.events.changed.disconnect(callback))
	return box
static func bind_all(all_box:CheckBox,boxes:Array)->void:
	for box in boxes:
		box.toggled.connect(func(_value):all_box.set_pressed_no_signal(not boxes.is_empty() and boxes.filter(func(item):return not item.disabled).all(func(item):return item.button_pressed)))
	all_box.toggled.connect(func(value):
		for box in boxes:
			if not box.disabled:box.set_pressed_no_signal(value))
static func skipped_message(world:RefCounted,reasons:Dictionary)->String:
	var lines:PackedStringArray=[]
	for id in reasons:
		if world.actors.has(id):lines.append(LocalText.text("hud.absent") % [LocalText.resident(world,id),LocalText.content(str(reasons[id]))])
	return "；".join(lines)
