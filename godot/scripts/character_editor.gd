class_name CharacterEditor
extends PanelContainer
const LocalText=preload("res://scripts/localization.gd")
var _locale_static:Dictionary={}
func T(key:String)->String:
	var value:String=LocalText.text(key);_locale_static[value]=key;return value
func _mark_static(node:Node)->void:
	var fields:Array=[]
	if node is Label or (node is Button and not node is OptionButton):fields.append("text")
	if node is Window:fields.append("title")
	if node is AcceptDialog:fields.append_array(["dialog_text","ok_button_text"])
	if node is ConfirmationDialog:fields.append("cancel_button_text")
	if node is LineEdit:fields.append("placeholder_text")
	for field in fields:
		if _locale_static.has(str(node.get(field))):node.set_meta("workshop_locale_"+field,_locale_static[str(node.get(field))])
	for child in node.get_children():_mark_static(child)
func _refresh_static(node:Node)->void:
	for field in ["text","title","dialog_text","ok_button_text","cancel_button_text","placeholder_text"]:
		if node.has_meta("workshop_locale_"+field):node.set(field,T(str(node.get_meta("workshop_locale_"+field))))
	for child in node.get_children():_refresh_static(child)

signal applied
signal blueprint_requested(id: String)
const Canvas = preload("res://scripts/pixel_canvas.gd")
const Catalog = preload("res://scripts/workshop_catalog.gd")
var file_menu_button:MenuButton
var library: RefCounted
var canvas: Control
var character_id := ""
var base_revision := 0
var drafts: Dictionary = {}
var last_work: Dictionary = {}
var dirty := false
var category := "character"
var group := LocalText.source("content.workshop.appearance")
var action := LocalText.source("content.workshop.standing")
var direction := "down"
var category_tabs: TabBar
var work_name: LineEdit
var work_picker: OptionButton
var group_picker: OptionButton
var action_picker: OptionButton
var direction_picker: OptionButton
var character_filters: HBoxContainer
var layer_picker: OptionButton
var frame_picker: OptionButton
var frame_label: Label
var feedback: Label
var draft_label: Label
var context_label: Label
var preview: TextureRect
var layer_name: LineEdit
var preview_playing := false
var preview_clock := 0.0
var preview_frame := ""
var play_button: Button
var structure_panel: VBoxContainer
var structure_inputs: Dictionary = {}
var structure_toggle: Button
var quote_label: Label
var use_blueprint: Button
var scroll: ScrollContainer
var canvas_host: Control
var color_picker: ColorPickerButton
var discard_dialog: ConfirmationDialog
var pending_discard := ""
var rename_row: HBoxContainer
var resident_picker: OptionButton
var resident_name: LineEdit
var template_dialog: AcceptDialog
var template_button: Button
var import_dialog: FileDialog
var export_dialog: FileDialog
var _syncing := false
var outfit_toggle: Button
var outfit_panel: VBoxContainer
var outfit_palette: OptionButton
var outfit_target: OptionButton
var outfit_checks: Dictionary = {}
var outfit_palette_icons: Dictionary = {}
var assembler_dialog: AcceptDialog
var assembler_preset: OptionButton
var assembler_parts: Dictionary = {}

