class_name FarmRenderer
extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
var food_textures:Dictionary={}
const Layout = preload("res://scripts/home_layout.gd")

func ground(view: Node2D) -> void:
	if view.has_method("use_cached_farm_ground") and view.use_cached_farm_ground():
		view.draw_cached_farm_ground();extras(view);return
	for farm in view.world.farms.farms.values():
		if not view.world.farms.ready(farm.id) or farm.get("raised_bed",false):continue
		var rect: Rect2 = view.world.catalog.rectangle(farm.rect)
		view._surface(Layout.rectangle(rect.grow(.45),.35),view.textures.sand,Color("d8c69e"))
		view._surface(Layout.rectangle(rect.grow(-.25),.2),view.textures.soil,Color("b4a082"))
		view._path(Layout.points(farm.road),.5)
		for plot in view.world.farms.farm_plots(farm.id):
			var point: Vector2 = view.world.point(plot)
			var bed: Rect2 = view.world.farms.bed(plot)
			view._surface(Layout.rectangle(bed,.09),view.textures.soil,Color("a89b7c") if plot.watered else Color("c3aa83"))
			for row in range(4):
				view.draw_line(view.screen(point+Vector2(-1.12,.8-row*.5)),view.screen(point+Vector2(1.12,.8-row*.5)),Color(.24,.14,.08,.33),1.5*view.zoom)
		# Narrow joined paths; all gardens use the same row spacing.
		for column in range(3):
			var x: float = float(farm.first[0]) + column*2.8 + 1.4
			view._path(PackedVector2Array([Vector2(x,rect.position.y+.25),Vector2(x,rect.end.y-.25)]),.09)
		for row in range(2):
			var y: float = float(farm.first[1]) + row*2.4 + 1.2
			view._path(PackedVector2Array([Vector2(rect.position.x+.25,y),Vector2(rect.end.x-.25,y)]),.09)
	if not view.get("baking_world"):extras(view)

func extras(view:Node2D)->void:
	for farm in view.world.farms.farms.values():
		if not view.world.farms.ready(farm.id):continue
		var rect:Rect2=view.world.catalog.rectangle(farm.rect)
		if view.world.farms.farm_plots(farm.id).all(func(plot):return plot.crop_id.is_empty()):empty_sign(view,farm)
		if farm.get("raised_bed",false):continue
		var at := Vector2(farm.seed_at[0],farm.seed_at[1])
		view._sprite("barrel", at+Vector2(-2,0),.5)
		view._sprite("picnic", Vector2(farm.meeting_at[0],farm.meeting_at[1]),.52)
		for i in range(mini(8,int(farm.flowers)/2)):
			view._sprite("flowers",rect.position+Vector2(1+i*1.6,rect.size.y-.3),.48)
		for job in view.world.work.jobs.values():
			if job.get("farm_id") == farm.id and job.get("step") == "enjoying": view._sprite("meal",Vector2(farm.meeting_at[0],farm.meeting_at[1]),.65)
		if view.has_method("map_label"):view.map_label(farm.name,view.world.catalog.rectangle(farm.rect).position+Vector2(farm.rect[2]/2,-3.5))
		else:
			var label: String = LocalText.content(farm.name)
			var width: float = view.font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x
			var p: Vector2 = view.screen(rect.position+Vector2(rect.size.x/2,-3.0))-Vector2(width/2,0)
			view.draw_string_outline(view.font,p,label,HORIZONTAL_ALIGNMENT_LEFT,-1,16,4,Color("293f31"))
			view.draw_string(view.font,p,label,HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("ffe9bc"))

func entries(view: Node2D, list: Array) -> void:
	for plot in view.world.farms.plots.values():
		if not view.world.farms.ready(plot.farm_id):continue
		list.append({"type":"crop","value":plot,"y":plot.position[1]})

