extends SceneTree
const Rules=preload("res://scripts/jieqi_rules.gd")
const System=preload("res://scripts/jieqi_system.gd")
var failures:=0
func check(value: bool,label: String) -> void:
	if not value:failures+=1;push_error(label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var dir:=OS.get_environment("HABITAT_DATA_DIR")
	if not dir.contains("youqi-test-"):quit(1);return
	var world:=preload("res://tests/cooking_fixture.gd").fresh()
	var system:=System.new(world);system.opponent="codex";system.match_id="jieqi-test";system.game=Rules.initial(15)
	var move: Array=Rules.legal_moves(system.game)[0];system.game=Rules.move(system.game,move[0],move[1]);system.phase="playing"
	var saved:=system.saved();check(system.valid_saved(saved),"active state valid")
	var next:=System.new(world);next.restore(JSON.parse_string(JSON.stringify(saved)))
	check(next.game.board==system.game.board and next.game.turn==system.game.turn and next.phase=="paused","JSON round trip exact board and reload paused")
	var tampered:=saved.duplicate(true);tampered.winner=1
	check(not next.valid_saved(tampered),"invented winner without terminal reason rejected")
	tampered=saved.duplicate(true);tampered.history.append([0,89]);check(not next.valid_saved(tampered),"illegal replay rejected")
	system.resign();check(system.valid_saved(system.saved()) and system.game.winner==2,"explicit resignation saves")
	next.restore(JSON.parse_string(JSON.stringify(system.saved())))
	check(next.phase=="finished" and next.game.winner==2,"finished save restores finished so Start can open a new game instead of attempting forbidden resume")
	var remaining:=System.new(world);remaining.restore({});check(remaining.game.is_empty(),"legacy absent state empty")
	print("Jieqi save failures: ",failures);quit(1 if failures else 0)
