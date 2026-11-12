extends AcceptDialog
const Text=preload("res://scripts/localization.gd")
var game:Node
func setup(host:Node)->void:
	game=host;title=Text.text("outdoor.title");size=Vector2i(360,300)
	var col:=VBoxContainer.new();add_child(col)
	for key in ["chair","path","flowers","plot"]:
		var button:=Button.new();button.focus_mode=Control.FOCUS_NONE;button.text=Text.text("outdoor."+key);button.custom_minimum_size=Vector2(320,45);col.add_child(button)
		button.pressed.connect(func():
			game.placing_facility="outdoor-"+key
			game.status.text=Text.text("outdoor.choose")
			hide())
	close_requested.connect(queue_free);confirmed.connect(queue_free)
