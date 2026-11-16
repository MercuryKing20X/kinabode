extends Node2D
const LocalText=preload("res://scripts/localization.gd")
var _locale_values:Dictionary={}
func T(key:String)->String:
	var value:String=LocalText.text(key);_locale_values[value]=key;return value
func _mark_locale(node:Node)->void:
	if not is_instance_valid(node):return
	var fields:Array=[]
	if (node is Label or node is Button) and node not in [status,order_label,stock,resident_status,day_label] and node.get_parent()!=choices:fields.append("text")
	if node is Control:fields.append("tooltip_text")
	if node is Window:fields.append("title")
	if node is AcceptDialog:fields.append_array(["dialog_text","ok_button_text"])
	if node is ConfirmationDialog:fields.append("cancel_button_text")
	for field in fields:
		var value:String=str(node.get(field))
		if _locale_values.has(value):node.set_meta("main_locale_"+str(field),_locale_values[value])
	if node is OptionButton:
		for index in range(node.item_count):
			var value:String=node.get_item_text(index)
			if _locale_values.has(value):node.set_meta("main_option_"+str(index),_locale_values[value])
	if node is PopupMenu:
		for index in range(node.item_count):
			var value:String=node.get_item_text(index)
			if _locale_values.has(value):node.set_meta("main_item_"+str(index),_locale_values[value])
func _mark_locale_deferred(node:Node)->void:
	call_deferred("_mark_locale_instance",node.get_instance_id())
func _mark_locale_instance(id:int)->void:
	if is_instance_id_valid(id):_mark_locale(instance_from_id(id))
func _refresh_main_locale(node:Node)->void:
	for field in ["text","tooltip_text","title","dialog_text","ok_button_text","cancel_button_text"]:
		var meta:String="main_locale_"+field
		if node.has_meta(meta) and str(node.get(field)) in [LocalText.source(str(node.get_meta(meta))),str(LocalText.entries.get(str(node.get_meta(meta)),{}).get("en",""))]:node.set(field,T(str(node.get_meta(meta))))
	if node is OptionButton:
		for index in range(node.item_count):
			if node.has_meta("main_option_"+str(index)):node.set_item_text(index,T(str(node.get_meta("main_option_"+str(index)))))
	if node is PopupMenu:
		for index in range(node.item_count):
			if node.has_meta("main_item_"+str(index)):node.set_item_text(index,T(str(node.get_meta("main_item_"+str(index)))))
	for child in node.get_children():_refresh_main_locale(child)
@export var showcase_default:=false
var ui_scale:Node
var local_host_commands:Node
var chat_send_button:Button
var _chat_ime_enter_frame:=-1
var island_hud:Control
var game_audio:Node
var audio_dialog:AcceptDialog
var backups:=preload("res://scripts/save_backup.gd").new()
const Opening=preload("res://scripts/world_opening.gd")
const Places = preload("res://scripts/map_locations.gd")

const World = preload("res://scripts/world_state.gd")
const View = preload("res://scripts/island_view.gd")
const Atlas = preload("res://scripts/atlas_view.gd")
const Endpoint = preload("res://scripts/read_endpoint.gd")
const Library = preload("res://scripts/character_library.gd")
const Editor = preload("res://scripts/character_editor.gd")
const Link = preload("res://scripts/companion_link.gd")
const Conversation = preload("res://scripts/conversation_link.gd")
const SharedLink = preload("res://scripts/shared_companion_link.gd")
const House = preload("res://scripts/house_panel.gd")
const Inside = preload("res://scripts/interior_panel.gd")
var leisure_panel: Control
var gomoku_match_host: RefCounted
var gomoku_dialogue: RefCounted
var storage_panel: Control
var jieqi_panel: Control
var chess_choice: Control
var gomoku_panel: Control
var participant_picker: ConfirmationDialog
var wish_panel: PanelContainer
var gift_panel: PanelContainer
var proposal_panel: PanelContainer
var proposal_host: RefCounted
var autonomy_notice: Label
var autonomy: RefCounted
var resident_connections: PanelContainer
var resident_connections_button: Button
var handbook_menu: MenuButton
var connection_ui_states: Dictionary = {}
var connection_state_cache: Dictionary = {}
var ai_connect_panel: AcceptDialog
var external_residents: Dictionary={}
var flower_panel:Control
var flower_placement:Dictionary={}
var flower_actor_ids:Array=[]
var playground:Node
var watch_ui:Node
var brain_panel:Control
var steward:Node
var action_dock: Control
var actions_button: Button
var fishing_panel: Control
var homestead_panel: Control
var journal_panel: Control
var day_label: Label
var day_journal_overlay: Node
var book_panel:Control
var memory_panel: Control
var model_fallback_requests:Dictionary={}
var fallback_revoked_actions:Dictionary={}
var immediate_turns:Dictionary={}
var connection_pool:Node
var connection_overview:Control
var connection_history:=ConfigFile.new()
var life_archive:Node
var memory_life:Node
var memory_books=preload("res://scripts/memory_books.gd").new()
var host_turn_grants:Dictionary={}
var follow_ui:Node
var gathering_button: Button
var gathering_note: Label
var placing_facility := ""
var farm_panel: Control
var farm_commands: RefCounted
var interior_panel: Control
var furniture_button: Button
var house_panel: Control
const Save = preload("res://scripts/save_store.gd")
var world := World.new(Opening.manifest_from_args())
var library := Library.new()
var view: Node2D
var journey:Node
var atlas: Node2D
var editor: Control
const Channels = preload("res://scripts/dialogue_channels.gd")
var dialogue := Channels.new()
var group_links: Dictionary = {}
var group_questions: Dictionary = {}
var group_chat := false
var question_picker: OptionButton
var daily_controls: Control
var stop_chat_button: Button
var find_partner_button: Button
var task_channels: Dictionary = {}
# Host extension point: (resident_id, scope) -> Node implementing the link contract.
var dialogue_adapter_factory: Callable
var links: Dictionary = {}
var chat_actor := "codex"
var chat_picker: OptionButton
var questions: Dictionary = {}
var link: Node
var status: Label
const ProjectPanel = preload("res://scripts/project_panel.gd")
var project_panel: Control
var order_bar: VBoxContainer
var order_label: Label
var stock: Label
var chat: PanelContainer
var chat_log: RichTextLabel
var connection_greetings:Dictionary={}
var intentions:Node
var command_page:Node
var chat_input: LineEdit
var choices: HFlowContainer
var activity_choices: HFlowContainer
var dialogue_button: Button
var assign := false
var selected_id := ""
var pending_camp: Dictionary = {}
var pending_chess: Dictionary = {}
var chess_ui_visibility:Dictionary={}
var direct_grill_fish_id := ""
var pending_question := ""
var data_dir := ""
var snapshot_path := ""
var scenario := ""
var autosave := 0.0
var autosave_interval:=4.0
var saved_revision := -1
var save_enabled := true
var seen_events: Dictionary = {}
var hud_time := 0.0
var local_seen_serial := 0
var endpoint: Node
var controller_picker: OptionButton
var activity_toggle: CheckButton
var chatter_toggle: CheckButton
var resident_status: Label
var local_settings := ConfigFile.new()
var conversation_thread := ""
var relay_button: Button
var shared_test := false
var shared_button: Button
signal opening_chosen(id:String)
var opening_dialog:ConfirmationDialog
var opening_picker:OptionButton
var ui_font:Font
var language:="zh"
func choose_opening(archive:bool=false)->void:
	opening_dialog=ConfirmationDialog.new();opening_dialog.title=T("ui.main.archive_and_restart_keep_characters") if archive else T("ui.main.a_new_island_life");add_child(opening_dialog)
	opening_dialog.ok_button_text=T("ui.main.archive_and_begin") if archive else T("ui.main.begin_life")
	var body:=VBoxContainer.new();opening_dialog.add_child(body)
	var note:=Label.new();note.text=T("ui.main.you_and_four_companions_starting_with_your_first_meal")+(T("ui.main.nthe_old_world_will_be_archived_intact_characters_and_artwork_sta") if archive else "");body.add_child(note)
	opening_picker=OptionButton.new();body.add_child(opening_picker)
	opening_picker.add_item(T("ui.main.standard_an_almost_empty_island_start_with_a_fire_and_a_meal"));opening_picker.set_item_metadata(0,"standard")
	opening_picker.add_item(T("ui.main.showcase_buildings_ready_so_you_can_explore_island_life"));opening_picker.set_item_metadata(1,"showcase");opening_picker.select(0)
	opening_dialog.confirmed.connect(func():
		var chosen:String=opening_picker.get_item_metadata(opening_picker.selected)
		if archive:
			if save_enabled and not Save.save_world(world,data_dir):opening_dialog.dialog_text=T("ui.main.couldn_t_save_your_progress_your_world_is_safe_nothing_was_restar");return
			save_enabled=false
			var pid:int=OS.create_process(OS.get_executable_path(),["--path",ProjectSettings.globalize_path("res://"),"--","--opening="+chosen,"--fresh-world"])
			if pid<=0:save_enabled=true;return
			get_tree().quit()
		else:opening_chosen.emit(chosen)
		opening_dialog.queue_free())
	opening_dialog.popup_centered(Vector2i(590,200))

var dark_ui:Node

