extends SceneTree
const World=preload("res://scripts/world_state.gd")
const Save=preload("res://scripts/save_store.gd")
var wall:float
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("CLOCK ",label," ",ok)
	if not ok:failures+=1
func run()->void:
	var dir:String=OS.get_environment("HABITAT_DATA_DIR")
	if not dir.contains("youqi-test-"):quit(2);return
	var w:=World.new()
	w.director.set_all_enabled(false)
	var start:float=w.forest.clock
	wall=start
	w.forest.wall_time=func():return wall
	var start_day:int=w.days.day()
	wall+=42180
	w.advance(.25)
	check(w.days.day()==start_day and is_equal_approx(w.forest.clock-start,.25),"a forward system jump never advances the game day")
	wall-=84000
	w.advance(.75)
	check(w.days.day()==start_day and is_equal_approx(w.forest.clock-start,1.0),"a backward system jump does not rewind")
	var before:float=w.forest.clock
	var written_wall:float=wall
	check(Save.save_world(w,dir),"writes schema-7 with a separate wall anchor")
	var restored:=World.new()
	restored.forest.wall_time=func():return wall
	wall=written_wall-30
	check(Save.load_world(restored,dir).ok and is_equal_approx(restored.forest.clock-before,0.0),"loading a negative offline interval adds nothing")
	wall=written_wall+45
	check(Save.load_world(restored,dir).ok and is_equal_approx(restored.forest.clock-before,45.0),"loading counts actual time away exactly once")
	quit(1 if failures else 0)
