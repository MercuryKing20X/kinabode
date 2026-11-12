extends Control
signal bubble_delivered(event: Dictionary)
signal change_requested
const Text=preload("res://scripts/localization.gd")
const Rules=preload("res://scripts/jieqi_rules.gd")
const Presentation=preload("res://scripts/chess_presentation.gd")
const History=preload("res://scripts/chess_history.gd")
const Chatter=preload("res://scripts/chess_chatter.gd")
const SceneEvents=preload("res://scripts/chess_scene_events.gd")
var scene_context:="move"
var scene_hunger:Dictionary={}
var presentation: Control
var chatter: RefCounted
var facts: Dictionary = {}
var observed_match := ""
var observed_hand := -1
var result_shown := false
var previous_hunger := -1
var player_wait := 0.0
var controls: VBoxContainer
var system: RefCounted
var card: PanelContainer
var board: Control
var picker: OptionButton
var info: Label
var selected:=-1
var ids: Array=[]
var captured_label: Label
var last_hand:=-1
var flip_time:=0.0
var feedback_until:=0.0
var portrait: TextureRect
var bubble: Label
var selected_mode:="standard"
var start_button:Button
var rules_label:Label
var title:Label
var resume_existing:=false
func setup(source: RefCounted) -> void:
	preload("res://scripts/chess_theme.gd").apply(self)
	system=source;Text.events.changed.connect(refresh_locale);set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);z_index=110;mouse_filter=Control.MOUSE_FILTER_STOP
	card=PanelContainer.new();card.set_meta("chess_scene_surface",true);card.add_theme_stylebox_override("panel",StyleBoxEmpty.new());add_child(card)
	var root:=Control.new();card.add_child(root)
	presentation=Presentation.new();root.add_child(presentation);presentation.setup(system.world,"jieqi")
	presentation.set_process(false)
	chatter=Chatter.new(system.world,"jieqi")
	chatter.delivered.connect(_bubble_delivered)
	system.panel_reaction.connect(func(context: String):
		scene_context=context
		if context!="move":
			chatter.observe_hand(system.game.history.size(),context))
	presentation.actor_tapped.connect(func(id:String):chatter.tapped(id))
	chatter.reaction.connect(func(id:String,action:String):presentation.set_actor_pose(id,action))
	presentation.change_requested.connect(func():change_requested.emit())
	presentation.leave_requested.connect(func():hide())
	presentation.replay_requested.connect(_replay)
	var col:=VBoxContainer.new();controls=col;col.add_theme_constant_override("separation",1);presentation.center.add_child(col)
	title=Label.new();col.add_child(title)
	var row:=HBoxContainer.new();col.add_child(row)
	picker=OptionButton.new();row.add_child(picker);picker.get_popup().about_to_popup.connect(func():_position_popup.call_deferred())
	for id in system.world.actors:
		if id!="human":ids.append(id);picker.add_item(Text.resident(system.world,id))
	start_button=Button.new();row.add_child(start_button);start_button.pressed.connect(begin)
	var actions:=HBoxContainer.new();col.add_child(actions)
	add_button(actions,"jieqi.resign",func():chatter.request({"category":"resign","priority":3});system.resign())
	add_button(actions,"jieqi.draw",func():chatter.request({"category":"drawoffer","priority":3});info.text=Text.text("jieqi.draw_yes" if system.offer_draw() else "jieqi.draw_no"))
	add_button(actions,"jieqi.close",func():hide())
	board=Control.new();presentation.center.add_child(board);board.draw.connect(draw_board);board.gui_input.connect(board_input)
	captured_label=Label.new();captured_label.hide();col.add_child(captured_label)
	info=Label.new();info.set_meta("ui_font_base",14);info.add_theme_font_size_override("font_size",14);info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;col.add_child(info)
	rules_label=Label.new();rules_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;rules_label.hide();col.add_child(rules_label)
	add_button(actions,"chess.presentation.rules",_show_rules)
	portrait=presentation.portrait;bubble=presentation.speech
	presentation.set_capture_origin(func(index: int) -> Vector2:return board.get_global_transform() * cell_position(index))
	hide()
func add_button(row: Container,key: String,action: Callable) -> void:
	var button:=Button.new();button.focus_mode=Control.FOCUS_NONE;button.set_meta("jieqi_key",key);button.text=Text.text(key);button.pressed.connect(action);row.add_child(button)
