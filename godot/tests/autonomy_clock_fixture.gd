extends "res://scripts/autonomy_scheduler.gd"
## Daily-total tests start at local noon; explicit advance still crosses actual days.
var clock_origin:=0.0
var noon:=0.0
func anchor(source:RefCounted)->void:
	clock_origin=source.forest.clock
	noon=43200.0 # Stable historical noon avoids ConfigFile large-float formatting.
func now()->float:return floor(noon+world.forest.clock-clock_origin)
