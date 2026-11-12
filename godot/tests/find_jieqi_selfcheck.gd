extends SceneTree
const Rules=preload("res://scripts/jieqi_rules.gd")
const Player=preload("res://scripts/jieqi_player.gd")
func _initialize() -> void:
	for seed_value in range(1000):
		var state:=Rules.initial(seed_value,"chaos")
		while state.winner==0 and not state.draw and state.history.size()<500:
			var options:=Rules.legal_moves(state)
			for option in options:
				var result:=Rules.move(state,option[0],option[1])
				if state.turn==1 and result.get("terminal_reason","")=="chaos_selfcheck":
					print(JSON.stringify({"seed":seed_value,"history":state.history,"move":option}));quit();return
			var move:=Player.choose(Rules.public_state(state),{"random":0.0,"capture":1.0},seed_value+state.history.size()*7919)
			if move.is_empty():break
			state=Rules.move(state,move[0],move[1])
	quit(1)
