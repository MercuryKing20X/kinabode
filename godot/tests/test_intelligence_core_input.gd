extends "res://tests/test_local_command_main_input.gd"
func fresh()->void:
	OS.set_environment("HABITAT_OPENING","standard")
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	game=load("res://scenes/main_v3.tscn").instantiate()
	game.world=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json")
	root.add_child(game)
	game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.island_hud.set_process(false);game.chat.hide()
	await process_frame;await process_frame
	for pair in [["codex","ai-gpt"],["companion-2","ai-deepseek"],["npc.mira","ai-claude"],["npc.nora","ai-glm"]]:
		check(game.world.assign_appearance(pair[0],pair[1]),"isolated nondefault appearance "+pair[0])
func picture(label:String)->void:
	if DisplayServer.get_name()=="headless":return
	if label.ends_with("watered"):
		game.chat.hide();game.view.follow_player=false;game.view.center=Vector2(48,78);game.view.queue_redraw()
	await process_frame;RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OS.get_environment("HABITAT_DATA_DIR").path_join(label+".png"))
func run()->void:
	OS.set_environment("HABITAT_OPENING","standard")
	await fresh()
	root.size=Vector2i(1280,800)
	var w:RefCounted=game.world
	var before:int=w.storage.count("seed.turnip")+w.storage.count("seed.tomato")
	await picture("group-before")
	await text_input("全部去种菜")
	await picture("group-started")
	check(not is_instance_valid(game.local_host_commands.card),"no card for ordinary group instruction")
	check(w.farms.orders.size()==4,"native exact user phrase starts four actual farm orders")
	for tick in range(6000):
		game._process(.1)
		if w.farms.orders.size()==4 and w.farms.orders.values().all(func(order):return order.status=="completed"):break
	check(w.farms.orders.values().all(func(order):return order.status=="completed"),"all four really complete")
	var watered:int=0
	for plot in w.farms.plots.values():
		if not str(plot.crop_id).is_empty() and bool(plot.get("watered",false)):watered+=1
	await picture("group-watered")
	check(watered==8,"eight planted seedlings have real first water")
	check(before-w.storage.count("seed.turnip")-w.storage.count("seed.tomato")==8,"eight real warehouse seeds consumed")
	game.queue_free();await process_frame
	await fresh()
	w=game.world
	game.chat_actor="codex"
	var turnips:int=w.storage.count("seed.turnip")
	await text_input("帮我种萝卜")
	await picture("snow-started")
	check(w.farms.orders.has("codex"),"native exact single phrase starts Snow")
	for tick in range(6000):
		game._process(.1)
		if w.farms.orders.has("codex") and w.farms.orders.codex.status=="completed":break
	check(w.farms.orders.get("codex",{}).get("status")=="completed","Snow really finishes planting and first water")
	await picture("snow-watered")
	check(w.storage.count("seed.turnip")<turnips,"Snow consumes real turnip seeds")
	game.queue_free();await process_frame
	print("INTELLIGENCE_CORE_INPUT ",checks," failed=",failed);quit(1 if failed else 0)
