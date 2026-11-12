extends Control

const Text = preload("res://scripts/localization.gd")
const ActorView = preload("res://scripts/chess_actor_view.gd")

class CaptureView extends Control:
	var host: Control
	var owner_side := 0
	func _draw() -> void:
		host.draw_captures(self)

class ConfettiView extends Control:
	var host: Control
	func _draw() -> void:
		host.draw_confetti(self)

signal portrait_tapped
signal actor_tapped(id: String)
signal replay_requested
signal change_requested
signal leave_requested

var world: Variant
var kind := ""
var opponent := ""
var left: Control
var center: Control
var right: Control
var portrait: TextureRect
var speech: Label
var captures: CaptureView
var capture_items: Array = []
var capture_flight := 0.0
var capture_bounce := 0.0
var capture_origin: Callable
var board_piece_diameter := 40.0
var result_board_rect := Rect2()
var result_grid_height := 0.0
var result_layer: Control
var result_title: Label
var result_summary: Label
var reopen: Button
var pose_name := "calm"
var pose_time := 0.0
var elapsed := 0.0
var result_time := 0.0
var result_outcome := ""
var confetti: ConfettiView
var symbol: Label
var actor_views: Dictionary = {}
var companion_ids: Array[String] = []
var human_captures: CaptureView
var opponent_moves: Label
var human_moves: Label
var opponent_label: Label
var bubble_order: Array[String] = []

func setup(source: Variant, game_kind: String) -> void:
	world = source
	kind = game_kind
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	var shade:=ColorRect.new();shade.color=Color(0,0,0,0.35);shade.mouse_filter=Control.MOUSE_FILTER_IGNORE;shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(shade)
	left = Control.new()
	center = Control.new()
	right = Control.new()
	add_child(left)
	add_child(center)
	add_child(right)
	for id in world.actors:
		if id!="human" and companion_ids.size()<4:companion_ids.append(str(id))
	for id in companion_ids:
		var actor:=ActorView.new();left.add_child(actor);actor.setup(id);actor.tapped.connect(_actor_tapped);actor_views[id]=actor;_attach_bubble(actor)
	var human:=ActorView.new();right.add_child(human);human.setup("human");actor_views["human"]=human
	opponent_label=Label.new();opponent_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;left.add_child(opponent_label)
	opponent_moves=Label.new();left.add_child(opponent_moves)
	human_moves=Label.new();right.add_child(human_moves)
	if not companion_ids.is_empty():set_opponent(companion_ids[0])
	_refresh_actor("human")
	captures = CaptureView.new()
	captures.host = self
	captures.owner_side=2
	left.add_child(captures)
	human_captures=CaptureView.new();human_captures.host=self;human_captures.owner_side=1;right.add_child(human_captures)
	set_side_moves(0,0)
	result_layer = Control.new()
	result_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(result_layer)
	var background := ColorRect.new()
	background.color = Color(0.08, 0.11, 0.12, 0.82)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_layer.add_child(background)
	confetti = ConfettiView.new()
	confetti.host = self
	confetti.mouse_filter = Control.MOUSE_FILTER_IGNORE
	confetti.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_layer.add_child(confetti)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_layer.add_child(column)
	result_title = Label.new()
	result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(result_title)
	result_summary = Label.new()
	result_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(result_summary)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(buttons)
	_add_button(buttons, "chess.presentation.replay", func() -> void: replay_requested.emit())
	_add_button(buttons, "chess.presentation.change", func() -> void: dismiss_result();change_requested.emit())
	_add_button(buttons, "chess.presentation.leave", func() -> void: dismiss_result();leave_requested.emit())
	result_layer.hide()
	result_layer.gui_input.connect(_result_input)
	reopen = Button.new()
	reopen.text = Text.text("chess.presentation.result")
	reopen.set_meta("chess_presentation_key","chess.presentation.result")
	reopen.pressed.connect(func() -> void: result_layer.show())
	right.add_child(reopen)
	reopen.hide()
	resized.connect(_layout)
	Text.events.changed.connect(refresh_locale)
	_layout()

func _add_button(parent: Control, label: String, action: Callable) -> void:
	var button := Button.new();button.focus_mode=Control.FOCUS_NONE;
	button.text = Text.text(label)
	button.set_meta("chess_presentation_key",label)
	button.pressed.connect(action)
	parent.add_child(button)

