extends Control
const LocalText=preload("res://scripts/localization.gd")
const SceneEvents=preload("res://scripts/chess_scene_events.gd")
var scene_hunger:Dictionary={}
var entry_radius:=4.5
signal bubble_delivered(event:Dictionary)
signal change_requested
signal ai_start_requested(site_id: String,black: String,white: String,sources: Dictionary)
signal ai_resume_requested(site_id: String)
signal ai_pause_requested(site_id: String)
signal ai_end_requested(site_id: String)
signal chat_requested(site_id: String,text: String)
signal start_requested(site_id: String,opponent: String,human_black: bool,mode: String,difficulty: String)
signal resume_requested(site_id: String)
signal build_requested(site_id: String)
signal model_step_requested(actor_id: String,site_id: String)
var world: RefCounted
var card: PanelContainer
var ai_setup: VBoxContainer
var game_type: OptionButton
var black_picker: OptionButton
var white_picker: OptionButton
var black_source: OptionButton
var white_source: OptionButton
var ai_button: Button
var connection_provider: Callable
var chat_edit: LineEdit
var chat_row: HBoxContainer
var portraits: Control
var options: HBoxContainer
var preset_menu: MenuButton
var board: Control
var opponent: OptionButton
var color: OptionButton
var mode: OptionButton
var difficulty: OptionButton
var message: Label
var status: Label
var title: Label
var start_button: Button
var resume_button: Button
var pause_button: Button
var resign_button: Button
var build_button: Button
var model_button: Button
var reopen_button: Button
var confirm: ConfirmationDialog
var site_id:="play.gomoku"
var current: Dictionary={}
var refresh_time:=0.0
var last_phase:=""
var starting:=false
var ui_factor:=1.0
var presentation:Control
var chatter:RefCounted
var stats:Label
var observed_match:=""
var observed_hand:=-1
var result_shown:=false
var player_wait:=0.0
var prior_hunger:=-1
var setup_requested:=true
var model_bubbles_seen:Dictionary={}
func setup(source: RefCounted) -> void:
	preload("res://scripts/chess_theme.gd").apply(self)
	LocalText.events.changed.connect(refresh_locale)
	world=source;entry_radius=float(JSON.parse_string(FileAccess.get_file_as_string("res://content/home-v3/ui.json")).context_radius);z_index=100;set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);mouse_filter=Control.MOUSE_FILTER_IGNORE
	card=PanelContainer.new();card.set_meta("chess_scene_surface",true);add_child(card)
	card.visibility_changed.connect(func():world.gomoku.companion.panel_tables[site_id]=card.visible)
	var style:=StyleBoxEmpty.new()
	card.add_theme_stylebox_override("panel",style)
	var col:=VBoxContainer.new();col.add_theme_constant_override("separation",4);card.add_child(col)
	var header:=HBoxContainer.new();col.add_child(header)
	title=Label.new();title.text=T("ui.gomoku_panel.seabreeze_chess_corner_gomoku");title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(title)
	game_type=OptionButton.new();game_type.add_item(T("ui.gomoku_panel.play_with_a_companion"));game_type.add_item(T("ui.gomoku_panel.watch_companions_play"));header.add_child(game_type);game_type.item_selected.connect(func(_index):refresh())
	button(header,T("ui.gomoku_panel.close"),func():card.hide();refresh())
	options=HBoxContainer.new();col.add_child(options)
	opponent=OptionButton.new();opponent.size_flags_horizontal=Control.SIZE_EXPAND_FILL;options.add_child(opponent)
	color=OptionButton.new();color.add_item(T("ui.gomoku_panel.i_play_black"));color.add_item(T("ui.gomoku_panel.i_play_white"));options.add_child(color)
	mode=OptionButton.new();mode.add_item(T("ui.gomoku_panel.local_opponent"));mode.add_item(T("ui.gomoku_panel.model_moves"));options.add_child(mode)
	difficulty=OptionButton.new();difficulty.add_item(T("ui.gomoku_panel.relaxed"));difficulty.add_item(T("ui.gomoku_panel.focused"));difficulty.select(1);options.add_child(difficulty)
	ai_setup=VBoxContainer.new();col.add_child(ai_setup)
	var blacks:=HBoxContainer.new();ai_setup.add_child(blacks)
	var whites:=HBoxContainer.new();ai_setup.add_child(whites)
	black_picker=OptionButton.new();black_picker.size_flags_horizontal=Control.SIZE_EXPAND_FILL;blacks.add_child(black_picker)
	white_picker=OptionButton.new();white_picker.size_flags_horizontal=Control.SIZE_EXPAND_FILL;whites.add_child(white_picker)
	black_source=OptionButton.new();blacks.add_child(black_source);white_source=OptionButton.new();whites.add_child(white_source)
	for picker in [game_type,opponent,color,mode,difficulty,black_picker,white_picker,black_source,white_source]:
		picker.get_popup().about_to_popup.connect(func():_position_popup.call_deferred(picker))
	for brain in world.gomoku.match_config.sources:
		for picker in [black_source,white_source]:picker.add_item(world.gomoku.match_config.sources[brain]);picker.set_item_metadata(picker.item_count-1,brain)
	status=Label.new();status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.custom_minimum_size.y=28;col.add_child(status)
	board=preload("res://scripts/gomoku_board.gd").new();board.size_flags_vertical=Control.SIZE_EXPAND_FILL;col.add_child(board)
	board.intersection.connect(func(p):submit("gomoku_move",{"x":p.x,"y":p.y}))
	var overlay:=Node2D.new();card.add_child(overlay)
	portraits=preload("res://scripts/gomoku_portraits.gd").new();portraits.world=world;overlay.add_child(portraits)
	chat_row=HBoxContainer.new();col.add_child(chat_row)
	chat_edit=LineEdit.new();chat_edit.placeholder_text=T("ui.gomoku_panel.talk_to_her_private_chat_this_never_plays");chat_edit.size_flags_horizontal=Control.SIZE_EXPAND_FILL;chat_edit.max_length=400;chat_row.add_child(chat_edit)
	chat_edit.text_submitted.connect(func(text):chat_requested.emit(site_id,text);chat_edit.clear();chat_edit.release_focus())
	button(chat_row,T("ui.gomoku_panel.say_it"),func():chat_edit.text_submitted.emit(chat_edit.text))
	var row:=HBoxContainer.new();col.add_child(row)
	start_button=button(row,T("ui.gomoku_panel.take_your_seat_start"),func():
		if opponent.item_count>0 and not starting:
			starting=true;start_button.disabled=true;message.text=T("ui.gomoku_panel.invited_walking_to_the_table")
			start_requested.emit(site_id,str(opponent.get_item_metadata(opponent.selected)),color.selected==0,"local" if mode.selected==0 else "model","easy" if difficulty.selected==0 else "normal"))
	ai_button=button(row,T("ui.gomoku_panel.confirm_ai_match"),request_ai)
	resume_button=button(row,T("ui.gomoku_panel.take_your_seat_continue"),func():
		if current.get("mode")=="ai":ai_resume_requested.emit(site_id)
		else:resume_requested.emit(site_id))
	pause_button=button(row,T("ui.gomoku_panel.pause_and_leave"),func():
		if current.get("mode")=="ai":ai_pause_requested.emit(site_id)
		else:submit("gomoku_leave"))
	resign_button=button(row,T("ui.gomoku_panel.resign"),request_resign)
	build_button=button(row,T("ui.gomoku_panel.choose_a_builder"),func():build_requested.emit(site_id))
	model_button=button(row,T("ui.gomoku_panel.ask_the_model_for_this_move"),func():
		if not current.is_empty():model_step_requested.emit(str(current.get("turn_actor_id","")),site_id))
	preset_menu=MenuButton.new();preset_menu.text=T("ui.gomoku_panel.say_something");header.add_child(preset_menu)
	for text in world.gomoku.companion.config.presets:preset_menu.get_popup().add_item(text)
	preset_menu.get_popup().id_pressed.connect(func(_index):
		if chatter!=null:chatter.tapped())
	message=Label.new();message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;message.text=T("ui.gomoku_panel.15_15_black_first_no_forbidden_moves_five");message.add_theme_font_size_override("font_size",13);col.add_child(message)
	reopen_button=button(self,"",func():card.show();refresh())
	reopen_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	reopen_button.offset_left=20;reopen_button.offset_right=350;reopen_button.offset_top=-145;reopen_button.offset_bottom=-95;reopen_button.hide()
	confirm=ConfirmationDialog.new();confirm.title=T("ui.gomoku_panel.end_this_game");confirm.dialog_text=T("ui.gomoku_panel.resigning_ends_the_current_game_and_records_its");add_child(confirm)
	presentation=preload("res://scripts/chess_presentation.gd").new();card.add_child(presentation);presentation.setup(world,"gomoku");presentation.set_process(false)
	col.reparent(presentation.center);col.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);board.reparent(presentation.center)
	title.reparent(col);col.move_child(title,0)
	var option_grid:=GridContainer.new();option_grid.columns=1
	for child in options.get_children():child.reparent(option_grid)
	options.add_child(option_grid);option_grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	options.reparent(presentation.right);ai_setup.reparent(presentation.right);chat_row.reparent(presentation.right)
	status.reparent(presentation.right);status.hide()
	message.reparent(presentation.right);message.set_meta("ui_font_base",13)
	stats=Label.new();stats.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;stats.set_meta("ui_font_base",14);presentation.right.add_child(stats)
	presentation.set_side_moves(0,0);portraits.hide()
	chatter=preload("res://scripts/chess_chatter.gd").new(world,"gomoku")
	chatter.delivered.connect(func(event):presentation.speak(event);presentation.set_actor_pose(str(event.get("actor_id",presentation.opponent)),str(event.get("action","calm")));bubble_delivered.emit(event))
	presentation.actor_tapped.connect(func(id:String):chatter.tapped(id))
	chatter.reaction.connect(func(id:String,action:String):presentation.set_actor_pose(id,action))
	presentation.replay_requested.connect(_replay_presentation)
	presentation.change_requested.connect(func():change_requested.emit())
	presentation.leave_requested.connect(func():card.hide())
	resized.connect(_layout);_layout();card.hide()
