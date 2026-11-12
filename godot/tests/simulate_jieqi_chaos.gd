extends SceneTree
const Rules=preload("res://scripts/jieqi_rules.gd")
const Player=preload("res://scripts/jieqi_player.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-"):quit(1);return
	var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/jieqi.json"))
	var results: Dictionary={}
	var count:=int(OS.get_environment("JIEQI_GAMES"));if count<=0:count=200
	for tag in config.chaos_profiles:
		if not OS.get_environment("JIEQI_PROFILE").is_empty() and tag!=OS.get_environment("JIEQI_PROFILE"):continue
		var wins:=0;var losses:=0;var draws:=0;var unfinished:=0
		for round_index in range(count):
			var seed_value: int=round_index*104729+197
			var game:=Rules.initial(seed_value,"chaos")
			while game.winner==0 and not game.draw and game.history.size()<4096:
				var profile: Dictionary={"random":0.0,"capture":1.0,"forward":0.0,"reveal":0.0} if game.turn==1 else config.chaos_profiles[tag]
				var move:=Player.choose(Rules.public_state(game),profile,seed_value+game.history.size()*7919)
				if move.is_empty():break
				game=Rules.move(game,move[0],move[1])
			if game.winner==1:wins+=1
			elif game.winner==2:losses+=1
			elif game.draw:draws+=1
			else:unfinished+=1
			if round_index%10==0:print(tag," ",round_index," / ",count);await process_frame
		results[tag]={"games":count,"player_wins":wins,"partner_wins":losses,"draws":draws,"unfinished":unfinished,"player_win_rate":float(wins)/count}
		print(tag,": ",results[tag])
	var file:=FileAccess.open(OS.get_environment("HABITAT_DATA_DIR").path_join("jieqi-simulation.json"),FileAccess.WRITE);file.store_string(JSON.stringify(results,"  "));file.close()
	quit(0)
