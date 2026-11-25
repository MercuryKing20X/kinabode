extends "res://tests/test_dialogue_bar_input.gd"
func run()->void:
	OS.set_environment("HABITAT_OPENING","showcase")
	var game:Node=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false);game.world.director.set_all_enabled(false)
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO;await frames()
	game.world.activities.release_follow("companion-2")
	var work:Dictionary=game.world.host_text_command("companion-2",{"intent":"gather_wood","tree_count":1})
	check(work.get("ok",false) and game.world.work.jobs.has("companion-2"),"real labor accepted before play")
	var job:Dictionary=game.world.work.jobs.get("companion-2",{}).duplicate(true)
	var offered:Dictionary=game.playground.start("hide")
	check(offered.get("ok",false) and "companion-2" not in game.playground.members,"busy worker excluded from play")
	check(game.world.work.jobs.get("companion-2",{})==job,"play does not interrupt worker")
	game.playground.stop();game.world.command("companion-2",{"intent":"stop"})
	# B: DIRECTION 2026-11-18「保留捉迷藏、踢毽子、跳绳和夜里节目」。
	for kind in ["hide","fireflies","circle","shuttlecock","rope"]:
		if not game.chat.visible:await UI.click(self,game.dialogue_button)
		await UI.tab(self,game.action_dock.action_tabs,1)
		var entries:Array=UI.descendants(game.watch_ui.menu_column).filter(func(n):return n is Button and n.text==preload("res://scripts/localization.gd").text("play.choose"))
		check(entries.size()==1,"one play entry")
		await UI.reveal(self,entries[0]);check(await UI.click(self,entries[0]),"real play selector")
		await frames()
		var cards:Array=game.get_children().filter(func(n):return n.has_meta("play_selector"))
		check(cards.size()==1,"selector shown")
		var controls:Array=UI.descendants(cards[0])
		if kind=="hide":
			var join:Array=controls.filter(func(n):return n.has_meta("play_join"));check(await UI.click(self,join[0]),"real join choice")
		var buttons:Array=controls.filter(func(n):return n.get_meta("play_kind","")==kind)
		check(await UI.click(self,buttons[0]),"real game choice "+kind);await frames()
		check(game.playground.kind==kind,"game accepted "+kind)
		if kind=="hide":check("human" in game.playground.members,"human joins only explicit UI")
		game.chat.hide();game.view.follow_player=false;game.view.center=game.playground.anchor;game.view.zoom=.8
		for tick in range(2400):
			game.world.advance(.1);game.playground.tick(.1)
			if tick in [15,75,110]:await frames(2);await capture(kind+"-"+str(tick))
			if game.playground.kind.is_empty():break
		check(game.playground.completed.any(func(e):return e.game==kind),"real game finishes "+kind)
		game.playground.stop();await frames()
	game.queue_free();await frames()
	game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false);await frames()
	game.world.director.set_all_enabled(true)
	game.world.activities.set_followers(game.steward.Pool.IDS)
	var distances:Dictionary={};var actions:Dictionary={}
	for id in game.steward.Pool.IDS:distances[id]=[];actions[id]={}
	for tick in range(6000):
		game.world.advance(.1);game.playground.tick(.1)
		for id in game.steward.Pool.IDS:
			if tick%10==0:distances[id].append(game.world.point(game.world.actors[id]).distance_to(game.world.point(game.world.actors.human)))
			if game.playground.nearby.has(id):actions[id][game.playground.nearby[id].action]=true
		if tick%1000==0:await frames(2);await capture("nearby-"+str(tick))
	var out:=FileAccess.open(OS.get_environment("HABITAT_UI_EVIDENCE").path_join("nearby-stats.json"),FileAccess.WRITE)
	out.store_string(JSON.stringify({"distances":distances,"actions":actions}));out.close()
	for id in game.steward.Pool.IDS:
		check(distances[id].max()<=6,"within six tiles "+id)
		check(actions[id].size()>=5,"five actions "+id)
	print("PLAYGROUND_INPUT ",checks," failed=",failed);game.queue_free();await frames();quit(1 if failed else 0)