func button(parent: Node,text: String,call: Callable) -> Button:
	var b:=Button.new();b.focus_mode=Control.FOCUS_NONE;b.text=text;b.pressed.connect(call);b.focus_mode=Control.FOCUS_NONE;parent.add_child(b);return b
func _layout() -> void:
	if card==null or presentation==null:return
	var viewport_size:Vector2=get_viewport_rect().size
	card.position=Vector2.ZERO;card.size=viewport_size
	var col:Control=title.get_parent()
	var board_side:float=viewport_size.y*.60+28
	board.custom_minimum_size=Vector2(board_side,board_side)
	board.size=Vector2(board_side,board_side)
	board.position=Vector2((presentation.center.size.x-board_side)*.5,(presentation.center.size.y-board_side)*.5)
	col.position=Vector2(board.position.x,minf(board.position.y+board_side+2,viewport_size.y-col.get_combined_minimum_size().y-12))
	col.size=Vector2(board_side,100)
	stats.position=Vector2(8,8);stats.size=Vector2(maxf(1,presentation.right.size.x-16),85)
	message.position=Vector2(8,96);message.size=Vector2(maxf(1,presentation.right.size.x-16),105)
	for form in [options,ai_setup,chat_row]:
		form.position=Vector2(8,viewport_size.y*.72);form.size=Vector2(maxf(1,presentation.right.size.x-16),0)
	status.hide();portraits.hide()
	presentation.set_result_board_rect(board.get_rect(),float(board.geometry().side))