func _ready() -> void:
	get_tree().node_added.connect(func(node):
		if node is Window and is_ancestor_of(node):node.window_input.connect(func(event):
			var focused:Control=node.gui_get_focus_owner()
			if event is InputEventKey and event.pressed and event.keycode==KEY_SPACE and not (focused is LineEdit or focused is TextEdit):_return_to_player();node.set_input_as_handled()
		)
	)
	call_deferred("_setup_dark_ui")
	if get_tree().get_meta("title_transition",false):
		get_tree().remove_meta("title_transition")
		var layer:=CanvasLayer.new();layer.layer=120;add_child(layer)
		var curtain:=ColorRect.new();curtain.color=Color.BLACK;curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);curtain.mouse_filter=Control.MOUSE_FILTER_IGNORE;layer.add_child(curtain)
		var transition:=create_tween();transition.tween_property(curtain,"color:a",0.0,.25);transition.tween_callback(layer.queue_free)
	if showcase_default and not Opening.v3(world) and "--opening=legacy" not in OS.get_cmdline_user_args() and OS.get_environment("HABITAT_OPENING")!="legacy":world=World.new("res://content/home-v3/world.json")
	if Opening.v3(world):get_window().content_scale_size=Vector2i.ZERO
	var opening_choice:String="showcase" if OS.get_environment("HABITAT_OPENING") in ["legacy","showcase"] else "standard"
	for value in OS.get_cmdline_user_args():
		if value in ["--opening=standard","--opening=showcase"]:opening_choice=value.trim_prefix("--opening=")
	var readers := 2
	var fresh_world := bool(get_tree().get_meta("title_fresh",false))
	if get_tree().has_meta("title_opening"):opening_choice=str(get_tree().get_meta("title_opening"))
	var preserved_identity:Dictionary={}
	var bind_conversation := false
	var independent_conversation := false
	var select_shared := false
	for arg in OS.get_cmdline_user_args():
		if arg == "--fresh-world": fresh_world = true
		if arg.begins_with("--snapshot="): snapshot_path = arg.trim_prefix("--snapshot=")
		if arg.begins_with("--scenario="): scenario = arg.trim_prefix("--scenario=")
		if arg.begins_with("--readers="): readers = clampi(arg.trim_prefix("--readers=").to_int(), 1, world.residents.capacity - world.residents.definitions.size() + 2)
		if arg.begins_with("--conversation-thread="):
			conversation_thread = arg.trim_prefix("--conversation-thread="); bind_conversation = true
		if arg == "--independent-conversation": independent_conversation = true
		if arg == "--shared-test": shared_test = true; select_shared = true
	if not conversation_thread.is_empty() and not Conversation.valid_thread(conversation_thread):
		push_error(T("ui.main.invalid_original_conversation_id_no_replacement_conversation_was")); get_tree().quit(1); return
	if not world.error.is_empty(): push_error(world.error); get_tree().quit(1); return
	for i in range(1, readers): world.add_companion("companion-%s" % (i + 1), world.residents.name_for("companion-%s" % (i+1)) if i == 1 else LocalText.source("ui.main.companion_s") % (i + 1))
	data_dir = OS.get_environment("HABITAT_DATA_DIR")
	if data_dir.is_empty(): data_dir = ProjectSettings.globalize_path("user://")
	if not get_tree().has_meta("title_opening") and Opening.v3(world) and (fresh_world or not FileAccess.file_exists(data_dir.path_join("island-v2.json"))) and snapshot_path.is_empty() and OS.get_environment("HABITAT_OPENING").is_empty() and not Array(OS.get_cmdline_user_args()).any(func(arg):return arg.begins_with("--opening=")) and DisplayServer.get_name()!="headless":
		save_enabled=false;set_process(false);choose_opening();opening_choice=await opening_chosen;save_enabled=true;set_process(true)
	if fresh_world and snapshot_path.is_empty():preserved_identity=Save.read_identity(data_dir)
	if fresh_world and snapshot_path.is_empty() and not Save.archive_progress(data_dir):
		push_error(T("ui.main.couldn_t_restart_your_existing_progress_is_safe")); get_tree().quit(1); return
	get_tree().remove_meta("title_fresh")
	get_tree().remove_meta("title_opening")
	var loaded: Dictionary = Save.load_world(world, data_dir)
	if not loaded.ok and loaded.get("error")=="world_template_mismatch":
		save_enabled=false
		if DisplayServer.get_name()=="headless":push_error(T("ui.main.this_save_uses_another_map_template_the_original_and_a_copy_are_s"));get_tree().quit(1);return
		set_process(false)
		var reset:=ConfirmationDialog.new();reset.title=T("ui.main.choose_a_new_home_island");reset.dialog_text=T("ui.main.your_world_uses_an_older_map_the_original_save_and_a_copy_are_saf");reset.ok_button_text=T("ui.main.archive_and_restart_keep_characters");reset.cancel_button_text=T("ui.main.not_now");add_child(reset)
		reset.confirmed.connect(func():choose_opening(true))
		reset.canceled.connect(func():get_tree().quit());reset.popup_centered(Vector2i(570,240));return
	if snapshot_path.is_empty():
		backups.setup(data_dir)
		backups.startup(bool(loaded.ok),bool(loaded.get("loaded",false)),world.days.day())
	var binding := ConfigFile.new()
	memory_books.setup(data_dir)
	world.director.quote_books=weakref(memory_books)
	memory_books.migrate(world)
	memory_books.entry_deleted.connect(_forget_memory_source)
	world.memories.notebook=memory_books
	world.memories.committed=func(raw:Dictionary):memory_books.ingest(world,raw,false)
	var binding_path := data_dir.path_join("conversation-binding.cfg")
	if independent_conversation:
		conversation_thread = ""
		DirAccess.remove_absolute(binding_path)
	elif bind_conversation:
		binding.set_value("conversation", "thread_id", conversation_thread)
		binding.set_value("conversation", "world_id", world.world_id)
		if binding.save(binding_path) != OK: push_warning(T("ui.main.couldn_t_save_the_conversation_binding_specify_it_again_next_time"))
	elif conversation_thread.is_empty() and binding.load(binding_path) == OK:
		var saved_thread: String = str(binding.get_value("conversation", "thread_id", ""))
		if binding.get_value("conversation", "world_id", "") == world.world_id and Conversation.valid_thread(saved_thread): conversation_thread = saved_thread
	var adapter_preferences:=ConfigFile.new()
	if adapter_preferences.load(data_dir.path_join("connection-mode.cfg"))==OK:
		var configured: Variant=adapter_preferences.get_value("connection","external_residents",{})
		if configured is Dictionary:external_residents={}
	var connection_settings := ConfigFile.new()
	if bind_conversation or independent_conversation:
		shared_test = false
		connection_settings.set_value("connection", "shared_test", false)
		connection_settings.save(data_dir.path_join("connection-mode.cfg"))
	elif select_shared:
		connection_settings.set_value("connection", "shared_test", true)
		connection_settings.save(data_dir.path_join("connection-mode.cfg"))
	elif not bind_conversation and not independent_conversation and not shared_test and connection_settings.load(data_dir.path_join("connection-mode.cfg")) == OK:
		shared_test = false
	world.residents.provision(world)
	world.village.enabled = false
	if not preserved_identity.is_empty():Save.apply_identity(world,preserved_identity)
	if not loaded.ok: save_enabled = loaded.get("safe_to_save", false)
	if not loaded.get("loaded", false) and world.actors.has("companion-2"):
		world.farms.farms["farm.hill"].manager_id = "companion-2"
	library.configure(data_dir)
	world.library = library
	Opening.install_templates(world,library)
	if Opening.v3(world) and not loaded.get("loaded",false):
		var initial:Dictionary=Opening.apply(world,library,opening_choice)
		if not initial.ok:save_enabled=false;push_error(str(initial));get_tree().quit(1);return
	world.director.brain_trace_directory=data_dir.path_join("brain-traces")
	for brain in world.director.brains.values():brain.trace_directory=world.director.brain_trace_directory
	world.activities.persist_follow=true
	local_settings.load(data_dir.path_join("local-life.cfg"))
	world.intelligence.setup(data_dir.path_join("intelligence-preferences.cfg"))
	world.intelligence.activate_presets()
	world.hunger.start()
	if world.standard.active():world.standard.install_sites(library)
	world.director.memory_reminders.setup(local_settings,data_dir.path_join("local-life.cfg"))
	world.relationships.setup_preferences(local_settings,data_dir.path_join("local-life.cfg"))
	for id in world.director.routines:
		var routine: RefCounted=world.director.routines[id]
		var section:="resident:"+str(id)
		routine.chatter=bool(local_settings.get_value(section,"chatter",local_settings.get_value("life","chatter",true)))
		routine.set_enabled(bool(local_settings.get_value(section,"enabled",local_settings.get_value("life","enabled",true) if id=="codex" else true)) and snapshot_path.is_empty())
	if not loaded.get("loaded",false) and Opening.v3(world) and (OS.get_environment("HABITAT_OPENING")!="legacy" or "--opening=standard" in OS.get_cmdline_user_args() or "--opening=showcase" in OS.get_cmdline_user_args()) and bool(local_settings.get_value("follow","enabled",true)):
		world.activities.set_followers(world.actors.keys().filter(func(id):return id!="human"))
	world.residents.apply_names(world)
	for id in world.actors:
		var appearance: String=world.residents.appearance_for(id,"")
		# Preserve explicit assignments even when a work is temporarily unavailable.
		if world.actors[id].get("custom_appearance",false):continue
		if not appearance.is_empty():world.actors[id].appearance_id=appearance
		elif id not in ["human","codex"]:world.actors[id].appearance_id=library.ensure_resident(id)
	if loaded.get("loaded", false) and world.actors.human.get("custom_appearance", false) and world.actors.human.appearance_id != world.residents.appearance_for("human") and snapshot_path.is_empty() and not _human_appearance_warning_acknowledged():
		call_deferred("_offer_human_appearance_restore")
	library.resident_world=world
	var font := FontVariation.new()
	font.base_font = load("res://assets/fonts/NotoSansSC.ttf") as Font
	font.variation_opentype = {"wght": 500};ui_font=font
	language=LocalText.configure(data_dir)
	get_tree().node_added.connect(_apply_window_font_deferred)
	get_tree().node_added.connect(_mark_locale_deferred)
	if not LocalText.events.changed.is_connected(refresh_locale):LocalText.events.changed.connect(refresh_locale)
	view = (preload("res://scripts/island_v3_view.gd").new() if Opening.v3(world) else View.new()); view.world = world; view.library = library; view.font = font; view.camera_defaults.configure(data_dir); add_child(view)
	if Opening.v3(world):
		var start:Array=world.map_anchor("camera");view.center=Vector2(start[0],start[1]);view.zoom=view.default_zoom("home",view.center)
	if world.actors.human.region_id in ["dark","homelands"]:view.show_region(world.actors.human.region_id);view.follow_player=true
	view.clicked.connect(_clicked)
	game_audio=preload("res://scripts/game_audio.gd").new();add_child(game_audio);game_audio.setup(world,view,data_dir)
	atlas = Atlas.new(); atlas.world = world; atlas.font = font; add_child(atlas); atlas.hide(); atlas.set_process_unhandled_input(false)
	atlas.land_clicked.connect(func(region, point):
		if atlas.navigation_mode:journey.go(region,point)
		elif region=="home":
			_toggle_atlas(false);view.show_region("home");view.follow_player=false;view.center=point)
	for id in world.actors:
		if world.director.model_controlled(id):_ensure_link(id)
	# Compatibility alias for existing controller tests; it never starts inference.
	_ensure_link("codex");link=links.codex
	endpoint = Endpoint.new(); endpoint.library = library; add_child(endpoint); endpoint.configure(world, data_dir)
	endpoint.conversation_links = links
	for id in links:
		if not _valid_link(links,id):continue
		if links[id].get_script()==preload("res://scripts/external_dialogue_link.gd"):endpoint.dialogue_links[id+":direct"]=links[id]
	var layer := CanvasLayer.new(); add_child(layer)
	var root := Control.new(); root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root.mouse_filter = Control.MOUSE_FILTER_IGNORE; layer.add_child(root)
	var theme := Theme.new(); theme.default_font = font; theme.default_font_size = 16
	theme.set_color("font_color", "Label", Color("fff4db"))
	theme.set_color("font_color", "Button", Color("fff4db"))
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	var button_style := _style(Color("294b42")); button_style.content_margin_left = 16; button_style.content_margin_right = 16; button_style.content_margin_top = 9; button_style.content_margin_bottom = 9
	theme.set_stylebox("normal", "Button", button_style)
	var hover := button_style.duplicate(); hover.bg_color = Color("476655"); theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", hover)
	root.theme = theme
	atlas.build_ui(root)
	journey=preload("res://scripts/host_journey.gd").new();add_child(journey);journey.setup(self,root)
	var top := HBoxContainer.new();top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE);top.offset_left=20;top.offset_right=-20;top.offset_top=18;top.add_theme_constant_override("separation",7);root.add_child(top)
	_button(top,T("storage.title"),func():storage_panel.open())
	_button(top,T("ui.main.my_view"),_return_to_player)
	var home_menu:=MenuButton.new();home_menu.text=T("ui.main.home");home_menu.flat=false;top.add_child(home_menu)
	for caption in [T("ui.main.farms"),T("ui.main.leisure_facilities"),T("ui.main.homestead_projects")]:home_menu.get_popup().add_item(caption)
	home_menu.get_popup().id_pressed.connect(func(id):
		if id==0:farm_panel.visible=not farm_panel.visible
		elif id==1:leisure_panel.rebuild()
		else:_open_homestead())
	var activity_menu:=MenuButton.new();activity_menu.text=T("ui.main.activities");activity_menu.flat=false;top.add_child(activity_menu)
	for caption in [T("ui.main.gomoku"),T("ui.main.fishery"),T("ui.main.barbecue")]:activity_menu.get_popup().add_item(caption)
	activity_menu.get_popup().id_pressed.connect(_activity_menu_selected)
	furniture_button=_button(top,T("ui.main.arrange"),func():interior_panel.visible=not interior_panel.visible);furniture_button.hide()
	_button(top,T("ui.main.stop_me"),func():world.command("human",{"intent":"stop"}))
	var space:=Control.new();space.size_flags_horizontal=Control.SIZE_EXPAND_FILL;top.add_child(space)
	var navigation: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/ui-navigation.json"))
	handbook_menu=MenuButton.new();handbook_menu.text=navigation.handbook_title;handbook_menu.flat=false;top.add_child(handbook_menu)
	for index in range(navigation.entries.size()):
		handbook_menu.get_popup().add_item(navigation.entries[index].label,index);handbook_menu.get_popup().set_item_metadata(index,navigation.entries[index].id)
	if world.standard.active():
		var goal_index:int=handbook_menu.get_popup().item_count
		handbook_menu.get_popup().add_item(T("theirs.goals"),goal_index);handbook_menu.get_popup().set_item_metadata(goal_index,"opening_board")
	handbook_menu.get_popup().id_pressed.connect(func(index):_handbook_selected(str(handbook_menu.get_popup().get_item_metadata(index))))
	# Compatibility reference for existing controller/editor probes; the visible entry is the handbook.
	resident_connections_button=handbook_menu
	var settings_menu:=MenuButton.new();settings_menu.text=T("ui.main.settings");settings_menu.flat=false;top.add_child(settings_menu)
	settings_menu.get_popup().add_item(T("title.return"),101)
	settings_menu.get_popup().add_item(T("ui.main.fullscreen_window"),0);settings_menu.get_popup().add_item(T("ui.main.sound_backups"),1)
	if Opening.v3(world):
		settings_menu.get_popup().add_item(T("ui.main.new_game_archive_and_restart"),99)
	settings_menu.get_popup().id_pressed.connect(func(id):
		if id==101:
			if save_enabled and Save.save_world(world,data_dir):get_tree().change_scene_to_file.call_deferred("res://scenes/title.tscn")
		elif id==99:choose_opening(true))
	settings_menu.get_popup().id_pressed.connect(func(id):
		if id==0:_toggle_fullscreen()
		elif id==1:_open_audio_settings())
	stock=Label.new();root.add_child(stock);stock.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);stock.offset_left=28;stock.offset_right=380;stock.offset_top=54;stock.horizontal_alignment=HORIZONTAL_ALIGNMENT_LEFT;stock.mouse_filter=Control.MOUSE_FILTER_IGNORE
	status=Label.new();status.set_meta("ui_message_key","ui.main.movement_hint");status.position=Vector2(28,78);status.size=Vector2(650,24);status.clip_text=true;status.add_theme_font_size_override("font_size",14);status.text=T("ui.main.movement_hint");root.add_child(status)
	order_bar = VBoxContainer.new(); order_bar.position = Vector2(28, 100); order_bar.add_theme_constant_override("separation", 12); root.add_child(order_bar)
	order_label = Label.new(); order_label.add_theme_font_size_override("font_size", 14); order_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; order_bar.add_child(order_label)
	_button(order_bar, T("ui.main.stop_this_resident"), func():_stop_resident(_control_actor())); order_bar.hide()
	var bottom := Label.new();bottom.set_meta("ui_role","movement_hint"); bottom.text = T("ui.main.arrow_keys_right_drag_to_pan_wheel_to_zoom"); bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT); bottom.offset_left = 28; bottom.offset_top = -36; bottom.add_theme_font_size_override("font_size", 13); root.add_child(bottom)
	day_label=Label.new();root.add_child(day_label);day_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT);day_label.offset_left=28;day_label.offset_top=-66;day_label.add_theme_font_size_override("font_size",18);day_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	day_label.text=LocalText.text("title.name")+" · "+T("ui.main.day_d_s_s")%[world.days.day(),LocalText.content(world.days.phase().name),LocalText.content(world.weather.current().name)]
	project_panel = ProjectPanel.new(); root.add_child(project_panel); project_panel.setup(world)
	project_panel.control_requested.connect(_project_control)
	project_panel.discuss_requested.connect(_discuss_project)
	project_panel.enter_requested.connect(func(id): _room_action({"intent": "enter", "target_id": id}))
	project_panel.inspect_requested.connect(func(id):
		_toggle_atlas(false); view.show_region(world.objects[id].region_id); view.center = world.point(world.objects[id]); house_panel.open_site(id))
	_build_chat(root)
	dialogue_button = _button(root, T("ui.main.chat"), func(): resident_connections.close_panel(); homestead_panel.hide(); memory_panel.hide(); chat.visible = not chat.visible; chat_input.release_focus(); view.motion.attend())
	dialogue_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	dialogue_button.offset_left = -164; dialogue_button.offset_right = -12; dialogue_button.offset_top = -60; dialogue_button.offset_bottom = -18
	follow_ui=preload("res://scripts/player_follow_ui.gd").new();add_child(follow_ui);follow_ui.setup(self)
	gathering_button=_button(root,T("ui.main.follow"),follow_ui.open);gathering_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	gathering_button.offset_left=92;gathering_button.offset_right=234;gathering_button.offset_top=-60;gathering_button.offset_bottom=-18
	actions_button=_button(root,T("ui.main.actions"),func():resident_connections.close_panel();homestead_panel.hide();chat.hide();action_dock.toggle_menu())
	actions_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM);actions_button.offset_left=12;actions_button.offset_right=164;actions_button.offset_top=-60;actions_button.offset_bottom=-18
	action_dock=preload("res://scripts/action_dock.gd").new();root.add_child(action_dock);action_dock.setup(world,self)
	action_dock.chat_requested.connect(func():action_dock.menu.hide();_select_chat(Channels.ALL);chat.show())
	ai_connect_panel=preload("res://scripts/ai_connect_panel.gd").new();root.add_child(ai_connect_panel);ai_connect_panel.setup(world,data_dir);ai_connect_panel.bind_requested.connect(_bind_external_ai)
	action_dock.connection_requested.connect(_toggle_resident_connections)
	action_dock.invite_requested.connect(_invite_fishers)
	journal_panel=preload("res://scripts/journal_panel.gd").new();root.add_child(journal_panel);journal_panel.setup(world,view.fishing_renderer)
	day_journal_overlay=preload("res://scripts/day_journal_overlay.gd").new();root.add_child(day_journal_overlay);day_journal_overlay.setup(world,journal_panel)
	action_dock.journal_requested.connect(func():chat.hide();journal_panel.open())
	gathering_note=Label.new();root.add_child(gathering_note);gathering_note.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM);gathering_note.offset_left=-240;gathering_note.offset_top=-90;gathering_note.offset_right=240;gathering_note.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	participant_picker=preload("res://scripts/participant_picker.gd").new();root.add_child(participant_picker);participant_picker.setup(world);participant_picker.chosen.connect(_participants_chosen)
	var activity_style := _style(Color("213e37"))
	activity_style.content_margin_left = 14; activity_style.content_margin_right = 14; activity_style.content_margin_top = 12; activity_style.content_margin_bottom = 12
	memory_panel=preload("res://scripts/memory_panel.gd").new();root.add_child(memory_panel)
	book_panel=preload("res://scripts/memory_book_panel.gd").new();root.add_child(book_panel);book_panel.setup(memory_books,world)
	memory_life=preload("res://scripts/memory_life.gd").new();add_child(memory_life);memory_life.setup(self)
	life_archive=preload("res://scripts/life_archive.gd").new();add_child(life_archive);life_archive.setup(self)
	memory_books.life_archive_ref=weakref(life_archive)
	if world.director.local_dialogue!=null:world.director.local_dialogue.mood_provider=func(id):return life_archive.snapshot(id).get("mood",{}) if life_archive.enabled(id) else {}
	_setup_connection_overview.call_deferred()
	memory_panel.add_theme_stylebox_override("panel",activity_style.duplicate());memory_panel.setup(world)
	leisure_panel=preload("res://scripts/leisure_panel.gd").new();root.add_child(leisure_panel);leisure_panel.setup(world)
	leisure_panel.invite_requested.connect(func(args):participant_picker.open_for(args,chat_actor))
	leisure_panel.edit_requested.connect(func(id):leisure_panel.hide();editor.open_art(id))
	leisure_panel.place_requested.connect(func(id):placing_facility=id;status.text=T("ui.main.choose_an_open_spot_for_the_facility_foundation"))
	leisure_panel.inspect_requested.connect(func(id):view.show_region("home");view.follow_player=false;view.center=world.point(world.leisure.sites[id]))
	leisure_panel.game_requested.connect(_walk_to_chess)
	storage_panel=preload("res://scripts/storage_panel.gd").new();root.add_child(storage_panel);storage_panel.setup(world)
	storage_panel.deposit_all_requested.connect(func():
		var result:Dictionary=world.deposit_all("human");status.text=T("storage.deposited") if result.ok else T("storage.transfer_failed");storage_panel.refresh())
	storage_panel.take_requested.connect(func(item,quantity):
		var result:Dictionary=world.take_storage_host(item,quantity);status.text=T("storage.taken") if result.ok else T("storage.transfer_failed");storage_panel.refresh())
	storage_panel.grill_requested.connect(choose_direct_grill)
	jieqi_panel=preload("res://scripts/jieqi_panel.gd").new();root.add_child(jieqi_panel);jieqi_panel.setup(world.jieqi)
	jieqi_panel.bubble_delivered.connect(_chess_bubble_sound)
	jieqi_panel.change_requested.connect(func():jieqi_panel.hide();_open_chess(world.jieqi.site_id))
	chess_choice=preload("res://scripts/chess_choice_panel.gd").new();root.add_child(chess_choice);chess_choice.setup(world)
	chess_choice.chosen.connect(func(kind,id):
		if kind=="gomoku":_open_gomoku(id)
		else:world.jieqi.site_id=id;_focus_chess_table(id);jieqi_panel.open(kind))
	chess_choice.continued.connect(func(kind,id):
		if kind=="gomoku":_open_gomoku(id)
		else:_focus_chess_table(id);jieqi_panel.open("",true))
	gomoku_panel=preload("res://scripts/gomoku_panel.gd").new();root.add_child(gomoku_panel);gomoku_panel.setup(world)
	gomoku_panel.bubble_delivered.connect(_chess_bubble_sound)
	gomoku_panel.change_requested.connect(func():gomoku_panel.card.hide();_open_chess(gomoku_panel.site_id))
	gomoku_panel.start_requested.connect(_begin_gomoku)
	gomoku_panel.resume_requested.connect(_resume_gomoku)
	gomoku_panel.build_requested.connect(func(id):gomoku_panel.card.hide();participant_picker.open_for({"intent":"build_facility","target_id":id},chat_actor))
	gomoku_match_host=preload("res://scripts/gomoku_match_host.gd").new();gomoku_match_host.setup(self)
	gomoku_panel.connection_provider=gomoku_match_host.connected
	gomoku_panel.ai_start_requested.connect(func(site,black,white,sources):
		var result: Dictionary=gomoku_match_host.begin(site,black,white,sources);gomoku_panel.message.text=str(result.get("message",result.get("error",T("ui.main.players_invited"))));gomoku_panel.refresh())
	gomoku_panel.ai_pause_requested.connect(func(site):gomoku_match_host.pause_site(site);gomoku_panel.refresh())
	gomoku_panel.ai_resume_requested.connect(func(site):
		var match_id: String=world.gomoku.sessions.get(site,{}).get("id","")
		gomoku_panel.ask_budget(func():
			if world.gomoku.sessions.get(site,{}).get("id")==match_id:
				var result: Dictionary=gomoku_match_host.resume(site);gomoku_panel.message.text=str(result.get("error",""));gomoku_panel.refresh()))
	gomoku_panel.ai_end_requested.connect(func(site):gomoku_match_host.end(site);gomoku_panel.refresh())
	gomoku_dialogue=preload("res://scripts/gomoku_dialogue_host.gd").new();gomoku_dialogue.setup(self)
	gomoku_panel.model_step_requested.connect(func(id,table_id):
		if not gomoku_dialogue.request(id,table_id):gomoku_panel.message.text=T("ui.main.can_t_send_right_now_wait_for_the_current_reply_or_check_the_conn"))
	gomoku_panel.chat_requested.connect(func(table_id,text):
		if not text.strip_edges().is_empty() and not gomoku_dialogue.chat(table_id,text):gomoku_panel.message.text=T("ui.main.this_message_hasn_t_been_sent_wait_for_the_current_reply"))

	house_panel = House.new(); root.add_child(house_panel); house_panel.setup(world, library)
	house_panel.build_requested.connect(func(id):
		var result: Dictionary = world.command("human", {"intent": "build", "target_id": id})
		house_panel.feedback.text = str(result.get("message", result.get("error", ""))); house_panel.refresh())
	house_panel.delivery_requested.connect(func(id):
		var result: Dictionary = world.command("human", {"intent": "deliver_wood", "target_id": id})
		house_panel.feedback.text = str(result.get("message", result.get("error", ""))))
	house_panel.enter_requested.connect(func(id): _room_action({"intent": "enter", "target_id": id}); house_panel.hide())
	house_panel.companion_requested.connect(func(id):participant_picker.open_for({"intent":"enter" if int(world.objects[id].get("stage_index",0))==5 else "build_house","target_id":id},chat_actor))
	house_panel.edit_requested.connect(func(id): house_panel.hide(); editor.open_art(id))
	editor = Editor.new(); editor.add_theme_stylebox_override("panel", _style(Color("203b36"))); root.add_child(editor); editor.setup(library)
	editor.applied.connect(func(): view.queue_redraw();_refresh_resident_names();leisure_panel.rebuild();leisure_panel.hide())
	editor.blueprint_requested.connect(func(id):
		var result: Dictionary = world.command("human", {"intent": "select_blueprint", "target_id": house_panel.site_id, "blueprint_id": id})
		editor.feedback.text = str(result.get("message", result.get("error", T("ui.main.design_selected")))))
	interior_panel = Inside.new(); root.add_child(interior_panel); interior_panel.setup(world, library)
	interior_panel.recipe_selected.connect(func(recipe): view.placement_recipe = recipe)
	interior_panel.action_requested.connect(_room_action)
	interior_panel.invite_requested.connect(func(id):participant_picker.open_for({"intent":"sit","target_id":id},chat_actor))
	interior_panel.edit_requested.connect(func(id): interior_panel.hide(); editor.open_art(id))
	farm_panel = preload("res://scripts/farm_panel.gd").new(); root.add_child(farm_panel); farm_panel.setup(world)
	farm_panel.focus_requested.connect(func(id): _toggle_atlas(false); view.show_region("home"); view.follow_player=false; view.center=world.catalog.rectangle(world.farms.farms[id].rect).get_center(); farm_panel.show())
	farm_panel.edit_requested.connect(func(id): farm_panel.hide(); editor.open_art(id))
	farm_panel.discuss_requested.connect(func(id,text): _select_chat(id); _send(text))
	farm_panel.helpers_requested.connect(_open_farm_helpers)
	farm_commands = preload("res://scripts/farm_commands.gd").new()
	local_host_commands=preload("res://scripts/local_host_commands.gd").new(self);add_child(local_host_commands)
	intentions=preload("res://scripts/resident_intentions.gd").new();add_child(intentions);intentions.setup(self)
	steward=preload("res://scripts/steward_host.gd").new();add_child(steward);steward.setup(self)
	world.flower_creation.trade_authority=func(id):return steward!=null and steward.authorized(id)
	brain_panel=preload("res://scripts/brain_panel.gd").new();root.add_child(brain_panel);brain_panel.setup(world,library)
	view.mind_clicked.connect(func(id):brain_panel.open(id))
	endpoint.resident_context=func(id):return {"management":steward.authorized(id),"managed_by":steward.manager if steward.active else "","work_options":steward.work_context() if steward.authorized(id) else []}
	local_host_commands.feedback.connect(_local_command_feedback)
	local_host_commands.completed.connect(_local_command_feedback)
	local_host_commands.actor_reply.connect(func(id:String,line:String,channel:String):_record_chat(channel,id,line,"local") if channel!="command" else null)
	local_host_commands.barbecue_requested.connect(_local_barbecue_requested)
	for resident in world.actors:
		if resident=="human":continue
		if world.director.model_controlled(resident) and memory_books.list_for(resident).any(func(e):return e.world_id!=world.world_id) and memory_books.add(resident,world.world_id,"reunion","facts","memory.reunion",{},world.days.day(),"local",["human",resident]):
			local_host_commands.speech_queue.append({"actor_id":resident,"line":T("memory.reunion"),"channel_id":Channels.direct(resident),"expires":world.director.time+180})
	view.need_clicked.connect(_need_clicked)
	var resort_ui=preload("res://scripts/resort_ui.gd").new();add_child(resort_ui);resort_ui.setup(self)
	fishing_panel=preload("res://scripts/fishing_panel.gd").new();root.add_child(fishing_panel)
	var fishing_style:=_style(Color("24454b"))
	fishing_style.content_margin_left=14;fishing_style.content_margin_right=14;fishing_style.content_margin_top=12;fishing_style.content_margin_bottom=12
	fishing_panel.add_theme_stylebox_override("panel",fishing_style);fishing_panel.setup(world,view.fishing_renderer)
	fishing_panel.grill_requested.connect(choose_direct_grill)
	fishing_panel.focus_requested.connect(_focus_fishery)
	fishing_panel.greet_requested.connect(func(id):view.fishing_renderer.greet(id,view.clock))
	_build_resident_connections(root)
	homestead_panel=preload("res://scripts/homestead_panel.gd").new();root.add_child(homestead_panel);homestead_panel.setup(world)
	homestead_panel.command_requested.connect(_homestead_action)
	homestead_panel.focus_requested.connect(func():_toggle_atlas(false);view.show_region("home");view.follow_player=false;view.center=world.homestead.area().get_center()+Vector2(0,1))
	homestead_panel.recipe_requested.connect(func():homestead_panel.hide();_show_barbecue_menu())
	_button(resident_connections.actions_host,T("ui.main.homestead_projects"),func():_open_homestead(resident_connections.selected_id))
	view.last_human_region = world.actors.human.region_id
	if world.actors.human.region_id != "home": view.show_region(world.actors.human.region_id)
	if not loaded.ok: status.text = T("ui.main.couldn_t_read_the_old_progress_file_the_original_is_safe_for_reco")
	playground=preload("res://scripts/playground.gd").new();add_child(playground);playground.setup(self)
	if Opening.v3(world):
		island_hud=preload("res://scripts/island_hud.gd").new();root.add_child(island_hud);island_hud.setup(self,root,top,settings_menu)
		watch_ui=preload("res://scripts/watch_ui.gd").new();add_child(watch_ui);watch_ui.setup.call_deferred(self)
		ui_scale=preload("res://scripts/ui_scale.gd").new();add_child(ui_scale);ui_scale.setup(self,root,data_dir)
	for panel_node in [farm_panel,journal_panel,memory_panel,book_panel,fishing_panel,resident_connections,house_panel,interior_panel,leisure_panel,homestead_panel,proposal_panel,wish_panel,editor,action_dock.menu,island_hud.wardrobe if island_hud!=null else null]:
		if panel_node==null:continue
		var overlay:Control=panel_node
		overlay.visibility_changed.connect(func():_present_overlay(overlay))
	if not snapshot_path.is_empty():
		if scenario.begins_with("interior"):
			_interior_scenario()
			if scenario == "interior_layout": interior_panel.show()
			if scenario == "interior_editor": editor.open_art("furniture-chair")
			if scenario == "interior_chair": interior_panel.select_item("furniture.4")
		if scenario.begins_with("project_"): _project_scenario()
		if scenario.begins_with("farm"): _farm_scenario()
		if scenario.begins_with("village"): _village_scenario()
		if scenario.begins_with("leisure"): _leisure_scenario()
		if scenario.begins_with("daily_"): _daily_scenario()
		if scenario == "partial_build": _partial_build_scenario()
		if scenario == "wood_order": _wood_order_scenario()
		if scenario == "forest_regrowth": _forest_scenario()
		if scenario == "house": _house_scenario()
		if scenario == "editor": editor.open_art("white-haired-girl")
		if scenario == "chat": chat.show()
		if scenario == "chat_group": _select_chat(Channels.ALL); chat.show()
		if scenario == "camera": _return_to_player()
		if scenario == "building_editor": editor.open_art("cottage")
		if scenario == "garden": view.center = world.locations.point("p_37_56"); view.zoom = 1.3
		if scenario == "map": _toggle_atlas(true)
		if scenario == "homestead_blue":
			world.command("human", {"intent": "select_blueprint", "target_id": "home.house.01", "blueprint_id": "cottage-blue"}); _house_scenario(); view.center = world.locations.point("p_39_40"); view.zoom = 1.0; house_panel.open_site("home.house.01")
		if scenario == "homestead": _house_scenario(); view.center = world.locations.point("p_39_40"); view.zoom = 1.0; house_panel.open_site("home.house.01")
		if scenario == "pond": view.center = world.locations.point("p_113_82"); view.zoom = .9
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(snapshot_path)
		get_tree().call_deferred("quit")

func _human_appearance_warning_acknowledged() -> bool:
	var preferences := ConfigFile.new()
	preferences.load(data_dir.path_join("appearance-preferences.cfg"))
	return bool(preferences.get_value("human", "keep_acknowledged", false))

func _remember_human_appearance() -> void:
	var preferences := ConfigFile.new()
	preferences.load(data_dir.path_join("appearance-preferences.cfg"))
	preferences.set_value("human", "keep_acknowledged", true)
	if preferences.save(data_dir.path_join("appearance-preferences.cfg")) != OK: status.text = T("ui.main.couldn_t_save_the_appearance_preference")

func _offer_human_appearance_restore() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = T("ui.main.check_your_appearance")
	dialog.dialog_text = T("ui.main.you_re_using_a_different_appearance_keep_it_if_you_chose_it_or_ba")
	dialog.ok_button_text = T("ui.main.back_up_and_restore_default")
	dialog.cancel_button_text = T("ui.main.keep_current_appearance")
	add_child(dialog)
	dialog.confirmed.connect(func():
		var result: Dictionary = Save.restore_human_appearance(world, data_dir) if save_enabled else {"ok": false}
		if not result.ok: status.text = T("ui.main.couldn_t_back_up_the_save_your_appearance_hasn_t_changed")
		else: status.text = T("ui.main.save_backed_up_and_your_default_appearance_restored")
		dialog.queue_free())
	dialog.canceled.connect(func(): _remember_human_appearance(); dialog.queue_free())
	dialog.popup_centered()

func _style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new(); style.bg_color = color
	style.corner_radius_top_left = 10; style.corner_radius_top_right = 10; style.corner_radius_bottom_left = 10; style.corner_radius_bottom_right = 10
	return style

func _toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	var fullscreen := mode in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)

func _input(event: InputEvent) -> void:
	if not flower_placement.is_empty() and event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
		flower_placement.clear();flower_actor_ids.clear();status.text="";get_viewport().set_input_as_handled();return
	if view!=null and not view.follow_player and (event is InputEventMouseButton or event is InputEventMouseMotion):view.peek_elapsed=0
	var typing:Control=get_viewport().gui_get_focus_owner()
	if event is InputEventKey and event.pressed and event.keycode==KEY_SPACE and not (typing is LineEdit or typing is TextEdit):
		_return_to_player();get_viewport().set_input_as_handled();return
	if steward!=null and event is InputEventKey and event.pressed and event.keycode in [KEY_UP,KEY_DOWN,KEY_LEFT,KEY_RIGHT] and (chat_input==null or chat_input.text.is_empty()):steward.manual_camera=true
	if chat_input!=null and chat.visible:
		if event is InputEventMouseButton and event.pressed and not chat.get_global_rect().has_point(event.position):chat_input.release_focus()
		if event is InputEventKey and event.pressed:
			if event.keycode==KEY_ESCAPE:
				chat.hide();chat_input.release_focus();get_viewport().set_input_as_handled();return
			if event.keycode in [KEY_ENTER,KEY_KP_ENTER] and not chat_input.has_focus():
				chat_input.grab_focus();get_viewport().set_input_as_handled();return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER,KEY_KP_ENTER] and chat_input!=null and chat_input.has_focus() and _chat_is_composing():
		_chat_ime_enter_frame=Engine.get_process_frames()
	if not pending_chess.is_empty() and event.is_pressed() and (event is InputEventMouseButton or event is InputEventKey):pending_chess.clear()
	if not pending_camp.is_empty() and event.is_pressed() and (event is InputEventMouseButton or event is InputEventKey):pending_camp.clear()
	var card_modal:bool=island_hud!=null and island_hud.ui_root!=null and island_hud.ui_root.get_children().any(func(child):return child is Window and child.visible)
	if not card_modal and island_hud!=null and island_hud.resident_card!=null and island_hud.resident_card.visible:
		var outside:bool=event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT and not island_hud.resident_card.get_global_rect().has_point(event.position)
		var escape:bool=event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE
		if outside or escape:
			island_hud.resident_card.hide();get_viewport().set_input_as_handled();return
	if world!=null and ((event is InputEventMouseMotion and event.relative!=Vector2.ZERO) or event.is_pressed()):
		world.director.moods.player_input()
		if event.is_pressed():
			world.relationships.player_input()
			if autonomy!=null:autonomy.player_input()
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE and book_panel!=null and book_panel.visible:book_panel.hide();get_viewport().set_input_as_handled();return
	if not event is InputEventKey or not event.pressed or event.echo: return
	if chat_input!=null and chat_input.has_focus() and event.keycode not in [KEY_UP,KEY_DOWN,KEY_LEFT,KEY_RIGHT,KEY_ENTER,KEY_KP_ENTER,KEY_ESCAPE]:return
	if event.keycode == KEY_F11 or (event.keycode == KEY_F and event.ctrl_pressed and event.meta_pressed):
		_toggle_fullscreen()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_M and not chat_input.has_focus() and not editor.visible:
		if journey.shortcuts.visible:journey.shortcuts.hide();_toggle_atlas(true,true)
		else:journey.toggle_menu()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and not editor.visible:
		journey.cancel()
		if homestead_panel!=null:homestead_panel.hide()
		if resident_connections!=null:resident_connections.close_panel()
		if gift_panel!=null:gift_panel.hide()
		memory_panel.hide()
		fishing_panel.hide()
		journal_panel.hide()
		action_dock.menu.hide();action_dock.strip.hide();action_dock.dismissed=true
		if atlas.visible:_toggle_atlas(false)
		view.placement_recipe = "";placing_facility="";leisure_panel.hide(); interior_panel.hide(); farm_panel.hide(); chat.hide(); get_viewport().set_input_as_handled()
		gomoku_panel.card.hide()
	elif event.keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT] and _camera_keys_allowed():
		_pan_camera({KEY_UP:Vector2.UP,KEY_DOWN:Vector2.DOWN,KEY_LEFT:Vector2.LEFT,KEY_RIGHT:Vector2.RIGHT}[event.keycode],1.0/60.0)
		get_viewport().set_input_as_handled()

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new();button.focus_mode=Control.FOCUS_NONE; button.text = text;button.set_meta("audio_primary",_locale_values.get(text,"") in ["ui.main.chat","ui.main.follow","ui.main.actions","ui.main.handbook","ui.main.settings"]); button.focus_mode = Control.FOCUS_NONE; button.pressed.connect(callback); parent.add_child(button); return button

func _toggle_atlas(visible_now: bool,navigation:bool=false) -> void:
	atlas.navigation_mode=navigation
	atlas.visible = visible_now; atlas.set_process_unhandled_input(visible_now)
	view.visible = not visible_now; view.set_process_unhandled_input(not visible_now)
	if status != null:status.visible=not visible_now
	if visible_now:
		if homestead_panel!=null:homestead_panel.hide()
		if resident_connections!=null:resident_connections.close_panel()
		atlas.open()
		if chat != null:chat.hide()
		if leisure_panel != null:leisure_panel.hide()
		if gomoku_panel != null:gomoku_panel.card.hide()
		if interior_panel != null:interior_panel.hide()
		if memory_panel != null:memory_panel.hide()
		if fishing_panel != null:fishing_panel.hide()
		if action_dock!=null:action_dock.menu.hide();action_dock.strip.hide();action_dock.dismissed=true
	else:
		atlas.panel.hide();atlas.dragging=false
	if house_panel != null: house_panel.hide()
	if farm_panel != null: farm_panel.hide()

func _return_to_player() -> void:
	_toggle_atlas(false)
	if steward!=null:steward.manual_camera=true
	view.follow_actor="human"
	view.center=world.point(world.actors.human)
	view.follow_player = true
	view.show_region(world.actors.human.region_id)
	view.follow_player = world.actors.human.region_id in ["home","dark","homelands"]
	view.dragging = false
	atlas.dragging = false

func _camera_keys_allowed() -> bool:
	if editor == null or editor.visible: return false
	if resident_connections!=null and resident_connections.visible:return false
	if homestead_panel!=null and homestead_panel.visible:return false
	if memory_panel != null and memory_panel.visible:return false
	if book_panel != null and book_panel.visible:return false
	var focus := get_viewport().gui_get_focus_owner()
	return focus==null or (focus==chat_input and chat_input.text.is_empty() and not _chat_is_composing())

