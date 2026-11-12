extends "res://tests/test_intent_input.gd"
func run()->void:
	root.size=Vector2i(1280,800)
	OS.set_environment("HABITAT_OPENING","standard")
	game=load("res://scenes/main_v3.tscn").instantiate()
	game.dialogue_adapter_factory=func(_id,_scope):return IntentFake.new()
	root.add_child(game);game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.island_hud.set_process(false);game.chat.hide()
	await process_frame;await process_frame
	var w:RefCounted=game.world
	w.director.set_all_enabled(false)
	var ids:Array=["codex","companion-2","npc.mira","npc.nora"]
	var initial:int=w.storage.count("wood")
	# Isolated initial fixture: move four existing warehouse logs into four real carries.
	check(w.storage.take({"wood":4}).ok,"fixture debits four real logs")
	var host:Vector2=w.point(w.actors.human)
	for index in ids.size():
		var id:String=ids[index]
		w.actors[id].carry={"wood":1}
		w.actors[id].region_id=w.actors.human.region_id
		w._routes.erase(id)
		var found:=false
		for degrees in range(index*25,360,10):
			var at:Vector2=host+Vector2.RIGHT.rotated(deg_to_rad(degrees))*18
			if not w.walkable(w.actors.human.region_id,at) or w.find_route(id,at).is_empty():continue
			w.actors[id].position=[at.x,at.y];found=true;break
		check(found,"far fixture on valid World route "+id)
		w.actors[id].activity="idle"
	var initial_host:Array=w.actors.human.position.duplicate()
	await text_input("大家递给我")
	check(w.deliveries.pending.size()==4,"real host input starts four deliveries")
	var slots:Dictionary={};var arrival:Dictionary={};var completions:Array=[];var runs:Dictionary={};var previous:Dictionary=w.deliveries.pending.duplicate(true)
	for id in ids:
		if w.deliveries.visits.has(id):slots[id]=w.deliveries.visits[id].point
	check(slots.size()==4,"all four slots assigned before approach")
	var distances:Array=[]
	for a in slots:
		for b in slots:
			if str(a)>=str(b):continue
			var d:float=slots[a].distance_to(slots[b]);distances.append({"a":a,"b":b,"distance":d});check(d>=1.5,"preallocated separation >=1.5")
	var conserved:=true;var shot:=false
	for tick in range(1200):
		for id in ids:
			if w.is_running(id):runs[id]=true
			if w.deliveries.visits.has(id) and w.deliveries.visits[id].arrival>0:arrival[id]=w.deliveries.visits[id].arrival
		game._process(.05);game.local_host_commands._process(.05)
		for id in previous:
			if not w.deliveries.pending.has(id):completions.append(id)
		previous=w.deliveries.pending.duplicate(true)
		var total:int=w.storage.count("wood")
		for id in ids:total+=int(w.actors[id].carry.get("wood",0))
		conserved=conserved and total==initial
		var nearby:bool=ids.all(func(id):return w.point(w.actors[id]).distance_to(host)<=6)
		if nearby and not shot:
			shot=true;game.chat.hide();game.view.follow_player=false;game.view.center=host;game.view.zoom=1.5;game.view.queue_redraw()
			await process_frame;await process_frame
			var evidence:String=OS.get_environment("HABITAT_V06_EVIDENCE")
			if not evidence.is_empty() and DisplayServer.get_name()!="headless":
				RenderingServer.force_draw(false);root.get_texture().get_image().save_png(evidence.path_join("four-deliveries.png"))
		if w.deliveries.pending.is_empty():break
		if tick%50==0:await process_frame
	check(runs.size()==4,"each distant resident uses original running presentation")
	check(completions.size()==4 and w.deliveries.pending.is_empty(),"all four real carries deposited")
	check(conserved and w.storage.count("wood")==initial,"wood conserved on every advance")
	check(w.actors.human.position==initial_host,"human never moved")
	var in_order:=true
	for i in range(1,completions.size()):in_order=in_order and int(arrival.get(completions[i-1],0))<int(arrival.get(completions[i],0))
	check(arrival.size()==4 and in_order,"service follows actual arrival order")
	var actual:Dictionary={};var actual_distances:Array=[]
	for id in ids:actual[id]=w.actors[id].position.duplicate()
	for a in ids:
		for b in ids:
			if str(a)>=str(b):continue
			actual_distances.append({"a":a,"b":b,"distance":w.point(w.actors[a]).distance_to(w.point(w.actors[b]))})
	if DisplayServer.get_name()!="headless":
		game.chat.hide();game.view.follow_player=false;game.view.center=host;game.view.zoom=1.5;game.view.queue_redraw()
		await process_frame;await process_frame;RenderingServer.force_draw(false)
		var final_evidence:String=OS.get_environment("HABITAT_V06_EVIDENCE")
		if not final_evidence.is_empty():root.get_texture().get_image().save_png(final_evidence.path_join("four-deliveries-final.png"))
	var report:Dictionary={"actual_positions":actual,"actual_distances":actual_distances,"slots":{},"pair_distances":distances,"arrival":arrival,"completion_order":completions,"runs":runs,"wood_before":initial,"wood_after":w.storage.count("wood"),"conserved":conserved,"captured":shot,"checks":checks,"failed":failed}
	for id in slots:report.slots[id]=[slots[id].x,slots[id].y]
	var evidence:String=OS.get_environment("HABITAT_V06_EVIDENCE")
	if not evidence.is_empty():FileAccess.open(evidence.path_join("four-deliveries.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("V06_DELIVERY_INPUT ",JSON.stringify(report))
	game.game_audio.shutdown();game.queue_free();await process_frame;quit(1 if failed else 0)