func setup(store: RefCounted) -> void:
	library = store
	mouse_filter = Control.MOUSE_FILTER_STOP
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation", 10); margin.add_child(column)
	var header := HBoxContainer.new(); column.add_child(header)
	var title := Label.new(); title.text = T("content.workshop.pixel_workshop"); title.add_theme_font_size_override("font_size", 24); header.add_child(title)
	draft_label = Label.new(); draft_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; draft_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; draft_label.add_theme_font_size_override("font_size", 13); header.add_child(draft_label)
	button(header, T("content.workshop.close"), close_workshop)
	category_tabs = TabBar.new(); category_tabs.add_tab(T("content.workshop.characters")); category_tabs.add_tab(T("content.workshop.buildings")); category_tabs.add_tab(T("content.workshop.facilities")); category_tabs.add_tab(T("content.workshop.plants")); category_tabs.tab_alignment = TabBar.ALIGNMENT_LEFT; column.add_child(category_tabs)
	for state in ["tab_selected", "tab_unselected", "tab_hovered"]:
		var tab_style := StyleBoxFlat.new(); tab_style.bg_color = Color("416755") if state == "tab_selected" else Color("2c4b40") if state == "tab_hovered" else Color("243e35")
		tab_style.set_corner_radius_all(7); tab_style.content_margin_left = 22; tab_style.content_margin_right = 22; tab_style.content_margin_top = 8; tab_style.content_margin_bottom = 8
		category_tabs.add_theme_stylebox_override(state, tab_style)
	category_tabs.add_theme_font_size_override("font_size", 18)
	category_tabs.add_theme_color_override("font_selected_color", Color("fff0c9"))
	category_tabs.tab_changed.connect(func(index): if not _syncing: select_category(Catalog.KINDS[index]))
	var selection := HBoxContainer.new(); column.add_child(selection)
	work_picker = OptionButton.new(); work_picker.custom_minimum_size.x = 160; selection.add_child(work_picker)
	work_picker.item_selected.connect(func(index): open_art(str(work_picker.get_item_metadata(index))))
	work_name=LineEdit.new();work_name.placeholder_text=T("content.workshop.work_name");work_name.max_length=48;work_name.custom_minimum_size.x=150;selection.add_child(work_name)
	work_name.text_changed.connect(func(value):
		if not _syncing:canvas.art.name=value.strip_edges();_mark_dirty())
	context_label = Label.new(); context_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; context_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; context_label.add_theme_font_size_override("font_size", 13); selection.add_child(context_label)
	var tools_row:=HFlowContainer.new();column.add_child(tools_row)
	button(tools_row,T("content.workshop.new_blank"),func():_duplicate_work(true))
	button(tools_row,T("content.workshop.assemble_character"),_open_assembler)
	button(tools_row,T("content.workshop.duplicate_work"),func():_duplicate_work(false))
	button(tools_row,T("content.workshop.import"),func():import_dialog.popup_centered_ratio(.7))
	button(tools_row,T("content.workshop.export"),func():export_dialog.current_file=character_id+".json";export_dialog.popup_centered_ratio(.7))
	template_button=button(tools_row,T("content.workshop.purpose_seats_materials"),func():template_dialog.open_config())
	var file_menu:=MenuButton.new();file_menu_button=file_menu;file_menu.text=T("content.workshop.file");column.add_child(file_menu);column.move_child(file_menu, tools_row.get_index())
	var file_popup:=file_menu.get_popup()
	var file_buttons:=tools_row.get_children()
	for item in file_buttons:
		file_popup.add_item(item.text)
		if _locale_static.has(item.text):file_popup.set_meta("workshop_item_"+str(file_popup.item_count-1),_locale_static[item.text])
	file_popup.id_pressed.connect(func(index):
		if index==5 and not template_button.visible:feedback.text=T("content.workshop.this_work_has_no_purpose_or_seating_configuration");return
		if index>=0 and index<file_buttons.size():file_buttons[index].pressed.emit())
	tools_row.hide()
	template_dialog=preload("res://scripts/template_editor.gd").new();add_child(template_dialog);template_dialog.setup(self)
	assembler_dialog = AcceptDialog.new(); assembler_dialog.title = T("content.workshop.assemble_a_new_character"); add_child(assembler_dialog)
	var assembler_box := VBoxContainer.new(); assembler_dialog.add_child(assembler_box)
	assembler_preset = OptionButton.new(); assembler_box.add_child(assembler_preset)
	for name in preload("res://scripts/character_assembler.gd").PRESETS:assembler_preset.add_item(LocalText.content(name));assembler_preset.set_item_metadata(assembler_preset.item_count-1,name)
	assembler_preset.item_selected.connect(func(_index): _assembler_apply_preset())
	for part in preload("res://scripts/character_assembler.gd").PARTS:
		var row := HBoxContainer.new(); assembler_box.add_child(row)
		var label := Label.new(); label.text = {"head":T("content.workshop.head"), "hair":T("content.workshop.hair"), "top":T("content.workshop.top"), "bottom":T("content.workshop.bottom"), "shoes":T("content.workshop.shoes"), "accessory":T("content.workshop.accessory")}[part]; row.add_child(label)
		var picker := OptionButton.new();picker.focus_mode=Control.FOCUS_NONE; picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(picker); assembler_parts[part] = picker
	button(assembler_box, T("content.workshop.create_independent_work"), _assemble_character)
	import_dialog=FileDialog.new();import_dialog.access=FileDialog.ACCESS_FILESYSTEM;import_dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILE;import_dialog.add_filter("*.json",T("content.workshop.pixel_artwork"));add_child(import_dialog)
	import_dialog.file_selected.connect(func(path):
		var result: Dictionary=library.import_work(path)
		if result.ok:open_art(result.id)
		else:feedback.text=T("content.workshop.import_failed")+str(result.error))
	export_dialog=FileDialog.new();export_dialog.access=FileDialog.ACCESS_FILESYSTEM;export_dialog.file_mode=FileDialog.FILE_MODE_SAVE_FILE;export_dialog.add_filter("*.json",T("content.workshop.pixel_artwork"));add_child(export_dialog)
	export_dialog.file_selected.connect(func(path):feedback.text=T("content.workshop.work_exported") if library.export_work(canvas.art,path) else T("content.workshop.export_failed"))
	rename_row=HBoxContainer.new();column.add_child(rename_row);resident_picker=OptionButton.new();rename_row.add_child(resident_picker)
	resident_name=LineEdit.new();resident_name.placeholder_text=T("content.workshop.resident_name");resident_name.max_length=24;rename_row.add_child(resident_name)
	resident_picker.item_selected.connect(func(index):resident_name.text=library.resident_world.actors[resident_picker.get_item_metadata(index)].name)
	button(rename_row,T("content.workshop.rename"),_rename_resident)
	button(rename_row,T("content.workshop.give_her_this_appearance"),_assign_appearance)
	character_filters = HBoxContainer.new(); column.add_child(character_filters)
	group_picker = OptionButton.new(); action_picker = OptionButton.new(); direction_picker = OptionButton.new()
	for picker in [group_picker, action_picker, direction_picker]:
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL; character_filters.add_child(picker)
	group_picker.item_selected.connect(func(index): group = str(group_picker.get_item_metadata(index)); action = ""; _rebuild_filters(false))
	action_picker.item_selected.connect(func(index): action = str(action_picker.get_item_metadata(index)); _rebuild_filters(false))
	direction_picker.item_selected.connect(func(index): direction = str(direction_picker.get_item_metadata(index)); _rebuild_filters(false))
	var frames_row := HBoxContainer.new(); column.add_child(frames_row)
	frame_label = Label.new(); frame_label.text = T("content.workshop.animation_frames"); frames_row.add_child(frame_label)
	frame_picker = OptionButton.new(); frame_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL; frames_row.add_child(frame_picker)
	frame_picker.item_selected.connect(func(index): _select_frame(str(frame_picker.get_item_metadata(index))))
	var body := HBoxContainer.new(); body.add_theme_constant_override("separation", 18); body.size_flags_vertical = Control.SIZE_EXPAND_FILL; column.add_child(body)
	canvas_host = Control.new(); canvas_host.custom_minimum_size = Vector2(250, 170); canvas_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL; canvas_host.size_flags_vertical = Control.SIZE_EXPAND_FILL; body.add_child(canvas_host)
	canvas_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas = Canvas.new(); canvas.library = store; canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; canvas_host.add_child(canvas)
	canvas_host.resized.connect(_fit_canvas)
	scroll = ScrollContainer.new(); scroll.custom_minimum_size.x = 324; scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; body.add_child(scroll)
	var tools := VBoxContainer.new(); tools.size_flags_horizontal = Control.SIZE_EXPAND_FILL; tools.custom_minimum_size.x = 306; tools.add_theme_constant_override("separation", 8); scroll.add_child(tools)
	var canvas_title:=Label.new();canvas_title.text=T("content.workshop.canvas_tools");tools.add_child(canvas_title)
	outfit_toggle = button(tools, T("content.workshop.clothing_regions"), func(): outfit_panel.visible = not outfit_panel.visible; outfit_toggle.text = T("content.workshop.clothing_regions_35") if outfit_panel.visible else T("content.workshop.clothing_regions"))
	outfit_panel = VBoxContainer.new(); tools.add_child(outfit_panel); outfit_panel.hide()
	button(outfit_panel, T("content.workshop.create_clothing_regions_for_this_character"), _create_outfit)
	outfit_palette = OptionButton.new(); outfit_panel.add_child(outfit_palette)
	for part in ["top", "bottom", "shoes", "head"]:
		var row := HBoxContainer.new(); outfit_panel.add_child(row)
		var enabled := CheckBox.new();enabled.focus_mode=Control.FOCUS_NONE; enabled.text = {"top":T("content.workshop.top"), "bottom":T("content.workshop.bottom"), "shoes":T("content.workshop.shoes"), "head":T("content.workshop.headwear")}[part]; row.add_child(enabled)
		enabled.toggled.connect(func(value): _toggle_outfit(part, value))
		outfit_checks[part] = enabled
		button(row, T("content.workshop.use_selected_color"), func(): _recolor_outfit(part))
	outfit_target = OptionButton.new(); outfit_panel.add_child(outfit_target)
	button(outfit_panel, T("content.workshop.copy_full_set_to_selected_work"), _copy_outfit)
	structure_toggle = button(tools, T("content.workshop.structure_materials"), func(): structure_panel.visible = not structure_panel.visible; structure_toggle.text = T("content.workshop.structure_materials_41") if structure_panel.visible else T("content.workshop.structure_materials"))
	structure_panel = VBoxContainer.new(); tools.add_child(structure_panel)
	var dimensions := HBoxContainer.new(); structure_panel.add_child(dimensions)
	for key in ["width", "depth", "floors", "porch"]:
		var field := VBoxContainer.new(); dimensions.add_child(field)
		var label := Label.new(); label.text = {"width": T("content.workshop.width"), "depth": T("content.workshop.depth"), "floors": T("content.workshop.floors"), "porch": T("content.workshop.porch")}[key]; field.add_child(label)
		var input := SpinBox.new(); input.min_value = {"width": 4, "depth": 4, "floors": 1, "porch": 0}[key]; input.max_value = {"width": 10, "depth": 8, "floors": 2, "porch": 2}[key]; input.step = 1; field.add_child(input)
		input.value_changed.connect(func(value): if not _syncing: canvas.art.structure[key] = int(value); _mark_dirty(); _quote())
		structure_inputs[key] = input
	quote_label = Label.new(); quote_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; quote_label.custom_minimum_size.x = 300; structure_panel.add_child(quote_label)
	layer_picker = OptionButton.new(); tools.add_child(layer_picker); layer_picker.item_selected.connect(func(index): canvas.layer = index)
	layer_name = LineEdit.new(); layer_name.placeholder_text = T("content.workshop.new_layer_name"); tools.add_child(layer_name)
	var layers := HFlowContainer.new(); tools.add_child(layers)
	button(layers, T("content.workshop.add_layer"), _add_layer); button(layers, T("content.workshop.show_hide"), _visibility); button(layers, T("content.workshop.delete_layer"), _delete_layer)
	button(layers, T("content.workshop.clear_layer"), func(): canvas.checkpoint(); canvas.art.frames[canvas.frame][canvas.layer].pixels.fill(0); canvas.refresh())
	color_picker = ColorPickerButton.new(); color_picker.color = canvas.color; color_picker.custom_minimum_size = Vector2(100, 30); tools.add_child(color_picker)
	color_picker.color_changed.connect(func(color): canvas.color = color; canvas.eraser = false)
	var brushes := HBoxContainer.new(); tools.add_child(brushes)
	button(brushes, T("content.workshop.brush"), func(): canvas.eraser = false; canvas.fill_tool = false)
	button(brushes, T("content.workshop.eraser"), func(): canvas.eraser = true; canvas.fill_tool = false)
	button(brushes, T("content.workshop.fill"), func(): canvas.eraser = false; canvas.fill_tool = true)
	var undo_row := HBoxContainer.new(); tools.add_child(undo_row)
	button(undo_row, T("content.workshop.undo"), func(): canvas.undo(); _sync_frame_navigation(); _layers(); _refresh_outfit())
	button(undo_row, T("content.workshop.redo"), func(): canvas.redo(); _sync_frame_navigation(); _layers(); _refresh_outfit())
	var preview_row := HBoxContainer.new(); tools.add_child(preview_row)
	preview = TextureRect.new(); preview.custom_minimum_size = Vector2(90, 108); preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; preview_row.add_child(preview)
	play_button = button(preview_row, T("content.workshop.play_preview"), _toggle_preview)
	tools.move_child(preview_row, 2)
	canvas.changed.connect(func(): preview.texture = canvas._image; preview_frame = ""; _layers())
	canvas.edited.connect(_mark_dirty)
	var draft_actions := HFlowContainer.new(); tools.add_child(draft_actions);draft_actions.hide()
	var save_toggle:=button(tools,T("content.workshop.save"),func():draft_actions.visible=not draft_actions.visible)
	tools.move_child(save_toggle,draft_actions.get_index())
	button(draft_actions, T("content.workshop.load_saved_version"), func(): _request_discard("reload"))
	button(draft_actions, T("content.workshop.undo_last_application"), func(): _request_discard("undo_publish"))
	use_blueprint = button(structure_panel, T("content.workshop.use_saved_template_on_selected_plot"), func(): blueprint_requested.emit(character_id))
	feedback = Label.new(); feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; feedback.add_theme_font_size_override("font_size", 13)
	var footer := HBoxContainer.new(); column.add_child(footer)
	feedback.size_flags_horizontal=Control.SIZE_EXPAND_FILL;footer.add_child(feedback)
	button(footer, T("content.workshop.save_and_apply"), _publish)
	discard_dialog = ConfirmationDialog.new(); discard_dialog.title = T("content.workshop.discard_this_unapplied_draft"); discard_dialog.dialog_text = T("content.workshop.only_this_work_s_draft_is_affected_other_drafts_stay_safe"); discard_dialog.ok_button_text = T("content.workshop.discard_and_continue"); discard_dialog.cancel_button_text = T("content.workshop.keep_draft"); add_child(discard_dialog)
	discard_dialog.confirmed.connect(func(): _discard_action())
	get_viewport().size_changed.connect(_layout)
	_layout(); hide()

	_mark_static(self)
	if not LocalText.events.changed.is_connected(refresh_locale):LocalText.events.changed.connect(refresh_locale)