func _pan_camera(direction: Vector2, delta: float) -> void:
	if direction.is_zero_approx(): return
	if atlas.visible:
		atlas.center += direction.normalized() * 620.0 * delta / atlas.scale_factor
		atlas.clamp_center()
	else:
		view.follow_player = false
		view.center += direction.normalized() * 1240.0 * delta / (32.0 * view.zoom)

func _build_chat(root: Control) -> void:
	chat = PanelContainer.new(); root.add_child(chat)
	chat.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	chat.offset_left = -350; chat.offset_right = 350; chat.offset_top = -410; chat.offset_bottom = -72
	# Extra choices grow upward while the input stays above the bottom buttons.
	chat.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var style := _style(Color("213e37")); style.content_margin_left = 18; style.content_margin_right = 18; style.content_margin_top = 12; style.content_margin_bottom = 12; chat.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation", 8); chat.add_child(column)
	var header := HBoxContainer.new(); column.add_child(header)
	var title := Label.new(); title.text = T("ui.main.chat"); title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; title.add_theme_font_size_override("font_size", 20); header.add_child(title)
	var who := Label.new(); who.text = T("ui.main.who_would_you_like_to_talk_to"); header.add_child(who)
	chat_picker = OptionButton.new(); header.add_child(chat_picker)
	for id in world.actors:
		if id == "human": continue
		chat_picker.add_item(LocalText.resident(world,id)); chat_picker.set_item_metadata(chat_picker.item_count-1,id)
	chat_picker.add_item(T("ui.main.everyone")); chat_picker.set_item_metadata(chat_picker.item_count-1, Channels.ALL)
	chat_picker.item_selected.connect(func(index): _select_chat(str(chat_picker.get_item_metadata(index))))
	find_partner_button = _button(header, T("ui.main.find_companion"), _focus_companion)
	find_partner_button.tooltip_text = T("ui.main.show_where_this_companion_is_only_the_camera_moves_nobody_s_actio")
	stop_chat_button = _button(header, T("ui.main.stop_companion"), _stop_companion)
	_button(header, T("ui.main.close"), func(): chat.hide(); chat_input.release_focus())
	var control_row:=VBoxContainer.new();column.add_child(control_row)
	controller_picker=OptionButton.new();controller_picker.add_item(T("ui.main.separate_conversation"));controller_picker.add_item(T("ui.main.local_interaction"));control_row.add_child(controller_picker)
	controller_picker.tooltip_text=T("ui.main.changing_control_source_pauses_existing_work_identity_items_and_c")
	controller_picker.item_selected.connect(_change_controller)
	relay_button = _button(control_row, T("ui.main.copy_to_codex"), _copy_conversation_message)
	relay_button.tooltip_text = T("ui.main.manual_relay_check_paste_into_the_bound_codex_conversation_this_e")
	shared_button = _button(control_row, T("ui.main.try_automatic_dialogue"), _toggle_shared_test)
	shared_button.hide()
	shared_button.tooltip_text = T("ui.main.use_a_separate_shared_test_conversation_keeping_the_original_bind")
	resident_status=Label.new();resident_status.size_flags_horizontal=Control.SIZE_EXPAND_FILL;control_row.add_child(resident_status)
	var daily := HFlowContainer.new(); daily_controls = daily; daily.add_theme_constant_override("h_separation", 12); column.add_child(daily)
	activity_toggle = CheckButton.new(); activity_toggle.text = T("ui.main.daily_activities_local"); activity_toggle.button_pressed = world.local_companion.enabled; daily.add_child(activity_toggle)
	activity_toggle.tooltip_text = T("ui.main.local_rules_handle_wandering_and_rest_without_model_calls_work_an")
	activity_toggle.toggled.connect(func(value): world.director.routines[_control_actor()].set_enabled(value); _save_local_settings(); _clear_local_bubble())
	chatter_toggle = CheckButton.new(); chatter_toggle.text = T("ui.main.daily_lines_local"); chatter_toggle.button_pressed = world.local_companion.chatter; daily.add_child(chatter_toggle)
	chatter_toggle.tooltip_text = T("ui.main.preset_scene_lines_marked_as_daily_chatter_they_never_replace_a_r")
	chatter_toggle.toggled.connect(func(value): world.director.routines[_control_actor()].set_chatter(value); _save_local_settings(); _clear_local_bubble())
	var greet_button := _button(daily, T("ui.main.say_hello"), func(): _local_interaction(false))
	greet_button.tooltip_text = T("ui.main.a_nearby_companion_replies_with_a_preset_line_no_model_request_is")
	_button(daily, T("ui.main.come_keep_me_company"), func(): _local_interaction(true))
	_button(daily,T("ui.main.dance_together"),func():participant_picker.open_for({"intent":"dance"},_control_actor()))
	chat_log = RichTextLabel.new(); chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL; chat_log.custom_minimum_size = Vector2(0, 112); chat_log.scroll_following = true; column.add_child(chat_log)
	choices = HFlowContainer.new(); column.add_child(choices)
	activity_choices = HFlowContainer.new(); column.add_child(activity_choices)
	question_picker = OptionButton.new(); column.add_child(question_picker); question_picker.hide()
	question_picker.item_selected.connect(func(_index): _refresh_chat_placeholder())
	var input_row := HBoxContainer.new(); column.add_child(input_row)
	chat_input = LineEdit.new(); chat_input.placeholder_text = T("ui.main.chat_or_ask_for_a_hand"); chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL; chat_input.text_submitted.connect(_send); input_row.add_child(chat_input)
	chat_send_button=_button(input_row, T("ui.main.send"), func(): _send(chat_input.text))
	chat.hide();_refresh_control_ui()
	command_page=preload("res://scripts/command_page.gd").new();add_child(command_page);command_page.setup(self,column)

func _clear_choices() -> void:
	for child in choices.get_children(): choices.remove_child(child); child.queue_free()

func _clear_activity_choices() -> void:
	for child in activity_choices.get_children(): activity_choices.remove_child(child); child.queue_free()

func _local_context_reply(id:String)->String:
	var choices:Array[String]=[]
	if world.hunger.rank(id)>=2:choices.append(LocalText.text("content.overnight.text.a854fac9fa318f"))
	if int(world.weather.current().get("rain",0))>0:choices.append(LocalText.text("content.overnight.text.59d3a67d8993ce"))
	if world.days.phase().id=="night":choices.append(LocalText.text("content.overnight.text.03a86a624ff6fd"))
	var completed:Array=world.work.events.filter(func(event):return event.actor_id==id and event.status=="completed")
	if not completed.is_empty():choices.append(LocalText.text("content.overnight.text.837d6153e7a867"))
	var neighbors:Array=world.actors.keys().filter(func(who):return who not in [id,"human"] and world.actors[who].region_id==world.actors[id].region_id and world.point(world.actors[who]).distance_to(world.point(world.actors[id]))<=4)
	if not neighbors.is_empty():choices.append(LocalText.resident(world,str(neighbors[0]))+LocalText.text("content.overnight.text.b933abf2e06aae"))
	if choices.is_empty():return T("memory.thinking."+world.intelligence.tag(id))
	return choices[(dialogue.histories.get(Channels.direct(id),[]).size())%choices.size()]

func _set_channel_status(channel: String, text: String) -> void:
	dialogue.statuses[channel] = text
	if text.ends_with(T("system.fireside.this_meal_has_finished")) or text.ends_with(T("system.fireside.the_fireside_ended_this_does_not_mean_the")):
		get_tree().create_timer(4).timeout.connect(func():
			if dialogue.statuses.get(channel,"")==text:dialogue.statuses[channel]=""
			if is_instance_valid(status) and status.text==text:status.text="")
	if channel == _chat_channel() and status != null:status.text=text;status.set_meta("external_receipt",text)

func _focus_companion() -> void:
	var id:=_control_actor()
	if (group_chat and not _resident_panel_open()) or not world.actors.has(id):return
	var actor: Dictionary=world.actors[id]
	_toggle_atlas(false);view.show_region(actor.region_id);view.center=world.point(actor);view.follow_player=false
	chat_input.release_focus();status.text=T("ui.main.resident_location") % LocalText.resident(world,id)

func _chat_channel() -> String:
	return Channels.ALL if group_chat else Channels.direct(chat_actor)

func _record_chat(channel: String, actor_id: String, text: String, kind := "message", request_id := "") -> Dictionary:
	var entry: Dictionary = dialogue.append(channel, actor_id, text, kind, request_id)
	if actor_id=="human" and kind in ["message","answer"]:
		var recipients:Array=(command_page.selected.duplicate() if command_page!=null and not command_page.selected.is_empty() else world.actors.keys().filter(func(id):return id!="human")) if channel==Channels.ALL else [channel.trim_prefix("direct:")]
		for resident in recipients:
			if world.director.brains.has(resident):world.director.brains[resident].interactions.talked_day=world.days.day()
			memory_books.remember_chat(resident,world.world_id,entry.message_id,text,world.days.day(),channel)
			memory_books.learn(resident,world.world_id,entry.message_id,text,world.days.day())
	if channel == _chat_channel(): _render_chat()
	else: dialogue.unread[channel] = int(dialogue.unread.get(channel, 0)) + 1
	return entry

func _render_chat(mark_read:bool=true) -> void:
	if chat_log == null: return
	chat_log.clear()
	var channel := _chat_channel()
	if mark_read:dialogue.unread.erase(channel)
	for entry in dialogue.histories.get(channel, []):
		var name: String = LocalText.resident(world,"human") if entry.sender_id == "human" else LocalText.resident(world,str(entry.sender_id)) if world.actors.has(entry.sender_id) else T("ui.main.notice")
		if entry.sender_id == "human": name += " → " + (T("ui.main.everyone") if group_chat else str(LocalText.resident(world,chat_actor)))
		var suffix: String = {"local":T("ui.main.daily"), "progress":T("ui.main.progress"), "notice":T("ui.main.notice_82")}.get(entry.kind, "")
		if entry.kind == "question":
			var pending: Dictionary = group_questions if group_chat else questions
			var question: Dictionary = pending.get(entry.sender_id, {})
			suffix = T("ui.main.waiting_for_your_answer") if not question.is_empty() and question.id == entry.get("request_id", "") and question.get("history_message_id", "") == entry.message_id else T("ui.main.question")
		if str(entry.sender_id) not in ["","human"] and entry.kind in ["message","question"]: name = T("ui.main.model") + name
		if entry.kind == "local": suffix = ""
		if entry.kind == "autonomy": name = T("ui.main.autonomous") + name; suffix = ""
		if str(entry.sender_id).is_empty(): suffix = ""
		if entry.kind=="execution":
			chat_log.push_font_size(preload("res://scripts/ui_scale.gd").pixels(12));chat_log.push_color(Color("b9c9bc"));chat_log.add_text(str(entry.text)+"\n");chat_log.pop();chat_log.pop()
		else:chat_log.add_text(name + suffix + "：" + str(entry.text) + "\n\n")

func _snapshot_for_chat(id: String, channel: String, recipients: Array, message_id: String) -> Dictionary:
	if _valid_link(links,id) and links[id].has_method("uses_intents") and links[id].uses_intents() and not world.gomoku.active(id):
		var small:Dictionary={"dialogue":_memory_dialogue_context(id,channel,recipients,message_id)}
		return {"intent_card":_intent_card(id,small,channel),"intelligence_level":resident_connections.preferences.preference(id).level}
	var snapshot: Dictionary = world.observe(id, {"limit": 60})
	for site in world.gomoku.sessions:
		var board:Dictionary=world.gomoku.sessions[site]
		if board.get("mode")=="model" and board.get("phase")=="playing" and id in world.gomoku.players(board):
			var owned_memories:Array=world.memories.records.filter(func(fact):return id in fact.participants).slice(-3).duplicate(true)
			snapshot={"ok":true,"world_id":world.world_id,"self_actor_id":id,"self":snapshot.self,"source":"host_requested_gomoku_match","gomoku":world.gomoku.read(site,id),"memories":owned_memories,"actions":{"version":2,"actions":snapshot.actions.actions.filter(func(action):return str(action.id).begins_with("gomoku_"))}}
			break
	if not selected_id.is_empty(): snapshot["selected_object_id"] = selected_id
	snapshot["dialogue"] = _memory_dialogue_context(id,channel,recipients,message_id)
	snapshot["memory_card"]=memory_books.card(id,"",channel,resident_connections.preferences.preference(id).level)
	if autonomy!=null and _valid_link(links,id) and links[id].has_method("autonomy_capabilities") and "low" in links[id].autonomy_capabilities().get("levels",[]):snapshot["intelligence_level"]=resident_connections.preferences.preference(id).level
	if _valid_link(links,id) and links[id].has_method("uses_intents") and links[id].uses_intents() and not str(snapshot.get("source","")).contains("gomoku"):
		snapshot["intent_card"]=_intent_card(id,snapshot,channel)
	return snapshot

func _intent_card(id:String,snapshot:Dictionary,channel:String)->Dictionary:
	var nearby:Array=[]
	for object in world.objects.values():
		if object.get("region_id")==world.actors[id].region_id and world.point(object).distance_to(world.point(world.actors[id]))<=8:
			nearby.append({"id":object.id,"kind":object.get("kind",""),"position":object.position})
	var stock:Dictionary={}
	for item in world.storage._items:
		if world.storage.count(item)>0 and stock.size()<10:stock[item]=world.storage.count(item)
	var recent:Array=[]
	for row in dialogue.histories.get(channel,[]):
		if row.sender_id=="human" and not _forgotten_quote(id,row.message_id):recent.append(str(row.text).left(400))
	var result:Dictionary={"work_options":steward.work_context() if steward!=null and steward.authorized(id) else [],"management":steward.authorized(id) if steward!=null else false,"companions":world.actors.keys().filter(func(who):return who!="human"),"self":{"id":id,"persona_id":id,"personality":world.intelligence.tag(id),"hunger":world.hunger.summary(id).get("state",""),"activity":world.actors[id].activity},"nearby":nearby.slice(0,16),"stock":stock,"places":["farm","campfire","house","coast","human"],"human_recent":recent.slice(-6),"memory_goals":memory_life.goal_options() if memory_life!=null else [],"memory_sources":memory_books.ai_sources(id,world.world_id,0,channel),"memory":memory_books.card(id,recent[-1] if not recent.is_empty() else "",channel,resident_connections.preferences.preference(id).level),"forget_revision":JSON.stringify(memory_books.deleted).sha256_text(),"local_execution":immediate_turns.get(id,{}).get("result",{}),"dialogue":{"channel_id":snapshot.dialogue.channel_id,"recipient_ids":snapshot.dialogue.recipient_ids}}
	if life_archive!=null and life_archive.enabled(id):result.life_request=life_archive.request(id)
	return result

func _chat_is_composing()->bool:
	return chat_input!=null and (chat_input.has_ime_text() or (DisplayServer.has_feature(DisplayServer.FEATURE_IME) and not DisplayServer.ime_get_text().is_empty()))

func _finish_chat_input()->void:
	chat_input.clear();dialogue.drafts[_chat_channel()]=""
	chat_input.grab_focus()

func _local_command_feedback(line:String,channel:String)->void:
	if channel=="command":status.text=line;return
	_set_channel_status(channel,line)
	_record_chat(channel,"",line,"notice")

func _restore_command_focus()->void:
	if is_instance_valid(chat_input) and chat.visible:chat_input.grab_focus()

func _local_barbecue_requested(station_id:String,ids:Array)->void:
	if not world.barbecues.has(station_id):return
	var life:RefCounted=world.barbecues[station_id]
	var accepted:Array=[]
	for id in ids:
		var checked:Dictionary=life.fireside.can_invite([id])
		if not checked.get("ok",false):
			status.text=LocalText.resident(world,id)+": "+str(checked.get("message",checked.get("error","")));continue
		accepted.append(id)
	var result:Dictionary=life.fireside.invite(accepted)
	if not result.get("ok",false):status.text=str(result.get("message",result.get("error","")));return
	var center:Vector2=world.point(life.station)
	for index in accepted.size():
		var id:String=accepted[index]
		world.activities.pause_follow(id)
		for offset in [Vector2(-3,3),Vector2(3,3),Vector2(-3,-3),Vector2(3,-3)]:
			var at:Vector2=center+offset.rotated(index*PI/2)
			if world.walkable(life.station.region_id,at) and world.host_command(id,{"intent":"move","region_id":life.station.region_id,"x":at.x,"y":at.y}).get("ok",false):break
	status.text=LocalText.source("content.one_line.literal_13")

func _submit_local_command(text:String,fallback_ids:Array,channel:String)->bool:
	if local_host_commands==null:return false
	chat_input.release_focus();_refresh_conversation_holds()
	if intentions!=null and intentions.chat_only(text):
		var response:Dictionary=local_host_commands.unknown(fallback_ids,text)
		_record_chat(channel,"human",text)
		if not str(response.actor_id).is_empty():
			_record_chat(channel,str(response.actor_id),str(response.line),"local");view.say(str(response.line),"local_rules",str(response.actor_id))
		for child in choices.get_children():choices.remove_child(child);child.queue_free()
		for example in response.examples.slice(0,2):
			var command:String=str(example)
			_button(choices,LocalText.content(command),func():_send(command))
		_finish_chat_input();return true
	var result:Dictionary=local_host_commands.submit(text,fallback_ids,channel)
	if not result.get("handled",false):
		var models_only:Array=result.get("model_ids",[])
		if not models_only.is_empty() and result.get("explicit_targets",false):
			if models_only.size()==1 and channel!=Channels.ALL:_send_direct(str(models_only[0]),text)
			else:_send_group(text,models_only)
			return true
		if not models_only.is_empty():return false
		var response:Dictionary=local_host_commands.unknown(fallback_ids,text)
		result={"handled":true,"reply":response,"model_ids":[]}
		_local_command_feedback(str(response.line)+" / "+" / ".join(response.examples),channel)
	var human_entry:Dictionary=_record_chat(channel,"human",text)
	_finish_chat_input()
	if result.has("reply"):
		var response:Dictionary=result.reply
		response.examples=response.examples.slice(0,2)
		if not str(response.actor_id).is_empty():
			var line:String=str(response.line)+"\n"+" / ".join(response.examples)
			_record_chat(channel,str(response.actor_id),line,"local")
			world.director.say_local(str(response.actor_id),str(response.line),"host_command_unknown",float(world.hunger.config.personal_gap),float(world.hunger.config.village_gap))
		for child in choices.get_children():choices.remove_child(child);child.queue_free()
		for example in response.examples:
			var command:String=str(example)
			_button(choices,LocalText.content(command),func():_send(command))
		chat.show()
	if result.has("card"):
		var card:Window=result.card
		card.tree_exited.connect(_restore_command_focus,CONNECT_ONE_SHOT)
	var models:Array=result.get("model_ids",[])
	if not models.is_empty():_send_group(text,models,human_entry if channel==Channels.ALL else {})
	return true

func _send(text: String) -> void:
	if _chat_is_composing() or _chat_ime_enter_frame==Engine.get_process_frames():
		status.text=T("ui.chat.finish_composing");return
	text = text.strip_edges()
	if pending_question.is_empty() and questions.is_empty() and group_questions.is_empty() and _flower_local_chat(text):return
	var play_text:String=text.replace(LocalText.source("content.overnight.text.87c479f93e29ce"),LocalText.source("content.overnight.text.29f07ca1600fd9")).replace(LocalText.source("content.overnight.text.f1bf53c0148547"),LocalText.source("content.overnight.text.6adb4bfec2ff5b")).replace(LocalText.source("content.overnight.text.33f5a6f0f66c60"),LocalText.source("content.overnight.text.6adb4bfec2ff5b")).replace(LocalText.source("content.overnight.text.6f9543d8ee7fcd"),LocalText.source("content.overnight.text.6adb4bfec2ff5b"))
	if text.is_empty():
		status.text=T("ui.chat.empty");chat_input.grab_focus();return
	if not group_chat and world.director.brains.has(chat_actor) and (text.contains("陪我玩") or text.contains("一起散步") or text.contains("一起看星星") or text.to_lower() in ["play with me", "walk with me", "watch stars with me"]):
		_record_chat(_chat_channel(),"human",text)
		var b:RefCounted=world.director.brains[chat_actor]
		var response:Dictionary=b.interactions.social("walk" if text.contains("散步") or text.to_lower().contains("walk") else "stars" if text.contains("星星") or text.to_lower().contains("stars") else "play")
		if response.ok:
			b.invitation={"from":"human","action":"wander","until":b.clock+float(b.config.invite_seconds)};b.next_decision=b.clock
			b.interactions.enqueue("accept","accepted_social_invitation")
		_finish_chat_input();return
	if playground!=null:
		if text.strip_edges() in [LocalText.source("content.overnight.text.16833aa2becf6e"),LocalText.source("content.overnight.text.312062aef6737d"),LocalText.source("content.overnight.text.cfb252a606cf13"),"stop","stop playing"] and not playground.kind.is_empty():
			playground.finish();_finish_chat_input();return
		for entry in [["eagle",LocalText.source("play.eagle")],["handkerchief",LocalText.source("play.handkerchief")],["hide",LocalText.source("play.hide")],["shuttlecock",LocalText.source("play.shuttlecock")],["rope",LocalText.source("play.rope")]]:
			if not intentions.negated(text) and (str(entry[1]) in play_text or {"eagle":"eagle","handkerchief":"handkerchief","hide":"hide and seek","shuttlecock":"shuttlecock","rope":"jump rope"}[entry[0]] in play_text.to_lower()):
				steward.player(text)
				steward.queue.clear();steward.timeline.clear()
				for who in intentions.plans.keys():
					if intentions.plans[who].get("sponsor","")==steward.manager and not steward.manager.is_empty():intentions.cancel(who)
				var result:Dictionary=playground.start(entry[0]);status.text="" if result.get("ok",false) else T("play.unavailable")
				_record_chat(_chat_channel(),"human",text)
				var line:String=T("memory.ack."+world.intelligence.tag(chat_actor)) if result.get("ok",false) else T("play.unavailable")
				_record_chat(_chat_channel(),chat_actor,line,"local");view.say(line,"local_rules",chat_actor)
				_finish_chat_input();return
	if steward!=null and world.director.model_controlled(chat_actor) and steward.permission_prompt(chat_actor,text):_finish_chat_input();return
	if steward!=null and steward.player(text):_finish_chat_input();return
	if text.begins_with(LocalText.source("memory.teach_prefix")) or text.begins_with("When I say "):
		if not group_chat and world.actors.has(chat_actor):
			if world.director.model_controlled(chat_actor):_send_direct(chat_actor,text)
			else:
				var taught:Dictionary=_record_chat(_chat_channel(),"human",text)
				if memory_books.learn(chat_actor,world.world_id,taught.message_id,text,world.days.day()) or memory_books.list_for(chat_actor,"about_you").any(func(e):return e.event_id=="agreement:"+taught.message_id):
					_record_chat(_chat_channel(),chat_actor,T("memory.learned"),"local");view.say(T("memory.learned"),"local_rules",chat_actor)
				_finish_chat_input()
		return
	if steward!=null and not group_chat and steward.authorized(chat_actor):_send_direct(chat_actor,text);return
	if command_page!=null and command_page.dispatch(text):return
	if intentions!=null and pending_question.is_empty() and questions.is_empty() and group_questions.is_empty():
		var lead:String=text.split(LocalText.source("content.intent.separator.call"))[0]
		var named:Dictionary=local_host_commands.parser.parse_command(world,lead,[])
		if named.get("explicit_targets",false) and named.get("actor_ids",[]).size()==1:
			var who:String=str(named.actor_ids[0])
			if world.director.model_controlled(who) and not intentions.understand(text,who).is_empty():
				command_page.selected=[who];command_page.rebuild_targets();_send_direct(who,text);return
	var stop_command:Dictionary=local_host_commands.parser.parse_command(world,text) if local_host_commands!=null else {}
	if stop_command.get("ok",false) and stop_command.get("action")=="stop":
		for id in stop_command.actor_ids:_cancel_resident_turn(id)
		_record_chat(_chat_channel(),"human",text,"message");chat_input.release_focus()
		local_host_commands.submit(text,stop_command.actor_ids,_chat_channel(),stop_command.actor_ids);chat_input.clear();return
	if autonomy!=null:
		autonomy.player_input()
		if autonomy.defer_chat(text,"group" if group_chat else "direct",chat_actor):return
	if group_chat:
		if question_picker.selected > 0:
			var target: Dictionary = question_picker.get_item_metadata(question_picker.selected)
			_answer_group(target.actor_id,target.request_id,text)
		else:
			var recipients:Array=command_page.selected.duplicate() if command_page!=null and not command_page.selected.is_empty() else world.actors.keys().filter(func(id):return id!="human")
			var parsed:Dictionary=local_host_commands.parser.parse_command(world,text,recipients) if local_host_commands!=null and not intentions.chat_only(text) else {}
			if recipients.any(func(id):return world.director.model_controlled(id)) and not parsed.get("ok",false):_send_group(text,recipients.filter(func(id):return world.director.model_controlled(id)))
			elif not _submit_local_command(text,recipients if parsed.get("ok",false) else [],Channels.ALL):_send_group(text)
		return
	if world.actors.has(chat_actor) and world.director.model_controlled(chat_actor):
		_send_direct(chat_actor,text);return
	if _submit_local_command(text,[chat_actor] if world.actors.has(chat_actor) and chat_actor!="human" else [],_chat_channel()):return
	_send_direct(chat_actor,text)

func _instant_busy_reply(id:String,text:String)->void:
	var began:int=Time.get_ticks_msec()
	if not world._routes.has(id):world.director.routines[id]._face_human()
	var parsed:Dictionary={} if intentions.chat_only(text) else local_host_commands.parser.parse_command(world,text,[id])
	var line:String=T("memory.ack."+world.intelligence.tag(id)) if parsed.get("ok",false) else T("memory.thinking."+world.intelligence.tag(id))
	_record_chat(Channels.direct(id),id,line,"local");view.say(line,"local_rules",id)
	print("LOCAL_FIRST_REPLY ",JSON.stringify({"resident":id,"ms":Time.get_ticks_msec()-began,"queued":true}))