func draw_entry(view: Node2D, entry: Dictionary) -> void:
	var object: Dictionary = entry.value
	var point: Vector2 = view.world.point(object)
	var stage: String = view.world.farms.stage(object)
	if stage!="empty" and object.crop_id in ["potato","corn"]:
		var frame:String="seedling" if stage=="dry" else stage
		var path:String="res://assets/island-food/"+str(object.crop_id)+"-"+frame+".png"
		if ResourceLoader.exists(path):
			if not food_textures.has(path):food_textures[path]=load(path)
			for offset in ([Vector2.ZERO] if view.world.farms.farms[object.farm_id].get("raised_bed",false) else [Vector2(-.62,-.05),Vector2(.62,-.05),Vector2(0,.9)]):
				view.draw_texture_rect(food_textures[path],Rect2(view.screen(point+offset)-Vector2(32,70)*view.zoom*.72,Vector2(64,72)*view.zoom*.72),false)
	elif stage != "empty":
		var art_id: String = view.world.farms.crops[object.crop_id].art
		if view.library.artworks.has(art_id):
			var art: Dictionary = view.library.artworks[art_id]
			var frame := "seedling" if stage=="dry" else stage
			var scale_value := .62 if object.crop_id == "apple" else .82 if object.crop_id == "blueberry" else .72
			var offsets: Array = [Vector2.ZERO] if view.world.farms.farms[object.farm_id].get("raised_bed",false) else [Vector2(0,.65)] if object.crop_id in ["apple","blueberry"] else [Vector2(-.62,-.05),Vector2(.62,-.05),Vector2(0,.9)]
			for offset in offsets:
				var p: Vector2 = view.screen(point+offset)
				view.draw_set_transform(p,sin(view.clock*1.6+point.x)*.014)
				view.draw_texture_rect(view.library.texture(art_id,frame),Rect2(-Vector2(art.anchor[0],art.anchor[1])*view.zoom*scale_value,Vector2(art.width,art.height)*view.zoom*scale_value),false)
				view.draw_set_transform(Vector2.ZERO)
		if stage == "dry": view.draw_circle(view.screen(point)+Vector2(20,-24)*view.zoom,4*view.zoom,Color("91d0e7"))
	for actor_id in view.world.work.jobs:
		var job: Dictionary = view.world.work.jobs[actor_id]
		if job.get("target_id") == object.id and view.world.actors[actor_id].activity == "watering":
			for n in range(7):
				var t := fmod(view.clock*1.8+n*.16,1.0)
				var drop: Vector2 = view.screen(point) + Vector2(sin(n*2.5)*18, -28+30*t)*view.zoom
				view.draw_line(drop,drop+Vector2(-2,4)*view.zoom,Color(.52,.85,.95,1.0-t*.6),2*view.zoom)
	if object.id in [view.hover_id,view.selected_id]:
		view.draw_arc(view.screen(point),32*view.zoom,0,TAU,32,Color("ffe6a7"),2,true)

func hit(view: Node2D, mouse: Vector2) -> String:
	var local: Vector2 = view.local_point(mouse)
	for plot in view.world.farms.plots.values():
		if not view.world.farms.ready(plot.farm_id):continue
		if view.world.farms.bed(plot).has_point(local): return plot.id
	return ""

func empty_sign(view:Node2D,farm:Dictionary)->void:
	var at:Vector2=view.screen(Vector2(float(farm.rect[0])-2.5,float(farm.rect[1])+float(farm.rect[3])*.5))
	var label:String=LocalText.text("ingredients.empty")
	var font_size:int=clampi(roundi(12*view.zoom),8,16)
	var width:float=view.font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	var extent:=Vector2((width+16)/.75,70*view.zoom)
	view.draw_texture_rect(preload("res://scripts/home_island_renderer.gd").decoration("sign"),Rect2(at-Vector2(extent.x/2,extent.y),extent),false)
	view.draw_string(view.font,at+Vector2(-width/2,-extent.y*.65),label,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color("fff4db"))