func button(parent: Node, text: String, callback: Callable) -> Button:
	var b := Button.new();b.focus_mode=Control.FOCUS_NONE; b.text = text; b.focus_mode = Control.FOCUS_NONE; b.pressed.connect(callback); parent.add_child(b); return b

func _layout() -> void:
	var available := get_viewport_rect().size
	var is_v3:bool=library.resident_world!=null and library.resident_world.catalog.manifest.get("template_id", "") == "home-v3"
	size = Vector2(minf(1060, available.x - 48), maxf(400, available.y - (75 if is_v3 else 185)))
	position = Vector2((available.x - size.x) / 2, 10 if is_v3 else 105)
	_fit_canvas()

func _fit_canvas() -> void:
	if canvas == null or canvas.art.is_empty(): return
	var available: Vector2 = canvas_host.size
	canvas.pixel_scale = maxf(.1, minf((available.x - 16) / float(canvas.art.width), (available.y - 16) / float(canvas.art.height)))
	canvas.size = Vector2(canvas.art.width, canvas.art.height) * canvas.pixel_scale
	canvas.position = (available - canvas.size) / 2
	canvas.queue_redraw()

func toggle_workshop() -> void:
	if visible: close_workshop()
	elif character_id.is_empty(): open_art("white-haired-girl")
	else: open_art(character_id)