var next_chat:Dictionary={}
var next_chat_due:Dictionary={}
var next_chat_sources:Dictionary={}
func _send_direct(actor_id: String,text: String,recorded_entry:Dictionary={}) -> void:
	if gomoku_match_host!=null:
		if gomoku_match_host.defer_direct(actor_id,text):return
		gomoku_match_host.pause_target(actor_id)
	var request_id: String=str(questions.get(actor_id,{}).get("id",""))
	if not world.director.model_controlled(actor_id):
		_submit_local_command(text,[actor_id],Channels.direct(actor_id));return
	_ensure_link(actor_id)
	var group_busy:bool=group_questions.has(actor_id) or (_valid_link(group_links,actor_id) and group_links[actor_id].is_busy())
	# Manual relay and shared-test transports retain their own exact mailbox/FIFO contract.
	var transport_queue:bool=links[actor_id].has_method("read_mailbox") or links[actor_id].has_method("can_queue")
	if transport_queue:
		if group_busy:
			status.text=T("ui.main.they_re_replying_in_group_chat_finish_or_stop_that_conversation_f");return
		if request_id.is_empty() and links[actor_id].is_busy() and (not links[actor_id].has_method("can_queue") or not links[actor_id].can_queue()):
			status.text=T("ui.main.the_previous_message_is_still_running_or_the_queue_is_full_your_i");return
	if not transport_queue and request_id.is_empty() and (group_busy or links[actor_id].is_busy() or (recorded_entry.is_empty() and (next_chat.has(actor_id) or text.length()>4000))):
		var original:Dictionary=recorded_entry if not recorded_entry.is_empty() else _record_chat(Channels.direct(actor_id),"human",text)
		var queued:Array=next_chat.get(actor_id,[])
		var sources:Array=next_chat_sources.get(actor_id,[])
		for offset in range(0,text.length(),4000):
			queued.append(text.substr(offset,4000));sources.append(original.duplicate(true))
		next_chat[actor_id]=queued;next_chat_sources[actor_id]=sources
		next_chat_due[actor_id]=Time.get_ticks_msec()+350
		if recorded_entry.is_empty():_instant_busy_reply(actor_id,text)
		_finish_chat_input();return
	world.director.routines[actor_id].interrupt(35)
	_clear_local_bubble(); chat.show(); view.motion.attend()
	var entry: Dictionary = recorded_entry if not recorded_entry.is_empty() else _record_chat(Channels.direct(actor_id), "human", text, "answer" if not request_id.is_empty() else "message")
	_finish_chat_input()
	if not request_id.is_empty():
		var id := request_id; questions.erase(actor_id); _refresh_question_controls()
		links[actor_id].answer(id, {"answer": text, "project": world.projects.state(actor_id), "farm_order": world.farms.orders.get(actor_id,{})}); return
	var native_intent:bool=links[actor_id].has_method("uses_intents") and links[actor_id].uses_intents()
	if native_intent and world.gomoku.active(actor_id):native_intent=false
	if native_intent:
		local_host_commands.last_execution={}
		var began:int=Time.get_ticks_msec()
		var parsed:Dictionary={} if intentions.chat_only(text) else local_host_commands.parser.parse_command(world,text,[actor_id])
		var special:Array=intentions.understand(text,actor_id)
		if not special.is_empty():
			if intentions.plans.has(actor_id):intentions.cancel(actor_id)
			for camp in world.barbecues.values():
				if camp.fireside.jobs.has(actor_id):camp.fireside.command_received(actor_id,"move")
			if world.work.jobs.get(actor_id,{}).get("intent") in ["resort","use_facility"]:world.work.stop(actor_id,false)
			var held:Variant=world.activities.held.get(actor_id,false)
			world.activities.held.erase(actor_id)
			var request:Dictionary=intentions.submit(actor_id,special,Channels.direct(actor_id))
			world.activities.held[actor_id]=held
			local_host_commands.last_execution=request
			local_host_commands.last_execution["plan_steps"]=special.duplicate(true)
			if request.ok and autonomy!=null:autonomy.scheduler.note_model_action(actor_id)
		elif parsed.get("ok",false):
			var held:Variant=world.activities.held.get(actor_id,false)
			world.activities.held.erase(actor_id)
			local_host_commands.submit(text,[actor_id],Channels.direct(actor_id),[actor_id])
			world.activities.held[actor_id]=held
		if not world._routes.has(actor_id):world.director.routines[actor_id]._face_human()
		var line:String=T("memory.ack."+world.intelligence.tag(actor_id)) if (parsed.get("ok",false) or not special.is_empty()) and local_host_commands.last_execution.get("ok",false) else _local_context_reply(actor_id)
		_record_chat(Channels.direct(actor_id),actor_id,line,"local");view.say(line,"local_rules",actor_id)
		immediate_turns[actor_id]={"text":text,"plan":not special.is_empty(),"command":(parsed.get("ok",false) and parsed.get("action")!="query_state") or intentions.is_request(text),"result":local_host_commands.last_execution.duplicate(true) if parsed.get("ok",false) or not special.is_empty() else {},"local_ms":Time.get_ticks_msec()-began,"first_visible_ms":Time.get_ticks_msec()-began,"sent_at_ms":began,"job_id":str(world.work.jobs.get(actor_id,{}).get("id","")),"farm_order_id":str(world.farms.orders.get(actor_id,{}).get("host_order_id",""))}
		links[actor_id].helper_filename="intent_companion.py"
	var previous_key:String=str(links[actor_id].get("turn_key")) if links[actor_id].get_property_list().any(func(p):return p.name=="turn_key") else ""
	var message_snapshot:Dictionary=_snapshot_for_chat(actor_id, Channels.direct(actor_id), [actor_id], entry.message_id)
	if native_intent:
		immediate_turns[actor_id]["memory_sources"]=message_snapshot.get("intent_card",{}).get("memory_sources",[]).map(func(e):return e.id)
		immediate_turns[actor_id]["memory_request"]={"goals":message_snapshot.get("intent_card",{}).get("memory_goals",[])}
	links[actor_id].send_message(text, message_snapshot)
	var current_key:String=str(links[actor_id].get("turn_key")) if links[actor_id].get_property_list().any(func(p):return p.name=="turn_key") else ""
	if native_intent:
		immediate_turns[actor_id]["turn_key"]=current_key
		return
	if local_host_commands.parser.parse_command(world,text,[actor_id]).get("ok",false) or intentions.is_request(text):
		if not links[actor_id].is_busy():_run_model_fallback(actor_id,text,Channels.direct(actor_id))
		elif not current_key.is_empty() and current_key!=previous_key:
			model_fallback_requests[actor_id]={"text":text,"turn_key":current_key,"deadline":Time.get_ticks_msec()+(120000 if links[actor_id].has_method("uses_intents") and links[actor_id].uses_intents() and resident_connections.preferences.preference(actor_id).level=="high" else 30000),"generation":links[actor_id].get("_generation"),"scope":"direct","channel":Channels.direct(actor_id)}
			host_turn_grants[actor_id]=model_fallback_requests[actor_id].duplicate(true)


func _group_recipients() -> Array:
	var result: Array = []
	for id in world.actors:
		if id != "human" and world.director.model_controlled(id): result.append(id)
	return result

func _send_group(text: String,selected_models:Array=[],existing_entry:Dictionary={}) -> void:
	var recipients: Array = []
	var unavailable: Array[String] = []
	for id in (_group_recipients() if selected_models.is_empty() else selected_models.filter(func(id):return id in _group_recipients())):
		if gomoku_match_host!=null:gomoku_match_host.pause_target(id)
		_ensure_link(id)
		if links[id].has_method("read_mailbox"):
			unavailable.append(LocalText.resident(world,id) + T("ui.main.manual_relay_use_direct_chat")); continue
		if questions.has(id) or links[id].is_busy() or group_questions.has(id):
			unavailable.append(LocalText.resident(world,id) + T("ui.main.busy_or_awaiting_an_answer")); continue
		_ensure_group_link(id)
		var connection: Node = group_links[id]
		if connection.is_busy() and (not connection.has_method("can_queue") or not connection.can_queue()):
			unavailable.append(LocalText.resident(world,id) + T("ui.main.busy")); continue
		recipients.append(id)
	if recipients.is_empty():
		status.text = T("ui.main.no_connected_ai_can_receive_this_group_message_right_now_your_inp") + T("ui.main.list_separator").join(unavailable); return
	chat.show(); view.motion.attend(); _clear_local_bubble()
	var entry: Dictionary = _record_chat(Channels.ALL, "human", text) if existing_entry.is_empty() else existing_entry
	_finish_chat_input()
	var names: Array[String] = []
	for id in recipients: names.append(LocalText.resident(world,id))
	_record_chat(Channels.ALL, "", T("ui.main.sent_to") + T("ui.main.list_separator").join(names) + (T("ui.main.not_sent") + T("ui.main.list_separator").join(unavailable) if not unavailable.is_empty() else ""), "notice")
	# Freeze recipients and channel before any adapter emits asynchronous events.
	for id in recipients:
		if gomoku_match_host!=null:gomoku_match_host.pause_target(id)
		world.director.routines[id].interrupt(35)
		var previous_key:String=str(group_links[id].get("turn_key")) if group_links[id].get_property_list().any(func(p):return p.name=="turn_key") else ""
		var native:bool=group_links[id].has_method("uses_intents") and group_links[id].uses_intents()
		if native:
			var parsed:Dictionary={} if intentions.chat_only(text) else local_host_commands.parser.parse_command(world,text,[id])
			var special:Array=intentions.understand(text,id)
			var result:Dictionary={}
			var held:Variant=world.activities.held.get(id,false);world.activities.held.erase(id)
			if not special.is_empty():result=intentions.submit(id,special,Channels.ALL)
			elif parsed.get("ok",false) and parsed.action in ["plant","ready","water","chop"]:
				var phrase:String=LocalText.resident(world,id)+" "+{"ready":"harvest"}.get(parsed.action,parsed.action)+(" "+str(parsed.crop_id) if parsed.get("crop_id","mixed")!="mixed" else "")
				if parsed.action=="chop":phrase=LocalText.resident(world,id)+" chop "+str(local_host_commands.tree_count(text))+" trees"
				elif not str(parsed.get("farm_id","")).is_empty():phrase+=" "+str(world.farms.farms[parsed.farm_id].name)
				local_host_commands.submit(phrase,[id],Channels.ALL,[id]);result=local_host_commands.last_execution.duplicate(true)
			world.activities.held[id]=held
			immediate_turns[id]={"scope":"group","text":text,"command":(parsed.get("ok",false) and parsed.get("action")!="query_state") or intentions.is_request(text),"plan":not special.is_empty(),"result":result,"job_id":str(world.work.jobs.get(id,{}).get("id","")),"farm_order_id":str(world.farms.orders.get(id,{}).get("host_order_id","")),"memory_sources":[]}
			group_links[id].helper_filename="intent_companion.py"
		var snapshot:Dictionary=_snapshot_for_chat(id,Channels.ALL,recipients,entry.message_id)
		if native:immediate_turns[id].memory_sources=snapshot.get("intent_card",{}).get("memory_sources",[]).map(func(row):return row.id)
		group_links[id].send_message(text,snapshot)
		var current_key:String=str(group_links[id].get("turn_key")) if group_links[id].get_property_list().any(func(p):return p.name=="turn_key") else ""
		if native:immediate_turns[id]["turn_key"]=current_key;continue
		if local_host_commands.parser.parse_command(world,text,[id]).get("ok",false) or intentions.is_request(text):
			if not group_links[id].is_busy():_run_model_fallback(id,text,Channels.ALL)
			elif not current_key.is_empty() and current_key!=previous_key:
				model_fallback_requests[id]={"text":text,"turn_key":current_key,"deadline":Time.get_ticks_msec()+(120000 if group_links[id].get_script()==preload("res://scripts/companion_link.gd") and resident_connections.preferences.preference(id).level=="high" else 30000),"generation":group_links[id].get("_generation"),"scope":"group","channel":Channels.ALL}
				host_turn_grants[id]=model_fallback_requests[id].duplicate(true)


func _answer_group(actor_id: String, request_id: String, text: String) -> void:
	if not group_questions.has(actor_id) or group_questions[actor_id].id != request_id or not _valid_link(group_links,actor_id):
		status.text = T("ui.main.that_question_has_ended"); return
	group_questions.erase(actor_id)
	_record_chat(Channels.ALL, "human", T("ui.main.reply_to_resident") % [LocalText.resident(world,actor_id),text], "answer")
	chat_input.clear(); _refresh_question_controls()
	group_links[actor_id].answer(request_id, {"answer": text, "project": world.projects.state(actor_id), "farm_order": world.farms.orders.get(actor_id,{})})

func _refresh_chat_placeholder() -> void:
	if group_chat:
		chat_input.placeholder_text = T("ui.main.talk_to_all_connected_ai")
		if question_picker.selected > 0: chat_input.placeholder_text = T("ui.main.answer_placeholder") % LocalText.resident(world,question_picker.get_item_metadata(question_picker.selected).actor_id)
	else: chat_input.placeholder_text = T("ui.main.chat_or_ask_for_a_hand") if world.director.model_controlled(chat_actor) else T("ui.main.no_model_connected_say_hello_gather_companions_or_ask_help_me_pla")

func _refresh_question_controls() -> void:
	var previous: Dictionary = {}
	if question_picker.visible and question_picker.selected > 0: previous = question_picker.get_item_metadata(question_picker.selected)
	_clear_choices()
	_clear_activity_choices()
	pending_question = "" if group_chat else str(questions.get(chat_actor, {}).get("id", ""))
	question_picker.clear(); question_picker.add_item(T("ui.main.send_to_everyone"))
	if group_chat:
		for id in group_questions:
			var question: Dictionary = group_questions[id]
			question_picker.add_item(T("ui.main.answer_label") % LocalText.resident(world,id))
			question_picker.set_item_metadata(question_picker.item_count-1, {"actor_id":id, "request_id":question.id})
			for answer in question.get("choices", []): _button(choices, LocalText.resident(world,id) + " · " + str(answer), _answer_group.bind(id, str(question.id), str(answer)))
	else:
		for answer in questions.get(chat_actor, {}).get("choices", []): _button(choices, str(answer), func(): _send(str(answer)))
	question_picker.visible = group_chat and not group_questions.is_empty()
	question_picker.select(0)
	for index in range(1, question_picker.item_count):
		if question_picker.get_item_metadata(index) == previous: question_picker.select(index)
	_refresh_chat_placeholder()
	_render_chat()

func _invite_fishers(ids: Array) -> void:
	if action_dock.start_host_on_invite:
		action_dock.start_host_on_invite=false
		if world.work.jobs.get("human",{}).get("intent")!="fish":
			var started:Dictionary=action_dock.perform({"intent":"fish"},"human")
			if not started.get("ok",false):return
	var available: Array=ids.filter(func(id):return not _resident_chat_busy(id))
	var result: Dictionary=world.fishing.invite_host(available)
	if result.has("skipped"):
		for id in ids:
			if id not in available:
				result.skipped.append(id)
				if not result.has("reasons"):result.reasons={}
				result.reasons[id]=T("ui.main.replying_to_you")
		result.message=world.fishing.invitation_message(result.skipped,result.get("reasons",{}))
	action_dock.invited(result)

func _focus_fishery(id: String) -> void:
	_toggle_atlas(false);view.show_region(world.fishing.pens[id].region_id);view.follow_player=false
	var pen: Dictionary=world.fishing.pens[id]
	var center: Vector2=world.catalog.rectangle(pen.rect).get_center()
	view.center=center+Vector2(4,3);view.zoom=view.camera_defaults.distance_factor*float(view.camera_defaults.config.fishing)

func _open_fishing(target_id: String="") -> void:
	_toggle_atlas(false);chat.hide();memory_panel.hide();farm_panel.hide();leisure_panel.hide()
	fishing_panel.open(target_id,"human")
	if not target_id.is_empty():_focus_fishery(target_id)

func choose_direct_grill(fish_id:String)->void:
	var fish:Dictionary=world.fishing.fish.get(fish_id,{})
	if not world.life.fireside.direct_fish_available(fish):status.text=T("ui.main.fish_unavailable");return
	var choices:Array=world.barbecues.keys().filter(func(id):return world.standard.ready(id) and world.barbecues[id].station.region_id==world.actors.human.region_id)
	if choices.is_empty():status.text=T("ui.main.no_completed_campfire_yet_you_re_still_holding_the_fish");return
	var dialog:=ConfirmationDialog.new();dialog.title=T("ui.main.choose_a_campfire");dialog.ok_button_text=T("ui.main.go_there");add_child(dialog)
	var list:=OptionButton.new();list.focus_mode=Control.FOCUS_NONE;dialog.add_child(list)
	choices.sort_custom(func(a,b):return world.point(world.barbecues[a].station).distance_squared_to(world.point(world.actors.human))<world.point(world.barbecues[b].station).distance_squared_to(world.point(world.actors.human)))
	for id in choices:list.add_item(T("ui.main.home_island_campfire") if id=="home.barbecue" else T("ui.main.moon_island_campfire") if id=="moon.barbecue" else LocalText.content(str(world.barbecues[id].station.name)));list.set_item_metadata(list.item_count-1,id)
	dialog.confirmed.connect(func():
		direct_grill_fish_id=fish_id
		_camp_action(str(list.get_item_metadata(list.selected)),"direct_fish")
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free);dialog.close_requested.connect(dialog.queue_free);dialog.popup_centered(Vector2i(380,150))

func _show_opening_board()->void:
	var dialog:=AcceptDialog.new();dialog.title=T("ui.main.noticeboard_island_life");dialog.theme=Theme.new();dialog.theme.default_font=view.font;dialog.theme.default_font_size=16;add_child(dialog)
	var body:=VBoxContainer.new();dialog.add_child(body)
	for entry in world.standard.board():
		var row:=HBoxContainer.new();body.add_child(row)
		var line:=RichTextLabel.new();line.bbcode_enabled=true;line.fit_content=true;line.custom_minimum_size.x=300;line.size_flags_horizontal=Control.SIZE_EXPAND_FILL;line.text=("✓ [s]"+entry.text+"[/s]") if entry.done else "· "+entry.text;line.modulate=Color("9ea995") if entry.done else Color("fff1ce");line.add_theme_font_size_override("normal_font_size",18);row.add_child(line)
		var where:=Button.new();where.focus_mode=Control.FOCUS_NONE;where.text=T("ui.main.where_is_it");where.custom_minimum_size=Vector2(82,36);row.add_child(where)
		where.pressed.connect(func():view.focus_location(world.standard.board_point(entry.target));dialog.hide();dialog.queue_free())
	if world.standard.board().all(func(e):return e.done):
		var quote:=Label.new();quote.text=world.standard.board_quote();body.add_child(quote)
	dialog.confirmed.connect(dialog.queue_free);dialog.close_requested.connect(dialog.queue_free);dialog.popup_centered(Vector2i(480,260))
func _clicked(id: String, local: Vector2) -> void:
	if _flower_clicked(id,local):return
	if id.begins_with("resort."):
		get_node("ResortUI").show_target(id);return
	if has_node("ResortUI"):get_node("ResortUI").leave()
	if journey!=null:journey.cancel()
	pending_chess.clear()
	if dark_ui!=null and dark_ui.handle(id,local):return
	pending_camp.clear()
	if id=="pet.yuzu":
		for child in get_children():
			if child.get_script()==preload("res://scripts/cat_companion_ui.gd"):child.show_menu();return
	if id.begins_with("fish:"):
		var fish_id:String=id.trim_prefix("fish:");var entry:Dictionary=world.fishing.fish.get(fish_id,{})
		if not entry.is_empty() and world.fishing.pens.has(entry.location):
			fishing_panel.open(entry.location,entry.owner_id);fishing_panel.selected_fish=fish_id;fishing_panel.show_fish()
		return
	if world.standard.active() and id=="opening.board":_show_opening_board();return
	if world.standard.active() and (world.fishing.pens.has(id) or world.barbecues.has(id)) and not world.standard.ready(id):leisure_panel.open_site(world.standard.site_for(id));return
	if world.standard.active() and world.farms.plots.has(id) and not world.standard.ready(world.farms.plots[id].farm_id):leisure_panel.open_site(world.standard.site_for(world.farms.plots[id].farm_id));return
	chat_input.release_focus()
	if Opening.v3(world) and id=="human":_return_to_player();return
	selected_id = id
	if not placing_facility.is_empty():
		if view.region_id!="home":status.text=T("ui.main.return_to_the_island_to_place_this");return
		var result: Dictionary=preload("res://scripts/outdoor_building.gd").new_plot(world,local.snapped(Vector2.ONE)+Vector2(.5,.5)) if placing_facility=="outdoor-plot" else world.leisure.place(placing_facility,local.snapped(Vector2.ONE)+Vector2(.5,.5));status.text=str(result.get("error",T("ui.main.foundation_placed_choose_a_builder")))
		if result.ok:
			var plot:bool=placing_facility=="outdoor-plot";placing_facility=""
			if plot:house_panel.open_site(result.site_id)
			else:leisure_panel.rebuild();leisure_panel.open_site(result.site_id)
		return
	if id==world.homestead.config.site.id:_open_homestead();return
	if not world.gomoku.table(id).is_empty():_walk_to_chess(id);return
	if world.leisure.sites.has(id):leisure_panel.open_site(id);return
	if view.region_id != world.actors.human.region_id:
		status.text = T("ui.main.return_to_your_own_view_at_the_top_left_before_acting"); return
	if view.region_id=="homelands":
		if world.barbecues.has(id):_camp_action(id,"panel",local);return
		if world.objects.has(id) and world.objects[id].kind=="construction_site":house_panel.open_site(id);return
		var southern_move:Dictionary=world.command("human",{"intent":"move","x":local.x,"y":local.y})
		if southern_move.ok and view.run_click:world.force_human_run()
		return
	if view.region_id != "home":
		_room_clicked(id, local); return
	if world.fishing.pens.has(id):_open_fishing(id);return
	if world.farms.plots.has(id) or world.farms.containers.has(id):
		var object: Dictionary = world.object_by_id(id)
		farm_panel.open_farm(object.farm_id, id); house_panel.hide()
		if world.farms.plots.has(id):
			var stage: String = world.farms.stage(object)
			if assign: _send(T("ui.main.please_check_and_tend_this_field_target")+id)
			elif stage in ["dry","mature"]:
				var result: Dictionary = world.command("human",{"intent":"water" if stage=="dry" else "harvest","target_id":id})
				farm_panel.note.text = str(result.get("message",result.get("error","")))
		return
	if world.barbecues.has(id):
		_camp_action(id,"panel",local)
		return
	if world.objects.has(id) and world.objects[id].kind == "construction_site" and not assign:
		house_panel.open_site(id); return
	if world.all_mushrooms().has(id):
		if assign: _send(T("ui.main.please_gather_these_mushrooms_and_store_them_target") + id)
		else:
			var result: Dictionary = world.command("human", {"intent": "forage", "target_id": id})
			status.text = str(result.get("message", result.get("error", "")))
		return
	if assign and not id.is_empty():
		if world.objects.has(id) and world.objects[id].kind == "tree" and world.objects[id].status != "mature":
			status.text = T("ui.main.this_sapling_is_growing_give_it_a_little_time"); return
		if world.objects.has(id) and world.objects[id].kind == "tree": _send(T("ui.main.please_chop_this_tree_and_store_the_wood_target") + id)
		elif world.objects.has(id) and world.objects[id].kind == "construction_site": _send((T("ui.main.please_enter_this_house_target") if int(world.objects[id].get("stage_index", 0)) == 5 else T("ui.main.please_complete_the_next_construction_stage_of_this_house_target")) + id)
		elif world.drops.has(id): _send(T("ui.main.please_store_this_pile_of_wood_target") + id)
		return
	var command: Dictionary
	if world.objects.has(id):
		match world.objects[id].kind:
			"tree": command = {"intent": "chop", "target_id": id}
			"construction_site": command = {"intent": "build", "target_id": id}
			_: return
	elif world.drops.has(id): command = {"intent": "collect", "target_id": id}
	else:
		world.command("human", {"intent": "stop"})
		command = {"intent": "move", "region_id": "home", "x": local.x, "y": local.y}
	if steward!=null:steward.player()
	var result: Dictionary = world.command("human", command)
	if result.ok and command.intent == "move" and id.is_empty() and view.run_click: world.force_human_run()
	status.text = str(result.get("message", T("ui.main.on_the_way") if result.ok else T("ui.main.can_t_do_that_right_now") + str(result.get("error", ""))))

func _select_chat(id: String) -> void:
	if id != Channels.ALL and (not world.actors.has(id) or id == "human"): return
	if command_page!=null and id!=Channels.ALL:command_page.selected=[id]
	dialogue.drafts[_chat_channel()] = chat_input.text
	group_chat = id == Channels.ALL
	if not group_chat: chat_actor = id
	chat_input.text = str(dialogue.drafts.get(_chat_channel(), ""))
	_refresh_control_ui()
	if not group_chat and not _resident_panel_open(): project_panel.actor_id=id;project_panel.refresh()
	for index in range(chat_picker.item_count):
		if chat_picker.get_item_metadata(index) == id: chat_picker.select(index)
	_refresh_question_controls(); _render_chat()
	if status != null: status.text = str(dialogue.statuses.get(_chat_channel(), ""))

func _companion_event(event: Dictionary) -> void:
	_bound_companion_event(event, "codex")

