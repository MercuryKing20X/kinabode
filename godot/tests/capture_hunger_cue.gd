extends "res://tests/capture_route_latched.gd"
func shot(label:String)->void:
	game.view.queue_redraw();await process_frame;RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
func run()->void:
	output=OS.get_environment("HABITAT_DARK_EVIDENCE");assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"));root.size=Vector2i(1280,800)
	game=UI.init_game(self);await process_frame;await process_frame
	var w:RefCounted=game.world;var audio:Node=game.game_audio
	audio.mute_unfocused=false;audio.enabled=true;audio.focused=true
	var id:String="codex";var events:Array=[]
	for rank in [1,2,3]:
		w.hunger.ensure(id);w.hunger.states[id].elapsed=[240,600,1600][rank-1]
		game.view.center=w.point(w.actors[id]);game.view.follow_player=false;game.view.zoom=1.25
		var before:float=audio.clock
		for frame in range(1200):
			game.view._process(.1);audio.advance(.1);await process_frame
			if game.view.hunger_symbols.has(id) and game.view.hunger_symbols[id]>game.view.clock:break
		var sounded:bool=audio.trace.filter(func(e):return float(e.get("time",-1))>before).any(func(e):return e.get("action")=="scheduled" and str(e.get("event","")).begins_with("hunger.") and e.get("actor")==id)
		var symbol:bool=game.view.hunger_symbols.has(id) and game.view.hunger_symbols[id]>game.view.clock
		if sounded or not symbol:failed=true
		events.append_array(audio.trace.filter(func(e):return float(e.get("time",-1))>before and str(e.get("event","")).begins_with("hunger.")))
		await shot("hunger-rank-"+str(rank))
		records.append({"rank":rank,"sound":sounded,"symbol_same_frame":symbol,"clock":audio.clock})
		for frame in range(20):game.view._process(.1);audio.advance(.1);await process_frame
	game.view.center=w.point(w.actors[id])+Vector2(100,0)
	var before:float=audio.clock
	for frame in range(1000):game.view._process(.1);audio.advance(.1);await process_frame
	var offscreen:int=audio.trace.filter(func(e):return float(e.get("time",-1))>before).filter(func(e):return e.get("action")=="scheduled" and str(e.get("event","")).begins_with("hunger.") and e.get("actor")==id).size()
	if offscreen!=0:failed=true
	records.append({"offscreen_scheduled":offscreen})
	FileAccess.open(output.path_join("sound-events.json"),FileAccess.WRITE).store_string(JSON.stringify(events,"  "));FileAccess.open(output.path_join("cue-results.json"),FileAccess.WRITE).store_string(JSON.stringify(records,"  "));print(JSON.stringify(records));game.queue_free();await process_frame;quit(1 if failed else 0)
