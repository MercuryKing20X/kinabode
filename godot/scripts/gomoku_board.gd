extends Control
signal intersection(p: Vector2i)
var match_state: Dictionary={}
var interactive:=false
var flash_clock:=0.0
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_STOP;resized.connect(queue_redraw)
func geometry() -> Dictionary:
	var side:=maxf(1,minf(size.x,size.y)-28)
	return {"origin":(size-Vector2(side,side))/2,"step":side/14.0,"side":side}
func _draw() -> void:
	var g:=geometry();var origin: Vector2=g.origin;var side: float=g.side;var spacing: float=g.step
	draw_style_box(_style(),Rect2(origin-Vector2(12,12),Vector2(side+24,side+24)))
	for index in range(15):
		draw_line(origin+Vector2(index*spacing,0),origin+Vector2(index*spacing,side),Color("866341"),1,true)
		draw_line(origin+Vector2(0,index*spacing),origin+Vector2(side,index*spacing),Color("866341"),1,true)
	for p in [Vector2i(3,3),Vector2i(11,3),Vector2i(7,7),Vector2i(3,11),Vector2i(11,11)]:draw_circle(origin+Vector2(p)*spacing,2.8,Color("765434"))
	var history: Array=match_state.get("history",[])
	for index in range(history.size()):
		var p: Array=history[index];var at: Vector2=origin+Vector2(p[0],p[1])*spacing
		draw_circle(at+Vector2(1,2),spacing*.4,Color(0,0,0,.18))
		draw_circle(at,spacing*.4,Color("293d43") if index%2==0 else Color("fff4df"))
		draw_circle(at-Vector2(spacing*.12,spacing*.14),spacing*.11,Color("607779") if index%2==0 else Color.WHITE)
		if index==history.size()-1:draw_arc(at,spacing*.46,0,TAU,24,Color("cf7455"),2,true)
	var line: Array=match_state.get("winning_line",[])
	for p in line:draw_arc(origin+Vector2(p[0],p[1])*spacing,spacing*.46,0,TAU,24,Color("c35341"),2.5,true)
	if line.size()>=5:
		var points:=PackedVector2Array()
		for p in line:points.append(origin+Vector2(p[0],p[1])*spacing)
		draw_polyline(points,Color(1.0,0.85,0.3,.65+.35*sin(flash_clock*5)),5,true)
func _style() -> StyleBoxFlat:
	var style:=StyleBoxFlat.new();style.bg_color=Color("e5c68f");style.set_border_width_all(3);style.border_color=Color("aa7f4d");style.set_corner_radius_all(8);return style
func _gui_input(event: InputEvent) -> void:
	if not interactive or not event is InputEventMouseButton or event.button_index!=MOUSE_BUTTON_LEFT or not event.pressed:return
	var g:=geometry();var local: Vector2=(event.position-g.origin)/float(g.step);var p:=Vector2i(roundi(local.x),roundi(local.y))
	if p.x<0 or p.y<0 or p.x>=15 or p.y>=15 or local.distance_to(Vector2(p))>.48:return
	intersection.emit(p);accept_event()
