extends Node2D
const Text=preload("res://scripts/localization.gd")
var game:Node
var menu:AcceptDialog
var textures:Dictionary={}
var contact_art:Dictionary={}
static var hit_images:Dictionary={}
var last_contact_count:=0
var last_fish_rub:=0
func setup(host:Node)->void:
	game=host;z_index=20
	for filename in DirAccess.get_files_at("res://assets/cat"):
		if filename.ends_with(".png"):
			var texture: Texture2D=load("res://assets/cat/"+filename)
			if texture!=null:textures[filename.trim_suffix(".png")]=texture
	for filename in DirAccess.get_files_at("res://assets/cat-contact-redraw"):
		if filename.ends_with("-hold-down-0.png"):contact_art[filename.trim_suffix("-hold-down-0.png")]=true
func _process(_delta:float)->void:
	queue_redraw()
	if game==null or game.game_audio==null:return
	var pet:RefCounted=game.world.cat
	if pet.fish_rub_serial>last_fish_rub:
		last_fish_rub=pet.fish_rub_serial
		game.game_audio.play_event("cat.meow",pet.position,pet.region,"",1,1,"cat-fish-rub:"+str(last_fish_rub))
	var count:int=0
	for value in game.world.cat.interactions.values():count+=int(value)
	if count>last_contact_count:
		last_contact_count=count
		var cat:RefCounted=game.world.cat
		game.game_audio.play_event("cat.purr",cat.position,cat.region,"",1,1,"cat-contact")
func _draw()->void:
	if game==null:return
	var cat:RefCounted=game.world.cat;cat.initialize()
	if not cat.discovered or game.view.region_id!=cat.region or not game.view.visible:return
	# The new full-body default poses already include the pet; avoid a second cat.
	for id in game.world.actors:
		var contact:Dictionary=cat.actor_poses.get(id,{})
		if cat.carrier!=id and not (contact.get("action")=="pet" and float(contact.get("until",0))>cat.clock and not game.world.work.jobs.has(id) and not game.world._routes.has(id)):continue
		var actor:Dictionary=game.world.actors[id]
		var visual:String=game.library.visual_appearance(actor)
		if int(game.library.artworks[visual].get("revision",1))==1 and contact_art.has(visual):return
	var key:String=cat.pose+"_"+cat.facing+"_"+str(int(cat.clock*3)%2)
	if not textures.has(key):return
	var p:Vector2=game.view.screen(cat.position)
	var scale_value:float=game.view.zoom*2
	if not cat.carrier.is_empty():p+=Vector2(0,-45)*game.view.zoom
	draw_texture_rect(textures[key],Rect2(p-Vector2(24,44)*game.view.zoom,Vector2(24,24)*scale_value),false)
	if cat.pose=="rub" and cat.fish_rub_serial>0:
		draw_string(game.view.font,p-Vector2(6,52)*game.view.zoom,Text.text("cat.meow"),HORIZONTAL_ALIGNMENT_LEFT,-1,14)
func _unhandled_input(event:InputEvent)->void:
	if game==null or not event is InputEventMouseButton or not event.pressed or event.button_index!=MOUSE_BUTTON_LEFT:return
	var cat:RefCounted=game.world.cat
	if not hits(game.view,event.position):return
	get_viewport().set_input_as_handled();show_menu()
func show_menu()->void:
	if is_instance_valid(menu):menu.queue_free()
	menu=AcceptDialog.new();menu.title=Text.text("cat.name");menu.ok_button_text=Text.text("cat.close");game.add_child(menu)
	var box:=VBoxContainer.new();box.custom_minimum_size.x=240;menu.add_child(box)
	for action in ["hold","pet","release"]:
		var b:=Button.new();b.focus_mode=Control.FOCUS_NONE;b.text=Text.text("cat."+action);b.custom_minimum_size.y=42;box.add_child(b)
		b.pressed.connect(func():
			if game.world.cat.interact("human",action):menu.queue_free()
			else:game.status.text=Text.text("cat.near"))
	menu.confirmed.connect(menu.queue_free);menu.close_requested.connect(menu.queue_free);menu.popup_centered()

static func hits(view:Node,mouse:Vector2)->bool:
	var cat:RefCounted=view.world.cat
	if not cat.discovered or view.region_id!=cat.region or not view.visible:return false
	if not cat.carrier.is_empty():return mouse.distance_to(view.screen(cat.position)-Vector2(0,16)*view.zoom)<=32*view.zoom
	var rect:=Rect2(view.screen(cat.position)-Vector2(24,44)*view.zoom,Vector2(48,48)*view.zoom)
	if not rect.has_point(mouse):return false
	var key:String=cat.pose+"_"+cat.facing+"_"+str(int(cat.clock*3)%2)
	if not hit_images.has(key):hit_images[key]=preload("res://scripts/bundled_image.gd").read("res://assets/cat/"+key+".png")
	var pixels:Image=hit_images[key]
	if pixels.is_empty():return false
	var at:Vector2i=Vector2i((mouse-rect.position)/(2*view.zoom))
	return pixels.get_pixelv(at).a>.1
