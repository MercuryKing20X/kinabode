extends RefCounted

static func apply(control: Control) -> void:
	var theme := Theme.new()
	theme.default_font_size = 16
	theme.default_font = preload("res://assets/fonts/NotoSerifSC-Black.ttf")
	theme.set_color("font_outline_color","Label",Color(0.06,0.08,0.07,0.95))
	theme.set_constant("outline_size","Label",2)
	control.theme = theme
	control.add_theme_font_size_override("font_size",16)
