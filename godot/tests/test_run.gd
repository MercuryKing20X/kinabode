extends SceneTree
const World = preload("res://scripts/world_state.gd")
const Save = preload("res://scripts/save_store.gd")
class GestureView extends "res://scripts/island_view.gd":
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func hit(_mouse: Vector2) -> String: return ""
	# This gesture-only view intentionally has no rendering/font setup.
	func speech_layout() -> Array: return []
	func local_point(_point: Vector2) -> Vector2: return Vector2.ZERO
var checks := 0
var failed := false
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failed = true; push_error(message)
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"): quit(1); return
	var world := World.new()
	var start: Vector2 = world.point(world.actors.human)
	var route: Array[Vector2] = [start + Vector2(12, 0)]
	world._apply_route("human", route)
	check(not world.is_running("human"), "12 tiles walks")
	world._apply_route("human", [start + Vector2(12.01, 0)])
	check(world.is_running("human"), "more than 12 tiles runs")
	world.advance(.1)
	check(is_equal_approx(world.point(world.actors.human).x - start.x, World.RUN_SPEED * .1), "real advance uses run speed")
	check(world.is_running("human"), "route stays running after remaining distance drops below 12")
	start = world.point(world.actors.human)
	world._apply_route("human", [start + Vector2(20, 0)])
	world.actors.human.carry = {"wood": 1}
	check(not world.is_running("human"), "carrying prevents running")
	world.actors.human.carry = {}
	world.work.jobs.human = {"intent":"test"}
	check(not world.is_running("human"), "accepted work immediately prevents running")
	world.work.jobs.erase("human")
	check(world.is_running("human"), "running resumes when unladen and idle")
	# C: The threshold/loaded/work assertions above exercise the unchanged human
	# branch. Partners retain their prior authorized default run presentation.
	world._apply_route("codex", [world.point(world.actors.codex)+Vector2(1,0)])
	check(world.is_running("codex"),"partner default short route displays running")
	world.actors.codex.carry={"wood":1}
	check(world.is_running("codex") and is_equal_approx(world.movement_speed("codex"),World.CARRY_SPEED),"partner loaded run display preserves exact original125px/s")
	world.actors.codex.carry={};world._routes.erase("codex")
	world._apply_route("human", [world.point(world.actors.human) + Vector2(1,0)])
	check(not world.is_running("human"), "short human route walks")
	world.force_human_run()
	check(world.is_running("human"), "explicit human gesture forces short run")
	world._apply_route("human", [world.point(world.actors.human) + Vector2(1,0)])
	check(not world.is_running("human"), "new route clears force")
	var view := GestureView.new()
	view.world = world
	root.add_child(view)
	view.clicked.connect(func(_id, _point):
		world._apply_route("human", [world.point(world.actors.human) + Vector2(1, 0)])
		if view.run_click: world.force_human_run())
	var click := InputEventMouseButton.new()
	click.pressed = true; click.button_index = MOUSE_BUTTON_LEFT; click.shift_pressed = true
	view._unhandled_input(click)
	check(world.is_running("human"), "shift click forces run through real view signal")
	click.shift_pressed = false; click.double_click = true
	view._unhandled_input(click)
	check(world.is_running("human"), "double click forces run through real view signal")
	click.double_click = false
	view._unhandled_input(click)
	check(not world.is_running("human"), "ordinary short click does not force run")
	view.queue_free()
	var another := World.new()
	check(not another.is_running("human"), "new world has no saved run")
	var directory := OS.get_environment("HABITAT_DATA_DIR")
	world._apply_route("human", [world.point(world.actors.human) + Vector2(1,0)])
	world.force_human_run()
	check(Save.save_world(world, directory), "save while force is active")
	check(Save.load_world(world, directory).ok and world._forced_runs.is_empty() and world._routes.is_empty(), "reload clears force and routes")
	check(is_equal_approx(World.RUN_SPEED * 32, 260.0), "run speed is 260 pixels per second")
	print("Distance running: %s checks, %s" % [checks, "FAIL" if failed else "PASS"])
	quit(1 if failed else 0)
