extends "res://tests/test_dialogue_bar_input.gd"
func run()->void:
	OS.set_environment("HABITAT_OPENING","showcase")
	var game:Node=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false)
	root.size=Vector2i(1280,800);await frames()
	# Actual mouse selector, not a direct start masquerading as UI input.
	await UI.click(self,game.dialogue_button);await UI.tab(self,game.action_dock.action_tabs,1)
	var entries:Array=UI.descendants(game.watch_ui.menu_column).filter(func(n):return n is Button and n.text==preload("res://scripts/localization.gd").text("play.choose"))
	await UI.reveal(self,entries[0]);check(await UI.click(self,entries[0]),"real selector click")
	var cards:Array=game.get_children().filter(func(n):return n.has_meta("play_selector"))
	var buttons:Array=UI.descendants(cards[0]).filter(func(n):return n.get_meta("play_kind","")=="rope")
	check(await UI.click(self,buttons[0]),"real rope input")
	game.chat.hide();game.view.follow_player=false;game.view.center=game.playground.anchor;game.view.zoom=1.2
	var frames_api=preload("res://scripts/play_frames.gd").new()
	for id in ["human","codex","companion-2","npc.mira","npc.nora"]:
		for column in range(27):check(frames_api.texture(game.library,game.world.actors[id],column)!=null,"authored frame "+id+" "+str(column))
	var captured:=false;var counted:=false;var tripped:=false
	for tick in range(1201):
		game.world.advance(.1);game.playground.tick(.1)
		if game.playground.kind.is_empty():break
		var phase:float=fposmod(game.playground.rope_time,1.6)/1.6
		if game.playground.rope_count>=2 and not counted:
			await frames(2);await capture("rope-count");counted=true
		if phase>.48 and phase<.58 and game.playground.rope_time>1 and not captured:
			await frames(2);await capture("rope-air-hands");captured=true
			var pixels:Image=root.get_texture().get_image()
			for key in ["a","b"]:
				var at:Array=game.playground.render_probe[key]
				var color:Color=pixels.get_pixel(int(at[0]),int(at[1]))
				check(Vector3(color.r,color.g,color.b).distance_to(Vector3(.953,.827,.604))<.2,"visible rope hand endpoint "+key)
		if game.playground.rope_pause>0 and not tripped:
			await frames(2);await capture("rope-trip");tripped=true
	check(game.playground.completed.any(func(e):return e.game=="rope"),"rope completes by 120")
	check(game.playground.rope_swaps>0,"real trip rotates roles")
	check(game.playground.rope_counts.size()>=5,"counted actual rope crossings")
	# Settled idle life, real World roll route, retain before/after coordinates.
	game.world.activities.set_followers(game.steward.Pool.IDS)
	for tick in range(900):game.world.advance(.1);game.playground.tick(.1)
	var rolls:Array=[];var seen_lie:=false
	for tick in range(3000):
		game.world.advance(.1);game.playground.tick(.1)
		for id in game.playground.nearby:
			var state:Dictionary=game.playground.nearby[id]
			if state.action=="play_roll" and state.has("roll_start") and Vector2(state.roll_start).distance_to(game.world.point(game.world.actors[id]))>1.5 and rolls.is_empty():
				rolls.append({"id":id,"from":[state.roll_start.x,state.roll_start.y],"to":game.world.actors[id].position.duplicate()});game.view.center=game.world.point(game.world.actors[id]);await frames(2);await capture("idle-roll")
			if state.action=="play_lie" and float(state.get("age",0))>float(state.get("duration",1))*.3 and not seen_lie:game.view.center=game.world.point(game.world.actors[id]);await frames(2);await capture("idle-lie");seen_lie=true
		if seen_lie and not rolls.is_empty():break
	check(seen_lie,"real idle lie")
	check(not rolls.is_empty(),"real roll translates through World")
	var file:=FileAccess.open(OS.get_environment("HABITAT_UI_EVIDENCE").path_join("result.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failed":failed,"rolls":rolls,"swaps":game.playground.rope_swaps,"counts":game.playground.rope_counts}));file.close()
	print("REWORK ",checks," failed=",failed);game.queue_free();await frames();quit(1 if failed else 0)
