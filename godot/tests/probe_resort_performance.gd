extends "res://tests/test_home_island_input.gd"
var metrics:Array=[]
func measure_walk(game:Node,target:Vector2,label:String)->void:
	game.chat.hide();game.view.center=target;game.view.follow_player=false
	await process_frame
	var click_started:int=Time.get_ticks_usec()
	await click_at(game.view.screen(target))
	var click_ms:float=(Time.get_ticks_usec()-click_started)/1000.0
	var samples:Array=[];var costs:Array=[];var process_costs:Array=[];var draw_costs:Array=[]
	var start_position:Vector2=game.world.point(game.world.actors.human)
	for i in range(180):
		var start:int=Time.get_ticks_usec()
		game._process(.1)
		var processed:int=Time.get_ticks_usec();process_costs.append((processed-start)/1000.0)
		game.view.center=game.world.point(game.world.actors.human);game.view.queue_redraw()
		RenderingServer.force_draw(false)
		draw_costs.append((Time.get_ticks_usec()-processed)/1000.0)
		costs.append((Time.get_ticks_usec()-start)/1000.0)
		await process_frame
		samples.append((Time.get_ticks_usec()-start)/1000.0)
		if i>=60 and not game.world._routes.has("human"):break
	var total:float=0;var cpu:float=0;var process_sum:float=0;var draw_sum:float=0
	for x in samples:total+=x
	for x in costs:cpu+=x
	for x in process_costs:process_sum+=x
	for x in draw_costs:draw_sum+=x
	metrics.append({"label":label,"frames":samples.size(),"average_frame_ms":total/samples.size(),"worst_frame_ms":samples.max(),"average_process_draw_ms":cpu/costs.size(),"worst_process_draw_ms":costs.max(),"average_logic_ms":process_sum/process_costs.size(),"worst_logic_ms":process_costs.max(),"average_draw_ms":draw_sum/draw_costs.size(),"worst_draw_ms":draw_costs.max(),"click_and_route_ms":click_ms,"walked_tiles":start_position.distance_to(game.world.point(game.world.actors.human)),"arrived":game.world.point(game.world.actors.human).distance_to(target)<1})
	print("PERF_SEGMENT ",JSON.stringify(metrics.back()))
func run()->void:
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	OS.set_environment("HABITAT_OPENING","standard")
	var game:Node=load("res://scenes/main_v3.tscn").instantiate()
	game.world=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json")
	root.add_child(game);game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.island_hud.set_process(false);game.chat.hide()
	await process_frame;await process_frame
	for i in range(20):game.view.queue_redraw();await process_frame
	await measure_walk(game,Vector2(81,105),"main-walk")
	# Actual original World traversal; no actor position changes.
	game.view.center=Vector2(81,178);game.view.follow_player=false;await process_frame
	await click_at(game.view.screen(Vector2(81,178)))
	for i in range(1800):
		game._process(.1)
		if i%20==0:await process_frame
		if not game.world._routes.has("human"):break
	check(game.world.home_island.here(),"native long bridge traversal reaches south")
	await measure_walk(game,Vector2(81,199),"south-arrival-walk")
	await measure_walk(game,Vector2(141,199),"south-east-walk")
	await measure_walk(game,Vector2(141,247),"south-south-walk")
	var result:Dictionary={"metrics":metrics,"failed":failed,"display":DisplayServer.get_name(),"viewport":[1280,800],"memory_static_bytes":OS.get_static_memory_usage()}
	var output:String=OS.get_environment("HABITAT_DATA_DIR").path_join("performance.json")
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("RESORT_PERFORMANCE ",JSON.stringify(result));game.queue_free();await process_frame;quit(1 if failed else 0)