func _bound_companion_event(event: Dictionary, actor_id: String, scope := "direct") -> void:
	var connection:Variant= group_links.get(actor_id) if scope == "group" else links.get(actor_id, link)
	if not is_instance_valid(connection) or not world.actors.has(actor_id): return
	# A local fallback revokes this exact model turn's mutations, while its reply
	# may still arrive. Read-only observations and independent future turns survive.
	if _fallback_actions_revoked(actor_id,scope,event,connection):
		if event.get("kind") in ["action","edit_work","question"]:
			if not str(event.get("id","")).is_empty():connection.reply(str(event.id),{"ok":false,"error":"stale_host_instruction"})
			return
		if event.get("kind")=="intent_result":
			event={"kind":"intent_result","turn_key":str(event.get("turn_key","")),"speech":str(event.get("speech","")),"intents":[],"memory":[],"planning":[],"autonomy":bool(event.get("autonomy",false))}
	if gomoku_match_host!=null and gomoku_match_host.event(actor_id,event,scope):return
	var channel := Channels.ALL if scope == "group" else Channels.direct(actor_id)
	var pending: Dictionary = group_questions if scope == "group" else questions
	var name: String = LocalText.resident(world,actor_id)
	if not world.director.model_controlled(actor_id):
		if event.get("kind") in ["action","observe","read_work","edit_work"]:connection.reply(str(event.id),{"ok":false,"error":"controller_changed"})
		return
	if gomoku_dialogue!=null and gomoku_dialogue.stale(actor_id,event):
		if event.get("kind") in ["action","edit_work"]:connection.reply(str(event.id),{"ok":false,"error":"stale_chess_dialogue"})
		return
	if autonomy!=null:autonomy.event(event,actor_id,scope)
	if connection_pool!=null and event.get("kind")=="usage":connection_pool.receive(actor_id,event.merged({"scope":scope},true))
	if life_archive!=null and not str(event.get("turn_key","")).is_empty() and str(event.get("turn_key"))==str(connection.turn_key):life_archive.record_event(actor_id,event)
	if memory_life!=null and scope=="direct":memory_life.event(actor_id,event)
	if immediate_turns.get(actor_id,{}).get("maintenance",false) and immediate_turns[actor_id].get("turn_key")==event.get("turn_key") and event.get("kind") in ["action","question","observe","read_work","edit_work"]:
		connection.reply(str(event.get("id","")),{"ok":false,"error":"memory_only"});return
	if model_fallback_requests.has(actor_id) and model_fallback_requests[actor_id].get("scope","direct")==scope and str(event.get("turn_key",""))==str(model_fallback_requests[actor_id].turn_key):
		if event.get("kind")=="question":model_fallback_requests.erase(actor_id)
		elif event.get("kind")=="error" or (event.get("kind")=="state" and event.get("state") in ["ready","error","disconnected"]):
			var fallback_text:String=model_fallback_requests[actor_id].text
			model_fallback_requests.erase(actor_id)
			_run_model_fallback(actor_id,fallback_text,channel)
	if event.get("kind")=="state":
		connection_ui_states[actor_id+":"+scope]=str(event.get("state","idle"))
		if event.get("state")=="ready" and event.get("turnComplete",true)==false:
			var greeting:String=T("simple.hello."+actor_id)
			connection_greetings[actor_id]=greeting
		if external_residents.get(actor_id,false) and event.get("state")=="ready":connection_history.set_value("external",actor_id,Time.get_unix_time_from_system())
		if event.get("state")=="ready":connection_history.set_value("connected",actor_id,Time.get_unix_time_from_system());connection_history.save(data_dir.path_join("connection-overview.cfg"))
	elif event.get("kind")=="error":connection_ui_states[actor_id+":"+scope]="ready" if event.get("code")=="invalid_intent_reply" else "error"
	if steward!=null and immediate_turns.get(actor_id,{}).get("steward",false) and event.get("kind")=="intent_result" and (steward.pending.is_empty() or steward.pending.get("key")!=event.get("turn_key")):return
	if steward!=null and steward.result(actor_id,event):return
	match str(event.get("kind", "")):
		"usage":
			if event.get("complete",false) and immediate_turns.has(actor_id):
				var path:String=data_dir.path_join("ai-turn-metrics.json")
				var rows:Variant=JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else []
				if not rows is Array:rows=[]
				rows.append({"resident_id":actor_id,"turn_key":event.get("turn_key",""),"at":Time.get_unix_time_from_system(),"input_tokens":event.get("input_tokens"),"output_tokens":event.get("output_tokens"),"ai_reply_ms":event.get("ai_reply_ms"),"first_token_ms":event.get("first_token_ms"),"local_ms":immediate_turns[actor_id].get("local_ms"),"first_visible_ms":immediate_turns[actor_id].get("first_visible_ms"),"complete_ms":Time.get_ticks_msec()-int(immediate_turns[actor_id].get("sent_at_ms",Time.get_ticks_msec()))})
				memory_books.atomic(path,rows.slice(-2000))
		"speech_partial":
			var turn:Dictionary=immediate_turns.get(actor_id,{})
			if turn.get("turn_key","")!=event.get("turn_key") or scope!=str(turn.get("scope","direct")):return
			if not turn.has("stream_first_ms"):turn["stream_first_ms"]=Time.get_ticks_msec()-int(turn.get("sent_at_ms",Time.get_ticks_msec()))
			view.say(str(event.get("text","")).left(1000),"model",actor_id)
		"intent_result":
			var immediate:Dictionary=immediate_turns.get(actor_id,{})
			if immediate.get("turn_key","")!=event.get("turn_key") or scope!=str(immediate.get("scope","direct")):return
			var supplied:Array=immediate.get("memory_sources",[])
			if life_archive!=null:
				life_archive.accept(actor_id,event,supplied,str(event.turn_key))
				if immediate.get("maintenance",false):life_archive.accept_day(actor_id,event.get("life_day",{}),supplied,int(immediate.get("memory_request",{}).get("day",0)))
			if memory_life!=null:memory_life.check_letter_reply(actor_id,event.get("memory",[]),immediate)
			memory_books.accept_ai(actor_id,world.world_id,str(connection.get_meta("memory_provider","Codex")),event.get("memory",[]),supplied,world.days.day(),immediate.get("memory_request",{}))
			if immediate.get("maintenance",false):return
			var structured:Array=event.get("intents",[]).filter(func(step):return step is Dictionary and step.has("action"))
			if not structured.is_empty() and immediate.get("command",false) and not immediate.get("plan",false) and not immediate.get("result",{}).get("ok",false):
				var adopted:Dictionary={}
				if immediate.get("result",{}).get("ok",false):
					var original:Dictionary=local_host_commands.parser.parse_command(world,str(immediate.get("text","")),[actor_id])
					if structured[0].action=={"ready":"harvest","forage":"gather","start_project":"build"}.get(original.get("action",""),original.get("action","")):adopted={"job_id":immediate.get("job_id",""),"farm_order_id":immediate.get("farm_order_id","")}
				var permitted:bool=not event.get("autonomy",false) or (autonomy!=null and autonomy.scheduler.active.get(actor_id,{}).get("id")==event.get("turn_key") and structured.size()<=int(autonomy.scheduler.policy_for(actor_id).get("tools",0)))
				var result:Dictionary=intentions.submit(actor_id,structured,channel,adopted) if permitted else world._error("autonomy_tool_budget")
				if result.ok and life_archive!=null:life_archive.bind_plan(actor_id,str(event.turn_key))
				if result.ok and autonomy!=null:autonomy.scheduler.note_model_action(actor_id)
				if not result.ok:_local_command_feedback(str(result.get("error","rejected")),channel)
			for intention in event.get("intents",[]):
				if intention.has("action") or immediate.get("plan",false):continue
				if not immediate.get("command",false):continue
				var parsed:Dictionary=local_host_commands.parser.parse_command(world,str(intention.text),[actor_id])
				if not parsed.get("ok",false) or parsed.actor_ids!=[actor_id]:continue
				# A correction can replace only this turn's accepted order.
				if immediate.get("result",{}).get("ok",false):continue
				if not immediate.result.is_empty():
					if not intention.get("replace",false):continue
					var original:Dictionary=local_host_commands.parser.parse_command(world,immediate.text,[actor_id])
					if parsed.get("action")!=original.get("action") or parsed.keys().any(func(field):return field not in ["crop_id","source_text"] and parsed[field]!=original.get(field)):continue
					var own_order:String=str(immediate.get("farm_order_id",""))
					var own_job:String=str(immediate.get("job_id",""))
					if not own_order.is_empty():
						var current_order:Dictionary=world.farms.orders.get(actor_id,{})
						if current_order.get("host_order_id","")!=own_order or current_order.get("status","") not in ["working","waiting"]:continue
					elif own_job.is_empty() or world.work.jobs.get(actor_id,{}).get("id","")!=own_job:continue
					local_host_commands.replace_order(actor_id)
				var held:Variant=world.activities.held.get(actor_id,false)
				world.activities.held.erase(actor_id)
				local_host_commands.submit(str(intention.text),[actor_id],channel,[actor_id])
				world.activities.held[actor_id]=held
				immediate.result=local_host_commands.last_execution.duplicate(true)
			if not str(event.get("speech","")).is_empty():
				var spoken:String=_persona_speech(event.speech,actor_id)
				memory_books.offer_ai_quote(actor_id,world.world_id,str(event.turn_key),spoken,str(connection.get_meta("memory_provider","Codex")),world.days.day(),channel)
				if steward!=null and not world.gomoku.active(actor_id):steward.speak(actor_id,spoken,channel)
				else:_record_chat(channel,actor_id,spoken);view.say(spoken,"model",actor_id)
		"observe": connection.reply(str(event.id), world.observe(actor_id, event.get("query", {})))
		"read_work": connection.reply(str(event.id), library.read_work(event.query))
		"edit_work":
			var id := str(event.query.get("artwork_id", ""))
			var own: String = world.actors[actor_id].appearance_id
			var editable: bool = library.artworks.has(id) and "spare" not in library.artworks[id].get("tags", []) and (id == own or library.artworks[id].get("kind", "character") in ["plant","building","facility"])
			connection.reply(str(event.id), library.patch(id, event.query) if editable else {"ok":false,"error":"not_editable"})
		"action":
			if autonomy!=null:autonomy.scheduler.note_model_action(actor_id)
			var chess_guard: Dictionary=gomoku_dialogue.guard(actor_id,event) if gomoku_dialogue!=null and scope=="direct" else {}
			var result: Dictionary = chess_guard if not chess_guard.is_empty() else {"ok":false,"error":"waiting_for_answer"} if questions.has(actor_id) or group_questions.has(actor_id) else {"ok":false,"error":"assembly_active"} if world.activities.members.has(actor_id) else _execute_model_action(actor_id,event,channel)
			if event.get("autonomy",false) and autonomy!=null:autonomy.scheduler.records.action(actor_id,str(event.get("turn_key","")),event.command,result)
			if gomoku_dialogue!=null and scope=="direct":gomoku_dialogue.accepted(actor_id,event,result)
			if result.get("ok",false):model_fallback_requests.erase(actor_id)
			if result.get("ok", false): task_channels[actor_id] = channel
			connection.reply(str(event.id), result)
		"question":
			event=event.duplicate(true);event.text=_persona_speech(str(event.text),actor_id)
			if resident_connections!=null:resident_connections.close_panel()
			world.homestead.pause(actor_id,T("ui.main.answer_the_question_first_the_project_and_materials_are_safe"))
			if homestead_panel!=null:homestead_panel.hide()
			world.days.interrupt(actor_id)
			if journal_panel!=null:journal_panel.hide()
			var was_chess: bool=world.gomoku.active(actor_id)
			world.gomoku.pause_actor(actor_id,T("ui.main.resume_the_game_after_the_question_has_a_clear_answer"))
			if was_chess and gomoku_panel!=null:gomoku_panel.card.hide();gomoku_panel.refresh()
			if world.work.jobs.get(actor_id,{}).get("intent")=="fish":world.work.stop(actor_id)
			if world.shared_activity.contains(actor_id): world.shared_activity.pause(T("ui.main.wait_for_resident_answer") % name)
			world.farms.pause(actor_id, T("ui.main.waiting_for_your_answer_before_farming_continues"))
			if world.projects.active(actor_id): world.projects.pause(actor_id, T("ui.main.after_your_answer_discuss_how_to_continue"))
			pending[actor_id] = event.duplicate(true)
			# An incoming question belongs to its original channel. Showing the
			# command-first drawer must not reselect its last command recipients.
			var selected_target:String=Channels.ALL if group_chat else chat_actor
			chat.show()
			if command_page!=null:
				command_page.selected=command_page.actors() if selected_target==Channels.ALL else [selected_target]
				command_page.show_mode(false)
			_select_chat(selected_target)
			var entry: Dictionary = _record_chat(channel, actor_id, str(event.text), "question", str(event.id))
			pending[actor_id]["history_message_id"] = entry.message_id
			view.say(str(event.text), "model", actor_id)
			if channel == _chat_channel(): _refresh_question_controls()
		"assistant":
			event=event.duplicate(true);event.text=_persona_speech(str(event.text),actor_id)
			var proactive: bool=bool(event.get("autonomy",false))
			if steward!=null and not world.gomoku.active(actor_id):steward.speak(actor_id,str(event.text),channel,false,"autonomy" if proactive else "message")
			else:
				_record_chat(channel,actor_id,str(event.text),"autonomy" if proactive else "message")
				if gomoku_dialogue==null or scope!="direct" or not gomoku_dialogue.assistant(actor_id,event):view.say(str(event.text),"autonomy" if proactive else "model",actor_id)
		"queue": _set_channel_status(channel, name + T("ui.main.s_pending") % int(event.get("count", 0)))
		"error":
			# Transport diagnostics belong to the resident connection lamp/log only.
			pending.erase(actor_id)
			if channel == _chat_channel(): _refresh_question_controls()
		"state":
			if gomoku_dialogue!=null and scope=="direct":gomoku_dialogue.event(actor_id,event)
			if event.get("state") not in ["cancelling","cancelled","error","disconnected"]:_set_channel_status(channel, name + " · " + str(event.get("message", "")))
			if event.get("state") in ["cancelled", "error", "disconnected"]:
				pending.erase(actor_id)
				if channel == _chat_channel(): _refresh_question_controls()

func _flush_autonomy_messages() -> void:
	if autonomy!=null:autonomy.flush_pending()

func _setup_dark_ui()->void:
	if flower_panel==null and is_instance_valid(view):_setup_flowers_ui()
	if not has_node("IngredientUI"):
		var ingredient_ui=preload("res://scripts/island_ingredients_ui.gd").new();ingredient_ui.name="IngredientUI";add_child(ingredient_ui);ingredient_ui.setup(self)
	if dark_ui==null and is_instance_valid(view):
		dark_ui=preload("res://scripts/dark_island_ui.gd").new();add_child(dark_ui);dark_ui.setup(self)
		var outdoor_ui=preload("res://scripts/outdoor_ui.gd").new();add_child(outdoor_ui);outdoor_ui.setup(self)
		var their_ui=preload("res://scripts/their_island_ui.gd").new();add_child(their_ui);their_ui.setup(self)
		var cat_ui=preload("res://scripts/cat_companion_ui.gd").new();add_child(cat_ui);cat_ui.setup(self)

func _chat_focus_holds(id:String)->bool:
	if intentions!=null and intentions.plans.has(id):return false
	if chat_input==null or not chat_input.has_focus():return false
	if local_host_commands!=null and local_host_commands.pending.get("rows",[]).any(func(row):return row.actor_id==id):return false
	# An editing caret is idle attention, never a pause order for accepted work
	# or its physical delivery/follow route. Questions and model turns stay held.
	if world.farms.active(id) or world.projects.active(id) or world.homestead.active(id) or world.deliveries.active(id) or world.activities.following.has(id) or world.activities.members.has(id):return false
	var routine:RefCounted=world.director.routines.get(id)
	if world.work.jobs.has(id) and (routine==null or not routine.owns_job()):return false
	if world._routes.has(id) and (routine==null or not routine.owns_route):return false
	return true

func _link_holds_body(connection:Variant,id:String="",scope:String="direct")->bool:
	if not is_instance_valid(connection) or not connection.is_busy():return false
	if steward!=null and not steward.pending.is_empty() and connection==links.get(steward.pending.get("id","")) and str(connection.get("turn_key"))==steward.pending.get("key",""):return false
	if not id.is_empty() and connection.get_property_list().any(func(property):return property.name=="turn_key") and _fallback_actions_revoked(id,scope,{"turn_key":str(connection.get("turn_key"))},connection):return false
	# Startup/reconnect owns no model turn. Transport busy must not freeze life.
	# Legacy/manual transports without turn keys retain their original gates.
	if connection.get_property_list().any(func(property):return property.name=="turn_key"):
		return not str(connection.get("turn_key")).is_empty()
	return true

func _refresh_conversation_holds()->void:
	world.activities.held.clear()
	for resident_id in world.director.routines:
		var held: bool=questions.has(resident_id) or group_questions.has(resident_id) or (_valid_link(links,resident_id) and _link_holds_body(links[resident_id],resident_id,"direct")) or (_valid_link(group_links,resident_id) and _link_holds_body(group_links[resident_id],resident_id,"group"))
		held = held or (not group_chat and resident_id==chat_actor and (not pending_question.is_empty() or _chat_focus_holds(resident_id))) or (editor!=null and editor.visible)
		world.activities.held[resident_id]=held
		world.director.set_held(resident_id,held)
		if held and view!=null:view.clear_local_speech(resident_id)

var camera_panels_open:=false
func _process(delta: float) -> void:
	var panels_open:bool=[farm_panel,atlas,house_panel,interior_panel,homestead_panel,journal_panel,memory_panel,book_panel].any(func(panel):return is_instance_valid(panel) and panel.visible)
	if camera_panels_open and not panels_open:_return_to_player()
	camera_panels_open=panels_open
	for who in next_chat.keys():
		var group_busy:bool=_valid_link(group_links,who) and group_links[who].is_busy()
		if chat_input.text.is_empty() and not _chat_is_composing() and _valid_link(links,who) and not links[who].is_busy() and not group_busy and Time.get_ticks_msec()>=int(next_chat_due.get(who,0)) and not questions.has(who) and not group_questions.has(who):
			var batch:Array=next_chat[who];var sources:Array=next_chat_sources.get(who,[])
			var parts:Array=[];var length:=0
			while not batch.is_empty() and length+str(batch[0]).length()+(1 if not parts.is_empty() else 0)<=4000:
				var part:String=str(batch.pop_front());length+=part.length()+(1 if not parts.is_empty() else 0);parts.append(part)
			var source:Dictionary=sources[0] if not sources.is_empty() else {}
			for i in mini(parts.size(),sources.size()):sources.pop_front()
			if batch.is_empty():next_chat.erase(who);next_chat_due.erase(who);next_chat_sources.erase(who)
			else:next_chat[who]=batch;next_chat_sources[who]=sources
			_send_direct(who,"\n".join(parts),source)
	for who in connection_greetings.keys():
		if world.actors.has(who) and view.visible and view.region_id==world.actors[who].region_id and get_viewport_rect().has_point(view.screen(world.point(world.actors[who]))):
			var greeting:String=str(connection_greetings[who]);connection_greetings.erase(who)
			_record_chat(Channels.direct(who),who,greeting,"local");view.say(greeting,"local",who)
	if playground!=null:
		playground.tick(delta)
		if not playground.kind.is_empty() and "human" not in playground.members:
			for who in playground.members:
				if world.director.brains.has(who) and world.director.brains[who].distance()<=8:world.director.brains[who].interactions.condition("watch_play",true,playground.elapsed)
	if intentions!=null:intentions.advance(delta)
	if steward!=null:steward.tick(delta)
	if not world.pocket_notice.is_empty():status.text=world.pocket_notice;world.pocket_notice=""
	for id in host_turn_grants.keys():
		if not _grant_current(id,host_turn_grants[id]):host_turn_grants.erase(id)
	for id in model_fallback_requests.keys():
		var request:Dictionary=model_fallback_requests[id]
		if not _grant_current(id,request):model_fallback_requests.erase(id);continue
		if Time.get_ticks_msec()>=int(request.deadline):
			model_fallback_requests.erase(id);_run_model_fallback(id,request.text,str(request.get("channel",Channels.direct(id))))
	_setup_dark_ui()
	_refresh_conversation_holds()
	if gomoku_match_host!=null:gomoku_match_host.prepare(delta)
	world.advance(delta)
	if game_audio!=null:game_audio.advance(delta)
	if jieqi_panel!=null:jieqi_panel.tick_presentation(delta)
	if gomoku_panel!=null:gomoku_panel.tick_presentation(delta)
	_sync_chess_ui()
	_tick_pending_camp()
	_tick_pending_chess()
	if gomoku_match_host!=null:gomoku_match_host.tick(delta)
	if autonomy!=null:autonomy.tick(delta)
	if proposal_panel!=null:proposal_panel.refresh()
	if wish_panel!=null:wish_panel.refresh(editor.visible or chat.visible or resident_connections.visible or gift_panel.visible or atlas.visible)
	if day_label!=null:day_label.text=LocalText.text("title.name")+" · "+T("ui.main.day_d_s_s")%[world.days.day(),LocalText.content(world.days.phase().name),LocalText.content(world.weather.current().name)]
	for event in world.director.events:
		if int(event.serial)<=local_seen_serial:continue
		local_seen_serial=int(event.serial)
		if world.director.routines[event.actor_id].held:continue
		if view!=null:view.say(str(event.text),"local_rules",event.actor_id,str(event.get("context","")))
		if event.explicit and chat_log!=null:_record_chat(Channels.direct(event.actor_id), event.actor_id, str(event.text), "local")
	if stock == null: return
	furniture_button.visible = view.region_id.begins_with("room.") and view.region_id == world.actors.human.region_id
	if not furniture_button.visible: interior_panel.hide()
	if _camera_keys_allowed():
		var direction := Vector2(float(Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_LEFT)), float(Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_UP)))
		_pan_camera(direction, delta)
	view.set_process_unhandled_input(not atlas.visible and not editor.visible)
	atlas.set_process_unhandled_input(atlas.visible and not editor.visible)
	hud_time += delta
	if hud_time > .2:
		hud_time = 0
		_update_order_bar()
		_refresh_resident_names()
		_refresh_control_status()
		_refresh_gathering()
		stock.text = T("ui.main.wood_s_mushrooms_s") % [world.storage.count("wood"), world.storage.count("mushroom")]
		for event in world.work.events:
			if seen_events.has(event.id): continue
			seen_events[event.id] = true
			if event.has("shared_activity_id"): continue
			if event.actor_id != "human" and world.actors.has(event.actor_id):
				var channel: String = str(task_channels.get(event.actor_id, Channels.direct(event.actor_id)))
				_set_channel_status(channel, LocalText.resident(world,event.actor_id) + " · " + str(event.message))
				_record_chat(channel, event.actor_id, str(event.message), "progress")
				if event.status == "project_completed": view.say(T("ui.main.the_house_is_finished_come_take_a_look"), "local_rules")
			else:
				status.text = str(event.message)
				if event.get("intent","") in ["fireside","eat"] or str(event.message) in [T("system.fireside.this_meal_has_finished"),T("system.fireside.the_fireside_ended_this_does_not_mean_the")]:
					var message:String=status.text
					get_tree().create_timer(4).timeout.connect(func():if is_instance_valid(status) and status.text==message:status.text="")
				if str(event.message).begins_with("+"):view.say(str(event.message),"local_rules","human")
	autosave += delta
	if autosave >= autosave_interval:
		autosave = 0
		memory_books.migrate(world)
		_connection_rows()
		if save_enabled and saved_revision != world.revision and snapshot_path.is_empty():
			if Save.save_world(world, data_dir):
				if life_archive!=null:life_archive.flush()
				saved_revision = world.revision
			else: status.text = T("ui.main.couldn_t_save_progress_check_free_disk_space")

	if save_enabled and snapshot_path.is_empty() and saved_revision==world.revision:backups.tick(world.days.day())

func _exit_tree() -> void:
	if is_instance_valid(life_archive):life_archive.flush()
	if autonomy!=null:autonomy.dispose()
	if world.proposals!=null:world.proposals.level_provider=Callable()
	if save_enabled and not data_dir.is_empty() and snapshot_path.is_empty(): Save.save_world(world, data_dir)

func _house_scenario() -> void:
	# Only a disposable QA world may advance the real game rules for a staged capture.
	if OS.get_environment("HABITAT_DATA_DIR").is_empty(): return
	var site:Dictionary=world.objects["home.house.01"]
	var needed:int=0
	for cost in world.work.stage_costs(site):needed+=int(cost)
	needed-=int(site.get("invested",0))+int(site.get("delivered",{}).get("wood",0))
	# The capture uses real stock, not the retired eight-trees/eight-wood yield.
	for tree in world.objects.values():
		if world.storage.count("wood")>=needed:break
		if tree.kind!="tree" or tree.status!="mature" or tree.region_id!=world.actors.codex.region_id or world.work.claims.has(tree.id) or not world.can_approach("codex",tree):continue
		var result: Dictionary = world.command("codex", {"intent": "chop", "target_id": tree.id})
		if not result.ok: push_error(str(result)); return
		for tick in range(10000):
			if not world.work.jobs.has("codex") and not world._routes.has("codex") and not world.deliveries.active("codex"): break
			world.advance(.2)
	for i in range(5):
		var result: Dictionary = world.command("codex", {"intent": "build", "target_id": "home.house.01"})
		if not result.ok: push_error(str(result)); return
		for tick in range(10000):
			if not world.work.jobs.has("codex") and not world._routes.has("codex") and not world.deliveries.active("codex"): break
			world.advance(.2)

func _camp_action(station_id:String,action:String,preferred:Vector2=Vector2.INF)->void:
	pending_camp.clear()
	if not world.barbecues.has(station_id):return
	var life:RefCounted=world.barbecues[station_id]
	var fire:RefCounted=life.fireside
	if fire.near("human",float(fire.config.near_radius)):
		_perform_camp_action(station_id,action);return
	if world.actors.human.region_id!=life.station.region_id:
		status.text=T("ui.main.return_to_the_campfire_s_region_first");return
	var center:Vector2=world.point(life.station)
	var side:Vector2=(preferred-center).normalized() if preferred!=Vector2.INF and preferred.distance_to(center)>.1 else (world.point(world.actors.human)-center).normalized()
	if side.length()<.1:side=Vector2.DOWN
	var candidates:Array=[]
	for radius in [2.0,2.5,3.5,4.0,4.5]:
		for i in range(32):
			var offset:Vector2=side.rotated(TAU*i/32.0)*radius
			var p:Vector2=center+offset
			if not world.walkable(life.station.region_id,p):continue
			if life.seats().any(func(seat):return world.point(seat).distance_to(p)<1.0):continue
			if world.actors.values().any(func(actor):return actor.id!="human" and actor.region_id==life.station.region_id and world.point(actor).distance_to(p)<1.2):continue
			candidates.append({"point":p,"score":radius*20.0+(1.0-side.dot(offset.normalized()))*5.0+world.point(world.actors.human).distance_to(p)*.1})
	if candidates.is_empty():status.text=T("ui.main.no_reachable_space_beside_this_fire_right_now");return
	candidates.sort_custom(func(a,b):return a.score<b.score)
	var destination:Vector2=Vector2.INF
	for candidate in candidates:
		if not world.find_route("human",candidate.point).is_empty():destination=candidate.point;break
	if destination==Vector2.INF:status.text=T("ui.main.no_reachable_space_beside_this_fire_right_now");return
	var result:Dictionary=world.command("human",{"intent":"move","x":destination.x,"y":destination.y})
	if not result.ok:status.text=str(result.get("message",result.get("error",T("ui.main.can_t_reach_the_fire"))));return
	pending_camp={"station_id":station_id,"action":action,"target":destination};status.text=T("ui.main.walking_to_the_fire")
	for child in get_children():
		if child.get_script()==preload("res://scripts/fireside_panel.gd") and child.life.station.id==station_id:child.feedback.text=T("ui.main.walking_to_the_fire")