func open(mode:String="",continuing:bool=false) -> void:
	resume_existing=continuing or mode.is_empty()
	selected_mode=str(system.game.get("mode","standard")) if resume_existing and not system.game.is_empty() else (mode if mode in ["standard","chaos"] else "standard")
	if resume_existing and ids.has(system.opponent):picker.select(ids.find(system.opponent))
	selected=-1;info.text="";feedback_until=0;show();move_to_front();refresh_locale();queue_redraw()
func begin()->void:
	var result:Dictionary
	if resume_existing and not system.game.is_empty():
		result=system.resume() if system.phase=="paused" else {"ok":true}
	else:
		result=system.start(ids[picker.selected],-1,selected_mode,system.site_id)
	if result.ok:resume_existing=true;info.text="";_begin_chatter()
	else:
		var key:String={"hungry":"jieqi.hungry","unfinished_facility":"chess.unbuilt","busy":"chess.busy","full":"chess.seats_busy","match_exists":"chess.finish_previous","different_region":"chess.other_island"}.get(str(result.get("error","")),"jieqi.unavailable")
		info.text=Text.text(key)
	feedback_until=Time.get_ticks_msec()/1000.0+4;selected=-1;board.queue_redraw()
func _process(delta: float) -> void:
	if not visible:return
	var viewport_size:=get_viewport_rect().size
	var h: float=viewport_size.y*0.60+36
	system.panel_speech=true
	card.position=Vector2.ZERO;card.size=viewport_size
	var center_size: Vector2=presentation.center.size
	board.size=Vector2(minf(center_size.x,h*0.9),minf(center_size.y,h))
	board.position=Vector2((center_size.x-board.size.x)*0.5,(center_size.y-board.size.y)*0.5)
	presentation.board_piece_diameter=spacing()*0.8
	presentation.set_result_board_rect(board.get_rect(),spacing()*9)
	controls.position=Vector2(board.position.x,board.position.y+board.size.y+2);controls.size=Vector2(board.size.x,maxf(0,center_size.y-controls.position.y))
	presentation.result_layer.move_to_front()
	var live:bool=not system.game.is_empty() and system.phase in ["arriving","playing"]
	start_button.disabled=live
	picker.get_parent().visible=not resume_existing or system.phase=="paused"
	start_button.text=Text.text("chess.resume" if resume_existing and system.phase=="paused" else "jieqi.start")
	picker.disabled=live or (resume_existing and not system.game.is_empty())
	if resume_existing and not system.game.is_empty():
		if last_hand!=system.game.history.size():last_hand=system.game.history.size();flip_time=0.35
		flip_time=maxf(0,flip_time-delta)
		if observed_match!=system.match_id:
			_begin_chatter()
		if observed_hand!=system.game.history.size():
			var animate_capture: bool=observed_hand>=0 and system.game.history.size()==observed_hand+1
			observed_hand=system.game.history.size();player_wait=0.0
			facts=History.jieqi(int(system.game.seed),system.game.history,str(system.game.get("mode","standard")))
			presentation.set_captures(facts.get("captures",[]),animate_capture)
			chatter.observe_hand(observed_hand)
			var mover:String="human" if observed_hand%2==1 else system.opponent
			SceneEvents.hand(presentation,system.world,system.opponent,observed_hand,system.game.turn==1,mover,scene_context)
			var took:Array=facts.get("captures",[])
			if not took.is_empty() and int(took[-1].hand)==observed_hand:
				presentation.pose("happy" if int(took[-1].capturer)==2 else "panic");presentation.set_actor_pose("human","tense" if int(took[-1].capturer)==2 else "happy")
				chatter.request({"category":"goodmove" if int(took[-1].capturer)==1 and not bool(took[-1].own) else "regret" if bool(took[-1].own) else "nearwin","priority":1})
			elif system.phase=="playing" and system.game.get("turn")==2:presentation.pose("thinking")
			var mine:int=0;var hers:int=0
			for token in took:
				if int(token.capturer)==1:mine+=1
				else:hers+=1
			if mine>=hers+4:chatter.request({"category":"nearlose","priority":1})
			elif hers>=mine+4:chatter.request({"category":"nearwin","priority":1})
		if not result_shown and (system.game.winner!=0 or system.game.draw):
			result_shown=true
			var result_text: String=Text.text("chess.presentation.win") if system.game.winner==1 else Text.text("chess.presentation.opponent_win") % Text.resident(system.world,system.opponent) if system.game.winner==2 else Text.text("jieqi.draw_yes")
			presentation.show_result(result_text,_result_summary(),"win" if system.game.winner==1 else "lose" if system.game.winner==2 else "draw")
			var response:String="lose" if system.game.winner==1 else "win" if system.game.winner==2 else "draw"
			var action:String="sad" if response=="lose" else "happy" if response=="win" else "thinking"
			SceneEvents.result(presentation,system.world,system.opponent,"win" if system.game.winner==1 else "lose" if system.game.winner==2 else "draw");presentation.pose(action);chatter.request({"category":"result","outcome":response,"action":action,"priority":100})
	board.queue_redraw()
	if resume_existing and not system.game.is_empty() and Time.get_ticks_msec()/1000.0>feedback_until:info.text=Text.text("jieqi.win" if system.game.winner==1 else "jieqi.lose" if system.game.winner==2 else "jieqi.draw_yes" if system.game.draw else "jieqi.your_turn" if system.game.turn==1 else "jieqi.thinking")