func close_workshop() -> void:
	canvas.finish_stroke()
	_stash()
	if get_viewport().gui_get_focus_owner() != null: get_viewport().gui_get_focus_owner().release_focus()
	hide()

func _input(event: InputEvent) -> void:
	if visible and not discard_dialog.visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		# Popups receive their own Esc; closing a color picker should not close the workshop.
		if color_picker.get_popup().visible: return
		for picker in [work_picker, frame_picker, group_picker, action_picker, direction_picker, layer_picker]:
			if picker.get_popup().visible: return
		close_workshop(); get_viewport().set_input_as_handled()

func _stash() -> void:
	if character_id.is_empty(): return
	canvas.finish_stroke()
	drafts[character_id] = {"art": canvas.art, "base_revision": base_revision, "frame": canvas.frame, "layer": canvas.layer, "undo": canvas.undo_stack, "redo": canvas.redo_stack, "dirty": dirty, "group": group, "action": action, "direction": direction, "scroll": scroll.scroll_vertical, "preview": preview_playing, "clock": preview_clock, "structure": structure_panel.visible, "color": canvas.color, "eraser": canvas.eraser, "fill": canvas.fill_tool, "layer_name": layer_name.text}
	last_work[category] = character_id

func select_category(kind: String) -> void:
	if kind == category and not character_id.is_empty(): return
	for id in library.artworks:
		if library.artworks[id].get("kind", "character") == kind:
			open_art(str(last_work.get(kind, id))); return

