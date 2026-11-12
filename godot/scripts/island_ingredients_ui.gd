extends Node2D
## Nearby host button; world collection itself revalidates arrival and availability.
var icon_cache:Dictionary={}
var game:Node
var button:Button
var selection:=""
var dry_button:Button
func setup(host:Node)->void:
	game=host
	var layer:=CanvasLayer.new();layer.layer=3;add_child(layer)
	button=Button.new();button.add_theme_font_override("font",game.view.font);button.position=Vector2(18,244);layer.add_child(button)
	dry_button=Button.new();dry_button.add_theme_font_override("font",game.view.font);dry_button.position=Vector2(18,362);layer.add_child(dry_button);dry_button.pressed.connect(func():game.world.ingredients.dry_fish())
	button.pressed.connect(func():
		var result:Dictionary=game.world.ingredients.begin(selection)
		if not result.ok:game.status.text=str(result.get("error","")))
func _process(_delta:float)->void:
	if game==null or game.world==null:return
	dry_button.text=preload("res://scripts/localization.gd").text("ingredients.dry")
	dry_button.visible=game.world.actors.human.region_id=="home" and game.world.point(game.world.actors.human).distance_to(game.world.ingredients.dry_position())<3
	selection="";var distance:=10.0
	for item in game.world.ingredients.sources():
		if not game.world.ingredients.available(item):continue
		var d:float=game.world.point(game.world.actors.human).distance_to(Vector2(item.position[0],item.position[1]))
		if d<distance:
			distance=d;selection=item.id
			button.text=preload("res://scripts/localization.gd").text("ingredients.collect")%preload("res://scripts/localization.gd").content(str(item.name))
	button.visible=not selection.is_empty() and game.view.region_id==game.world.actors.human.region_id
	queue_redraw()
func _draw()->void:
	if game==null or game.world==null:return
	for item in game.world.ingredients.sources():
		if item.region!=game.view.region_id or not game.world.ingredients.visible(item):continue
		var at:Vector2=game.view.screen(Vector2(item.position[0],item.position[1]))
		if not get_viewport_rect().grow(20).has_point(at):continue
		if item.has("icon_crop"):
			var crop:Dictionary=game.world.farms.crops.get(str(item.icon_crop),{})
			if not crop.is_empty():
				draw_texture_rect(game.world.library.texture(str(crop.art),"seedling"),Rect2(at-Vector2(18,32),Vector2(36,36)),false);continue
		var texture_path:String="res://assets/island-food/"+str(item.id)+".png"
		if ResourceLoader.exists(texture_path):
			if not icon_cache.has(texture_path):icon_cache[texture_path]=load(texture_path)
			draw_texture_rect(icon_cache[texture_path],Rect2(at-Vector2(18,32),Vector2(36,36)),false);continue
		var color:=Color("b1d778") if game.world.ingredients.available(item) else Color("73654b")
		draw_rect(Rect2(at-Vector2(5,8),Vector2(10,8)),color)
		draw_rect(Rect2(at-Vector2(2,12),Vector2(4,4)),Color("437747"))
