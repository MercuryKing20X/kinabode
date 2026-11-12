extends "res://scripts/main.gd"
## Isolated input comparison fixture, not an old binary. Only camera delta scales.
var test_pan_factor:=1.0
func _pan_camera(direction:Vector2,delta:float)->void:
	super._pan_camera(direction,delta*test_pan_factor)
