class_name AIConnectPanel
extends AcceptDialog
const LocalText=preload("res://scripts/localization.gd")
signal bind_requested(actor_id: String, external: bool)
var world: RefCounted
var data_dir: String
var actors: OptionButton
var text: RichTextLabel
var note: Label
func setup(source: RefCounted,directory: String) -> void:
	world=source;data_dir=directory;title=LocalText.text("ui.ai_connect_panel.connect_your_own_ai");size=Vector2i(640,460)
	# Bound the dialog independently of wrapped text's transient minimum height.
	var frame:=Control.new();frame.custom_minimum_size=Vector2(600,360);add_child(frame)
	var body:=VBoxContainer.new();frame.add_child(body);body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	actors=OptionButton.new();body.add_child(actors);actors.item_selected.connect(func(_index):refresh())
	text=RichTextLabel.new();text.fit_content=false;text.selection_enabled=true;text.scroll_active=true;text.custom_minimum_size=Vector2(0,180);text.size_flags_vertical=Control.SIZE_EXPAND_FILL;body.add_child(text)
	var buttons:=HBoxContainer.new();body.add_child(buttons)
	var connect:=Button.new();connect.focus_mode=Control.FOCUS_NONE;connect.text=LocalText.text("ui.ai_connect_panel.connect_external_ai_and_copy_settings");buttons.add_child(connect)
	connect.pressed.connect(func():
		if actors.item_count==0:return
		bind_requested.emit(str(actors.get_item_metadata(actors.selected)),true))
	var original:=Button.new();original.focus_mode=Control.FOCUS_NONE;original.text=LocalText.text("ui.ai_connect_panel.back_to_the_original_connection");buttons.add_child(original)
	original.pressed.connect(func():
		if actors.item_count>0:bind_requested.emit(str(actors.get_item_metadata(actors.selected)),false))
	note=Label.new();note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;note.text=LocalText.text("ui.ai_connect_panel.ai_clients_that_support_mcp_can_use_the_settings");body.add_child(note)
func open() -> void:
	actors.clear()
	for actor in world.actors.values():
		if not world.director.model_controlled(actor.id):continue
		actors.add_item(LocalText.resident(world,str(actor.id)));actors.set_item_metadata(actors.item_count-1,actor.id)
	refresh();popup_centered(Vector2i(640,460))
func configuration() -> Dictionary:
	if actors.item_count==0:return {}
	var python:=OS.get_environment("HABITAT_PYTHON")
	if python.is_empty():python="/usr/bin/python3"
	var script: String=ProjectSettings.globalize_path("res://").path_join("../scripts/habitat_godot.py").simplify_path()
	return {"mcpServers":{"youqi":{"command":python,"args":[script,"--data-dir",data_dir,"--resident",str(actors.get_item_metadata(actors.selected)),"--world",world.world_id,"mcp"]}}}
func refresh() -> void:
	text.text=JSON.stringify(configuration(),"  ") if actors.item_count>0 else LocalText.text("ui.ai_connect_panel.first_choose_this_resident_s_model_connection_in_resident")