func _tick_pending_camp()->void:
	if pending_camp.is_empty():return
	var target:Vector2=pending_camp.target
	if world._routes.has("human"):
		if world._routes.human.is_empty() or world._routes.human.back().distance_to(target)>.01:pending_camp.clear()
		return
	var request:Dictionary=pending_camp.duplicate();pending_camp.clear()
	if world.point(world.actors.human).distance_to(target)>.01:return
	if not world.barbecues.has(request.station_id) or not world.barbecues[request.station_id].fireside.near("human",float(world.barbecues[request.station_id].fireside.config.near_radius)):return
	_perform_camp_action(request.station_id,request.action)

func _perform_camp_action(station_id:String,action:String)->void:
	match action:
		"panel":_show_barbecue_menu(station_id)
		"light":
			var result:Dictionary=world.barbecues[station_id].fireside.light_host()
			status.text=str(result.get("message",result.get("error","")))
			for child in get_children():
				if child.get_script()==preload("res://scripts/fireside_panel.gd") and child.life.station.id==station_id:child.show_result(result);child.refresh()
		"roast":_invite_barbecue(station_id)
		"direct_fish":
			var result:Dictionary=world.barbecues[station_id].fireside.direct_grill(direct_grill_fish_id)
			direct_grill_fish_id="";status.text=str(result.get("message",result.get("error","")))
			if result.get("ok",false):_show_barbecue_menu(station_id)

func _frame_camp(station_id:String)->void:
	if view==null or not world.barbecues.has(station_id):return
	var station:Dictionary=world.barbecues[station_id].station
	if view.region_id!=station.region_id:return
	var reserved:float=0.0
	if island_hud!=null and island_hud.residents_panel.visible:reserved=island_hud.residents_panel.size.x+24
	view.follow_player=false
	view.center=world.point(station)+Vector2(reserved/(64.0*view.zoom),1.0)

func _show_barbecue_menu(station_id:String="")->void:
	if station_id.is_empty():
		var selected:RefCounted=world.nearest_barbecue("human")
		if selected==null:return
		station_id=selected.station.id
	if not world.barbecues.has(station_id):return
	chat.hide();chat_input.release_focus()
	for child in get_children():
		if child.get_script() in [preload("res://scripts/fireside_panel.gd"),preload("res://scripts/fireside_invitation.gd"),preload("res://scripts/fireside_menu.gd")]:child.hide();child.queue_free()
	var panel:=preload("res://scripts/fireside_panel.gd").new();add_child(panel);panel.setup(self,station_id);panel.popup_centered(Vector2i(470,210))

func _invite_barbecue(station_id:String="")->void:
	if station_id.is_empty():
		var selected:RefCounted=world.nearest_barbecue("human")
		if selected==null:return
		station_id=selected.station.id
	if not world.barbecues.has(station_id):return
	chat.hide();chat_input.release_focus()
	for child in get_children():
		if child.get_script() in [preload("res://scripts/fireside_panel.gd"),preload("res://scripts/fireside_invitation.gd"),preload("res://scripts/fireside_menu.gd")]:child.hide();child.queue_free()
	var invitation:=preload("res://scripts/fireside_invitation.gd").new();add_child(invitation);invitation.setup(self,station_id);invitation.popup_centered()

func _show_shared_activity()->void:
	_show_barbecue_menu()

func _clear_local_bubble() -> void:
	if view != null:view.clear_local_speech(_control_actor())

func _save_local_settings() -> void:
	# Other local panels share this file; preserve their newest preference keys.
	local_settings.load(data_dir.path_join("local-life.cfg"))
	local_settings.set_value("life", "enabled", world.local_companion.enabled)
	local_settings.set_value("life", "chatter", world.local_companion.chatter)
	for id in world.director.routines:
		local_settings.set_value("resident:"+str(id),"enabled",world.director.routines[id].enabled)
		local_settings.set_value("resident:"+str(id),"chatter",world.director.routines[id].chatter)
	if local_settings.save(data_dir.path_join("local-life.cfg")) != OK: status.text = T("ui.main.couldn_t_save_daily_life_preferences")

func _open_farm_helpers(_farm_id:String)->void:
	var dialog:=preload("res://scripts/farm_invitation.gd").new();add_child(dialog);dialog.setup(self,farm_panel);dialog.popup_centered()

## Local residents understand a short farm request; the host still confirms before any order.
func _local_farm_command(actor_id:String,text:String)->bool:
	if not world.actors.has(actor_id) or world.director.model_controlled(actor_id):return false
	return _submit_local_command(text,[actor_id],Channels.direct(actor_id))

func _run_farm_command(actor_id:String,parsed:Dictionary)->void:
	var result:Dictionary=world.farms.host_order(actor_id,str(parsed.farm_id),str(parsed.crop_id),str(parsed.intent))
	var context:="farm_command_"+("plant" if parsed.intent=="plant" else "harvest")
	if not result.get("ok",false):
		context="farm_command_busy" if str(result.get("error","")) in ["busy","farm_order_active","hands_full"] else ""
	var line:=str(result.get("message","")) if context.is_empty() else ""
	if not context.is_empty():
		var pool:Array=world.intelligence.speech_pool(actor_id,context)
		line=str(pool[randi()%pool.size()]) if not pool.is_empty() else (T("ui.main.all_right_i_ll_go") if result.get("ok",false) else T("ui.main.let_me_finish_this_first"))
	if line.is_empty():line=T("ui.main.i_can_t_go_right_now")
	view.say(line,"local_rules",actor_id);_record_chat(Channels.direct(actor_id),actor_id,line,"local")
	status.text=T("ui.main.farm_departure") % [LocalText.resident(world,actor_id),LocalText.content(str(world.farms.farms[parsed.farm_id].name))] if result.get("ok",false) else LocalText.resident(world,actor_id)+"："+farm_panel.message(result)

func _local_interaction(come: bool) -> void:
	var id:=_control_actor();chat_input.release_focus()
	if (group_chat and not _resident_panel_open()) or _resident_chat_busy(id):status.text=T("ui.main.finish_the_current_conversation_first");return
	var result: Dictionary=world.host_command(id,{"intent":"come_near" if come else "greet"})
	if result.ok and not come:
		view.say(str(result.message),"local_rules",id);_record_chat(Channels.direct(id),id,str(result.message),"local")
	status.text=str(result.get("message",result.get("error",T("ui.main.coming_over"))))

func _toggle_memories() -> void:
	_toggle_atlas(false)
	if memory_panel.visible:memory_panel.hide();return
	chat.hide();chat_input.release_focus();memory_panel.open()

func _handbook_selected(entry: String) -> void:
	if autonomy!=null:autonomy.player_input()
	match entry:
		"recipes":
			var book:=preload("res://scripts/recipe_book.gd").new();add_child(book);book.setup(world,ui_font)
		"opening_board":_show_opening_board()
		"map":_toggle_atlas(not atlas.visible)
		"memory_books":
			if book_panel.visible:book_panel.hide()
			else:memory_books.migrate(world);book_panel.open()
		"memories":_toggle_memories()
		"workshop":_toggle_workshop()
		"residents":_toggle_resident_connections()
		"autonomy_records":
			if not resident_connections.visible:_toggle_resident_connections()
			resident_connections.tabs.current_tab=2;resident_connections.records_host.show();resident_connections.refresh()
			call_deferred("_scroll_autonomy_records")
func _scroll_autonomy_records() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if resident_connections.visible and resident_connections.records_host.visible:resident_connections.details_scroll.ensure_control_visible(resident_connections.records_text)

func _toggle_workshop() -> void:
	if not editor.visible:
		chat.hide(); house_panel.hide(); interior_panel.hide(); farm_panel.hide(); view.placement_recipe = ""
	editor.toggle_workshop()

func _room_action(args: Dictionary) -> void:
	view.placement_recipe = ""
	var result: Dictionary = world.command("human", args)
	if result.ok and args.get("intent") == "move" and view.run_click: world.force_human_run()
	status.text = str(result.get("message", result.get("error", "")))
	if interior_panel != null: interior_panel.note.text = status.text

func _room_clicked(id: String, position: Vector2) -> void:
	var point := position.floor() + Vector2(.5, .5)
	var carried := str(world.actors.human.get("furniture_id", ""))
	if not view.placement_recipe.is_empty():
		var args := {"intent": "furnish", "target_id": world.interior.rooms()[view.region_id].site_id, "recipe_id": view.placement_recipe, "x": point.x, "y": point.y}
		if assign: _send(T("ui.main.please_craft_and_place_furniture_at_this_spot_inside_the_house") + JSON.stringify(args)); view.placement_recipe = ""
		else: _room_action(args)
		return
	if not carried.is_empty() and id != "room.exit": _room_action({"intent": "place_furniture", "x": point.x, "y": point.y}); return
	if id == "room.exit": _room_action({"intent": "exit"}); return
	if world.interior.furniture.has(id):
		interior_panel.select_item(id); return
	world.command("human", {"intent": "stop"})
	_room_action({"intent": "move", "x": position.x, "y": position.y})

func _qa_job(actor_id: String, args: Dictionary) -> void:
	var result: Dictionary = world.command(actor_id, args)
	if not result.ok: push_error(str(result)); return
	for tick in range(16000):
		if not world.work.jobs.has(actor_id) and not world._routes.has(actor_id) and not world.deliveries.active(actor_id): return
		if world.work.jobs.get(actor_id,{}).get("step") == "seated": return
		world.advance(.15)
	push_error("Interior QA job timed out: " + str(args))

func _interior_scenario() -> void:
	if OS.get_environment("HABITAT_DATA_DIR").is_empty(): return
	_house_scenario()
	for i in range(9, 13): _qa_job("codex", {"intent": "chop", "target_id": "home.tree.%02d" % i})
	for placement in [["rug", 13.5, 5.5], ["table", 13.5, 5.5], ["chair", 11.5, 6.5], ["chair", 15.5, 6.5], ["lamp", 21.5, 2.5]]:
		_qa_job("codex", {"intent": "furnish", "target_id": "home.house.01", "recipe_id": placement[0], "x": placement[1], "y": placement[2]})
	_qa_job("human", {"intent": "sit", "target_id": "furniture.3"})
	_qa_job("codex", {"intent": "sit", "target_id": "furniture.4"})
	view.show_region(world.actors.human.region_id); view.last_human_region = view.region_id
	furniture_button.show(); hud_time = .3
	status.text = T("ui.main.use_furniture_arrange_room_return_to_the_yard_at_the_door")
	view.say(T("ui.main.little_by_little_this_cottage_feels_like_ours"), "local_rules")

func _stop_companion() -> void:
	if group_chat:
		for id in group_links:
			if not _valid_link(group_links,id):continue
			group_links[id].cancel_turn()
			if task_channels.get(id) == Channels.ALL: world.command(id, {"intent":"stop"})
		group_questions.clear(); _refresh_question_controls()
	else:
		_cancel_resident_turn(chat_actor)
		world.command(chat_actor, {"intent":"stop"})
	_update_order_bar()

func _update_order_bar() -> void:
	var id:=_control_actor()
	var job: Dictionary = world.work.jobs.get(id, {})
	order_bar.visible = job.get("intent") == "gather_wood" and not job.has("project_id")
	if not order_bar.visible: return
	var count := str(job.trees_completed) if int(job.tree_count) == 0 else "%s / %s" % [job.trees_completed, job.tree_count]
	order_label.text = T("ui.main.s_gathering_wood_s_trees_hauled_s_wood_stored") % [LocalText.resident(world,id),count, job.wood_stored]

func _partial_build_scenario() -> void:
	if OS.get_environment("HABITAT_DATA_DIR").is_empty(): return
	for plan in [["cottage", 5, 5], ["cottage-blue", 5, 8]]:
		var art: Dictionary = library.artworks[plan[0]].duplicate(true)
		art.structure.width = plan[1]; art.structure.depth = plan[2]; library.publish(art, int(art.revision))
	_qa_job("human", {"intent": "select_blueprint", "target_id": "home.house.01", "blueprint_id": "cottage"})
	_qa_job("human", {"intent": "select_blueprint", "target_id": "home.house.02", "blueprint_id": "cottage-blue"})
	_qa_job("codex", {"intent": "chop", "target_id": "home.tree.01"})
	_qa_job("human", {"intent": "build", "target_id": "home.house.01"})
	_qa_job("human", {"intent": "take"})
	_qa_job("human", {"intent": "build", "target_id": "home.house.02"})
	_qa_job("codex", {"intent": "chop", "target_id": "home.tree.02"})
	_qa_job("human", {"intent": "take"})
	_qa_job("codex", {"intent": "take"})
	_qa_job("codex", {"intent": "build", "target_id": "home.house.02"})
	house_panel.open_site("home.house.02"); view.center = world.locations.point("p_71_83"); view.zoom = .95; hud_time = .3

func _wood_order_scenario() -> void:
	if OS.get_environment("HABITAT_DATA_DIR").is_empty(): return
	var result: Dictionary = world.command("codex", {"intent": "gather_wood", "target_id": "home.tree.01"})
	if not result.ok: push_error(str(result)); return
	for tick in range(16000):
		world.advance(.15)
		if world.work.jobs.has("codex") and world.work.jobs.codex.trees_completed >= 2 and world.work.jobs.codex.phase == "chop": break
	_update_order_bar(); view.center = world.point(world.actors.codex) + Vector2(0, -3); view.zoom = .85; hud_time = .3

func _project_control(args: Dictionary) -> void:
	var id: String=project_panel.actor_id
	if args.intent in ["pause_project","cancel_project"]:
		_cancel_resident_turn(id)
	if args.intent=="resume_project" and _resident_chat_busy(id):status.text=T("ui.main.finish_the_current_conversation_first");return
	var result: Dictionary=world.command(id,args);status.text=str(result.get("message",result.get("error",T("ui.main.plan_updated"))));project_panel.refresh()

func _discuss_project(id: String) -> void:
	_select_chat(project_panel.actor_id)
	_send(T("ui.main.house_plan_request") % id)

func _cancel_resident_turn(id: String) -> void:
	next_chat.erase(id);next_chat_due.erase(id);next_chat_sources.erase(id)
	if steward!=null:steward.bubbles=steward.bubbles.filter(func(entry):return entry.id!=id)
	if intentions!=null:intentions.cancel(id)
	if memory_life!=null:memory_life.cancel_pending(id)
	host_turn_grants.erase(id)
	model_fallback_requests.erase(id)
	if gomoku_match_host!=null:
		gomoku_match_host.discard_chat(id);gomoku_match_host.pause_target(id,T("ui.main.the_player_stopped_or_changed_participants_keep_the_board_as_it_i"))
	if autonomy!=null:autonomy.interrupted(id)
	if _valid_link(links,id):links[id].cancel_turn()
	if _valid_link(group_links,id):group_links[id].cancel_turn()
	questions.erase(id); group_questions.erase(id)
	if group_chat or chat_actor==id: _refresh_question_controls()

func _sync_chess_ui()->void:
	var shown:bool=(jieqi_panel!=null and jieqi_panel.visible) or (gomoku_panel!=null and gomoku_panel.card.visible) or (chess_choice!=null and chess_choice.visible)
	view.chess_overlay=shown
	if island_hud==null:return # The retained legacy scene has no island HUD shell.
	if shown:
		if chess_ui_visibility.is_empty():chess_ui_visibility={"hud":island_hud.visible,"day":day_label.visible,"status":status.visible}
		island_hud.hide();day_label.hide();status.hide()
	elif not chess_ui_visibility.is_empty():
		island_hud.visible=bool(chess_ui_visibility.hud) and not editor.visible and not atlas.visible
		day_label.visible=bool(chess_ui_visibility.day)
		status.visible=bool(chess_ui_visibility.status) and not editor.visible and not atlas.visible
		chess_ui_visibility.clear()

func _focus_chess_table(id:String)->void:
	var site:Dictionary=world.gomoku.table(id)
	if site.is_empty():return
	view.show_region(str(site.region_id));view.follow_player=false;view.center=world.point(site)

func _chess_bubble_sound(event:Dictionary)->void:
	var id:String=str(event.get("actor_id",""))
	event["world_gate_before"]=world.director.speech_after
	event["personal_gate_before"]=world.director.routines[id].next_speech if world.director.routines.has(id) else -1.0
	if game_audio!=null and game_audio.observer!=null:
		event["voice_scheduled"]=game_audio.observer.panel_bubble(event)
		event["voice_clock"]=game_audio.clock
		event["voice_distance"]=world.point(world.actors[id]).distance_to(game_audio.listener) if world.actors.has(id) else -1.0
		event["voice_enabled"]=game_audio.enabled and game_audio.speech_enabled
		event["voice_focused"]=game_audio.focused
	event["world_gate_after"]=world.director.speech_after
	event["personal_gate_after"]=world.director.routines[id].next_speech if world.director.routines.has(id) else -1.0

func _walk_to_chess(id:String)->void:
	pending_chess.clear()
	var site:Dictionary=world.gomoku.table(id)
	if site.is_empty():return
	var human:Dictionary=world.actors.human
	if human.region_id!=site.region_id:status.text=T("chess.other_island");return
	var radius:float=float(island_hud.config.context_radius) if island_hud!=null else float(JSON.parse_string(FileAccess.get_file_as_string("res://content/home-v3/ui.json")).context_radius)
	var center:Vector2=world.point(site)
	if world.point(human).distance_to(center)<=radius:_open_chess(id);return
	var candidates:Array=[]
	for reach in [2.0,3.0,4.0]:
		if reach>radius:continue
		for i in range(24):
			var point:Vector2=center+Vector2.from_angle(TAU*i/24.0)*reach
			if world.walkable(site.region_id,point):candidates.append(point)
	candidates.sort_custom(func(a,b):return a.distance_squared_to(world.point(human))<b.distance_squared_to(world.point(human)))
	for point in candidates:
		if world.find_route("human",point).is_empty():continue
		var result:Dictionary=world.command("human",{"intent":"move","x":point.x,"y":point.y})
		if not result.ok:status.text=str(result.get("message",result.get("error","")));return
		pending_chess={"site_id":id,"target":point};status.text=T("chess.entry.walking");return
	status.text=T("chess.entry.unreachable")

func _tick_pending_chess()->void:
	if pending_chess.is_empty():return
	var target:Vector2=pending_chess.target
	if world._routes.has("human"):
		if world._routes.human.is_empty() or world._routes.human.back().distance_to(target)>.01:pending_chess.clear()
		return
	var request:Dictionary=pending_chess.duplicate();pending_chess.clear()
	if world.point(world.actors.human).distance_to(target)>.05:return
	if world.gomoku.table(request.site_id).is_empty():return
	_open_chess(request.site_id)

func _open_chess(id:String="")->void:
	if id.is_empty():
		if island_hud!=null:id=island_hud.nearby_chess_site()
		else:
			# Retained legacy scene has no contextual HUD; preserve its observational menu.
			var nearest:=INF
			for site in world.leisure.sites.values():
				if world.gomoku.table(str(site.id)).is_empty():continue
				var distance:float=world.point(site).distance_to(world.point(world.actors.human))
				if distance<nearest:nearest=distance;id=str(site.id)
		if id.is_empty():status.text=T("chess.entry.nearby_only");return
	_toggle_atlas(false);chat.hide();chat_input.release_focus();leisure_panel.hide();farm_panel.hide();memory_panel.hide();gomoku_panel.card.hide();jieqi_panel.hide()
	gomoku_panel.site_id=id
	chess_choice.open(id)
func _open_gomoku(id: String="") -> void:
	if id.is_empty():
		id=gomoku_panel.site_id
		for game in world.gomoku.sessions.values():
			if game.phase in ["arriving","playing"] and "human" in world.gomoku.players(game):id=game.site_id;break
	_toggle_atlas(false);chat.hide();chat_input.release_focus();leisure_panel.hide();farm_panel.hide();memory_panel.hide()
	view.show_region("home");view.follow_player=false
	if world.leisure.sites.has(id):view.center=world.point(world.leisure.sites[id])+Vector2(0,1)
	gomoku_panel.open(id)
func _begin_gomoku(id: String,opponent: String,human_black: bool,mode: String,difficulty: String) -> void:
	if world.actors.human.region_id!=world.gomoku.table(id).get("region_id",""):
		gomoku_panel.starting=false;gomoku_panel.start_button.disabled=false;gomoku_panel.message.text=T("chess.other_island");return
	if not world.jieqi.game.is_empty() and world.jieqi.phase in ["paused","arriving","playing"]:
		gomoku_panel.starting=false;gomoku_panel.start_button.disabled=false;gomoku_panel.message.text=T("chess.finish_previous");return
	if world.hunger.rank(opponent)>=3:
		gomoku_panel.starting=false;gomoku_panel.start_button.disabled=false;gomoku_panel.message.text=T("jieqi.hungry");return
	var checked: Dictionary=world.gomoku.validate_begin(id,opponent,human_black,mode,difficulty)
	if not checked.ok:gomoku_panel.starting=false;gomoku_panel.start_button.disabled=false;gomoku_panel.message.text=str(checked.get("message",checked.get("error","")));return
	if _resident_chat_busy(opponent):gomoku_panel.starting=false;gomoku_panel.start_button.disabled=false;gomoku_panel.message.text=T("ui.main.this_companion_is_replying_or_awaiting_your_answer_invite_them_la");return
	_cancel_resident_turn(opponent)
	var result: Dictionary=world.gomoku.begin_host(id,opponent,human_black,mode,difficulty)
	gomoku_panel.message.text=str(result.get("message",result.get("error","")));gomoku_panel.refresh()
func _resume_gomoku(id: String) -> void:
	if world.actors.human.region_id!=world.gomoku.table(id).get("region_id",""):
		gomoku_panel.message.text=T("chess.other_island");return
	var game: Dictionary=world.gomoku.sessions.get(id,{})
	if game.is_empty():return
	for who in world.gomoku.players(game):
		if who!="human" and world.hunger.rank(who)>=3:gomoku_panel.message.text=T("jieqi.hungry");return
		if who!="human" and _resident_chat_busy(who):gomoku_panel.message.text=T("ui.main.answer_the_companion_s_question_or_wait_for_their_reply_to_finish");return
	for who in world.gomoku.players(game):
		if who!="human":_cancel_resident_turn(who)
	var result: Dictionary=world.gomoku.resume_host(id)
	gomoku_panel.message.text=str(result.get("message",result.get("error","")));gomoku_panel.refresh()

func _participants_chosen(ids: Array,args: Dictionary) -> void:
	if args.get("intent")=="build_house" and ids.size()>1:
		var eligible:Array=ids.filter(func(id):return world.actors.has(id) and participant_picker.unavailable(world.actors[id]).is_empty())
		for id in eligible:_cancel_resident_turn(id)
		var team_results:Array=world.projects.invite_team(eligible,str(args.get("target_id","")))
		status.text=" · ".join(PackedStringArray(team_results.map(func(result):return str(result.get("message",result.get("error",""))))))
		return
	var results: Array=[]
	for id in ids:
		_cancel_resident_turn(id)
		var result: Dictionary=world.host_command(id,args)
		results.append(LocalText.resident(world,id)+"："+str(result.get("message",T("ui.main.started") if result.ok else result.get("error",T("ui.main.can_t_do_that_right_now_162")))))
	status.text=" · ".join(results)

func _gather_residents() -> void:
	if not world.activities.gathering.is_empty():world.activities.dismiss();_refresh_gathering();return
	for id in world.actors:
		if id!="human":_cancel_resident_turn(id)
	world.activities.gather();_refresh_gathering()

func _refresh_gathering() -> void:
	var state: Dictionary=world.activities.gathering
	gathering_button.text=T("ui.main.follow") if world.activities.following.is_empty() else T("ui.main.follow_d")%world.activities.following.size()
	gathering_note.text=""
	if state.is_empty():return
	var arrived: int=world.activities.members.values().filter(func(m):return m.arrived).size()
	gathering_note.text=T("ui.main.gathering_s_s")%[arrived,state.total] if state.phase=="arriving" else T("ui.main.staying_together_s_sec")%int(ceil(state.remaining))
	if not state.failures.is_empty():gathering_note.text+=T("ui.main.s_couldn_t_arrive")%state.failures.size()

func _refresh_resident_names() -> void:
	var wanted: Array = world.actors.keys().filter(func(id): return id != "human")
	wanted.append(Channels.ALL)
	var current: Array = []
	for i in range(chat_picker.item_count): current.append(chat_picker.get_item_metadata(i))
	if current != wanted:
		chat_picker.clear()
		for id in wanted:
			chat_picker.add_item(""); chat_picker.set_item_metadata(chat_picker.item_count-1, id)
	for i in range(chat_picker.item_count):
		var id: String = chat_picker.get_item_metadata(i)
		var channel: String = Channels.ALL if id == Channels.ALL else Channels.direct(id)
		var waiting: bool = not group_questions.is_empty() if id == Channels.ALL else questions.has(id)
		chat_picker.set_item_text(i, (T("ui.main.everyone") if id == Channels.ALL else str(LocalText.resident(world,id))) + (T("ui.main.awaiting_answer") if waiting else T("ui.main.new_message") if dialogue.unread.has(channel) else ""))
		if id == (Channels.ALL if group_chat else chat_actor): chat_picker.select(i)