func open(id: String="play.gomoku") -> void:
	if world.gomoku.table(id).is_empty():return
	move_to_front()
	setup_requested=true
	world.gomoku.companion.panel_tables.erase(site_id)
	world.gomoku.companion.panel_tables[id]=true
	site_id=id;world.gomoku.companion.observe(id);opponent.clear();black_picker.clear();white_picker.clear()
	for actor in world.actors.values():
		if actor.id=="human" or not world.residents.supports(actor,"gomoku_join"):continue
		opponent.add_item(LocalText.resident(world,str(actor.id)));opponent.set_item_metadata(opponent.item_count-1,actor.id)
		for picker in [black_picker,white_picker]:picker.add_item(LocalText.resident(world,str(actor.id)));picker.set_item_metadata(picker.item_count-1,actor.id)
	if white_picker.item_count>1:white_picker.select(1)
	card.show();_layout();refresh();call_deferred("_layout")
	if not current.is_empty() and current.get("phase") not in ["finished","abandoned"]:
		var buddy:String=_presentation_opponent()
		for index in opponent.item_count:
			if opponent.get_item_metadata(index)==buddy:opponent.select(index);break
		color.select(0 if current.black_id=="human" else 1)
		mode.select(1 if current.get("mode")=="model" else 0)
		difficulty.select(0 if current.get("difficulty")=="easy" else 1)
