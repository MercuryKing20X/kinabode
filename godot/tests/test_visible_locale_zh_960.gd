extends "res://tests/test_visible_locale_input.gd"
func _initialize()->void:
	audit_size=Vector2i(960,640);audit_locale="zh_CN";audit_opening="showcase";call_deferred("run")
