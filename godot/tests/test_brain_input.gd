extends "res://tests/test_brain_30min.gd"
var media:String
var response_latency_ms:=0.0
func text_input(text:String,send_by_button:bool=false)->void:
	if not game.chat.visible:check(await UI.click(self,game.dialogue_button),"native opens chat")
	await process_frame;await process_frame
	root.grab_focus()
	var p:Vector2=game.chat_input.get_global_rect().get_center()
	var motion:=InputEventMouseMotion.new();motion.position=p;motion.global_position=p;root.push_input(motion,true)
	await process_frame
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=p;event.global_position=p;event.pressed=down;event.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0;root.push_input(event,true);await process_frame
	for index in text.length():
		for down in [true,false]:
			var event:=InputEventKey.new();event.unicode=text.unicode_at(index);event.pressed=down;root.push_input(event,true);await process_frame
	check(game.chat_input.text==text,"exact real typed phrase")
	var started:int=Time.get_ticks_usec()
	for down in [true,false]:
		var event:=InputEventKey.new();event.keycode=KEY_ENTER;event.pressed=down;root.push_input(event,true)
		if down:response_latency_ms=float(Time.get_ticks_usec()-started)/1000.0
		await process_frame
func shot(name:String)->void:
	game.view.queue_redraw();await process_frame;await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(media.path_join(name+".png"))
func ground(at:Vector2)->bool:
	game.chat.hide();game.brain_panel.hide();game.view.center=game.world.point(game.world.actors.human);game.view.zoom=1;game.view.follow_player=false
	await process_frame
	var p:Vector2=game.view.screen(at)
	if not Rect2(Vector2.ZERO,Vector2(root.size)).grow(-100).has_point(p):game.view.center=at;await process_frame;p=game.view.screen(at)
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=p;event.global_position=p;event.pressed=down;root.push_input(event,true);await process_frame
	return game.world._routes.has("human")