func refresh() -> void:
	if not card.visible:
		for game in world.gomoku.sessions.values():
			if game.phase in ["arriving","playing"] and "human" in world.gomoku.players(game):site_id=game.site_id;break
	var site: Dictionary=world.gomoku.table(site_id)
	if site.is_empty():return
	title.text=LocalText.content(str(site.name))+T("ui.gomoku_panel.gomoku")
	current=world.gomoku.read(site_id,"human").match
	var phase: String=str(current.get("phase","empty"));var finished:=phase in ["finished","abandoned"]
	if last_phase!=phase:
		message.text=T("ui.gomoku_panel.no_winner_no_completed_game_memory") if phase=="abandoned" else T("ui.gomoku_panel.the_result_is_in_both_players_memories_you") if finished else T("ui.gomoku_panel.15_15_black_first_no_forbidden_moves_five")
		last_phase=phase
	var live: bool=phase in ["playing","arriving"]
	starting=false;start_button.disabled=live
	start_button.visible=site.complete and (current.is_empty() or finished) and game_type.selected==0
	ai_setup.visible=(current.is_empty() or finished) and game_type.selected==1 and (not finished or setup_requested)
	ai_button.visible=site.complete and ai_setup.visible
	game_type.disabled=not (current.is_empty() or finished)
	if game_type.disabled:game_type.select(1 if current.get("mode")=="ai" else 0)
	if connection_provider.is_valid():
		for pair in [[black_picker,black_source],[white_picker,white_source]]:
			if pair[0].item_count>0:pair[1].set_item_disabled(2,not connection_provider.call(str(pair[0].get_item_metadata(pair[0].selected))))
	start_button.text=T("ui.gomoku_panel.take_your_seat_play_again") if finished else T("ui.gomoku_panel.take_your_seat_start")
	resume_button.text=T("ui.gomoku_panel.continue_match_confirm_budget") if current.get("mode")=="ai" else T("ui.gomoku_panel.take_your_seat_continue")
	resign_button.text=T("ui.gomoku_panel.end_this_match") if current.get("mode")=="ai" else T("ui.gomoku_panel.resign")
	resume_button.visible=phase=="paused";pause_button.visible=live;resign_button.visible=not current.is_empty() and not finished
	build_button.visible=not site.complete
	model_button.visible=phase=="playing" and current.get("mode")=="model" and current.get("turn_actor_id")!="human"
	for option in [opponent,color,mode,difficulty]:option.disabled=not (current.is_empty() or finished)
	if not site.complete:
		status.text=T("ui.gomoku_panel.the_table_is_not_built_yet_wood_s")%[site.invested,world.leisure.Rules.cost(world.leisure.art(site).recreation)]
	elif current.is_empty():status.text=T("ui.gomoku_panel.choose_a_companion_then_take_your_seat_local")
	elif live and current.get("mode")=="ai":
		status.text=T("ui.gomoku_panel.s_plays_black_s_plays_white_move_s")%[LocalText.resident(world,current.black_id),LocalText.resident(world,current.white_id),current.history.size()+1,T("ui.gomoku_panel.taking_their_seats") if phase=="arriving" else LocalText.resident(world,current.turn_actor_id)+T("ui.gomoku_panel.thinking"),current.ai.tokens,current.ai.get("reserved_tokens",0),current.ai.unknown_tokens,current.ai.token_limit]
	elif phase=="abandoned":status.text=T("ui.gomoku_panel.ended_without_a_winner_no_completed_game_memory")
	elif live:
		status.text=T("ui.gomoku_panel.walking_to_the_seats_together") if phase=="arriving" else T("ui.gomoku_panel.s_plays_black_s_plays_white_move_s_2")%[LocalText.resident(world,current.black_id),LocalText.resident(world,current.white_id),current.history.size()+1,T("ui.gomoku_panel.your_turn") if current.turn_actor_id=="human" else LocalText.resident(world,current.turn_actor_id)+(T("ui.gomoku_panel.studying_the_board_local") if current.mode=="local" else T("ui.gomoku_panel.waiting_for_a_real_model_move_request_this"))]
	elif finished:status.text=T("ui.gomoku_panel.draw_after_s_moves")%current.history.size() if current.result=="draw" else T("ui.gomoku_panel.s_wins_s_s_moves")%[LocalText.resident(world,current.winner_id),T("ui.gomoku_panel.five_in_a_row") if current.result=="five" else T("ui.gomoku_panel.opponent_resigned"),current.history.size()]
	else:status.text=T("ui.gomoku_panel.paused")+str(current.get("reason",T("ui.gomoku_panel.the_board_is_kept")))
	chat_row.visible=phase=="playing" and current.get("mode")=="model" and "human" in [current.get("black_id"),current.get("white_id")]
	options.visible=not live and not chat_row.visible and game_type.selected==0 and (current.get("mode")!="ai" or finished) and (not finished or setup_requested)
	game_type.visible=not finished or setup_requested
	message.visible=true
	preset_menu.visible=phase=="playing" and current.get("mode")=="local" and "human" in [current.get("black_id"),current.get("white_id")]
	portraits.match_state=current;portraits.hide()
	board.visible=not current.is_empty() and (not finished or game_type.selected==0)
	board.match_state=current;board.interactive=phase=="playing" and current.get("turn_actor_id")=="human";board.queue_redraw()
	reopen_button.visible=not card.visible and not current.is_empty() and not finished and world.actors.human.region_id==site.region_id and world.point(world.actors.human).distance_to(world.point(site))<=entry_radius
	reopen_button.text=T("ui.gomoku_panel.gomoku_2")+(T("ui.gomoku_panel.waiting_for_you_to_continue") if phase=="paused" else T("ui.gomoku_panel.taking_seats") if phase=="arriving" else T("ui.gomoku_panel.your_turn_2") if current.get("turn_actor_id")=="human" else T("ui.gomoku_panel.companion_s_turn"))
	stats.text=_stats_text()
	_layout()
