extends Control
const LocalText=preload("res://scripts/localization.gd")
## Draw-only integer zoom of the actor's current editable work. Never rewrites artwork.
var world: RefCounted
var match_state: Dictionary={}
var card_rect:=Rect2()
var bounds_by_actor: Dictionary={}
var shown: Array=[]
var resolved_frames: Dictionary={}
func _init() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE;texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
func _draw() -> void:
	shown.clear();resolved_frames.clear();bounds_by_actor.clear()
	if world==null or world.library==null or match_state.is_empty():return
	var ids: Array=world.gomoku.players(match_state).filter(func(id):return id!="human")
	var font: Font=preload("res://assets/fonts/NotoSansSC.ttf")
	for index in range(ids.size()):
		var id: String=ids[index];var actor: Dictionary=world.actors[id]
		var art: Dictionary=world.library.artworks.get(actor.appearance_id,{})
		if art.is_empty():continue
		var pose: String=world.gomoku.companion.pose(match_state,id)
		var frame: String=world.gomoku.companion.frame(art,pose);resolved_frames[id]=frame;shown.append(id)
		var width: float=maxf(1,card_rect.position.x-20)
		var left: float=10 if index==0 else card_rect.end.x+10
		var screen_transform: Transform2D=get_viewport().get_final_transform()*get_global_transform_with_canvas()
		var screen_scale: float=maxf(.1,screen_transform.get_scale().x)
		var pixel_zoom:=maxi(1,mini(2,int(floor(width*screen_scale/float(art.width)))))
		var zoom: float=pixel_zoom/screen_scale
		var font_size:=int(ceil(14/screen_scale));var line_step: float=20/screen_scale
		var top: float=maxf(92,(size.y-float(art.height)*zoom-120/screen_scale)/2)
		var tex: Texture2D=world.library.texture(actor.appearance_id,frame)
		# Compensate canvas stretch so displayed sprite pixels have integer zoom; board untouched.
		bounds_by_actor[id]=Rect2(Vector2(left,top),Vector2(width,float(art.height)*zoom))
		var source_width: float=minf(float(art.width),floor(width/zoom))
		var image_origin: Vector2=screen_transform.affine_inverse()*(screen_transform*Vector2(left+(width-source_width*zoom)/2,top)).round()
		draw_texture_rect_region(tex,Rect2(image_origin,Vector2(source_width,float(art.height))*zoom),Rect2(Vector2((float(art.width)-source_width)/2,0),Vector2(source_width,float(art.height))))
		var x: float=left
		var baseline: float=top+float(art.height)*zoom+line_step
		var b: Dictionary=world.gomoku.companion.bubble(match_state,id)
		var style:=StyleBoxFlat.new();style.bg_color=Color("24454b");style.set_corner_radius_all(8)
		var bubble_width: float=maxf(1,width-8)
		var bubble_rows: int=int(ceil(font.get_string_size(("" if b.get("source")=="local_rules" else LocalText.text("ui.speech.model"))+(LocalText.speech(world,id,str(b.get("text",""))) if b.get("source")=="local_rules" else str(b.get("text",""))),HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x/bubble_width))
		draw_style_box(style,Rect2(Vector2(left-2,baseline-19/screen_scale),Vector2(width+4,(31+bubble_rows*20 if not b.is_empty() else 25)/screen_scale)))
		draw_string(font,Vector2(x,baseline),LocalText.resident(world,id)+(LocalText.text("ui.gomoku.black_suffix") if id==match_state.black_id else LocalText.text("ui.gomoku.white_suffix")),HORIZONTAL_ALIGNMENT_LEFT,width,font_size,Color("fff4df"))
		if not b.is_empty():
			var label: String=("" if b.source=="local_rules" else LocalText.text("ui.speech.model"))+(LocalText.speech(world,id,str(b.text)) if b.source=="local_rules" else str(b.text))
			var row:=0;var text:="";var available: float=width-8
			for character in label:
				if font.get_string_size(text+character,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>available:
					draw_string(font,Vector2(x,baseline+23/screen_scale+row*line_step),text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color("fff4df"));row+=1;text=""
				text+=character
			draw_string(font,Vector2(x,baseline+23/screen_scale+row*line_step),text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color("fff4df"))
