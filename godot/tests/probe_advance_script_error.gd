extends SceneTree
class BrokenWishes extends "res://scripts/wish_system.gd":
	func advance(_delta:float)->void:
		var empty:Dictionary={}
		var _missing:Variant=empty.missing
class ErrorObserver extends Logger:
	var errors:=0
	func _log_error(_function:String,_file:String,_line:int,_code:String,_rationale:String,_editor_notify:bool,error_type:int,_backtraces:Array[ScriptBacktrace])->void:
		if error_type==Logger.ERROR_TYPE_SCRIPT:errors+=1
func _initialize()->void:call_deferred("run")
func run()->void:
	var world=preload("res://tests/cooking_fixture.gd").fresh()
	var observer:=ErrorObserver.new();OS.add_logger(observer)
	world.wishes=BrokenWishes.new(world)
	var before:float=world.lively.time
	world.advance(.1);world.advance(.1)
	OS.remove_logger(observer)
	print("ADVANCE_ERROR_PROBE observed=",observer.errors," lively_delta=",world.lively.time-before)
	quit()
