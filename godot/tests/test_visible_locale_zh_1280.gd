extends "res://tests/test_visible_locale_input.gd"
func _initialize()->void:
	audit_size=Vector2i(1280,800);audit_locale="zh_CN";call_deferred("run")
