extends Control
const Text=preload("res://scripts/localization.gd")

signal tapped(id: String)
var actor_id := ""
var portrait: TextureRect
var speech: Label
var symbol: Label
var pose_name := "calm"
var pose_time := 0.0
var speech_time := 0.0
var elapsed := 0.0
var base_position := Vector2.ZERO

func setup(id: String) -> void:
	actor_id=id
	mouse_filter=Control.MOUSE_FILTER_PASS
	portrait=TextureRect.new()
	portrait.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter=Control.MOUSE_FILTER_STOP
	portrait.gui_input.connect(_input_portrait)
	add_child(portrait)
	speech=Label.new();speech.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	speech.add_theme_font_size_override("font_size",13)
	var style:=StyleBoxFlat.new();style.bg_color=Color("213c37");style.set_content_margin_all(5)
	speech.add_theme_stylebox_override("normal",style);speech.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(speech);speech.hide()
	symbol=Label.new();symbol.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;symbol.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(symbol)
	resized.connect(_layout);_layout()

func _layout() -> void:
	if portrait==null:return
	portrait.position=Vector2(4,size.y*0.18);base_position=portrait.position
	portrait.size=Vector2(maxf(0,size.x-8),size.y*0.82);portrait.pivot_offset=portrait.size*0.5
	symbol.position=Vector2(0,size.y*0.13);symbol.size=Vector2(size.x,25)

func show_line(text: String) -> void:
	speech.text=text;speech_time=3.6;speech.visible=not text.is_empty()

func pose(action: String) -> void:
	pose_name=action;pose_time=1.2
	symbol.text={"thinking":"…","happy":"♪","cheer":"♪","clap":"♪","panic":"！","tense":"!","shy":"…","proud":"～","sad":"…","surprised":"？！","hunger":Text.text("ui.island_view.rumble"),"yawn":"～","watch":""}.get(action,"")

func advance(delta: float) -> void:
	elapsed+=delta;pose_time=maxf(0,pose_time-delta);speech_time=maxf(0,speech_time-delta)
	if speech_time==0:speech.hide()
	var target:=base_position
	var angle:=0.0
	var stretch:=Vector2.ONE
	if pose_name=="thinking":angle=0.06
	elif pose_time>0 and pose_name in ["happy","cheer","clap"]:target.y-=absf(sin(elapsed*10))*6
	elif pose_time>0 and pose_name in ["panic","tense"]:angle=sin(elapsed*20)*0.06
	elif pose_name in ["sad","hunger"]:angle=-0.07;target.y+=6
	elif pose_name=="shy":angle=-0.04
	elif pose_name=="proud":angle=0.04;target.y-=4
	elif pose_name=="surprised":target.y-=5
	elif pose_name=="watch":angle=0.04 if actor_id!="human" else -0.04
	elif pose_name=="yawn":stretch=Vector2(0.96,1.05);target.y-=3
	if actor_id=="human" and pose_name=="tense":symbol.text=""
	queue_redraw()
	var blend:=1.0-exp(-delta*12.0)
	portrait.position=portrait.position.lerp(target,blend)
	portrait.rotation=lerpf(portrait.rotation,angle,blend)
	portrait.scale=portrait.scale.lerp(stretch,blend)

func _input_portrait(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT and actor_id!="human":tapped.emit(actor_id)

func _draw()->void:
	if actor_id=="human" and pose_name=="tense" and symbol!=null:
		var p:Vector2=symbol.position+Vector2(size.x*.5,12)
		var blue:=Color("8bd1ef")
		draw_colored_polygon(PackedVector2Array([p+Vector2(0,-9),p+Vector2(-5,1),p+Vector2(5,1)]),blue)
		draw_circle(p+Vector2(0,2),5,blue)
