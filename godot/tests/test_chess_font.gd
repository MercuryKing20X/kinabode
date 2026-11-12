extends SceneTree
func _initialize()->void:
	var scope:=Control.new();root.add_child(scope)
	preload("res://scripts/chess_theme.gd").apply(scope)
	var font:Font=scope.get_theme_default_font()
	assert(font.resource_path=="res://assets/fonts/NotoSerifSC-Black.ttf")
	assert(font.get_font_name().contains("Noto Serif SC"))
	assert(font.get_font_style_name().contains("Black") or font.get_font_weight()==900)
	for kind in ["K","A","E","H","R","C","S"]:
		var glyph:String=preload("res://scripts/localization.gd").source("jieqi.piece."+kind)
		assert(font.has_char(glyph.unicode_at(0)))
	assert(font.has_char(65))
	var unrelated:=Control.new();root.add_child(unrelated)
	assert(unrelated.theme==null)
	print("Chess static Heavy font and isolated theme passed")
	quit(0)
