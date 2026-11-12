extends "res://tests/test_intelligence_core_input.gd"
func run()->void:
	await fresh()
	var w:RefCounted=game.world
	check(w.assign_appearance("human","suit-hulk",true,true),"protected human outfit")
	game.view.zoom=.85
	game.view.follow_player=false
	game.view.center=w.point(w.actors.human)
	var atlas:RefCounted=game.view.action_atlases
	for action in ["walk","run","chop","gather","eat","farm","gesture"]:
		for direction in ["down","left","right","up"]:
			w.actors.human.facing=direction
			for col in int(atlas.manifests[action].columns):check(atlas.texture(action,game.library,w.actors.human,col)!=null,"new texture "+action+direction+str(col))
	# Native ground clicks from the actual standard opening. No position/material injection.
	var trace:Array=[]
	for mode in ["walk","run"]:
		var origin:Vector2=w.point(w.actors.human)
		game.view.center=origin
		await process_frame
		var clicked:=false
		for offset in [Vector2(-5 if mode=="walk" else -15,0),Vector2(5 if mode=="walk" else 15,0),Vector2(0,5 if mode=="walk" else 15)]:
			var dest:Vector2=origin+offset
			if not w.walkable(w.actors.human.region_id,dest):continue
			var at:Vector2=game.view.screen(dest)
			for down in [true,false]:
				var e:=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;e.position=at;e.global_position=at;root.push_input(e,true);await process_frame
			if w._routes.has("human"):clicked=true;break
		check(clicked,"native "+mode+" ground route")
		for tick in 100:
			game._process(.04);game.view._process(.04)
			var motion:Dictionary=w.motion_state("human")
			trace.append({"mode":mode,"tick":tick,"motion":motion,"position":w.actors.human.position.duplicate(),"running":w.is_running("human"),"walk_col":game.view.motion.walk_column("human"),"run_col":game.view.motion.run_column("human",w.intelligence.gait("human"))})
			if tick%8==0:await picture(mode+"-"+str(tick))
		w.host_command("human",{"intent":"stop"})
	# Real Godot material viewport: all columns rendered at actual pixel scale.
	game.hide()
	for node in UI.descendants(game):
		if node is CanvasLayer:node.visible=false
	root.size=Vector2i(1152,660)
	var bg:=ColorRect.new();bg.color=Color("7d9174");bg.size=Vector2(1152,660);root.add_child(bg)
	for action in ["walk","run","chop","gather","eat","farm","gesture"]:
		var pane:=Control.new();root.add_child(pane)
		for row in 4:
			w.actors.human.facing=["down","left","right","up"][row]
			for col in int(atlas.manifests[action].columns):
				var t:=TextureRect.new();t.texture=atlas.texture(action,game.library,w.actors.human,col);t.position=Vector2(12+col*110,row*160);t.size=Vector2(96,128);t.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;pane.add_child(t)
		var l:=Label.new();l.text=action+" / material review only";l.position=Vector2(10,638);pane.add_child(l)
		await picture("viewport-"+action)
		pane.queue_free();await process_frame
	var f:=FileAccess.open(OS.get_environment("HABITAT_DATA_DIR").path_join("trace.json"),FileAccess.WRITE);f.store_string(JSON.stringify(trace));f.close()
	print("SUIT_V2 checks=",checks," failed=",failed)
	game.queue_free();bg.queue_free();await process_frame;quit(1 if failed else 0)
