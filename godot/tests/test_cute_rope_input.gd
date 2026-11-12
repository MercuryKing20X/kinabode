extends "res://tests/test_dialogue_bar_input.gd"
func run()->void:
	seed(20261110)
	OS.set_environment("HABITAT_OPENING","showcase")
	var game:Node=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false)
	root.size=Vector2i(1280,800);await frames()
	await UI.click(self,game.dialogue_button);await UI.tab(self,game.action_dock.action_tabs,1)
	var entries:Array=UI.descendants(game.watch_ui.menu_column).filter(func(n):return n is Button and n.text==preload("res://scripts/localization.gd").text("play.choose"))
	await UI.reveal(self,entries[0]);check(await UI.click(self,entries[0]),"mouse opens game chooser")
	var cards:Array=game.get_children().filter(func(n):return n.has_meta("play_selector"))
	var buttons:Array=UI.descendants(cards[0]).filter(func(n):return n.get_meta("play_kind","")=="rope")
	check(await UI.click(self,buttons[0]),"mouse starts double rope")
	game.chat.hide();game.view.follow_player=false;game.view.center=game.playground.anchor;game.view.zoom=1.5
	var api=preload("res://scripts/play_frames.gd").new()
	for id in ["human","codex","companion-2","npc.mira","npc.nora"]:
		for col in range(27,35):check(api.texture(game.library,game.world.actors[id],col)!=null,"new frame "+id+" "+str(col))
	var upper:=false;var lower:=false;var trip:=false;var gap:=0.0
	for tick in range(1201):
		game.world.advance(.1);game.playground.tick(.1)
		if game.playground.kind.is_empty():break
		var phase:float=fposmod(game.playground.rope_time,1.6)/1.6
		if game.playground.rope_time<1:continue
		var ids:Array=game.playground.rope_roles()
		if phase<.1 and not upper:await frames(2);await capture("rope-overhead");upper=true
		if phase>.48 and phase<.58 and game.playground.rope_pause<=0 and not lower:
			await frames(2);await capture("rope-two-air")
			gap=game.world.point(game.world.actors[ids[0]]).distance_to(game.world.point(game.world.actors[ids[1]]))
			check(gap>=6 and gap<=8,"turners 6-8 tiles apart")
			check(absf(game.world.point(game.world.actors[ids[2]]).distance_to(game.world.point(game.world.actors[ids[3]]))-1)<.1,"jumpers one tile apart")
			for id in ids.slice(2,4):
				check(game.view.motion.play_poses[id]=="play_jump","both jumping "+id)
				var pose:Dictionary=game.view.motion.pose(game.world.actors[id],{},game.world.actors)
				check(float(pose.get("play_lift",0))<=-19,"both physically lifted "+id)
			var pixels:Image=root.get_texture().get_image()
			for key in ["a","b"]:
				var at:Array=game.playground.render_probe[key]
				var color:Color=pixels.get_pixel(int(at[0]),int(at[1]))
				check(Vector3(color.r,color.g,color.b).distance_to(Vector3(1,.878,.541))<.2,"visible hand endpoint "+key)
			lower=true
		if game.playground.rope_pause>0 and not trip:await frames(2);await capture("rope-trip");trip=true
	check(game.playground.completed.any(func(e):return e.game=="rope"),"120 second finish")
	check(game.playground.rope_swaps>0,"both pairs rotate on trip")
	check(upper and lower and trip,"three rope views captured")
	# Fresh world and natural approach; no player save or position edits.
	var swaps:int=game.playground.rope_swaps
	game.queue_free();await frames();game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false);await frames()
	game.world.activities.set_followers(game.steward.Pool.IDS)
	for tick in range(1200):
		game.world.advance(.1);game.playground.tick(.1)
		if game.steward.Pool.IDS.all(func(id):return game.world.point(game.world.actors[id]).distance_to(game.world.point(game.world.actors.human))<6):break
	game.playground.cute_counts.clear();game.playground.cute_events.clear()
	var rolls:=0;var cute_shot:=false;var best_clearance:=-1.0
	for tick in range(3000):
		game.world.advance(.1);game.playground.tick(.1)
		for id in game.playground.nearby:
			var state:Dictionary=game.playground.nearby[id]
			if state.action=="play_roll":rolls+=1
			if state.action=="play_cute" and game.view.motion.play_poses.get(id)=="play_cute" :
				var phase:float=float(game.view.motion.play_phases.get(id,0))
				if phase>.4 and phase<.55:
					var clearance:=100.0
					for other in game.world.actors:
						if other!=id:clearance=minf(clearance,game.world.point(game.world.actors[id]).distance_to(game.world.point(game.world.actors[other])))
					if clearance<=best_clearance:continue
					best_clearance=clearance
					game.view.follow_player=false;game.view.center=game.world.point(game.world.actors[id]);game.view.zoom=1.5;await frames(2);await capture("nearby-cute");cute_shot=true
	check(rolls==0,"five minutes zero rolls")
	check(cute_shot,"natural cute jump visible")
	var counts:Dictionary=game.playground.cute_counts.duplicate()
	check(int(counts.get("companion-2",0))>int(counts.get("npc.nora",0)),"lively jumps more than quiet")
	var file:=FileAccess.open(OS.get_environment("HABITAT_UI_EVIDENCE").path_join("result.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failed":failed,"turner_gap":gap,"swaps":swaps,"roll_ticks":rolls,"cute_counts_300s":counts,"cute_events":game.playground.cute_events}));file.close()
	print("CUTE_ROPE ",checks," failed=",failed);game.queue_free();await frames();quit(1 if failed else 0)
