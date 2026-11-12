extends "res://tests/test_dialogue_bar_input.gd"
func type_into(game:Node,text:String)->void:
	var at:Vector2=game.chat_input.get_global_rect().get_center()
	for down in [true,false]:
		var e:=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.position=at;e.global_position=at;e.pressed=down;root.push_input(e,true);await process_frame
	for ch in text:
		var e:=InputEventKey.new();e.unicode=ch.unicode_at(0);e.pressed=true;root.push_input(e,true);await process_frame
	var enter:=InputEventKey.new();enter.keycode=KEY_ENTER;enter.pressed=true;root.push_input(enter,true);await frames(2)
func run()->void:
	OS.set_environment("HABITAT_OPENING","showcase")
	var game:Node=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false)
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO;await frames(2)
	var w:RefCounted=game.world
	for i in range(800):game._process(.1)
	# Visual fixture: isolate presentation, use a reviewed forward-facing head, and keep feet still.
	w.director.set_all_enabled(false);w.activities.set_followers([])
	game.playground.nearby.clear();game.view.motion.play_poses.clear();game.view.motion.play_phases.clear() # Isolate the talking pose from independently tested idle play.
	check(not w.work.jobs.has("npc.mira") and not w._routes.has("npc.mira"),"real settled idle before speaking")
	w.actors["npc.mira"].facing="down";w.actors["npc.mira"].activity="idle"
	# Keep moving neighbours outside the mouth/shoe comparison ROI via real World routes.
	var open_at:Vector2=w.point(w.actors["npc.mira"])+Vector2(0,6)
	if w.walkable("home",open_at) and w.route_to("npc.mira",open_at):
		for tick in range(600):w.advance(.05)
	w.actors["npc.mira"].facing="down";w.actors["npc.mira"].activity="idle"
	var orange_at:Vector2=w.point(w.actors["npc.mira"])
	for other in ["codex","companion-2","npc.nora"]:
		w.command(other,{"intent":"stop"})
		for angle in range(16):
			var destination:Vector2=orange_at+Vector2.from_angle(TAU*angle/16)*8
			if w.walkable("home",destination) and w.route_to(other,destination):break
	for tick in range(600):w.advance(.05)
	game.view.set_process(false);game.view.follow_player=false;game.view.center=w.point(w.actors["npc.mira"]);game.view.zoom=2
	for candidate in range(1000):
		w.weather.weather_seed=candidate
		if w.weather.current().id=="sunny":break
	await UI.click(self,game.dialogue_button)
	var name:String=preload("res://scripts/localization.gd").resident(w,"npc.mira")
	var choices:Array=UI.descendants(game.command_page.targets).filter(func(n):return n is Button and not n is CheckBox and n.tooltip_text.begins_with(name))
	check(choices.size()==1,"exact existing Orange target button")
	if choices.is_empty():game.queue_free();quit(1);return
	check(await UI.click(self,choices[0]),"real mouse chooses Orange direct scope")
	# Existing local teaching acknowledgment creates an actual product bubble, with no fake model event.
	await type_into(game,"以后我说晨光就是你好")
	var speech:Dictionary=game.view.speech_by_actor.get("npc.mira",{})
	check(not speech.is_empty() and speech.get("text")==preload("res://scripts/localization.gd").text("memory.learned"),"real host teaching acknowledgment is displayed")
	check(game.links.values().all(func(link):return not is_instance_valid(link) or link._pid==-1),"no real model process")
	game.chat.hide();game.chat_input.release_focus()
	var images:Dictionary={};var anchors:Array=[]
	for tick in range(20):
		# Advance the existing presentation clock; do not invent speech or move the actor.
		game.view._process(.04)
		var col:int=3+int(game.view.clock*6)%3
		if images.has(col):continue
		await frames(2);RenderingServer.force_draw(false)
		var image:Image=root.get_texture().get_image();images[col]=image;anchors.append(w.actors["npc.mira"].position.duplicate())
		var dir:String=OS.get_environment("HABITAT_UI_EVIDENCE")
		if not dir.is_empty():image.save_png(dir.path_join("orange-speaking-col-"+str(col)+".png"))
		if images.size()==3:break
	check(images.size()==3 and anchors.all(func(p):return p==anchors[0]),"three actual bubble frames keep original World foot anchor")
	if images.has(3) and images.has(4):
		var at:Vector2=game.view.screen(w.point(w.actors["npc.mira"]))
		var face_changes:=0;var foot_changes:=0
		for y in range(49,55):
			for x in range(44,53):
				var p:Vector2i=Vector2i(at+Vector2(x-48,y-120)*2)
				if images[3].get_pixelv(p)!=images[4].get_pixelv(p):face_changes+=1
		for y in range(110,120):
			for x in range(31,65):
				var p:Vector2i=Vector2i(at+Vector2(x-48,y-120)*2)
				if images[3].get_pixelv(p)!=images[4].get_pixelv(p):foot_changes+=1
		check(face_changes>0,"actual viewport mouth region opens and closes")
		check(foot_changes==0,"actual viewport standing shoes stay planted while speaking")
		print("ORANGE_TALK_PIXELS face=",face_changes," feet=",foot_changes)
	print("ORANGE_TALK ",checks," failed=",failed);game.queue_free();await frames();quit(1 if failed else 0)
