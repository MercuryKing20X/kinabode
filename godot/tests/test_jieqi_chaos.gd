extends SceneTree
const Rules=preload("res://scripts/jieqi_rules.gd")
const Player=preload("res://scripts/jieqi_player.gd")
const System=preload("res://scripts/jieqi_system.gd")
func _initialize() -> void:
	var failures:=0
	for seed_value in range(50):
		var state:=Rules.initial(seed_value,"chaos")
		var visible:=Rules.public_state(state)
		var mixed:=false
		var count:=[0,0,0]
		for i in range(90):
			var piece: Variant=state.board[i]
			if piece!=null and piece.hidden:
				count[piece.true_side]+=1
				if piece.true_side!=piece.side:mixed=true
				if visible.board[i].has("true_side") or visible.board[i].kind!="?":failures+=1
		if not mixed or count[1]!=15 or count[2]!=15:failures+=1
		var moves:=Rules.legal_moves(state)
		if moves.is_empty():failures+=1;continue
		var next:=Rules.move(state,moves[0][0],moves[0][1])
		var replayed:=Rules.replay(seed_value,next.history,"chaos")
		if replayed!=next:failures+=1
		var swapped:=state.duplicate(true)
		var hidden: Array=[]
		for i in range(90):
			if swapped.board[i]!=null and swapped.board[i].hidden:hidden.append(i)
		var first: Dictionary=swapped.board[hidden[0]];var second: Dictionary=swapped.board[hidden[1]]
		var old_kind: String=first.kind;var old_side: int=first.true_side
		first.kind=second.kind;first.true_side=second.true_side;second.kind=old_kind;second.true_side=old_side
		if Rules.legal_moves(state)!=Rules.legal_moves(swapped) or Rules.public_state(state)!=Rules.public_state(swapped):failures+=1
		var profiles: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/jieqi.json")).chaos_profiles
		for tag in profiles:
			if Player.choose(Rules.public_state(state),profiles[tag],seed_value)!=Player.choose(Rules.public_state(swapped),profiles[tag],seed_value):failures+=1
	var scenario:=Rules.initial(1,"chaos")
	scenario.board.fill(null)
	scenario.board[4]={"side":2,"kind":"K","cover":"K","hidden":false}
	scenario.board[85]={"side":1,"kind":"K","cover":"K","hidden":false}
	scenario.board[49]={"side":1,"true_side":2,"kind":"R","cover":"R","hidden":true}
	var cover_board: Array=scenario.board.duplicate(true);cover_board[49].kind="H"
	if not Rules.pseudo(cover_board,49,58) or Rules.pseudo(cover_board,49,60):failures+=1
	var revealed:=Rules.move(scenario,49,58)
	if revealed.is_empty() or revealed.board[58].side!=2 or revealed.winner!=2 or revealed.get("terminal_reason")!="chaos_selfcheck" or revealed.has("extra_turn"):failures+=1
	var king_capture:=Rules.move(scenario,49,4)
	if king_capture.is_empty() or king_capture.winner!=2 or king_capture.get("terminal_reason")!="chaos_selfcheck":failures+=1
	var mirrored:=Rules.initial(1,"chaos");mirrored.board.fill(null);mirrored.turn=2
	mirrored.board[4]={"side":2,"kind":"K","cover":"K","hidden":false};mirrored.board[85]={"side":1,"kind":"K","cover":"K","hidden":false}
	mirrored.board[40]={"side":2,"true_side":1,"kind":"R","cover":"R","hidden":true}
	var other:=Rules.move(mirrored,40,31)
	if other.is_empty() or other.winner!=1 or other.get("terminal_reason")!="chaos_selfcheck":failures+=1
	scenario.board[40]={"side":2,"kind":"S","cover":"S","hidden":false}
	scenario.board[48]={"side":2,"true_side":1,"kind":"H","cover":"R","hidden":true}
	var capture:=Rules.move(scenario,49,48)
	if capture.is_empty() or capture.captured.size()!=1 or capture.captured[0].side!=1 or capture.captured[0].hidden or capture.captured[0].has("true_side"):failures+=1
	scenario.board[40]=null;scenario.board[48]=null
	scenario.board[75]={"side":2,"kind":"R","cover":"R","hidden":false}
	scenario.board[77]={"side":2,"kind":"R","cover":"R","hidden":false}
	var mate:=Rules.move(scenario,49,58)
	if mate.is_empty() or mate.winner!=2 or mate.get("terminal_reason")!="chaos_selfcheck":failures+=1
	var world:=preload("res://tests/cooking_fixture.gd").fresh()
	var system:=System.new(world);system.opponent="codex";system.match_id="chaos-test";system.game=Rules.initial(314,"chaos")
	var choice: Array=Rules.legal_moves(system.game)[0];system.game=Rules.move(system.game,choice[0],choice[1]);system.phase="playing"
	var saved: Dictionary=JSON.parse_string(JSON.stringify(system.saved()))
	var restored:=System.new(world);restored.restore(saved)
	if not system.valid_saved(saved) or restored.game.board!=system.game.board or restored.game.turn!=system.game.turn or restored.game.has("extra_turn") or restored.phase!="paused" or restored.site_id!=system.site_id:failures+=1
	# Saves written before modes/site IDs remain standard and replay exactly.
	system.game=Rules.initial(15);system.phase="playing"
	var legacy:Dictionary=system.saved();legacy.erase("mode");legacy.erase("site_id")
	restored.restore(JSON.parse_string(JSON.stringify(legacy)))
	if not system.valid_saved(legacy) or restored.game.get("mode")!="standard" or restored.game.board!=system.game.board or restored.site_id!="play.gomoku":failures+=1
	legacy["mode"]="invalid"
	if system.valid_saved(legacy):failures+=1
	var old:=Rules.initial(0,"chaos",true);old=Rules.move(old,88,69)
	if not old.get("extra_turn",false):failures+=1
	system.game=old;system.terminal_reason="";system.phase="paused"
	var old_save:=system.saved();old_save.erase("rules_version")
	if not system.valid_saved(old_save):failures+=1
	restored.restore(JSON.parse_string(JSON.stringify(old_save)))
	if restored.game.get("winner")!=2 or restored.game.get("terminal_reason")!="chaos_selfcheck" or restored.game.has("extra_turn") or restored.phase!="finished":failures+=1
	var migrated:=restored.saved()
	if not restored.valid_saved(JSON.parse_string(JSON.stringify(migrated))):failures+=1
	var replies:=Rules.legal_moves(old)
	if not replies.is_empty():
		old=Rules.move(old,replies[0][0],replies[0][1]);system.game=old;old_save=system.saved();old_save.erase("rules_version")
		if not system.valid_saved(old_save):failures+=1
		restored.restore(old_save)
		if restored.game.history.size()!=1 or restored.game.winner!=2:failures+=1
	print("Jieqi chaos failures: ",failures)
	quit(1 if failures else 0)
