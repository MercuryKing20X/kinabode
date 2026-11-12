extends "res://tests/test_intelligence_core_input.gd"
func run()->void:
	await fresh()
	var w:RefCounted=game.world
	var records:Array=[]
	game.view.zoom=.7
	var origin:Vector2=w.point(w.actors.human)
	for offset in [Vector2(-10,0),Vector2(10,0),Vector2(0,10),Vector2(0,-10)]:
		var dest:Vector2=origin+offset
		if not w.walkable(w.actors.human.region_id,dest):continue
		var at:Vector2=game.view.screen(dest)
		for down in [true,false]:
			var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=at;event.global_position=at;event.pressed=down;root.push_input(event,true);await process_frame
		if w._routes.has("human"):break
	check(w._routes.has("human"),"real ground input starts route")
	for tick in 160:
		game._process(.05);game.view._process(.05)
		for id in ["human","codex","companion-2","npc.mira","npc.nora"]:
			var m:Dictionary=w.motion_state(id)
			var pose:Dictionary=game.view.motion.pose(w.actors[id],w.work.jobs.get(id,{}),w.actors,{"motion":m})
			records.append({"tick":tick,"id":id,"position":w.actors[id].position.duplicate(),"motion":m,"step":game.view.motion.states.get(id,{}).get("step",0),"frame":pose.frame,"walk_column":game.view.motion.walk_column(id)})
		if tick%20==0:await picture("walk-"+str(tick))
	var f:=FileAccess.open(OS.get_environment("HABITAT_DATA_DIR").path_join("walk-trace.json"),FileAccess.WRITE);f.store_string(JSON.stringify(records));f.close()
	var nearest:String=""
	for id in w.objects:
		var o:Dictionary=w.objects[id]
		if o.kind=="tree" and o.status=="mature" and o.get("region_id","home")==w.actors.human.region_id:
			if nearest.is_empty() or w.point(o).distance_to(w.point(w.actors.human))<w.point(w.objects[nearest]).distance_to(w.point(w.actors.human)):nearest=id
	game.view.follow_player=false;game.view.center=w.point(w.objects[nearest]);await process_frame
	var tree_at:Vector2=game.view.screen(w.point(w.objects[nearest]))+Vector2(0,-28)*game.view.zoom
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=tree_at;event.global_position=tree_at;event.pressed=down;root.push_input(event,true);await process_frame
	var hit_seen:=false
	for tick in 1800:
		game._process(.025);game.view._process(.025)
		for effect in game.view.effects:
			if effect.kind=="hit" and effect.get("actor_id","")=="human" and game.view.clock-float(effect.started)<.06:
				hit_seen=true;await picture("real-hit");break
		if hit_seen:break
	check(hit_seen,"native tree click produces actual hit and viewport shake")
	print("WALK_NATIVE failed=",failed)
	game.queue_free();await process_frame;quit(1 if failed else 0)