func open_art(id: String) -> void:
	if not library.artworks.has(id): return
	_stash()
	character_id = id
	category = str(library.artworks[id].get("kind", "character"))
	var state: Dictionary = drafts.get(id, {})
	# Clean cached works follow external edits; unapplied drafts keep their original revision.
	if not state.is_empty() and not state.dirty and int(state.base_revision) != int(library.artworks[id].revision):
		state.art = library.artworks[id].duplicate(true); state.base_revision = int(state.art.revision); state.undo = []; state.redo = []
	if state.is_empty():
		canvas.art = library.artworks[id].duplicate(true); base_revision = int(canvas.art.revision)
		canvas.frame = "mature" if category == "plant" else "stage_4" if category == "building" else "down_0" if category == "character" else "idle" if canvas.art.get("facility_type")=="recreation" else "down" if canvas.art.get("facility_type") == "furniture" else "cold"
		canvas.layer = 0; canvas.undo_stack = []; canvas.redo_stack = []; dirty = false
		group = LocalText.source("content.workshop.appearance"); action = LocalText.source("content.workshop.standing"); direction = "down"; preview_playing = false; preview_clock = 0; layer_name.text = ""
		structure_panel.hide(); scroll.scroll_vertical = 0
	else:
		canvas.art = state.art; base_revision = int(state.base_revision); canvas.frame = state.frame; canvas.layer = state.layer
		canvas.undo_stack = state.undo; canvas.redo_stack = state.redo; dirty = state.dirty
		group = state.group; action = state.action; direction = state.direction; preview_playing = state.preview; preview_clock = state.clock
		structure_panel.visible = state.structure; canvas.color = state.color; canvas.eraser = state.eraser; canvas.fill_tool = state.fill; layer_name.text = state.layer_name
		call_deferred("_restore_scroll", id, int(state.scroll))
	_syncing = true
	category_tabs.current_tab = Catalog.KINDS.find(category)
	work_picker.clear()
	for work_id in library.artworks:
		var work: Dictionary = library.artworks[work_id]
		if work.get("kind", "character") != category: continue
		work_picker.add_item(Catalog.work_name(library.artworks[work_id],work_id))
		work_picker.set_item_metadata(work_picker.item_count - 1, work_id)
		if work_id == id: work_picker.select(work_picker.item_count - 1)
	work_name.text=str(canvas.art.get("name",character_id))
	template_button.visible=canvas.art.has("recreation")
	rename_row.visible=false
	resident_picker.clear()
	if library.resident_world!=null:
		for actor in library.resident_world.actors.values():
			if actor.get("role", "") == "human": continue
			resident_picker.add_item(LocalText.resident(library.resident_world,actor.id));resident_picker.set_item_metadata(resident_picker.item_count-1,actor.id)
			if actor.appearance_id==character_id:resident_picker.select(resident_picker.item_count-1)
		if resident_picker.selected>=0:resident_name.text=library.resident_world.actors[resident_picker.get_item_metadata(resident_picker.selected)].name
	character_filters.visible = category == "character"
	outfit_toggle.visible = category == "character"
	if category != "character": outfit_panel.hide()
	structure_toggle.visible = category == "building"; use_blueprint.visible = category == "building"
	if category != "building": structure_panel.hide()
	else:
		for key in structure_inputs: structure_inputs[key].set_value_no_signal(canvas.art.structure[key])
	structure_toggle.text = T("content.workshop.structure_materials_41") if structure_panel.visible else T("content.workshop.structure_materials")
	frame_label.text = T("content.workshop.growth_stage") if category == "plant" else T("content.workshop.construction_stage") if category == "building" else T("content.workshop.usage_state") if category == "facility" else T("content.workshop.animation_frames")
	context_label.text = {"plant": T("content.workshop.seedling_growing_and_mature_appearances_editing_art_never_changes"), "character": T("content.workshop.draw_the_whole_character_freely_and_edit_by_action_group"), "building": T("content.workshop.editing_a_building_template_houses_already_started_keep_their_ori"), "facility": T("content.workshop.appearance_and_usage_states_different_frames_in_one_work")}[category]
	color_picker.color = canvas.color
	_syncing = false
	_rebuild_filters(true); _quote(); _layers(); _refresh_outfit(); canvas.refresh(); _update_draft_label()
	play_button.text = T("content.workshop.pause_preview") if preview_playing else T("content.workshop.play_preview")
	feedback.text = T("content.workshop.draft_kept_for_this_session_save_before_leaving_the_game") if dirty else ""
	last_work[category] = id
	show(); _layout()

func _restore_scroll(id: String, value: int) -> void:
	if character_id == id: scroll.scroll_vertical = value

