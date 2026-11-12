extends "res://tests/test_intelligence_core_input.gd"
func run()->void:
	await fresh()
	var w:RefCounted=game.world
	var failures:Dictionary={};var chosen:=Vector2.INF
	for y in range(4,124,2):
		for x in range(4,156,2):
			var at:=Vector2(x+.5,y+.5)
			var validation:Dictionary=w.leisure.validate_place("play-gomoku",at)
			if not validation.ok:
				var why:String=str(validation.get("error","unknown"));failures[why]=int(failures.get(why,0))+1;continue
			chosen=at;break
		if chosen.is_finite():break
		await process_frame
	print("CHESS_SPACE ",chosen," ",JSON.stringify(failures)," home ",JSON.stringify(w.catalog.regions.home))
	game.queue_free();await process_frame;quit()