func _project_scenario() -> void:
	if OS.get_environment("HABITAT_DATA_DIR").is_empty(): return
	world.command("human", {"intent": "select_blueprint", "target_id": "home.house.01", "blueprint_id": "cottage-blue"})
	_qa_job("human", {"intent": "chop", "target_id": "home.tree.01"})
	_qa_job("human", {"intent": "take"})
	_qa_job("human", {"intent": "deliver_wood", "target_id": "home.house.01"})
	world.command("codex", {"intent": "build_house", "target_id": "home.house.01"})
	for tick in range(60000):
		world.advance(.2)
		if scenario == "project_paused" and int(world.objects["home.house.01"].stage_index) >= 2:
			world.command("codex", {"intent": "stop"}); break
		if not world.projects.active("codex"): break
	project_panel.refresh(); house_panel.open_site("home.house.01"); view.center = world.locations.point("p_40_40"); view.zoom = .8; hud_time = .3

func _farm_scenario() -> void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-"): return
	world.local_companion.set_enabled(false)
	for farm in world.farms.farms.values():
		var index := 0
		for plot in world.farms.farm_plots(farm.id):
			var crop: String = farm.crop_ids[index % farm.crop_ids.size()]
			_qa_job("human", {"intent":"plant","target_id":plot.id,"crop_id":crop})
			_qa_job("human", {"intent":"water","target_id":plot.id})
			index += 1
	# Disposable QA advances the same clock used by live growth; no save or inventory edits.
	world.advance(90000)
	if scenario == "farm_map": _toggle_atlas(true); return
	var id := "farm.home" if scenario == "farm_home" else "farm.hill" if scenario == "farm_hill" else "farm.lake" if scenario == "farm_lake" else "farm.east"
	view.center = world.catalog.rectangle(world.farms.farms[id].rect).get_center() + Vector2(1,1); view.zoom = 1.0
	if scenario == "farm_panel":
		view.center = world.locations.point("p_42_56"); view.zoom = 1.05; farm_panel.open_farm("farm.home", "farm.home.plot.01")
	if scenario == "farm_editor": editor.open_art("crop-tomato")

func _village_scenario() -> void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-"): return
	world.local_companion.set_enabled(false); world.village.enabled=false
	_house_scenario()
	_farm_scenario()
	_qa_job("human",{"intent":"move","x":world.locations.point("p_44_46").x,"y":world.locations.point("p_44_46").y})
	_qa_job("codex",{"intent":"move","x":world.locations.point("p_47_47").x,"y":world.locations.point("p_47_47").y})
	_qa_job("companion-2",{"intent":"move","x":world.locations.point("p_49_50").x,"y":world.locations.point("p_49_50").y})
	for pair in world.locations.section("village_snapshot"):
		world.route_to(pair[0],Vector2(pair[1],pair[2]))
		for tick in range(3000):
			if not world._routes.has(pair[0]): break
			world.advance(.1)
	view.follow_player=false; view.center=world.locations.point("p_44_49"); view.zoom=.85
	status.text=T("ui.main.neat_farm_rows_three_independent_characters_a_courtyard_to_share")
	if scenario=="village_people": view.center=world.locations.point("p_49_48"); view.zoom=1.25
	if scenario=="village_orange_editor": editor.open_art("orange-haired-girl")

func _leisure_scenario() -> void:
	if OS.get_environment("HABITAT_DATA_DIR").is_empty():return
	_qa_job("codex",{"intent":"gather_wood","tree_count":12})
	for id in world.leisure.sites:_qa_job("codex",{"intent":"build_facility","target_id":id})
	for entry in [["human","play.swing"],["codex","play.swing"],["companion-2","play.stage"],["npc.mira","play.gazebo"],["npc.nora","play.stage"]]:
		world.host_command(entry[0],{"intent":"use_facility","target_id":entry[1]})
	for tick in range(1000):
		world.advance(.1)
		if world.actors.codex.activity=="swinging" and world.actors["npc.mira"].activity=="seated" and world.actors["npc.nora"].activity=="dancing":break
	view.center=world.locations.point("p_38_60");view.zoom=.78;status.text=T("ui.main.swings_tea_breaks_a_woodland_stage")
	if scenario=="leisure_gather":
		_gather_residents()
		for tick in range(900):
			world.advance(.1)
			if world.activities.gathering.get("phase")=="holding":break
		_refresh_gathering();view.center=world.point(world.actors.human)+Vector2(0,1);view.zoom=1.05
	if scenario=="leisure_editor":editor.open_art("play-swing");editor.template_dialog.open_config()
	if scenario=="leisure_invite":participant_picker.open_for({"intent":"use_facility","target_id":"play.gazebo"},"npc.mira")

func _valid_link(collection:Dictionary,id:String)->bool:
	return collection.has(id) and is_instance_valid(collection[id]) and not collection[id].is_queued_for_deletion()

func _connection_releasing(id:String,scope:String)->void:
	var collection:Dictionary=links if scope=="direct" else group_links
	collection.erase(id)
	if scope=="direct" and id=="codex":link=null
	if endpoint!=null:endpoint.dialogue_links.erase(id+":"+scope)
	connection_ui_states.erase(id+":"+scope)

func _resident_chat_busy(id: String) -> bool:
	return questions.has(id) or group_questions.has(id) or (_valid_link(links,id) and _link_holds_body(links[id])) or (_valid_link(group_links,id) and _link_holds_body(group_links[id]))

func _bind_external_ai(id: String, external: bool, copy_config:=true) -> void:
	if autonomy!=null:resident_connections.preferences.enable_autonomy(id,false)
	if not world.director.model_controlled(id):return
	_cancel_resident_turn(id)
	world.command(id,{"intent":"stop"})
	if _valid_link(links,id):
		connection_pool.release(id)
		if autonomy!=null:autonomy.retire(id)
	_drop_group_link(id)
	connection_ui_states.erase(id+":direct");connection_ui_states.erase(id+":group")
	external_residents[id]=external
	if connection_pool!=null:
		var modes:Dictionary=connection_pool.settings.get_value("connection","external_residents",{});modes[id]=external;connection_pool.settings.set_value("connection","external_residents",modes)
	var settings:=ConfigFile.new();settings.load(data_dir.path_join("connection-mode.cfg"));settings.set_value("connection","external_residents",external_residents);settings.save(data_dir.path_join("connection-mode.cfg"))
	_ensure_link(id)
	if id=="codex":link=links[id]
	endpoint.sync_bindings()
	if external:
		if copy_config:DisplayServer.clipboard_set(JSON.stringify(ai_connect_panel.configuration(),"  "))
		ai_connect_panel.note.text=T("ui.main.configuration_copied_this_resident_now_uses_external_ai_game_mess")
	else:ai_connect_panel.note.text=T("ui.main.original_connection_restored_conversation_records_stay_send_a_mes")
	_refresh_control_ui()
	if resident_connections!=null:resident_connections.refresh()

func _new_dialogue_link(id: String, scope: String) -> Node:
	var connection: Node
	if external_residents.get(id,false):
		connection=preload("res://scripts/external_dialogue_link.gd").new()
	elif dialogue_adapter_factory.is_valid():
		connection = dialogue_adapter_factory.call(id, scope)
	elif id == "codex" and shared_test:
		connection = SharedLink.new()
		connection.snapshot_provider = func(): return world.observe(id, {"limit":6})
	elif scope == "direct" and id == "codex" and not conversation_thread.is_empty():
		connection = Conversation.new(); connection.thread_id = conversation_thread
	else: connection = Link.new()
	return connection

func _create_dialogue_link(id:String,scope:String)->Node:
	var pool:Node=preload("res://scripts/connection_session_pool.gd").obtain(get_tree(),data_dir)
	var connection:Node=pool.acquire(id,scope,_new_dialogue_link.bind(id,scope))
	connection.resident_id = id
	if connection.world_id.is_empty():connection.world_id = world.world_id
	if connection is Link: connection.conversation_scope = scope

	var callback:Callable=_bound_companion_event.bind(id) if scope=="direct" else _bound_companion_event.bind(id,scope)
	if not connection.event_received.is_connected(callback):connection.event_received.connect(callback)
	if endpoint!=null:
		if external_residents.get(id,false):endpoint.dialogue_links[id+":"+scope]=connection
		else:endpoint.dialogue_links.erase(id+":"+scope)
	return connection

func _ensure_link(id: String) -> void:
	if _valid_link(links,id): return
	links[id] = _create_dialogue_link(id, "direct")
	if endpoint != null: endpoint.conversation_links = links

func _ensure_group_link(id: String) -> void:
	if not _valid_link(group_links,id): group_links[id] = _create_dialogue_link(id, "group")

func _drop_group_link(id: String) -> void:
	if endpoint!=null:endpoint.dialogue_links.erase(id+":group")
	if not _valid_link(group_links,id): return
	connection_pool.release(id,"group");group_links.erase(id)

func _toggle_shared_test() -> void:
	if (group_chat and not _resident_panel_open()) or _control_actor() != "codex": return
	if autonomy!=null:resident_connections.preferences.enable_autonomy("codex",false)
	_cancel_resident_turn("codex")
	world.command("codex", {"intent":"stop"})
	connection_pool.release("codex"); _drop_group_link("codex")
	if autonomy!=null:autonomy.retire("codex")
	shared_test = not shared_test
	var settings := ConfigFile.new()
	settings.set_value("connection", "shared_test", shared_test)
	if settings.save(data_dir.path_join("connection-mode.cfg")) != OK: status.text = T("ui.main.couldn_t_save_the_connection_choice")
	world.director.set_controller("codex", "model")
	_ensure_link("codex"); link = links.codex; endpoint.sync_bindings()
	_record_chat(Channels.direct("codex"), "", T("ui.main.shared_test_companion_a_separate_conversation_that_replies_automa") if shared_test else T("ui.main.returned_to_the_original_dialogue_connection"), "notice")
	_refresh_control_ui()
	if resident_connections!=null:resident_connections.refresh()

func _copy_conversation_message() -> void:
	var connection:Variant= links.get(_control_actor())
	if not is_instance_valid(connection) or not connection.has_method("copy_prompt"): return
	var prompt: String = connection.copy_prompt()
	if prompt.is_empty(): status.text = T("ui.main.write_and_send_a_game_message_first"); return
	DisplayServer.clipboard_set(prompt)
	status.text = T("ui.main.copied_paste_into_the_bound_codex_conversation")

func _change_controller(index: int) -> void:
	if group_chat and not _resident_panel_open():return
	var id:=_control_actor();var source:="model" if index==0 else "local"
	if world.actors[id].controller==source:return
	if autonomy!=null:resident_connections.preferences.enable_autonomy(id,false)
	_cancel_resident_turn(id);connection_ui_states.erase(id+":direct");connection_ui_states.erase(id+":group")
	var result: Dictionary=world.director.set_controller(id,source)
	if result.ok:
		if autonomy!=null:autonomy.retire(id)
		if source=="model":_ensure_link(id)
		elif local_host_commands!=null:local_host_commands.speech_queue.append({"actor_id":id,"line":"I am still here with you." if TranslationServer.get_locale().begins_with("en") else preload("res://scripts/localization.gd").source("content.health_20261107.47378bd252c2"),"channel_id":Channels.direct(id),"expires":world.director.time+180})
		endpoint.sync_bindings()
		_set_channel_status(Channels.direct(id),LocalText.resident(world,id)+(T("ui.main.model_connection_selected_send_a_message_to_start_it") if source=="model" else T("ui.main.back_to_local_life_previous_work_is_paused")))
	_refresh_control_ui()
	if resident_connections!=null:resident_connections.refresh()

func _refresh_control_ui() -> void:
	if controller_picker==null:return
	var id:=_control_actor();var group_controls: bool=group_chat and not _resident_panel_open()
	controller_picker.visible=false;daily_controls.visible=not group_controls
	find_partner_button.visible=not group_controls
	stop_chat_button.visible=group_chat;stop_chat_button.text=T("ui.main.stop_group_chat")
	if group_controls:relay_button.hide();shared_button.hide();_refresh_control_status();return
	controller_picker.select(0 if world.director.model_controlled(id) else 1)
	var uses_conversation: bool=_valid_link(links,id) and links[id].has_method("read_mailbox")
	var uses_shared: bool=_valid_link(links,id) and links[id].has_method("can_queue")
	var source_label:String=T("simple.connect")
	if uses_conversation:source_label=T("ui.main.original_conversation_manual_relay")
	elif shared_test and id=="codex":source_label=T("ui.main.shared_test_automatic")
	elif resident_connections!=null and resident_connections.preferences.preference(id).runtime_active:source_label=T("ui.main.model_connection_messages_or_enabled_events")
	controller_picker.set_item_text(0,source_label);controller_picker.set_item_text(1,T("simple.local"))
	relay_button.visible=uses_conversation and world.director.model_controlled(id)
	shared_button.visible=id=="codex";shared_button.text=T("ui.main.return_to_original_connection") if shared_test else T("ui.main.try_automatic_dialogue")
	activity_toggle.set_pressed_no_signal(world.director.routines[id].enabled)
	chatter_toggle.set_pressed_no_signal(world.director.routines[id].chatter)
	_refresh_control_status()

func _refresh_control_status() -> void:
	if resident_status==null:return
	var state:=_resident_connection_snapshot(_control_actor())
	resident_status.text=state.origin+" · "+state.connection
	resident_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART

func _open_homestead(id: String="") -> void:
	if resident_connections!=null:resident_connections.close_panel()
	chat.hide();chat_input.release_focus();house_panel.hide();farm_panel.hide();leisure_panel.hide();memory_panel.hide();journal_panel.hide();fishing_panel.hide();gomoku_panel.card.hide();action_dock.menu.hide()
	homestead_panel.open(id)

func _homestead_action(id: String,args: Dictionary) -> void:
	if id!="human" and args.intent not in ["stop","homestead_cancel"] and _resident_chat_busy(id):homestead_panel.feedback.text=T("ui.main.finish_this_resident_s_conversation_or_answer_their_question_befo");return
	if id!="human" and args.intent in ["stop","homestead_cancel"]:_cancel_resident_turn(id)
	var result: Dictionary=world.command(id,args)
	homestead_panel.feedback.text=str(result.get("message",result.get("error",T("ui.main.assignment_accepted"))))
	homestead_panel.refresh()

func _activity_menu_selected(id: int) -> void:
	if resident_connections!=null:resident_connections.close_panel()
	match id:
		0:_open_chess()
		1:_open_fishing()
		2:_show_shared_activity()

func _stop_resident(id: String) -> void:
	if id=="human" or not world.actors.has(id):return
	_cancel_resident_turn(id);world.command(id,{"intent":"stop"});_update_order_bar()

func _resident_panel_open() -> bool:
	return resident_connections!=null and resident_connections.visible

func _control_actor() -> String:
	if _resident_panel_open() and world.actors.has(resident_connections.selected_id):return resident_connections.selected_id
	return chat_actor

func _build_resident_connections(root: Control) -> void:
	resident_connections=preload("res://scripts/resident_connections_panel.gd").new();root.add_child(resident_connections)
	resident_connections.setup(world,library,data_dir,_resident_connection_snapshot)
	resident_connections.life_archive_provider=func():return life_archive
	autonomy_notice=Label.new();root.add_child(autonomy_notice);autonomy_notice.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE);autonomy_notice.offset_left=26;autonomy_notice.offset_right=-26;autonomy_notice.offset_top=72;autonomy_notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;autonomy_notice.mouse_filter=Control.MOUSE_FILTER_IGNORE;autonomy_notice.add_theme_color_override("font_color",Color("ffe1a0"));autonomy_notice.hide()
	autonomy=preload("res://scripts/autonomy_host.gd").new();autonomy.setup(self,resident_connections.preferences)
	resident_connections.autonomy_provider=autonomy.status
	gift_panel=preload("res://scripts/gift_panel.gd").new();root.add_child(gift_panel);gift_panel.setup(world,func(args):
		autonomy.player_input()
		var result: Dictionary=world.command("human",args);status.text=str(result.get("message",result.get("error","")));return result)
	wish_panel=preload("res://scripts/wish_panel.gd").new();resident_connections.get_parent().add_child(wish_panel);wish_panel.setup(world)
	resident_connections.gift_requested.connect(func(id):resident_connections.close_panel();gift_panel.open(id))
	resident_connections.promise_cancel_requested.connect(func(id,key):
		var result: Dictionary=world.command(id,{"intent":"promise_cancel","promise_id":key})
		resident_connections.notice.text=str(result.get("error",T("ui.main.promise_cancelled_all_real_materials_are_safe")));resident_connections.refresh())
	world.proposals.level_provider=func(id):return resident_connections.preferences.preference(id).level
	proposal_host=preload("res://scripts/proposal_host.gd").new(self)
	proposal_panel=preload("res://scripts/proposal_panel.gd").new();root.add_child(proposal_panel);proposal_panel.setup(world)
	proposal_panel.responded.connect(func(key,accepted):
		autonomy.player_input()
		var result: Dictionary=world.proposals.respond_host(key,accepted,proposal_host.start)
		proposal_panel.note.text=str(result.get("message",result.get("error",T("ui.main.your_choice_is_recorded"))));proposal_panel.refresh())
	endpoint.model_action_requested.connect(func(id):autonomy.scheduler.note_model_action(id))
	resident_connections.visibility_changed.connect(func():action_dock.visible=not resident_connections.visible)
	controller_picker.reparent(resident_connections.controls_host,false)
	controller_picker.hide()
	resident_connections.connect_requested.connect(func(id):_simple_connection_action(id))
	daily_controls.reparent(resident_connections.life_host,false)
	resident_status.hide()
	var advanced:=VBoxContainer.new();resident_connections.controls_host.add_child(advanced)
	var advanced_toggle:=_button(resident_connections.controls_host,T("ui.main.advanced_connection_options"),func():advanced.visible=not advanced.visible)
	advanced_toggle.toggle_mode=true;advanced.hide();advanced_toggle.hide()
	relay_button.reparent(advanced,false);shared_button.reparent(advanced,false)
	resident_connections.external_button.reparent(advanced,false)
	var external_note:=Label.new();external_note.text=T("simple.explain");external_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;advanced.add_child(external_note)
	find_partner_button.reparent(resident_connections.actions_host,false)
	gathering_button.reparent(resident_connections.actions_host,false)
	gathering_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	gathering_button.position=Vector2.ZERO;gathering_button.size=Vector2.ZERO
	gathering_note.reparent(resident_connections.life_host,false)
	gathering_note.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);gathering_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var delegate:=_button(resident_connections.actions_host,T("ui.main.ask_this_resident"),func():
		_select_chat(resident_connections.selected_id);assign=not assign
		status.text=T("ui.main.choose_a_target_to_discuss_with_this_companion") if assign else T("ui.main.movement_hint"))
	delegate.toggle_mode=true
	_button(resident_connections.actions_host,T("ui.main.invite_companions_to_fish"),func():action_dock.open_invite())
	order_bar.reparent(resident_connections.life_host,false);order_bar.position=Vector2.ZERO
	project_panel.reparent(resident_connections.life_host,false);project_panel.position=Vector2.ZERO
	project_panel.progress.custom_minimum_size.x=0;project_panel.detail.custom_minimum_size.x=0
	resident_connections.selected.connect(func(id):_refresh_control_ui();project_panel.actor_id=id;project_panel.refresh();_update_order_bar())
	resident_connections.chat_requested.connect(func(id):resident_connections.close_panel();_select_chat(id);chat.show())
	resident_connections.stop_requested.connect(_stop_resident)
	resident_connections.external_requested.connect(func(id):
		ai_connect_panel.open()
		for index in range(ai_connect_panel.actors.item_count):
			if ai_connect_panel.actors.get_item_metadata(index)==id:ai_connect_panel.actors.select(index)
		ai_connect_panel.refresh())
	_refresh_control_ui()

func _toggle_resident_connections() -> void:
	if resident_connections.visible:resident_connections.close_panel();return
	action_dock.menu.hide();chat.hide();chat_input.release_focus()
	if homestead_panel!=null:homestead_panel.hide()
	house_panel.hide();farm_panel.hide();leisure_panel.hide();interior_panel.hide();memory_panel.hide();fishing_panel.hide();journal_panel.hide();gomoku_panel.card.hide()
	resident_connections.open();_refresh_control_ui()

func _resident_connection_snapshot(id: String) -> Dictionary:
	var control: Dictionary=world.director.state(id)
	var behavior: String={"following":T("ui.main.stay_by_your_side"),"assembly":T("ui.main.gathering"),"shared_activity":T("ui.main.barbecue_together"),"conversation":T("ui.main.talking_or_awaiting_an_answer"),"task":T("ui.main.doing_assigned_engine_work"),"command":T("ui.main.heading_to_the_assigned_target"),"idle":T("ui.main.staying_quietly"),"local_rules":T("ui.main.local_daily_activities")}.get(control.effective,T("ui.main.staying_quietly"))
	if control.effective=="task":
		var job: Dictionary=world.work.jobs.get(id,{})
		var task: String={"chop":T("ui.main.chopping_and_hauling"),"gather_wood":T("ui.main.gathering_wood"),"build":T("ui.main.delivering_and_building"),"build_house":T("ui.main.house_building_plan"),"fish":T("ui.main.shore_fishing"),"play_gomoku":T("ui.main.playing_gomoku"),"farm_work":T("ui.main.farm_work"),"house_work":T("ui.main.arranging_the_cottage"),"build_facility":T("ui.main.building_a_facility"),"store":T("ui.main.storing_supplies"),"collect":T("ui.main.collecting_wood")}.get(str(job.get("intent","")),T("ui.main.doing_assigned_work"))
		behavior=T("ui.main.engine_task")+task
		if str(job.get("phase","")).begins_with("fire_"):behavior={"fire_travel":T("ui.main.walking_to_the_fire_216"),"fire_sit":T("ui.main.sitting_by_the_fire"),"fire_eat":T("ui.main.eating_by_the_fire")}.get(job.phase,behavior)
		if world.cooperation.active(id):behavior+=T("ui.main.delivering_together")
	if control.effective=="local_rules":behavior=T("ui.main.local_life")+{"facility":T("ui.main.enjoying_a_facility"),"garden":T("ui.main.looking_at_the_fields"),"wander":T("ui.main.taking_a_walk"),"rest":T("ui.main.resting"),"nearby":T("ui.main.coming_near_you"),"look":T("ui.main.looking_around"),"stretch":T("ui.main.stretching"),"watch":T("ui.main.keeping_company"),"flower_gift":T("ui.main.offering_a_flower"),"daily_gesture":T("ui.main.a_small_daily_activity"),"schedule":T("ui.main.following_the_time_of_day"),"relationship_sea":T("ui.main.watching_the_sea_together"),"relationship_work":T("ui.main.keeping_you_company_at_work"),"relationship_place":T("ui.main.heading_to_a_shared_favorite_spot"),"relationship_welcome":T("ui.main.welcoming_you"),"relationship_sit_approach":T("ui.main.coming_to_sit_beside_you")}.get(control.local_life.behavior,T("ui.main.free_time"))
	if autonomy!=null and autonomy.scheduler.active.has(id):behavior=T("ui.main.autonomous_reasoning_budgeted_turn")
	if not control.get("local_life",{}).get("mood",{}).is_empty():behavior+=T("ui.main.nstate")+LocalText.content(str(control.local_life.mood.name))+T("ui.main.local")
	var origin: String=world.intelligence.display_name(id)+T("ui.main.local_personality")
	if not world.director.model_controlled(id):return {"origin":origin,"connection":T("ui.main.optional_extension_off"),"activity":behavior}
	var connection: String=T("ui.main.configured_not_started")
	var state: String=str(connection_ui_states.get(id+":direct",""));var group_state: String=str(connection_ui_states.get(id+":group",""))
	if group_state in ["connecting","thinking","acting","waiting","cancelling","error","disconnected"]:state=group_state
	var now: float = Time.get_ticks_msec() / 1000.0
	var cached: Dictionary = connection_state_cache.get(id, {})
	var cached_state: String = str(cached.get("state", ""))
	var locked_until: float = float(cached.get("locked_until", 0.0))
	if state != cached_state:
		if now < locked_until:
			state = cached_state
		else:
			connection_state_cache[id] = {"state": state, "locked_until": now + 0.8}
	if not state.is_empty():connection={"connecting":T("ui.main.connecting"),"thinking":T("ui.main.waiting_for_the_model_s_reply"),"acting":T("ui.main.model_processing"),"waiting":T("ui.main.waiting_for_a_reply_or_client_processing"),"cancelling":T("ui.main.stopping"),"error":T("ui.main.connection_error"),"disconnected":T("ui.main.disconnected"),"cancelled":T("ui.main.this_turn_stopped"),"ready":T("ui.main.connection_ready")}.get(state,T("ui.main.configured_waiting_for_a_message"))
	if external_residents.get(id,false):
		if state=="ready":connection=T("ui.main.real_reply_received")
		elif state=="waiting":connection=T("ui.main.waiting_for_external_ai_to_read_or_reply")
		elif state.is_empty():connection=T("ui.main.bound_connection_unconfirmed")
	elif _valid_link(links,id) and links[id].has_method("read_mailbox"):
		if state.is_empty():connection=T("ui.main.bound_manual_relay")
	elif state.is_empty() and _valid_link(links,id) and links[id].is_busy():connection=T("ui.main.waiting_for_the_model")
	return {"origin":origin,"connection":connection,"activity":behavior,"light_state":_connection_light(id).state}

func _daily_scenario() -> void:
	if OS.get_environment("HABITAT_DATA_DIR").is_empty():return
	_leisure_scenario()
	for id in world.actors:world.command(id,{"intent":"stop"})
	for id in world.director.routines:
		world.director.routines[id].rng.seed=500+world.director.routines.keys().find(id)
		world.director.routines[id].set_enabled(true)
	for tick in range(700):world.advance(.1)
	view.center=world.locations.point("p_38_60");view.zoom=.72
	view.motion.advance(.1,world.actors)
	status.text=T("ui.main.everyone_is_doing_their_own_thing_say_hello_or_gather_together_an")
	if scenario=="daily_controls":
		_select_chat("npc.mira");chat.show();_refresh_control_status()
	if scenario=="daily_gather":
		_gather_residents()
		for tick in range(900):
			world.advance(.1)
			if world.activities.gathering.get("phase")=="holding":break
		_refresh_gathering();view.center=world.point(world.actors.human)+Vector2(0,2);view.zoom=1.0