func _bubble_delivered(event: Dictionary) -> void:
	presentation.speak(event)
	var action:String=str(event.get("action","calm"))
	if action!="calm":presentation.set_actor_pose(str(event.get("actor_id",system.opponent)),action)
	bubble_delivered.emit(event)
func _begin_chatter() -> void:
	observed_match=system.match_id;observed_hand=-1;result_shown=false;previous_hunger=system.world.hunger.rank(system.opponent);chatter.begin(observed_match,system.opponent);chatter.set_audience(presentation.companion_ids);presentation.set_opponent(system.opponent);portrait=presentation.portrait;bubble=presentation.speech;presentation.clear_result();chatter.request({"category":"start"})
func tick_presentation(delta: float) -> void:
	if not visible:
		system.panel_speech=false
		return
	_process(0.0)
	system.panel_speech=true
	if not system.opponent.is_empty() and system.world.actors.has(system.opponent):
		var hunger: int=system.world.hunger.rank(system.opponent)
		if previous_hunger>=0 and hunger>previous_hunger:
			presentation.pose("hunger");chatter.request({"category":"hunger","reaction":true,"priority":2})
		previous_hunger=hunger
		if system.phase=="playing" and system.game.get("turn",0)==2 and presentation.pose_time<=0:presentation.pose("thinking")
	if resume_existing and not system.game.is_empty() and system.phase=="playing" and system.game.turn==1:
		player_wait+=delta
		if player_wait>=24.0:
			player_wait=0.0;chatter.request({"category":"slowplayer","action":"thinking"})
	SceneEvents.hunger(presentation,system.world,chatter,scene_hunger,system.opponent)
	chatter.advance(delta)
	presentation._process(delta)

