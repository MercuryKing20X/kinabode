extends Node
const Text=preload("res://scripts/localization.gd")
var game:Node
var button:Button
func setup(host:Node)->void:
	game=host
	var layer:=CanvasLayer.new();layer.layer=3;add_child(layer)
	button=Button.new();button.position=Vector2(18,275);button.custom_minimum_size=Vector2(150,38);button.add_theme_font_override("font",game.view.font);layer.add_child(button)
	button.pressed.connect(func():
		var panel=preload("res://scripts/outdoor_panel.gd").new();game.add_child(panel);panel.setup(game);panel.popup_centered())
func _process(_delta:float)->void:
	if game==null:return
	button.visible=game.world.actors.human.region_id=="home" and game.world.home_island.contains(game.world.point(game.world.actors.human)) and not game.world.resort.contains(game.world.point(game.world.actors.human))
	button.text=Text.text("outdoor.title")