func command_for(action: String,extra: Dictionary={}) -> Dictionary:
	var args: Dictionary={"intent":action,"site_id":site_id,"match_id":current.get("id",""),"revision":current.get("revision",0)};args.merge(extra);return args
func submit(action: String,extra: Dictionary={}) -> Dictionary:
	var result: Dictionary=world.command("human",command_for(action,extra))
	if not result.get("ok",false):
		var explanations: Dictionary={"stale_chess_turn":T("ui.gomoku_panel.the_board_just_changed_it_has_been_updated"),"not_your_turn":T("ui.gomoku_panel.wait_for_your_companion_s_move_then_it"),"occupied_intersection":T("ui.gomoku_panel.that_intersection_is_occupied_choose_an_empty_one"),"invalid_intersection":T("ui.gomoku_panel.click_an_empty_intersection_on_the_board")}
		message.text=str(result.get("message",explanations.get(result.get("error",""),T("ui.gomoku_panel.that_action_is_unavailable_check_the_current_match"))))
	else:message.text=T("ui.gomoku_panel.15_15_black_first_no_forbidden_moves_five")
	refresh();return result
func ask_budget(callback: Callable) -> void:
	for connection in confirm.confirmed.get_connections():confirm.confirmed.disconnect(connection.callable)
	confirm.title=T("ui.gomoku_panel.confirm_this_ai_match_budget")
	confirm.dialog_text=T("ui.gomoku_panel.only_the_selected_two_players_move_the_human")%[world.gomoku.match_config.max_steps,world.gomoku.match_config.max_tokens,world.gomoku.match_config.step_tokens,world.gomoku.match_config.step_timeout]
	confirm.confirmed.connect(callback,CONNECT_ONE_SHOT);confirm.popup_centered(Vector2i(480,250))
func request_ai() -> void:
	if black_picker.item_count==0 or white_picker.item_count==0:return
	var black: String=str(black_picker.get_item_metadata(black_picker.selected));var white: String=str(white_picker.get_item_metadata(white_picker.selected))
	var sources: Dictionary={black:str(black_source.get_item_metadata(black_source.selected)),white:str(white_source.get_item_metadata(white_source.selected))};var site: String=site_id
	if sources.values().has("model"):ask_budget(func():ai_start_requested.emit(site,black,white,sources))
	else:ai_start_requested.emit(site,black,white,sources)