func _layout() -> void:
	if left == null: return
	left.position = Vector2.ZERO
	left.size = Vector2(size.x * 0.25, size.y)
	center.position = Vector2(size.x * 0.25, 0)
	center.size = Vector2(size.x * 0.50, size.y)
	right.position = Vector2(size.x * 0.75, 0)
	right.size = Vector2(size.x * 0.25, size.y)
	var spectators: Array[String]=[]
	for id in companion_ids:
		if id!=opponent:spectators.append(id)
	for i in spectators.size():
		var actor: Control=actor_views[spectators[i]]
		actor.position=Vector2(left.size.x*(0.02+i*0.29),size.y*(0.24+(i%2)*0.035))
		actor.size=Vector2(left.size.x*0.38,size.y*0.24)
	if actor_views.has(opponent):
		var active: Control=actor_views[opponent];active.position=Vector2(left.size.x*0.18,size.y*0.42);active.size=Vector2(left.size.x*0.64,size.y*0.30);active.move_to_front()
	var human: Control=actor_views.get("human")
	if human!=null:human.position=Vector2(right.size.x*0.15,size.y*0.32);human.size=Vector2(right.size.x*0.7,size.y*0.38)
	opponent_label.position=Vector2(0,size.y*0.48);opponent_label.size=Vector2(left.size.x,24);opponent_label.move_to_front()
	_layout_bubbles()
	captures.position=Vector2(8,size.y*0.72);captures.size=Vector2(maxf(0,left.size.x-16),size.y*0.22)
	human_captures.position=Vector2(8,size.y*0.72);human_captures.size=Vector2(maxf(0,right.size.x-16),size.y*0.22)
	opponent_moves.position=Vector2(8,size.y*0.75);human_moves.position=Vector2(8,size.y*0.75)
	result_layer.position = result_board_rect.position
	result_layer.size = result_board_rect.size if result_board_rect.size != Vector2.ZERO else center.size
	reopen.position = Vector2(8, size.y * 0.93)
	result_title.add_theme_font_size_override("font_size", maxi(20, roundi((result_grid_height if result_grid_height > 0 else result_layer.size.y) * 0.15)))

func set_result_board_rect(rect: Rect2, grid_height: float = 0.0) -> void:
	result_board_rect = rect
	result_grid_height = grid_height
	_layout()

func set_opponent(id: String) -> void:
	if not actor_views.has(id) and world!=null and world.actors.has(id) and id!="human":
		if companion_ids.size()>=4:
			var removed: String=companion_ids.pop_back()
			bubble_order.erase(removed);actor_views[removed].speech.queue_free();actor_views[removed].queue_free();actor_views.erase(removed)
		companion_ids.append(id)
		var added:=ActorView.new();left.add_child(added);added.setup(id);added.tapped.connect(_actor_tapped);actor_views[id]=added;_attach_bubble(added)
	opponent = id
	if actor_views.has(id):
		var actor: Control=actor_views[id];portrait=actor.portrait;speech=actor.speech;symbol=actor.symbol
	_refresh_portrait()
	if opponent_label!=null:opponent_label.text=Text.text("chess.scene.opponent")+" · "+Text.resident(world,id)
	if captures!=null:_layout()

func _refresh_portrait() -> void:
	for id in actor_views:_refresh_actor(str(id))

func _refresh_actor(id: String) -> void:
	if world == null or not world.actors.has(id) or world.library == null or not actor_views.has(id):return
	var actor: Dictionary = world.actors[id]
	var appearance: String = str(actor.get("appearance_id", ""))
	var art: Dictionary = world.library.artworks.get(appearance, {})
	if art.is_empty():
		actor_views[id].portrait.texture = null
		return
	var frame: String = world.gomoku.companion.frame(art, "think" if actor_views[id].pose_name == "thinking" else "idle")
	if actor_views[id].pose_name=="watch" and art.frames.has("left_0" if id=="human" else "right_0"):frame="left_0" if id=="human" else "right_0"
	actor_views[id].portrait.texture = world.library.texture(appearance, frame)

func pose(action: String) -> void:
	pose_name = action
	pose_time = 1.2
	set_actor_pose(opponent,action)

func set_actor_pose(id: String, action: String) -> void:
	if id==opponent:pose_name=action;pose_time=1.2
	if actor_views.has(id):actor_views[id].pose(action);_refresh_actor(id)

func speak(event: Variant) -> void:
	var id: String=str(event.get("actor_id",opponent)) if event is Dictionary else opponent
	var line: String=str(event.get("text",event.get("line",""))) if event is Dictionary else str(event)
	if id!="human" and actor_views.has(id):
		if not line.is_empty():
			bubble_order.erase(id);bubble_order.append(id)
			while bubble_order.size()>2:
				var oldest: String=bubble_order.pop_front();actor_views[oldest].speech.hide();actor_views[oldest].speech_time=0
		actor_views[id].show_line(Text.resident(world,id)+" · "+line if not line.is_empty() else "");_layout_bubbles()

