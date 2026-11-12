extends SceneTree
## Test-only simulation switch. Production read API and world rules are unchanged.
class FixtureControl extends Node:
	var game:Node
	var directory:=""
	var serial:=-1
	func _process(_delta:float)->void:
		var path:String=directory.path_join("fixture-simulation.json")
		if not FileAccess.file_exists(path):return
		var request:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
		if not request is Dictionary or not request.get("freeze") is bool or not request.get("serial") is float and not request.get("serial") is int:return
		if int(request.serial)==serial:return
		serial=int(request.serial);game.set_process(not request.freeze)
		var file:=FileAccess.open(directory.path_join("fixture-simulation-ack.json.tmp"),FileAccess.WRITE)
		file.store_string(JSON.stringify({"serial":serial,"freeze":request.freeze,"revision":game.world.revision}));file.close()
		DirAccess.rename_absolute(directory.path_join("fixture-simulation-ack.json.tmp"),directory.path_join("fixture-simulation-ack.json"))
func _initialize()->void:run.call_deferred()
func run()->void:
	var directory:String=OS.get_environment("HABITAT_DATA_DIR")
	assert(directory.contains("youqi-"))
	var control:=FixtureControl.new();control.directory=directory;root.add_child(control)
	var game:Node=load("res://scenes/main_v3.tscn").instantiate();control.game=game;root.add_child(game)
	game.save_enabled=false