func _rebuild_filters(keep_frame: bool) -> void:
	canvas.finish_stroke()
	var keys: Array = []
	if category == "character":
		group_picker.clear()
		for name_key in Catalog.GROUPS:
			var name:String=LocalText.source(name_key)
			if not Catalog.frames(canvas.art, name).is_empty():group_picker.add_item(LocalText.content(name));group_picker.set_item_metadata(group_picker.item_count-1,name)
		if not _select_text(group_picker, group): group = str(group_picker.get_item_metadata(0)); group_picker.select(0)
		var actions: Array = []
		for key in Catalog.frames(canvas.art, group):
			var name: String = LocalText.source("content.workshop.walking") if group == LocalText.source("content.workshop.movement") else Catalog.describe(key).action
			if not actions.has(name): actions.append(name)
		action_picker.clear()
		for name in actions:action_picker.add_item(LocalText.content(name));action_picker.set_item_metadata(action_picker.item_count-1,name)
		if not _select_text(action_picker, action): action = actions[0]; action_picker.select(0)
		var directions: Array = []
		for key in Catalog.frames(canvas.art, group, action):
			var value: String = Catalog.describe(key).direction
			if not directions.has(value): directions.append(value)
		direction_picker.clear()
		for value in directions:
			direction_picker.add_item(LocalText.text(str(Catalog.DIRECTIONS.get(value, value)))); direction_picker.set_item_metadata(direction_picker.item_count - 1, value)
		if not directions.has(direction): direction = directions[0]
		direction_picker.select(directions.find(direction)); direction_picker.visible = directions != [""]
		keys = Catalog.frames(canvas.art, group, action, direction)
	else: keys = canvas.art.frames.keys()
	frame_picker.clear()
	for key in keys:
		var status: String = str(canvas.art.get("frame_status", {}).get("frames", {}).get(key, ""))
		var suffix := T("content.workshop.reused") if status == "reused" else T("content.workshop.mirrored") if status == "mirrored" else T("content.workshop.placeholder_missing") if status == "placeholder" else ""
		frame_picker.add_item(Catalog.label(key) + suffix); frame_picker.set_item_metadata(frame_picker.item_count - 1, key)
	if not keep_frame or not keys.has(canvas.frame): canvas.frame = str(keys[0]); canvas.layer = 0
	frame_picker.select(keys.find(canvas.frame))
	_layers(); canvas.refresh()

func _select_text(picker: OptionButton, value: String) -> bool:
	for i in range(picker.item_count):
		if str(picker.get_item_metadata(i)) == value: picker.select(i); return true
	return false

func _select_frame(key: String) -> void:
	canvas.finish_stroke(); canvas.frame = key; canvas.layer = 0; preview_clock = 0; _layers(); canvas.refresh()

func _sync_frame_navigation() -> void:
	if category == "character":
		var info := Catalog.describe(canvas.frame)
		group = info.group; action = info.action; direction = info.direction
	_rebuild_filters(true)

func _mark_dirty() -> void:
	dirty = true; _update_draft_label()

func _refresh_outfit() -> void:
	if outfit_palette == null or category != "character": return
	outfit_palette.clear()
	for color in canvas.art.palette:
		var key := str(color)
		if not outfit_palette_icons.has(key):
			var swatch := Image.create(8, 8, false, Image.FORMAT_RGBA8); swatch.fill(Color(key))
			outfit_palette_icons[key] = ImageTexture.create_from_image(swatch)
		outfit_palette.add_icon_item(outfit_palette_icons[key], key)
	outfit_target.clear()
	for id in library.artworks:
		if id == character_id or library.artworks[id].get("kind", "character") != "character": continue
		outfit_target.add_item(library.display_name(id)); outfit_target.set_item_metadata(outfit_target.item_count - 1, id)
	for part in outfit_checks:
		var entry: Dictionary = canvas.art.get("outfit", {}).get(part, {})
		outfit_checks[part].set_pressed_no_signal(entry.get("enabled", false))
		outfit_checks[part].disabled = entry.is_empty()

func _create_outfit() -> void:
	if canvas.art.has("outfit"): feedback.text = T("content.workshop.this_work_already_has_clothing_regions"); return
	if character_id != "human-starter": feedback.text = T("content.workshop.this_work_has_no_confirmed_clothing_mask_yet"); return
	var profile: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/outfits/human-starter.json"))
	if not profile is Dictionary or not library.OutfitRules.valid(profile.get("parts"), canvas.art): feedback.text = T("content.workshop.clothing_mask_unavailable"); return
	canvas.checkpoint_outfit(); canvas.art.outfit = profile.parts.duplicate(true)
	_refresh_outfit(); canvas.refresh(); feedback.text = T("content.workshop.candidate_regions_created_check_each_action_before_saving")

func _toggle_outfit(part: String, value: bool) -> void:
	if not canvas.art.get("outfit", {}).has(part): return
	canvas.checkpoint_outfit(); canvas.art.outfit[part].enabled = value; canvas.refresh()

func _recolor_outfit(part: String) -> void:
	if not canvas.art.get("outfit", {}).has(part) or outfit_palette.selected < 0: feedback.text = T("content.workshop.create_regions_and_select_a_palette_color_first"); return
	var target_index := outfit_palette.selected
	var target := Color(canvas.art.palette[target_index])
	if target.a == 0: feedback.text = T("content.workshop.choose_an_opaque_color"); return
	var entry: Dictionary = canvas.art.outfit[part]
	var indices := {}
	for frame in entry.masks:
		for pixel in entry.masks[frame]:
			for layer in canvas.art.frames[frame]:
				var source: int = int(layer.pixels[int(pixel)])
				if Color(canvas.art.palette[source]).a > 0: indices[source] = true
	canvas.checkpoint_outfit()
	entry.colors = {}
	for source in indices:
		var old := Color(canvas.art.palette[source])
		var desired := Color.from_hsv(target.h, maxf(target.s, .25), old.v, old.a)
		var best := target_index; var distance := INF
		for i in range(canvas.art.palette.size()):
			var candidate := Color(canvas.art.palette[i])
			if candidate.a == 0: continue
			var delta := Vector3(candidate.r-desired.r,candidate.g-desired.g,candidate.b-desired.b).length_squared()
			if delta < distance: distance = delta; best = i
		entry.colors[str(source)] = best
	entry.enabled = true; _refresh_outfit(); canvas.refresh(); feedback.text = T("content.workshop.region_recolored_with_the_existing_palette_check_the_other_action")