func _attach_bubble(actor: Control) -> void:
	actor.remove_child(actor.speech);left.add_child(actor.speech)
	actor.speech.clip_text=true
	actor.speech.vertical_alignment=VERTICAL_ALIGNMENT_CENTER

func _layout_bubbles() -> void:
	if left==null:return
	var width: float=minf(220.0,maxf(0.0,left.size.x-12.0))
	var slot_height: float=minf(68.0,size.y*0.105)
	for i in bubble_order.size():
		var id: String=bubble_order[i]
		if not actor_views.has(id):continue
		var label: Label=actor_views[id].speech
		label.position=Vector2((left.size.x-width)*0.5,4.0+i*(slot_height+4.0))
		label.size=Vector2(width,slot_height)
		var font_size:int=preload("res://scripts/ui_scale.gd").pixels(13)
		label.add_theme_font_size_override("font_size",font_size)
		label.size.y=maxf(slot_height,label.get_line_count()*label.get_theme_font("font").get_height(font_size)+10)
		label.move_to_front()

func set_side_moves(human: int, other: int) -> void:
	human_moves.text=Text.text("chess.scene.moves")%human
	opponent_moves.text=Text.text("chess.scene.moves")%other
	human_moves.visible=kind=="gomoku";opponent_moves.visible=kind=="gomoku"
	captures.visible=kind!="gomoku";human_captures.visible=kind!="gomoku"

func _actor_tapped(id: String) -> void:
	actor_tapped.emit(id)
	if id==opponent:portrait_tapped.emit()

func set_capture_origin(callback: Callable) -> void:
	capture_origin = callback

func set_captures(items: Array, animate: bool = true) -> void:
	if animate and items.size() > capture_items.size(): capture_flight = 0.4;capture_bounce = 0.0
	capture_items = items.duplicate(true)
	captures.queue_redraw()
	human_captures.queue_redraw()

