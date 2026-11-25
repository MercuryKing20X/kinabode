extends "res://tests/test_intent_input.gd"
func run()->void:
	OS.set_environment("HABITAT_OPENING","showcase")
	root.size=Vector2i(1280,800)
	game=load("res://scenes/main_v3.tscn").instantiate()
	game.dialogue_adapter_factory=func(_id,_scope):return IntentFake.new()
	root.add_child(game);game.save_enabled=false;game.set_process(false)
	await process_frame;await process_frame
	var w:RefCounted=game.world
	var actor:Dictionary=w.actors["npc.mira"]
	var atlas:RefCounted=preload("res://scripts/motion_atlas.gd").new()
	for direction in ["down","left","right","up"]:
		var copy:Dictionary=actor.duplicate(true);copy.facing=direction
		var fingerprints:Dictionary={}
		for col in range(5):
			var texture:Texture2D=atlas.texture("chop",game.library,copy,col)
			check(texture!=null,"imported chop frame "+direction+str(col))
			if texture==null:continue
			var im:Image=texture.get_image();var bounds:Rect2i=im.get_used_rect()
			check(bounds.position.x>0 and bounds.end.x<96 and bounds.position.y>0 and bounds.end.y==120,"whole body and axe fit; consistent foot anchor "+direction+str(col))
			fingerprints[im.get_data().hex_encode().sha256_text()]=true
		check(fingerprints.size()==5,"five genuinely distinct authored phases "+direction)
	await text_input("小橙砍一棵树")
	game.chat.hide()
	var reached:=false
	for tick in range(2400):
		game._process(.1);game.local_host_commands._process(.1)
		if actor.activity=="chopping":
			reached=true
			if fposmod(float(w.work.jobs.get("npc.mira",{}).get("time",0)),float(w.forest.settings.swing_seconds))/float(w.forest.settings.swing_seconds)<.15:continue
			game.resident_connections.hide();game.action_dock.hide()
			game.view.follow_player=false;game.view.follow_actor="";game.view.center=w.point(actor);game.view.zoom=1.5;game.view.queue_redraw()
			await process_frame;RenderingServer.force_draw(false)
			if DisplayServer.get_name()!="headless":
				root.get_texture().get_image().save_png(OS.get_environment("HABITAT_UI_EVIDENCE").path_join("orange-real-chop-v06.png"))
			break
		if tick%30==0:await process_frame
	check(reached,"real keyboard host command routes Orange to real tree and chopping")
	print("ORANGE_CHOP_V06 ",checks," failed=",failed)
	game.queue_free();await process_frame;quit(1 if failed else 0)