func _copy_outfit() -> void:
	if not canvas.art.has("outfit") or outfit_target.selected < 0: feedback.text = T("content.workshop.create_clothing_regions_and_select_a_work_first"); return
	var destination: String = outfit_target.get_item_metadata(outfit_target.selected)
	var copy: Dictionary = canvas.art.outfit.duplicate(true)
	var source_frames: Dictionary = canvas.art.frames
	var source_palette: Array = canvas.art.palette
	open_art(destination)
	if canvas.art.frames != source_frames or canvas.art.palette != source_palette:
		feedback.text = T("content.workshop.the_target_has_no_matching_mask_confirm_and_create_its_mask_first"); return
	canvas.checkpoint_outfit(); canvas.art.outfit = copy; _refresh_outfit(); canvas.refresh(); feedback.text = T("content.workshop.copied_into_the_target_draft_save_to_apply_it")

func _update_draft_label() -> void:
	draft_label.text = T("content.workshop.draft_not_applied") if dirty else T("content.workshop.saved")
	draft_label.modulate = Color("f1ce8c") if dirty else Color("b5c9bc")

func _layers() -> void:
	layer_picker.clear()
	for entry in canvas.art.frames[canvas.frame]: layer_picker.add_item(LocalText.content(str(entry.get("name", T("content.workshop.layer")))) + ("" if entry.get("visible", true) else T("content.workshop.hidden")))
	canvas.layer = clampi(canvas.layer, 0, layer_picker.item_count - 1); layer_picker.select(canvas.layer)

func _add_layer() -> void:
	var layers: Array = canvas.art.frames[canvas.frame]
	if layers.size() >= 16: return
	canvas.checkpoint()
	var pixels: Array = []; pixels.resize(int(canvas.art.width) * int(canvas.art.height)); pixels.fill(0)
	layers.append({"id": "layer-%s" % Time.get_ticks_usec(), "name": layer_name.text if not layer_name.text.is_empty() else T("content.workshop.new_layer"), "visible": true, "pixels": pixels})
	canvas.layer = layers.size() - 1; _layers(); canvas.refresh()

func _visibility() -> void:
	canvas.checkpoint()
	var layer: Dictionary = canvas.art.frames[canvas.frame][canvas.layer]
	layer.visible = not layer.get("visible", true); _layers(); canvas.refresh()

func _delete_layer() -> void:
	if canvas.art.frames[canvas.frame].size() <= 1: return
	canvas.checkpoint(); canvas.art.frames[canvas.frame].remove_at(canvas.layer); _layers(); canvas.refresh()

func _publish() -> void:
	canvas.finish_stroke()
	var result: Dictionary = library.publish(canvas.art, base_revision)
	if result.ok:
		base_revision = int(result.revision); canvas.art.revision = base_revision; dirty = false; _update_draft_label(); _stash()
		feedback.text = T("content.workshop.template_saved_houses_already_started_keep_their_original_design") if category == "building" else T("content.workshop.saved_the_game_now_uses_this_work")
		applied.emit()
	else:
		feedback.text = T("content.workshop.another_edit_updated_this_work_your_draft_is_safe_load_the_saved") if result.error == "stale_artwork" else T("content.workshop.save_failed") + str(result.error)

func _request_discard(operation: String) -> void:
	pending_discard = operation
	if dirty: discard_dialog.popup_centered()
	else: _discard_action()

func _discard_action() -> void:
	if pending_discard == "undo_publish": _undo_publish(); return
	_reload_saved()

func _reload_saved() -> void:
	var id := character_id
	var old_frame: String = canvas.frame
	drafts.erase(id); character_id = ""; open_art(id)
	if canvas.art.frames.has(old_frame): canvas.frame = old_frame; _sync_frame_navigation()

func _undo_publish() -> void:
	var result: Dictionary = library.undo_publish(character_id)
	if result.ok: _reload_saved(); applied.emit()
	else: feedback.text = T("content.workshop.no_application_to_undo")

func _toggle_preview() -> void:
	preview_playing = not preview_playing; preview_clock = 0; preview_frame = ""
	play_button.text = T("content.workshop.pause_preview") if preview_playing else T("content.workshop.play_preview")
	if not preview_playing: preview.texture = canvas._image

func _process(delta: float) -> void:
	if not visible: return
	# Containers may grow during their first layout pass; then fit the settled minimum.
	var available := get_viewport_rect().size
	var desired := Vector2(minf(1060, available.x - 48), maxf(400, available.y - 185))
	if not size.is_equal_approx(desired): _layout()
	if not preview_playing or canvas == null or canvas.art.is_empty(): return
	preview_clock += delta
	var sequence := Catalog.preview_frames(canvas.art, canvas.frame)
	if sequence.is_empty(): return
	var speed := 2.0 if category != "character" or group == LocalText.source("content.workshop.daily_life") else 5.0
	var key: String = str(sequence[int(preview_clock * speed) % sequence.size()])
	if canvas.frame.begins_with("blink_"): key = canvas.frame if fmod(preview_clock, 3.5) < .14 else canvas.frame.get_slice("_", 1) + "_0"
	if key != preview_frame:
		preview_frame = key; preview.texture = ImageTexture.create_from_image(library.render(canvas.art, key))

func _quote() -> void:
	if category != "building": return
	var quote: Dictionary = library.Blueprint.quote(canvas.art.structure)
	quote_label.text = T("content.workshop.wood_s_nfloor_s_frame_s_walls_s_nroof_s_finishing_s_porch_s") % [quote.wood, quote.breakdown.floor, quote.breakdown.frame, quote.breakdown.walls, quote.breakdown.roof, quote.breakdown.finish, quote.breakdown.porch]