func draw_captures(view: Control) -> void:
	if view.size.x<=0 or view.size.y<=0 or board_piece_diameter<=0:return
	var font: Font = get_theme_default_font()
	var diameter: float = board_piece_diameter * 0.6
	var y := 20.0
	var flight_target := Vector2.ZERO
	var last_piece: Dictionary=capture_items[-1] if not capture_items.is_empty() else {}
	for owner in [view.owner_side]:
		view.draw_string(font, Vector2(2, y), Text.text("chess.presentation.mine" if owner == 1 else "chess.presentation.hers"), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
		y += diameter * 0.7
		var grouped: Dictionary = {}
		for item in capture_items:
			if int(item.get("capturer", 0)) != owner: continue
			var key := "%s:%s:%s" % [item.get("kind", "?"), item.get("side", 0), item.get("own", false)]
			if not grouped.has(key): grouped[key] = {"piece":item, "count":0}
			grouped[key].count += 1
		var keys: Array = grouped.keys()
		keys.sort_custom(func(a: String, b: String) -> bool: return "RHCEASK".find(a.left(1)) < "RHCEASK".find(b.left(1)))
		var x := diameter * 0.55
		for key in keys:
			var entry: Dictionary = grouped[key]
			var piece: Dictionary = entry.piece
			var p := Vector2(x, y)
			var is_latest: bool=not last_piece.is_empty() and piece.kind==last_piece.kind and piece.side==last_piece.side and piece.own==last_piece.own and piece.capturer==last_piece.capturer
			if is_latest:flight_target=p
			if capture_flight <= 0 and capture_bounce > 0 and is_latest:p.y-=sin((capture_bounce/0.18)*PI)*6.0
			var count:int=int(entry.count)-(1 if is_latest and capture_flight>0 else 0)
			if count>0:_draw_token(view,p,diameter,piece,count)

			x += diameter * 2.0
			if x + diameter > view.size.x: x = diameter * 0.55; y += diameter * 1.8
		y += diameter * 2.6

	if capture_flight>0 and not last_piece.is_empty() and int(last_piece.capturer)==view.owner_side:
		var origin:Vector2=view.get_global_transform().affine_inverse()*(capture_origin.call(int(last_piece.from)) if capture_origin.is_valid() else center.global_position)
		var t:float=1.0-capture_flight/0.4
		var p:Vector2=origin.lerp(flight_target,t);p.y-=sin(t*PI)*18.0
		_draw_token(view,p,diameter,last_piece,1)

func _draw_token(view:Control,p:Vector2,diameter:float,piece:Dictionary,count:int)->void:
	var font:Font=get_theme_default_font()
	view.draw_circle(p,diameter*0.48,Color("fff0bd"))
	var ink:=Color("c1332c") if int(piece.side)==1 else Color("202830")
	view.draw_arc(p,diameter*0.48,0,TAU,32,ink,2)
	var label:String=Text.source("jieqi.piece."+str(piece.kind))
	var font_size:=preload("res://scripts/ui_scale.gd").pixels(maxi(8,roundi(diameter*0.6)))
	view.draw_string(font,p+Vector2(-font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x/2,font.get_ascent(font_size)*0.4),label,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,ink)
	if bool(piece.own):view.draw_string(font,p+Vector2(-diameter*0.4,diameter*1.05),Text.text("chess.presentation.own"),HORIZONTAL_ALIGNMENT_LEFT,-1,10,Color.WHITE)
	if count>1:view.draw_string(font,p+Vector2(diameter*0.25,diameter*0.65),"×"+str(count),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.WHITE)

func show_result(title_text: String, summary: String = "", outcome: String = "draw") -> void:
	result_layer.move_to_front()
	result_title.text = title_text
	result_time = 0.0
	result_outcome = outcome
	result_summary.text = summary
	result_title.add_theme_color_override("font_color", Color("f1ca68") if outcome == "win" else Color("a9d7e9") if outcome in ["loss", "lose"] else Color("cccccc"))
	result_title.add_theme_color_override("font_outline_color", Color("715020"))
	result_title.add_theme_constant_override("outline_size", 3)
	result_layer.show()
	reopen.show()

func dismiss_result() -> void:
	result_layer.hide()

func clear_result() -> void:
	result_layer.hide()
	reopen.hide()

func _portrait_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		portrait_tapped.emit()

func _input(event:InputEvent)->void:
	if is_visible_in_tree() and result_layer.visible and event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT and not result_layer.get_global_rect().has_point(event.global_position):
		# Only blank space dismisses the stamp. Preserve Close, setup, Result and portrait input.
		for node in _descendants(self):
			if node is BaseButton and node.is_visible_in_tree() and node.get_global_rect().has_point(event.global_position):return
		for actor in actor_views.values():
			if actor.portrait.get_global_rect().has_point(event.global_position):return
		dismiss_result()
		get_viewport().set_input_as_handled()

func _result_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		dismiss_result()

func draw_confetti(view: Control) -> void:
	if result_outcome != "win" or result_time >= 2.0: return
	var colors := [Color("f4c65e"), Color("e77972"), Color("87c9b6"), Color("a5c8e7")]
	for i in 32:
		var x: float = fposmod(float(i * 73) + sin(result_time * 3.0 + i) * 18.0, maxf(1.0, view.size.x))
		var y: float = fposmod(float(i * 47) + result_time * (90.0 + i * 2.0), maxf(1.0, view.size.y))
		view.draw_rect(Rect2(x, y, 5, 9), colors[i % colors.size()])

func _process(delta: float) -> void:
	elapsed += delta
	result_time += delta
	var was_flying := capture_flight > 0
	capture_flight = maxf(0.0, capture_flight - delta)
	if was_flying and capture_flight == 0: capture_bounce = 0.18
	else: capture_bounce = maxf(0.0, capture_bounce - delta)
	if captures != null and (was_flying or capture_bounce > 0): captures.queue_redraw();human_captures.queue_redraw()
	if confetti != null and result_layer.visible:
		confetti.queue_redraw()
		var stamp: float = minf(1.0, result_time / 0.5)
		result_title.scale = Vector2.ONE * (1.4 - 0.4 * stamp)
		result_title.modulate.a = stamp
	pose_time = maxf(0.0, pose_time - delta)
	for actor in actor_views.values():actor.advance(delta)
	for id in bubble_order.duplicate():
		if not actor_views.has(id) or not actor_views[id].speech.visible:bubble_order.erase(id)
	_layout_bubbles()

func refresh_locale()->void:
	for node in _descendants(self):
		if node is BaseButton and node.has_meta("chess_presentation_key"):node.text=Text.text(str(node.get_meta("chess_presentation_key")))
	if not result_outcome.is_empty():
		result_title.text=Text.text("chess.presentation.win") if result_outcome=="win" else Text.text("chess.presentation.draw") if result_outcome=="draw" else Text.text("chess.presentation.winner")%Text.resident(world,opponent)
	captures.queue_redraw()
	human_captures.queue_redraw()
	if not opponent.is_empty():opponent_label.text=Text.text("chess.scene.opponent")+" · "+Text.resident(world,opponent)
func _descendants(node:Node)->Array:
	var out:Array=[]
	for child in node.get_children():out.append(child);out.append_array(_descendants(child))
	return out
