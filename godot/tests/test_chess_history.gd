extends SceneTree
const Rules=preload("res://scripts/jieqi_rules.gd")
const History=preload("res://scripts/chess_history.gd")
const Player=preload("res://scripts/jieqi_player.gd")
func _initialize()->void:
	var own_seen:=false
	for mode in ["standard","chaos"]:
		for seed_value in [1,12,197]:
			var state:Dictionary=Rules.initial(seed_value,mode)
			var expected:Array=[]
			for step in range(65):
				var move:Array=Player.choose(Rules.public_state(state),{"capture":1,"random":0},seed_value+step)
				if move.is_empty():break
				var victim:Variant=state.board[move[1]]
				if victim!=null:
					var color:int=int(victim.get("true_side",victim.side))
					expected.append({"capturer":state.turn,"side":color,"kind":victim.kind,"own":color==state.turn,"hand":step+1,"from":move[1]})
					if color==state.turn:own_seen=true
				state=Rules.move(state,move[0],move[1])
			var facts:Dictionary=History.jieqi(seed_value,state.history,mode)
			assert(facts.captures==expected)
			assert(facts.captures.size()==state.captured.size())
			var restored:Dictionary=History.jieqi(seed_value,JSON.parse_string(JSON.stringify(state.history)),mode)
			assert(restored.captures==facts.captures and restored.dramatic==facts.dramatic)
	assert(own_seen)
	print("Chess history exact capturer/true color/own capture and JSON replay passed")
	quit(0)