func _replay() -> void:
	var result: Dictionary=system.start(system.opponent,-1,selected_mode,system.site_id)
	if result.get("ok",false):_begin_chatter()
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and system != null and not visible:system.panel_speech=false
func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):hide();get_viewport().set_input_as_handled()
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and not card.get_global_rect().has_point(event.global_position):hide()
func cell_position(i: int) -> Vector2:return Vector2((board.size.x-spacing()*8)/2+(i%9)*spacing(),18+(i/9)*spacing())
func spacing() -> float:return minf((board.size.x-36)/8,(board.size.y-36)/9)
func draw_board() -> void:
	if board.size.x<=36 or board.size.y<=36:return
	var ink:=Color("71543b");var font: Font=get_theme_default_font()
	board.draw_rect(Rect2(Vector2.ZERO,board.size),Color("ead3a0"))
	for y in range(10):board.draw_line(cell_position(y*9),cell_position(y*9+8),ink)
	for x in range(9):board.draw_line(cell_position(x),cell_position(81+x),ink)
	if not resume_existing or system.game.is_empty():return
	for i in range(90):
		var piece: Variant=system.game.board[i]
		if piece==null:continue
		var p:=cell_position(i);var r:=spacing()*0.4
		var flipping: bool=flip_time>0 and not system.game.history.is_empty() and system.game.history[-1][1]==i
		if flipping:board.draw_set_transform(p,0,Vector2(maxf(0.05,absf(cos((1-flip_time/0.35)*PI))),1));p=Vector2.ZERO
		board.draw_circle(p,r,Color("b49b70") if piece.hidden else Color("fff0bd"))
		board.draw_arc(p,r,0,TAU,32,Color("d34034") if piece.side==1 else Color("252b30"),2)
		if not piece.hidden:
			var label: String=Text.source("jieqi.piece."+piece.kind)
			var font_size:=roundi(r*1.2)
			board.draw_string(font,p-Vector2(font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x/2,-font.get_ascent(font_size)*0.4),label,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color("c1332c") if piece.side==1 else Color("202830"))
		if flipping:board.draw_set_transform(Vector2.ZERO)
	if selected>=0:
		board.draw_arc(cell_position(selected),spacing()*0.46,0,TAU,32,Color.CORAL,3)
		for move in Rules.legal_moves(system.game):
			if move[0]==selected:board.draw_circle(cell_position(move[1]),5,Color("389b75"))
	if not system.game.history.is_empty():
		for i in system.game.history[-1]:board.draw_arc(cell_position(i),spacing()*0.48,0,TAU,32,Color("37849a"),2)
	if result_shown:
		for i in facts.get("decisive",[]):board.draw_arc(cell_position(int(i)),spacing()*0.52,0,TAU,32,Color(1.0,0.85,0.25,0.65+0.35*sin(presentation.elapsed*5.0)),4)
func board_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed or event.button_index!=MOUSE_BUTTON_LEFT or system.game.is_empty():return
	var local: Vector2=(event.position-cell_position(0))/spacing();var x:=roundi(local.x);var y:=roundi(local.y)
	if x<0 or x>8 or y<0 or y>9:return
	var i:=y*9+x
	if selected>=0 and system.play(selected,i):selected=-1;board.queue_redraw();return
	if system.game.board[i]!=null and system.game.board[i].side==1:
		selected=i
		if system.game.board[i].hidden:chatter.request({"category":"prereveal","action":"thinking"})
	board.queue_redraw()

func refresh_locale() -> void:
	translate_children(self)
	if result_shown:presentation.result_summary.text=_result_summary()
	title.text=Text.text("jieqi.title")+" · "+Text.text("chess.chaos" if selected_mode=="chaos" else "chess.standard")
	rules_label.text=Text.text("jieqi.chaos_rules" if selected_mode=="chaos" else "jieqi.rules")
	for index in range(ids.size()):picker.set_item_text(index,Text.resident(system.world,ids[index]))
func translate_children(node: Node) -> void:
	if node.has_meta("jieqi_key"):node.text=Text.text(str(node.get_meta("jieqi_key")))
	for child in node.get_children():translate_children(child)

func _result_summary()->String:
	var summary:String=History.summary(facts)
	if system.game.get("terminal_reason","")=="chaos_selfcheck":
		var piece:String=Text.text("chess.summary.piece."+str(system.game.get("selfcheck_kind","R"))) if TranslationServer.get_locale().begins_with("en") else Text.source("jieqi.piece."+str(system.game.get("selfcheck_kind","R")))
		summary="%s\n%s"%[Text.text("chess.selfcheck.reason")%piece,summary]
	return summary

func _position_popup()->void:
	var popup:=picker.get_popup()
	if popup.visible and picker.get_global_rect().end.y+popup.size.y>get_viewport_rect().size.y:
		popup.position.y=roundi(maxf(0,picker.get_global_rect().position.y-popup.size.y))

func _show_rules()->void:
	var dialog:=AcceptDialog.new();add_child(dialog)
	dialog.theme=theme
	dialog.title=Text.text("chess.presentation.rules")
	dialog.dialog_text=Text.text("jieqi.chaos_rules" if selected_mode=="chaos" else "jieqi.rules")
	dialog.get_label().autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	dialog.confirmed.connect(dialog.queue_free);dialog.canceled.connect(dialog.queue_free);dialog.close_requested.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(mini(600,int(get_viewport_rect().size.x)-40),260))
