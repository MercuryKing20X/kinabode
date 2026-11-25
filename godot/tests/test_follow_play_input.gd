extends "res://tests/test_intelligence_core_input.gd"
func run()->void:
	OS.set_environment("HABITAT_OPENING","showcase")
	game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false)
	root.size=Vector2i(1280,800);await process_frame;await process_frame
	var buttons:Array=game.watch_ui.bar.get_children().filter(func(n):return n is Button and n.visible)
	# DIRECTION 11-19: “加‘观赏模式’”; keep the original destinations in order
	# and require the real Watch control in the visible dock.
	check(buttons==[game.dialogue_button,game.journey.map_button,game.island_hud.watch_button,game.gathering_button],"ordered bottom controls include Watch")
	await picture("four-buttons")
	var at:Vector2=game.gathering_button.get_global_rect().get_center()
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=at;event.global_position=at;event.pressed=down;root.push_input(event,true);await process_frame
	await picture("follow-panel")
	check(game.follow_ui.menu.visible,"native click opens original follow picker")
	game.follow_ui.menu.hide()
	game.chat_actor="codex"
	# B: DIRECTION 2026-11-18「从小游戏菜单、指令按钮和口语指令……拿掉」。
	await text_input("玩老鹰捉小鸡")
	check(game.playground.kind.is_empty() and game.status.text==game.T("company.games"),"retired spoken command offers available games")
	await text_input("玩捉迷藏")
	check(game.playground.kind=="hide","real keyboard command starts hide and seek")
	await picture("hide-request")
	var card:Dictionary=game._intent_card("codex",{"dialogue":{"channel_id":"direct:codex","recipient_ids":["codex"]}},"direct:codex")
	var file:=FileAccess.open(OS.get_environment("HABITAT_DATA_DIR").path_join("intent-card.json"),FileAccess.WRITE);file.store_string(JSON.stringify(card));file.close()
	game.playground.stop();game.chat.hide();game.chat_input.release_focus()
	# Stewardship approvals were removed from the world branch. The
	# follow, play and local-distance assertions still exercise live systems.
	game.world.director.set_all_enabled(true)
	var curve:Array=[]
	var farthest:=0.0
	for tick in range(9000):
		game._process(.1)
		if tick%100==0:
			var sample:Dictionary={"seconds":tick*.1}
			for who in game.world.director.routines:
				var distance:float=game.world.point(game.world.actors[who]).distance_to(game.world.point(game.world.actors.human))
				sample[who]=distance
				if tick>1200 and not game.world.work.jobs.has(who):farthest=maxf(farthest,distance)
			curve.append(sample)
	var log_file:=FileAccess.open(OS.get_environment("HABITAT_DATA_DIR").path_join("local-distance-900s.json"),FileAccess.WRITE);log_file.store_string(JSON.stringify(curve));log_file.close()
	print("LOCAL_DISTANCE_MAX ",farthest)
	check(farthest<=6,"local idle companions within six tiles after quiet period")
	print("FOLLOW_PLAY_INPUT ",checks," failed=",failed)
	game.queue_free();await process_frame;quit(1 if failed else 0)
