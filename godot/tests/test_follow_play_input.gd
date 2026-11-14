extends "res://tests/test_intelligence_core_input.gd"
func run()->void:
	OS.set_environment("HABITAT_OPENING","showcase")
	game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false)
	root.size=Vector2i(1280,800);await process_frame;await process_frame
	var buttons:Array=game.watch_ui.bar.get_children().filter(func(n):return n is Button and n.visible)
	check(buttons==[game.dialogue_button,game.journey.map_button,game.watch_ui.toggle,game.gathering_button],"four ordered bottom buttons")
	await picture("four-buttons")
	var at:Vector2=game.gathering_button.get_global_rect().get_center()
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=at;event.global_position=at;event.pressed=down;root.push_input(event,true);await process_frame
	await picture("follow-panel")
	check(game.follow_ui.menu.visible,"native click opens original follow picker")
	game.follow_ui.menu.hide()
	game.chat_actor="codex"
	await text_input("玩老鹰捉小鸡")
	check(game.playground.kind=="eagle","real keyboard command starts eagle")
	await picture("eagle-request")
	var card:Dictionary=game._intent_card("codex",{"dialogue":{"channel_id":"direct:codex","recipient_ids":["codex"]}},"direct:codex")
	var file:=FileAccess.open(OS.get_environment("HABITAT_DATA_DIR").path_join("intent-card.json"),FileAccess.WRITE);file.store_string(JSON.stringify(card));file.close()
	game.playground.stop();game.chat.hide();game.chat_input.release_focus()
	game.steward.manager="codex"
	# C: this fixture is an explicit host preparation; keep model follow protection.
	game.world.host_command("codex",{"intent":"move","region_id":"home","x":game.world.actors.human.position[0]+2,"y":game.world.actors.human.position[1]})
	for step in range(1000):
		game.world.advance(.1)
		if not game.world._routes.has("codex"):break
	for choice in ["yes","no","timeout"]:
		var row:Dictionary={"reason":choice,"intents":[{"action":"fish"}]}
		game.steward.queue=[row];game.steward.timeline=[{"status":"pending"}]
		game.steward.approve_next(row,.1)
		await process_frame;await process_frame
		check(is_instance_valid(game.steward.invitation) and game.steward.invitation.visible,"invitation visible "+choice)
		await picture("invite-"+choice)
		if not is_instance_valid(game.steward.invitation):
			print("INVITE_BLOCKED distance=",game.world.point(game.world.actors.codex).distance_to(game.world.point(game.world.actors.human))," focus=",game.get_viewport().gui_get_focus_owner())
			continue
		if choice=="timeout":
			for step in range(150):game.world.advance(.1);game.steward.approve_next(row,.1)
		else:
			var entries:Array=game.steward.invitation.get_child(0).get_child(1).get_children()
			var point:Vector2=entries[0 if choice=="yes" else 1].get_global_rect().get_center()
			for down in [true,false]:
				var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=point;event.global_position=point;event.pressed=down;root.push_input(event,true);await process_frame
		check(not game.steward.invitation.visible,"invitation resolved "+choice)
	game.steward.queue.clear();game.steward.timeline.clear();game.steward.manager=""
	game.world.director.set_all_enabled(true)
	var curve:Array=[]
	var farthest:=0.0
	for tick in range(9000):
		game._process(.1)
		if tick%100==0:
			var sample:Dictionary={"seconds":tick*.1}
			for who in game.steward.Pool.IDS:
				var distance:float=game.world.point(game.world.actors[who]).distance_to(game.world.point(game.world.actors.human))
				sample[who]=distance
				if tick>1200 and not game.world.work.jobs.has(who):farthest=maxf(farthest,distance)
			curve.append(sample)
	var log_file:=FileAccess.open(OS.get_environment("HABITAT_DATA_DIR").path_join("local-distance-900s.json"),FileAccess.WRITE);log_file.store_string(JSON.stringify(curve));log_file.close()
	print("LOCAL_DISTANCE_MAX ",farthest)
	check(farthest<=6,"local idle companions within six tiles after quiet period")
	print("FOLLOW_PLAY_INPUT ",checks," failed=",failed)
	game.queue_free();await process_frame;quit(1 if failed else 0)