func run()->void:
	base_directory=OS.get_environment("HABITAT_DATA_DIR");evidence=OS.get_environment("HABITAT_BRAIN_EVIDENCE");media=OS.get_environment("HABITAT_BRAIN_MEDIA")
	if evidence.is_empty():evidence=base_directory
	if media.is_empty():media=base_directory
	DirAccess.make_dir_recursive_absolute(media);DirAccess.make_dir_recursive_absolute(evidence)
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	node_added.connect(func(node):
		if node.get_script()!=null and node.get_script().resource_path=="res://scripts/main.gd":node.set_process(false);node.dialogue_adapter_factory=func(_id,_scope):return Fake.new())
	await fresh_title(3)
	var w:RefCounted=game.world
	var results:Array=[]
	for phrase in ["所有人跟我来","别跟了","小蓝跟我来","大家去种萝卜"]:
		var started:int=Time.get_ticks_msec()
		await text_input(phrase)
		var response_ms:int=Time.get_ticks_msec()-started
		var local_ms:float=response_latency_ms
		check(local_ms<1000,"Enter-to-command response below one second "+phrase)
		results.append({"phrase":phrase,"input_and_response_ms":response_ms,"local_ms":local_ms,"following":w.activities.following.keys(),"orders":w.farms.orders.duplicate(true),"result":game.local_host_commands.last_execution.duplicate(true)})
		if phrase=="所有人跟我来":check(w.activities.following.size()==4,"all four respond to actual typed follow")
		if phrase=="别跟了":check(w.activities.following.is_empty(),"actual typed release")
		if phrase=="小蓝跟我来":check(w.activities.following.keys()==["companion-2"],"actual typed named follow exact")
		print("BRAIN_INPUT_PHRASE ",phrase," response_ms=",local_ms)
		for tick in 10:game._process(.1)
	# Finish the actual authorized farm order before observing local life again.
	for tick in 2400:
		game._process(.1);game.local_host_commands._process(.1)
		if not w.farms.orders.values().any(func(order):return order.status=="working"):break
	check(w.farms.orders.size()==4 and w.farms.orders.values().all(func(order):return order.status=="completed"),"typed farm command really completes four orders")
	results.append({"farm_final":w.farms.orders.duplicate(true),"stock":w.storage.saved()})
	await text_input("所有人跟我来")
	game.chat.hide()
	check(w.assign_appearance("companion-2","ai-deepseek"),"nondefault appearance stays same resident")
	for tick in 120:w.advance(.25)
	# A real right click on the displayed resident opens the basic mind panel.
	var id:String="companion-2"
	await text_input("别跟了")
	await text_input("小蓝跟我来")
	var route_started:=await ground(w.point(w.actors.human)+Vector2(0,10))
	check(route_started,"mouse walks the host away from the overlapping group")
	if route_started:
		for tick in 500:
			game._process(.1);game.local_host_commands._process(.1)
			if not w._routes.has("human") and w.point(w.actors.human).distance_to(w.point(w.actors[id]))<4:break
	game.view.center=w.point(w.actors[id]);game.view.follow_player=false;game.view.zoom=1
	await process_frame
	var point:=Vector2.INF
	for attempt in 80:
		var screen_point:Vector2=game.view.screen(w.point(w.actors[id]))
		for offset in [Vector2(0,-40),Vector2(-16,-40),Vector2(16,-40),Vector2(0,-68),Vector2(0,-18)]:
			var candidate:Vector2=screen_point+offset
			if game.view.care_hit(candidate)==id:
				point=candidate;break
		if point.is_finite():break
		# Follow can briefly put two sprites on the same spot. Let the original
		# movement settle before choosing a position that visibly belongs to Blue.
		game._process(.1)
		await process_frame
	check(point.is_finite(),"Blue has a separately hittable part of the visible sprite")
	if not point.is_finite():quit(1);return
	var motion:=InputEventMouseMotion.new()
	motion.position=point;motion.global_position=point;root.push_input(motion,true)
	await process_frame
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_RIGHT;event.position=point;event.global_position=point;event.pressed=down;root.push_input(event,true);await process_frame
	if game.company.care_target!=id:
		var hover:Control=root.gui_get_hovered_control()
		print("BRAIN_CARE_HIT point=",point," candidate=",game.view.care_hit(point)," care=",game.company.care_target," hovered=",hover.get_path() if hover!=null else "none")
	check(game.company.care_target==id,"right click opens the exact resident's care card")
	if game.company.care_target==id:
		check(await UI.click(self,game.company.care_card.get_node_or_null("body/mind")),"native care card opens the resident's mind")
	check(game.brain_panel.visible and game.brain_panel.actor_id==id,"right click opens exact resident mind")
	for locale in ["zh","en"]:
		game.LocalText.select(game.data_dir,locale);game.brain_panel.refresh();await shot("mind-"+locale)
	game.brain_panel.hide()
	# One complete minute of unchanged local play, sampled at two frames/second.
	game.view.center=w.point(w.actors.human);game.view.follow_player=false
	for frame in 120:
		for tick in 5:w.advance(.1)
		game.view._process(.5)
		await shot("minute-%03d"%frame)
	# Main and Crescent use the original ground-click World route, never coordinates.
	var host:Vector2=w.point(w.actors.human)
	check(await ground(host+Vector2(0,10)),"main island actual mouse route")
	for tick in 800:
		game._process(.1)
		if not w._routes.has("human"):break
	await shot("mainland")
	var anchor:Array=w.map_anchor("moon.lookout");var moon:Vector2=Vector2(anchor[0],anchor[1])
	var clicked:bool=await ground(moon+Vector2(2,2));check(clicked,"Crescent actual mouse route")
	for tick in 4000:
		game._process(.1)
		if not w._routes.has("human"):break
	check(w.point(w.actors.human).distance_to(moon)<8,"human arrives Crescent by World route")
	for tick in 400:game._process(.1)
	game.view.center=moon;game.view.follow_player=false;await shot("crescent")
	results.append({"crescent_host":w.actors.human.position.duplicate(),"companions":w.director.brains.keys().map(func(who):return {"id":who,"position":w.actors[who].position,"current":w.director.brains[who].summary()})})
	var file:=FileAccess.open(evidence.path_join("input-results.json"),FileAccess.WRITE);file.store_string(JSON.stringify(results,"\t"));file.close()
	for link in game.links.values():check(link is Fake and link.sent.is_empty(),"zero model calls with prebuilt stub")
	game.queue_free();await process_frame
	print("BRAIN_INPUT ",checks," failed=",failed);quit(1 if failed else 0)
