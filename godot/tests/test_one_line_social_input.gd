extends "res://tests/test_local_command_main_input.gd"
func run()->void:
	OS.set_environment("HABITAT_OPENING","showcase")
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	game=load("res://scenes/main_v3.tscn").instantiate();game.world=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");root.add_child(game)
	game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.island_hud.set_process(false);game.chat.hide()
	await process_frame;await process_frame
	var w:RefCounted=game.world
	var stock:Dictionary=w.storage.saved();var human:Array=w.actors.human.position.duplicate()
	await text_input("你们都来吃饭")
	check(w.barbecues[game.local_host_commands.nearest_fire()].fireside.selected_guests.size()==4,"exact meal phrase commits all four original invitations")
	check(w._routes.size()>=4,"invited four take real World routes toward camp")
	check(w.storage.saved()==stock and w.actors.human.position==human,"invitation does not roast pay or move human")
	await text_input("别干了")
	await text_input("小蓝陪我下棋")
	check(w.gomoku.sessions.values().any(func(match_state):return match_state.white_id=="companion-2" and match_state.phase=="arriving"),"one-line chess starts original seats")
	game.queue_free();await process_frame
	print("ONE_LINE_SOCIAL_INPUT ",checks," failed=",failed);quit(1 if failed else 0)