func _forest_scenario() -> void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"): return
	world.director.set_all_enabled(false)
	_qa_job("codex", {"intent": "gather_wood", "zone_id": "home.forest", "tree_count": 12})
	world.forest.advance(240)
	var recovering: Array = world.objects.values().filter(func(tree): return tree.kind == "tree" and tree.status == "sapling")
	print("Forest viewport: ", recovering.size(), " saplings; positions ", recovering.map(func(tree): return tree.position))
	var center := Vector2.ZERO
	for tree in recovering: center += world.point(tree)
	view.center = center / maxf(1, recovering.size()); view.follow_player = false; view.zoom = 1.05
	status.text = T("ui.main.saplings_are_growing_again_where_we_chopped_trees")

func _open_audio_settings()->void:
	preload("res://scripts/audio_settings_panel.gd").open(self)
func _apply_window_font_deferred(node:Node)->void:
	if node is Window:call_deferred("_apply_window_font",node)
func _apply_window_font(window:Window)->void:
	if not is_instance_valid(window) or ui_font==null:return
	var font:Font=ui_font
	var owner:Node=window.get_parent()
	while owner!=null:
		if owner==gomoku_panel or owner==jieqi_panel:
			font=preload("res://assets/fonts/NotoSerifSC-Black.ttf");break
		owner=owner.get_parent()
	var theme:Theme=window.theme.duplicate() if window.theme!=null else Theme.new();theme.default_font=font;theme.default_font_size=16;window.theme=theme
func _notification(what:int)->void:
	if what==NOTIFICATION_PREDELETE and is_instance_valid(game_audio):game_audio.shutdown()

func refresh_locale()->void:
	get_window().title=T("storage.window_title")
	language="en" if LocalText.revision().begins_with("en") else "zh"
	if status!=null and status.text!=str(status.get_meta("external_receipt","")):status.text=LocalText.receipt(status.text)
	_refresh_main_locale(self)
	if view!=null:view.queue_redraw()
	if atlas!=null:atlas.queue_redraw()
	if status!=null and status.get_meta("ui_message_key","")=="ui.main.movement_hint" and status.text in [LocalText.source("ui.main.movement_hint"),str(LocalText.entries.get("ui.main.movement_hint",{}).get("en",""))]:status.text=T("ui.main.movement_hint")
	if chat_picker!=null:_refresh_resident_names()
	if chat_input!=null:_refresh_chat_placeholder()
	if controller_picker!=null:_refresh_control_ui()
	if chat_log!=null:_render_chat(false)
	if gathering_button!=null:_refresh_gathering()
	if order_label!=null:_update_order_bar()
	if island_hud!=null:island_hud.refresh()
	for overlay in [farm_panel,journal_panel,memory_panel,book_panel,fishing_panel,resident_connections,house_panel,interior_panel,leisure_panel,homestead_panel,proposal_panel,wish_panel,editor,action_dock.menu,island_hud.wardrobe if island_hud!=null else null]:
		if overlay!=null:_present_overlay(overlay)

func _present_overlay(overlay:Control)->void:
	if island_hud!=null:island_hud.refresh()
	if not overlay.visible:return
	var target:Control=overlay
	if overlay==action_dock.menu:target=action_dock
	target.get_parent().move_child(target,-1)

func _fallback_action_key(id:String,scope:String,key:String,generation:int)->String:
	return JSON.stringify([id,scope,key,generation])
func _revoke_fallback_actions(id:String,channel:String)->void:
	var scope:String="group" if channel==Channels.ALL else "direct"
	var connection:Variant=group_links.get(id) if scope=="group" else links.get(id)
	if not is_instance_valid(connection):return
	var key:String=str(connection.get("turn_key"))
	if key.is_empty():return
	var generation:int=int(connection.get("_generation")) if connection.get_property_list().any(func(field):return field.name=="_generation") else 0
	fallback_revoked_actions[_fallback_action_key(id,scope,key,generation)]=true
	if fallback_revoked_actions.size()>256:fallback_revoked_actions.erase(fallback_revoked_actions.keys()[0])
func _fallback_actions_revoked(id:String,scope:String,event:Dictionary,connection:Node)->bool:
	var generation:int=int(connection.get("_generation")) if connection.get_property_list().any(func(field):return field.name=="_generation") else 0
	return fallback_revoked_actions.has(_fallback_action_key(id,scope,str(event.get("turn_key","")),generation))

func _run_model_fallback(id:String,text:String,channel:String)->void:
	_revoke_fallback_actions(id,channel)
	if _valid_link(links,id) and links[id].has_method("_emit"):links[id]._emit({"kind":"local_fallback","text":text})
	if local_host_commands==null or not world.actors.has(id):return
	model_fallback_requests.erase(id)
	host_turn_grants.erase(id)
	var connection:Variant=group_links.get(id) if channel==Channels.ALL else links.get(id)
	# Local fallback does not cancel the independent model reply.
	chat_input.release_focus();_refresh_conversation_holds()
	local_host_commands.submit(text,[id],channel,[id])
	local_host_commands.speech_queue.append({"actor_id":id,"line":"I will use the familiar way to help you first." if TranslationServer.get_locale().begins_with("en") else preload("res://scripts/localization.gd").source("content.health_20261107.924b19a877d5"),"channel_id":channel,"expires":world.director.time+180})

func _execute_scoped_host_action(id:String,event:Dictionary,channel:String)->Dictionary:
	if event.get("autonomy",false) or not host_turn_grants.has(id):return {"ok":false,"error":"explicit_host_instruction_required"}
	var request:Dictionary=host_turn_grants[id]
	if str(event.get("turn_key",""))!=request.turn_key or not _grant_current(id,request):return {"ok":false,"error":"stale_host_instruction"}
	if event.command.size()!=1:return {"ok":false,"error":"arguments_must_come_from_host_instruction"}
	var parsed:Dictionary=local_host_commands.parser.parse_command(world,request.text,[id])
	var expected:String={"invite_barbecue":"barbecue","start_project":"start_project","open_chess":"open_chess"}[event.command.intent]
	if not parsed.get("ok",false) or parsed.action!=expected:return {"ok":false,"error":"host_instruction_mismatch"}
	local_host_commands.submit(request.text,[id],channel,[id])
	return local_host_commands.last_execution.duplicate(true) if not local_host_commands.last_execution.is_empty() else {"ok":false,"error":"host_confirmation_required"}

func _bound_labor_authorized(id:String,event:Dictionary)->bool:
	if event.get("autonomy",false):
		if autonomy==null or resident_connections==null:return false
		var preference:Dictionary=resident_connections.preferences.preference(id)
		return preference.autonomy_enabled and preference.level!="low" and autonomy.scheduler.active.get(id,{}).get("id")==event.get("turn_key")
	if not host_turn_grants.has(id):return false
	var grant:Dictionary=host_turn_grants[id]
	if grant.turn_key!=event.get("turn_key") or not _grant_current(id,grant):return false
	var parsed:Dictionary=local_host_commands.parser.parse_command(world,grant.text,[id])
	var wanted:String={"harvest":"ready","gather":"forage"}.get(str(event.command.intent),str(event.command.intent))
	return parsed.get("ok",false) and parsed.action==wanted and id in parsed.actor_ids

func _execute_bound_labor(id:String,event:Dictionary)->Dictionary:
	if not _bound_labor_authorized(id,event):return {"ok":false,"error":"autonomy_not_authorized"}
	var command:Dictionary=event.command
	var action:String=command.intent
	if world.hunger.rank(id)>=2:return world._error("hungry")
	if editor!=null and editor.visible:return world._error("busy")
	# A validated tool callback is already the active model turn. Its own
	# conversation hold must not masquerade as an unrelated assembly/work hold.
	var had_hold:bool=world.activities.held.has(id)
	var own_hold:bool=bool(world.activities.held.get(id,false))
	world.activities.held.erase(id)
	var why:String=preload("res://scripts/farm_host_plan.gd").reason(world.farms,id)
	if had_hold:world.activities.held[id]=own_hold

	if not why.is_empty():return world._error(why)
	if action in ["plant","water","harvest"]:
		var permitted:Array=["intent","target_id","crop_id"] if action=="plant" else ["intent","target_id"]
		if command.keys().any(func(key):return key not in permitted) or not command.get("target_id") is String:return world._error("invalid_command")
		var plot:Dictionary=world.farms.plots.get(command.target_id,{})
		if plot.is_empty() or not world.farms.ready(plot.farm_id) or world.work.claims.has(plot.id):return world._error("unknown_or_claimed_plot")
		var stage:String=world.farms.stage(plot)
		if (action=="plant" and stage!="empty") or (action=="water" and stage!="dry") or (action=="harvest" and stage!="mature"):return world._error("plot_stage_mismatch")
		var crop:String=str(command.get("crop_id",plot.crop_id))
		if crop not in world.farms.farms[plot.farm_id].crop_ids:return world._error("invalid_crop")
		return world.farms.host_order(id,plot.farm_id,crop,"ready" if action=="harvest" else "plant",[plot.id],{str(plot.id):crop})
	if command.keys().any(func(key):return key not in ["intent","target_id"]) or not command.get("target_id") is String:return world._error("invalid_command")
	world.activities.pause_follow(id)
	if action=="chop":return world.host_text_command(id,{"intent":"gather_wood","target_id":command.target_id,"tree_count":1})
	if action=="gather" and world.ingredients.sources().any(func(item):return item.id==command.target_id):return world.ingredients.begin_resident(id,command.target_id)
	return world.host_text_command(id,{"intent":"forage","target_id":command.target_id})

func _execute_delegated_host_action(id:String,event:Dictionary,channel:String)->Dictionary:
	if event.get("autonomy",false) or not host_turn_grants.has(id):return {"ok":false,"error":"explicit_host_instruction_required"}
	var grant:Dictionary=host_turn_grants[id]
	if grant.turn_key!=event.get("turn_key") or not _grant_current(id,grant):return {"ok":false,"error":"stale_host_instruction"}
	if steward.authorized(id):
		if event.command.keys().any(func(key):return key not in ["intent","actor_ids","target_id","crop_id","region_id","x","y"]):return world._error("invalid_intention")
		var step:Dictionary=event.command.duplicate(true);var action:String=str(step.intent);step.erase("intent")
		step.action={"gather_at":"assemble","start_project":"build","open_chess":"chess"}.get(action,action)
		if action=="invite_barbecue":return steward.assign(id,[{"action":"roast","actor_ids":[id],"guest_ids":step.actor_ids},{"action":"invite","actor_ids":[id],"guest_ids":step.actor_ids}],channel)
		return steward.assign(id,[step],channel)
	if event.command.keys().any(func(key):return key not in ["intent","actor_ids"]):return {"ok":false,"error":"delegated_targets_derive_from_host_instruction"}
	var ids:Variant=event.command.actor_ids
	if not ids is Array or ids.is_empty() or ids.any(func(actor):return not actor is String or actor=="human" or not world.actors.has(actor)):return world._error("invalid_participant")
	var parsed:Dictionary=local_host_commands.parser.parse_command(world,grant.text,[id])
	var expected:String={"harvest":"ready","gather":"forage","go_to":"gather","gather_at":"gather","invite_barbecue":"barbecue"}.get(str(event.command.intent),str(event.command.intent))
	if not parsed.get("ok",false) or parsed.action!=expected or ids.size()!=parsed.actor_ids.size() or ids.any(func(actor):return actor not in parsed.actor_ids):return {"ok":false,"error":"host_actor_or_action_scope_mismatch"}
	for actor in ids:
		if actor!=id and _resident_chat_busy(actor):return {"ok":false,"error":"participant_busy","actor_id":actor}
	# The callback owns this conversation hold; unrelated holds still reject above.
	var had_hold:bool=world.activities.held.has(id)
	var own_hold:bool=bool(world.activities.held.get(id,false))
	world.activities.held.erase(id)
	local_host_commands.submit(grant.text,ids,channel,ids)
	if had_hold:world.activities.held[id]=own_hold
	var result:Dictionary=local_host_commands.last_execution.duplicate(true) if not local_host_commands.last_execution.is_empty() else {"ok":false,"error":"host_confirmation_required"}
	if result.get("ok",false) and autonomy!=null:
		for actor in result.get("actors",[]):autonomy.scheduler.note_model_action(actor)
	return result

func _grant_current(id:String,grant:Dictionary)->bool:
	var connection:Variant=group_links.get(id) if grant.get("scope","direct")=="group" else links.get(id)
	return is_instance_valid(connection) and world.director.model_controlled(id) and str(connection.get("turn_key"))==str(grant.get("turn_key","")) and connection.get("_generation")==grant.get("generation")

func _execute_model_action(id:String,event:Dictionary,channel:String)->Dictionary:
	if not event.get("command") is Dictionary:return world._error("invalid_command")
	if event.command.has("actor_ids"):return _execute_delegated_host_action(id,event,channel)
	var action:String=str(event.command.get("intent",""))
	if action=="resident_plan":
		if event.command.keys().any(func(key):return key not in ["intent","steps"]) or not event.command.get("steps") is Array:return world._error("invalid_intention")
		if event.get("autonomy",false):
			if not _bound_labor_authorized(id,event) or event.command.steps.size()>int(autonomy.scheduler.policy_for(id).tools):return world._error("autonomy_tool_budget")
		elif not host_turn_grants.has(id) or not _grant_current(id,host_turn_grants[id]):return world._error("explicit_host_instruction_required")
		return intentions.submit(id,event.command.steps,channel)
	if action in ["invite_barbecue","start_project","open_chess"]:return _execute_scoped_host_action(id,event,channel)
	if action in ["plant","harvest","water","chop","gather","forage"] and (event.get("autonomy",false) or _bound_labor_authorized(id,event)):return _execute_bound_labor(id,event)
	return world.command(id,event.command)

func _need_clicked(id:String,kind:String)->void:
	if kind=="fish":
		local_host_commands.replace_order(id)
		local_host_commands.submit("fish",[id],"command",[id])
	elif kind in ["hungry","favorite"]:
		var station:String=local_host_commands.nearest_fire()
		if not station.is_empty():_local_barbecue_requested(station,[id])
	elif kind=="chess":
		for site in world.leisure.sites:
			if not world.gomoku.table(site).is_empty():_open_chess(site);break
	elif kind=="cat":world.cat.interact(id,"pet")

func _forget_memory_source(entry:Dictionary)->void:
	for collection in [links,group_links]:
		if _valid_link(collection,entry.resident_id) and collection[entry.resident_id].is_busy():collection[entry.resident_id].cancel_turn()
	immediate_turns.erase(entry.resident_id)
	if is_instance_valid(chat_log):_render_chat()

func _forgotten_quote(id:String,message_id:String)->bool:
	return memory_books.deleted.has((id+"|"+world.world_id+"|"+message_id+"|facts").sha256_text())
func _memory_dialogue_context(id:String,channel:String,recipients:Array,message_id:String)->Dictionary:
	var ignored:Array=dialogue.histories.get(channel,[]).filter(func(row):return _forgotten_quote(id,row.message_id)).map(func(row):return row.message_id)
	return dialogue.context(channel,recipients,message_id,ignored)

func _setup_connection_overview()->void:
	connection_pool=preload("res://scripts/connection_session_pool.gd").obtain(get_tree(),data_dir)
	connection_pool.releasing.connect(_connection_releasing)
	connection_pool.ledger_world=world.world_id;connection_pool.shared_preferences=resident_connections.preferences
	connection_pool.local_requested.connect(func(id):
		_drop_group_link(id)
		if _valid_link(links,id):links.erase(id)
		world.director.set_controller(id,"local");connection_ui_states[id+":direct"]="local"
		_refresh_control_ui()
	)
	connection_pool.quota_local_requested.connect(func(id,first_notice):
		# Revoke pending model authority without stopping accepted physical work.
		if autonomy!=null:autonomy.retire(id)
		if intentions!=null:intentions.plans.erase(id)
		next_chat.erase(id);next_chat_due.erase(id);next_chat_sources.erase(id)
		model_fallback_requests.erase(id);host_turn_grants.erase(id)
		if memory_life!=null:
			memory_life.cancel_pending(id);memory_life.maintenance.erase(id);memory_life.attempts.erase(id)
		if steward!=null and steward.manager==id:
			steward.pending.clear();steward.reasons.clear();steward.local_only=true
			# Preserve active task receipts and already committed meals; discard future AI assignments.
			steward.queue.clear()
		questions.erase(id);group_questions.erase(id);immediate_turns.erase(id)
		world.actors[id].controller="local";connection_ui_states[id+":direct"]="local"
		if first_notice:view.say(T("quota.exhausted"),"local_rules",id,"quota")
		_refresh_conversation_holds();_refresh_control_ui()
	)
	connection_pool.usage_notice.connect(func(id):view.say(T("gpt.warning"),"local_rules",id,"usage"))
	connection_history=connection_pool.history
	connection_pool.ledger_world=world.world_id
	connection_pool.start_saved()
	for id in connection_pool.IDS:
		if connection_pool.settings.get_value("enabled",id,false) and connection_pool.valid(id):
			links.erase(id)
			external_residents[id]=false;_ensure_link(id)
			world.director.set_controller(id,"model")
			if id=="codex":link=links[id]
			# This existing transport may have completed its handshake on the title screen.
			if not connection_ui_states.has(id+":direct") and connection_pool.states.has(id):
				connection_ui_states[id+":direct"]=str(connection_pool.states[id].get("state","unconnected"))
			connection_greetings[id]=T("simple.hello."+id)
	connection_overview=preload("res://scripts/connection_overview.gd").new();book_panel.get_parent().add_child(connection_overview);connection_overview.setup(data_dir,_connection_rows,_simple_connection_action)
	var connection_button:=Button.new();connection_button.focus_mode=Control.FOCUS_NONE;connection_button.text=T("memory.connections");resident_connections.connection_section.add_child(connection_button);connection_button.pressed.connect(connection_overview.open)
func _connection_light(id:String)->Dictionary:
	var local:bool=not world.director.model_controlled(id)
	var state:String="local" if local else str(connection_ui_states.get(id+":direct","unconnected"))
	var group_state:String=str(connection_ui_states.get(id+":group",""))
	if not local and group_state in ["connecting","thinking","acting","waiting","error","disconnected"]:state=group_state
	if not local and state in ["thinking","acting","waiting","cancelling","cancelled"]:state="ready" if connection_history.get_value("connected",id,0)>0 else "connecting"
	if state not in ["local","unconnected","connecting","ready","disconnected","error"]:state="unconnected"
	var account:Dictionary=autonomy.scheduler.usage(id) if autonomy!=null else resident_connections.preferences.accounting(id) if resident_connections!=null else {}
	return {"state":state,"provider":"" if local else T("simple.external_name") if external_residents.get(id,false) else "GPT API" if connection_pool!=null and connection_pool.settings.get_value("api",id,"codex")=="openai" else T("simple.builtin"),"tokens":str(account.get("tokens","?"))+(" + ?" if int(account.get("reserved",0))>0 or int(account.get("unknown_turns",0))>0 else ""),"last_connected":connection_history.get_value("connected",id,0),"color":Color("858585") if state in ["local","unconnected"] else Color("f3ce55") if state=="connecting" else Color("77ca91") if state=="ready" else Color("e97070")}
func _connection_rows()->Dictionary:
	var result:Dictionary={}
	for id in world.director.routines:
		result[id]=_connection_light(id);result[id].erase("color")
		result[id]["stale"]=connection_pool.stale(id) if connection_pool!=null else false
		if connection_pool!=null and connection_pool.states.has(id):
			for key in ["greeting","error"]:result[id][key]=connection_pool.states[id].get(key,"")
			if not str(result[id].get("error","")).is_empty():result[id].state="error"
		connection_history.set_value("residents",id,result[id])
		connection_history.set_value("tokens",id+"/"+Time.get_date_string_from_system(),result[id].tokens)
	connection_history.save(data_dir.path_join("connection-overview.cfg"))
	return result
func _probe_resident_connection(id:String)->void:
	if not world.director.model_controlled(id):return
	_ensure_link(id)
	if links[id].has_method("probe_connection"):links[id].probe_connection()

func _simple_connection_action(id:String,action:String="toggle")->void:
	if action=="external":
		world.director.set_controller(id,"model");_bind_external_ai(id,true,false)
		ai_connect_panel.open()
		for index in range(ai_connect_panel.actors.item_count):
			if ai_connect_panel.actors.get_item_metadata(index)==id:ai_connect_panel.actors.select(index)
		ai_connect_panel.refresh();return
	if action=="recover":
		connection_pool.use_builtin(id);external_residents[id]=false
		if _valid_link(links,id):_cancel_resident_turn(id);connection_pool.release(id)
		endpoint.sync_bindings();return
	if action=="disconnect" or (action=="toggle" and _connection_light(id).state in ["ready","connecting"]):
		_cancel_resident_turn(id)
		connection_pool.disconnect_ai(id)
		world.director.set_controller(id,"local");connection_ui_states[id+":direct"]="local"
	else:
		external_residents[id]=false;shared_test=false;conversation_thread="" if id=="codex" else conversation_thread
		var connection:Node=connection_pool.connect_ai(id,world.world_id)
		if not is_instance_valid(connection):return
		world.director.set_controller(id,"model")
		_ensure_link(id)
		if id=="codex":link=connection
	endpoint.sync_bindings();_refresh_control_ui();resident_connections.refresh()

func _persona_speech(line:String,id:String)->String:
	if preload("res://scripts/persona_cards.gd").safe_speech(line):return line
	print("PERSONA_SPEECH_FILTER resident=",id," reason=format_or_voice")
	return T("simple.fallback")

func _setup_flowers_ui()->void:
	flower_panel=preload("res://scripts/flower_panel.gd").new();add_child(flower_panel);flower_panel.theme=Theme.new();flower_panel.theme.default_font=ui_font;flower_panel.theme.default_font_size=18;flower_panel.setup()
	flower_panel.action_requested.connect(func(args):
		var result:Dictionary=world.host_command("human",args)
		flower_panel.stock.text=_flower_stock();flower_panel.message.text=_flower_result(result))
	flower_panel.placement_requested.connect(func(args):
		flower_placement=args.duplicate(true)
		if flower_actor_ids.is_empty():flower_actor_ids=["human"]
		status.text=T("flowers.choose_ground"))
func _flower_stock()->String:
	return T("flowers.stock")%[world.storage.count("wood"),world.storage.count("rose_red"),world.storage.count("rose_white"),world.storage.count("rose_yellow"),world.storage.count("rose_pink")]
func _open_flowers(ids:Array=["human"])->void:
	flower_actor_ids=ids.duplicate();flower_placement.clear()
	flower_panel.open(str(ids[0]),_flower_stock(),ids==["human"])
func _flower_result(result:Dictionary)->String:
	return str(result.get("message",(T("flowers.done") if result.get("status","")=="completed" else T("flowers.started")) if result.get("ok",false) else T("flowers.failed")+str(result.get("error",""))))
func _flower_clicked(id:String,at:Vector2)->bool:
	if flower_panel==null:return false
	if not flower_placement.is_empty():
		if flower_actor_ids.size()>1 and flower_placement.get("intent")=="arrange_flowers":
			var args:Dictionary=flower_placement.duplicate(true);args.position=[at.x,at.y];args.region_id=view.region_id
			status.text=_flower_result(world.flower_creation.arrange_group(flower_actor_ids,args));flower_placement.clear();flower_actor_ids.clear();return true
		var messages:Array=[]
		for who in flower_actor_ids:
			var args:Dictionary=flower_placement.duplicate(true);args.position=[at.x,at.y];args.region_id=view.region_id
			messages.append(_flower_result(world.host_command(who,args)))
		status.text=" · ".join(messages);flower_placement.clear();flower_actor_ids.clear();return true
	if id in ["flower.stall","flower.arrange"] or (view.region_id=="home" and at.distance_to(Vector2(43,208))<=1.8):
		_open_flowers();return true
	return false
func _flower_local_chat(text:String)->bool:
	var lower:String=text.to_lower()
	if not (text.contains("摆") or text.contains("送我花") or lower.contains("arrange flowers") or lower.contains("give me a rose")):return false
	if intentions!=null and (intentions.negated(text) or intentions.chat_only(text)):return false
	var fallback:Array=command_page.selected.duplicate() if group_chat and command_page!=null else [chat_actor]
	var parsed:Dictionary=local_host_commands.parser.parse_command(world,text,fallback)
	var ids:Array=parsed.get("actor_ids",fallback).filter(func(id):return id!="human" and world.actors.has(id))
	if ids.is_empty():return false
	# Connected residents keep their original model route; never parse on their behalf.
	if ids.any(func(id):return world.director.model_controlled(id)):return false
	var args:Dictionary={"intent":"gift_flower" if text.contains("送我花") or lower.contains("give me a rose") else "arrange_flowers","color":"red"}
	for pair in [["白","white"],["黄","yellow"],["粉","pink"],["红","red"]]:
		if text.contains(pair[0]) or lower.contains(pair[1]):args.color=pair[1]
	var pattern:=""
	for pair in [["爱心","heart"],["星星","star"],["笑脸","smile"],["太阳","sun"],["箭头","arrow"],["花形","flower"]]:
		if text.contains(pair[0]) or lower.contains(pair[1]):pattern=pair[1]
	var regex:=RegEx.new();regex.compile("(?:摆|arrange flowers)\\s*([A-Za-z0-9一二三十人大小中山口田王心]{1,6})\\s*$")
	var match_text:RegExMatch=regex.search(text)
	if not pattern.is_empty():args.pattern=pattern
	elif match_text!=null:args.text=match_text.get_string(1).to_upper()
	elif args.intent=="arrange_flowers" and not (text.contains("摆花") or lower.contains("arrange flowers")):return false
	_record_chat(_chat_channel(),"human",text)
	if ids.size()>1 and args.intent=="arrange_flowers":
		status.text=_flower_result(world.flower_creation.arrange_group(ids,args));_finish_chat_input();return true
	var messages:Array=[]
	for who in ids:
		messages.append(LocalText.resident(world,who)+" · "+_flower_result(world.host_command(who,args)))
	status.text=" · ".join(messages);_finish_chat_input();return true
