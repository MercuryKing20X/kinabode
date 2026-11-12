extends "res://tests/test_resort_revision_input.gd"
## UI/Performance targeted correction: native HUD collapse and exact arrival timing.
func run()->void:
	await fresh()
	await UI.click(self,game.island_hud.collapse_residents)
	check(game.island_hud.residents_collapsed,"native resident HUD collapse")
	await text_input("大家跟我来");game.chat.hide()
	await walk(Vector2(81,178));await walk(Vector2(81,190))
	await capture_scene("compact-clean-day",Vector2(81,207),.23)
	var w:RefCounted=game.world
	var gate:Vector2=Vector2(w.resort.config.villas[0].gate[0],w.resort.config.villas[0].gate[1])
	var start:Vector2=Vector2(81,185)+(gate-Vector2(81,185)).normalized()*4
	await walk(start);await click_point(gate)
	var elapsed:=0.0;var distance:=0.0;var previous:Vector2=w.point(w.actors.human)
	for i in 600:
		game._process(.1);elapsed+=.1
		var now:Vector2=w.point(w.actors.human);distance+=previous.distance_to(now);previous=now
		if i%20==0:await process_frame
		if not w._routes.has("human"):break
	check(previous.distance_to(gate)<.5,"exact gate timing arrives")
	var samples:Array=[]
	for target in [Vector2(81,190),start,Vector2(81,190),start]:
		await click_point(target)
		for i in 30:
			var t:int=Time.get_ticks_usec();game._process(.1)
			game.view.center=w.point(w.actors.human);game.view.queue_redraw();RenderingServer.force_draw(false);await process_frame
			samples.append((Time.get_ticks_usec()-t)/1000.0)
	var total:=0.0
	for n in samples:total+=n
	var data:Dictionary={"origin":[start.x,start.y],"gate":[gate.x,gate.y],"distance_tiles":distance,"arrival_sim_seconds":elapsed,"frames":samples.size(),"average_frame_ms":total/samples.size(),"worst_frame_ms":samples.max()}
	for i in 15000:
		if w.days.phase().id=="night":break
		game._process(.1)
		if i%300==0:await process_frame
	await capture_scene("compact-clean-night",Vector2(81,207),.23)
	FileAccess.open(OS.get_environment("HABITAT_DATA_DIR").path_join("capture-metrics.json"),FileAccess.WRITE).store_string(JSON.stringify(data,"\t"))
	print("REVISION_CAPTURE ",JSON.stringify(data)," checks=",checks," failed=",failed)
	game.queue_free();await process_frame;quit(1 if failed else 0)