func _duplicate_work(blank: bool) -> void:
	canvas.finish_stroke();var result: Dictionary=library.create_work(canvas.art,blank)
	if result.ok:open_art(result.id)
	else:feedback.text=str(result.error)

func _open_assembler() -> void:
	if category != "character": feedback.text = T("content.workshop.switch_to_characters_first"); return
	for part in assembler_parts:
		var picker: OptionButton = assembler_parts[part]; picker.clear()
		for id in ["human-starter", "white-haired-girl", "blue-haired-girl", "orange-haired-girl", "black-scarf-girl"]:
			picker.add_item(library.display_name(id)); picker.set_item_metadata(picker.item_count - 1, id)
	_assembler_apply_preset(); assembler_dialog.popup_centered(Vector2i(420, 420))

func _assembler_apply_preset() -> void:
	var presets: Dictionary = preload("res://scripts/character_assembler.gd").PRESETS
	if assembler_preset.selected < 0: return
	var preset: Dictionary = presets[str(assembler_preset.get_item_metadata(assembler_preset.selected))]
	for part in assembler_parts:
		var picker: OptionButton = assembler_parts[part]
		for index in range(picker.item_count):
			if picker.get_item_metadata(index) == preset[part]: picker.select(index); break

func _assemble_character() -> void:
	var parts := {}
	for part in assembler_parts:
		var picker: OptionButton = assembler_parts[part]
		if picker.selected < 0: feedback.text = T("content.workshop.choose_every_part"); return
		parts[part] = picker.get_item_metadata(picker.selected)
	var result: Dictionary = preload("res://scripts/character_assembler.gd").assemble(library, parts, str(assembler_preset.get_item_metadata(assembler_preset.selected)))
	if result.ok: assembler_dialog.hide(); open_art(result.id); feedback.text = T("content.workshop.independent_work_created_check_all_its_actions")
	else: feedback.text = T("content.workshop.assembly_failed") + str(result.error)
func _rename_resident() -> void:
	if library.resident_world==null or resident_picker.selected<0:return
	var id: String=resident_picker.get_item_metadata(resident_picker.selected)
	var result: Dictionary=library.resident_world.residents.rename(library.resident_world,id,resident_name.text)
	feedback.text=T("content.workshop.name_updated") if result.ok else T("content.workshop.names_must_contain_1_24_characters")
	if result.ok:
		resident_picker.set_item_text(resident_picker.selected,LocalText.resident(library.resident_world,id))
		for i in range(work_picker.item_count):work_picker.set_item_text(i,library.display_name(work_picker.get_item_metadata(i)))
		applied.emit()
func _assign_appearance() -> void:
	if library.resident_world==null or resident_picker.selected<0 or dirty:feedback.text=T("content.workshop.save_the_work_before_applying_it_to_a_resident");return
	var id: String=resident_picker.get_item_metadata(resident_picker.selected)
	if not library.resident_world.assign_appearance(id, character_id):feedback.text=T("content.workshop.can_t_change_this_character_s_appearance");return
	feedback.text=T("content.workshop.appearance_assigned_name_and_identity_stay_the_same");applied.emit()

func refresh_locale()->void:
	_refresh_static(self)
	for index in range(assembler_preset.item_count):assembler_preset.set_item_text(index,LocalText.content(str(assembler_preset.get_item_metadata(index))))
	for index in range(category_tabs.tab_count):category_tabs.set_tab_title(index,T(["content.workshop.characters","content.workshop.buildings","content.workshop.facilities","content.workshop.plants"][index]))
	# Relabel navigation only. Never reload art, finish a stroke, rebuild layers or touch undo.
	for picker_node in [group_picker,action_picker]:
		for index in range(picker_node.item_count):picker_node.set_item_text(index,LocalText.content(str(picker_node.get_item_metadata(index))))
	for index in range(direction_picker.item_count):direction_picker.set_item_text(index,LocalText.text(str(Catalog.DIRECTIONS.get(str(direction_picker.get_item_metadata(index)),""))))
	for index in range(frame_picker.item_count):
		var frame:String=str(frame_picker.get_item_metadata(index));var status:String=str(canvas.art.get("frame_status",{}).get("frames",{}).get(frame,""))
		var suffix:String=T("content.workshop.reused") if status=="reused" else T("content.workshop.mirrored") if status=="mirrored" else T("content.workshop.placeholder_missing") if status=="placeholder" else ""
		frame_picker.set_item_text(index,Catalog.label(frame)+suffix)
	for index in range(layer_picker.item_count):
		var entry:Dictionary=canvas.art.frames[canvas.frame][index]
		layer_picker.set_item_text(index,LocalText.content(str(entry.get("name",T("content.workshop.layer"))))+("" if entry.get("visible",true) else T("content.workshop.hidden")))
	for index in range(work_picker.item_count):
		var work_id:String=str(work_picker.get_item_metadata(index));work_picker.set_item_text(index,Catalog.work_name(library.artworks[work_id],work_id))
	for index in range(resident_picker.item_count):resident_picker.set_item_text(index,LocalText.resident(library.resident_world,str(resident_picker.get_item_metadata(index))))
	var popup:PopupMenu=file_menu_button.get_popup()
	for index in range(popup.item_count):
		var id:String=str(popup.get_meta("workshop_item_"+str(index),""))
		if not id.is_empty():popup.set_item_text(index,T(id))
	_update_draft_label()