func request_resign() -> void:
	if chatter!=null:chatter.request({"category":"resign","action":"surprised","priority":3})
	if current.get("mode")=="ai":
		ai_pause_requested.emit(site_id)
		for connection in confirm.confirmed.get_connections():confirm.confirmed.disconnect(connection.callable)
		var table_id: String=site_id;var match_id: String=current.id
		confirm.title=T("ui.gomoku_panel.end_this_match_2");confirm.dialog_text=T("ui.gomoku_panel.both_players_put_the_pieces_away_no_loss")
		confirm.confirmed.connect(func():
			if world.gomoku.sessions.get(table_id,{}).get("id")==match_id:ai_end_requested.emit(table_id),CONNECT_ONE_SHOT)
		confirm.popup_centered(Vector2i(400,180));return
	var args:=command_for("gomoku_resign")
	for connection in confirm.confirmed.get_connections():confirm.confirmed.disconnect(connection.callable)
	confirm.confirmed.connect(func():
		var result: Dictionary=world.command("human",args)
		if not result.ok:message.text=T("ui.gomoku_panel.the_match_state_changed_please_confirm_again")
		refresh(),CONNECT_ONE_SHOT)
	confirm.popup_centered(Vector2i(360,160))
func _position_popup(picker: OptionButton) -> void:
	var popup:=picker.get_popup()
	if not popup.visible:return
	var button_rect:=picker.get_global_rect()
	var viewport_height:=get_viewport_rect().size.y
	if button_rect.end.y+popup.size.y>viewport_height:
		popup.position.y=roundi(maxf(0.0,button_rect.position.y-popup.size.y))

func _process(delta: float) -> void:
	if card.visible:_layout()
	refresh_time+=delta
	if refresh_time<.2:return
	refresh_time=0;refresh()

var locale_labels:Dictionary={}
func T(key:String)->String:
	var result:=LocalText.text(key);locale_labels[LocalText.source(key)]=key;locale_labels[result]=key;return result
func refresh_locale()->void:
	_refresh_locale_nodes(self)
	for picker in [opponent,black_picker,white_picker]:
		for i in picker.item_count:
			var id:String=str(picker.get_item_metadata(i))
			if world.actors.has(id):picker.set_item_text(i,LocalText.resident(world,id))
	if visible:refresh()
	if result_shown:presentation.result_summary.text=LocalText.text("chess.summary.gomoku")%[current.get("history",[]).size(),_last_cell(current)]
func _refresh_locale_nodes(node:Node)->void:
	for property in ["text","title","placeholder_text","dialog_text","ok_button_text","cancel_button_text"]:
		if not node.get_property_list().any(func(p):return p.name==property):continue
		var value:Variant=node.get(property)
		if value is String and locale_labels.has(value):node.set(property,LocalText.text(locale_labels[value]))
	if node is OptionButton:
		for i in node.item_count:
			var value:String=node.get_item_text(i)
			if locale_labels.has(value):node.set_item_text(i,LocalText.text(locale_labels[value]))
	for child in node.get_children():_refresh_locale_nodes(child)

func _stats_text()->String:
	var previous:String="—"
	if not current.get("history",[]).is_empty():
		var cell:Array=current.history[-1];previous="%s%d"%[String.chr(65+int(cell[0])),int(cell[1])+1]
	var who:String=LocalText.text("chess.gomoku.finished") if current.get("phase")=="finished" else LocalText.resident(world,str(current.get("turn_actor_id","human")))
	return LocalText.text("chess.gomoku.stats")%[current.get("history",[]).size(),who,previous]
func _presentation_opponent()->String:
	if current.is_empty():return str(opponent.get_item_metadata(opponent.selected)) if opponent.item_count>0 else ""
	if current.get("black_id")=="human":return str(current.white_id)
	if current.get("white_id")=="human":return str(current.black_id)
	return str(current.get("turn_actor_id",current.get("white_id","")))
func tick_presentation(delta:float)->void:
	world.gomoku.companion.panel_tables[site_id]=card.visible
	if not card.visible:return
	var actual:Dictionary=world.gomoku.read(site_id,"human").get("match",{})
	if actual.is_empty():
		presentation.set_opponent(_presentation_opponent());return
	current=actual
	if observed_hand!=actual.history.size() or last_phase!=str(actual.phase):refresh()
	var id:String=str(actual.id);var buddy:String=_presentation_opponent()
	if buddy.is_empty():return
	if observed_match!=id:
		observed_match=id;observed_hand=-1;result_shown=false;player_wait=0;prior_hunger=world.hunger.rank(buddy)
		model_bubbles_seen.clear();chatter.begin(id,buddy);chatter.set_audience(presentation.companion_ids);presentation.set_opponent(buddy);presentation.clear_result();chatter.request({"category":"start","action":"calm"})
	var hand:int=actual.history.size()
	if hand!=observed_hand:
		observed_hand=hand;player_wait=0
		var public_facts:Dictionary=world.gomoku.companion.facts(world.gomoku.sessions[site_id])
		var context:String="nearwin" if public_facts.get("ahead_id","")==buddy else "nearlose" if public_facts.get("ahead_id","")=="human" else "move"
		chatter.observe_hand(hand,context if context!="move" else "")
		SceneEvents.hand(presentation,world,buddy,hand,actual.get("turn_actor_id")=="human",str(actual.black_id) if hand%2==1 else str(actual.white_id),context)
		var human_count:int=int(ceil(float(hand)/2.0)) if actual.black_id=="human" else int(floor(float(hand)/2.0))
		presentation.set_side_moves(human_count,hand-human_count)
		if actual.get("turn_actor_id")!="human":presentation.pose("thinking");chatter.request({"category":"thinking","action":"thinking"})
		var facts:Dictionary=world.gomoku.companion.facts(world.gomoku.sessions[site_id])
		if facts.get("ahead_id","")==buddy:chatter.request({"category":"nearwin","action":"proud","priority":1})
		elif facts.get("ahead_id","")=="human":chatter.request({"category":"nearlose","action":"panic","priority":1})
	else:
		player_wait+=delta
		if player_wait>=24 and actual.get("turn_actor_id")=="human":player_wait=0;chatter.request({"category":"slowplayer","action":"thinking"})
	var rank:int=world.hunger.rank(buddy)
	if rank>prior_hunger:chatter.request({"category":"hunger","action":"hunger","priority":3});presentation.pose("hunger")
	prior_hunger=rank
	if actual.get("phase")=="finished" and not result_shown:
		result_shown=true;setup_requested=false
		refresh()
		var outcome:String="draw" if actual.result=="draw" else "win" if actual.winner_id=="human" else "lose"
		var heading:String=LocalText.text("chess.presentation.win") if outcome=="win" else LocalText.text("chess.presentation.draw") if outcome=="draw" else LocalText.text("chess.presentation.winner")%LocalText.resident(world,str(actual.winner_id))
		SceneEvents.result(presentation,world,buddy,outcome)
		presentation.show_result(heading,LocalText.text("chess.summary.gomoku")%[hand,_last_cell(actual)],outcome)
		chatter.request({"category":"result","outcome":"lose" if outcome=="win" else "win" if outcome=="lose" else "draw","priority":100,"action":"sad" if outcome=="win" else "happy" if outcome=="lose" else "thinking"})
	for actor_id in world.gomoku.players(world.gomoku.sessions[site_id]):
		if actor_id=="human":continue
		var bubble:Dictionary=world.gomoku.companion.bubble(world.gomoku.sessions[site_id],actor_id)
		if bubble.get("source")=="model":
			var signature:String="model:%s:%s"%[actor_id,str(bubble.get("until",0))]
			if not model_bubbles_seen.has(signature):
				model_bubbles_seen[signature]=true
				chatter.request({"category":"model","actor_id":actor_id,"key":signature,"text":str(bubble.text),"priority":80})
	SceneEvents.hunger(presentation,world,chatter,scene_hunger,buddy)
	chatter.advance(delta);presentation._process(delta)
	board.flash_clock+=delta;board.queue_redraw()
	stats.text=_stats_text()
func _last_cell(game:Dictionary)->String:
	if game.get("history",[]).is_empty():return "—"
	var cell:Array=game.history[-1];return "%s%d"%[String.chr(65+int(cell[0])),int(cell[1])+1]
func _replay_presentation()->void:
	if current.is_empty():return
	if current.get("mode")=="ai":request_ai();return
	var buddy:String=_presentation_opponent()
	start_requested.emit(site_id,buddy,current.black_id=="human",str(current.mode),str(current.difficulty))
func _exit_tree()->void:
	if world!=null:world.gomoku.companion.panel_tables.erase(site_id)
