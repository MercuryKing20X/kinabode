extends "res://tests/test_intelligence_core_input.gd"
## UI/Integration — controlled genuine-state speech delivery fixture — BLOCKING click binding.
## Does not prove spontaneous selection frequency. No stock/position/hunger injections.
func click_bubble(id:String)->void:
	game.view.center=game.world.point(game.world.actors[id]);game.view.follow_player=false;game.view.queue_redraw()
	await process_frame;await process_frame
	var entries:Array=game.view.speech_layout().filter(func(e):return e.actor_id==id)
	check(not entries.is_empty(),"real rendered need bubble exists for "+id)
	if entries.is_empty():return
	var at:Vector2=entries[0].box.get_center()
	var motion:=InputEventMouseMotion.new();motion.position=at;motion.global_position=at;root.push_input(motion,true)
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=at;event.global_position=at;event.pressed=down;event.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0;root.push_input(event,true);await process_frame
func run()->void:
	await fresh()
	var w:RefCounted=game.world
	const Cook=preload("res://tests/cooking_fixture.gd")
	check(Cook.job(w,"human",{"intent":"gather_wood","tree_count":3}),"original gathered camp materials")
	check(Cook.job(w,"human",{"intent":"build_facility","target_id":"play.standard.camp"}),"original camp built using original starting wood")
	check(w.standard.ready("home.barbecue"),"main camp truly complete")
	await text_input("大家跟我来");game.chat.hide()
	var id:String="companion-2"
	var needs:RefCounted=w.director.routines[id].needs
	var delivered:bool=false
	for i in 1800:
		game._process(.1)
		if i%100==0:await process_frame
		if game.view.speech_by_actor.get(id,{}).get("context")=="need_hungry":delivered=true;break
	check(delivered,"spontaneous genuine blue hunger bubble")
	game.view.center=w.point(w.actors[id]);game.view.queue_redraw();await picture("blue-real-hungry")
	await click_bubble(id)
	print("BUBBLE_DIAG status=",game.status.text," guests=",w.life.fireside.selected_guests," fire=",game.local_host_commands.nearest_fire()," context=",game.view.speech_by_actor.get(id,{}))
	check(w.life.fireside.selected_guests==[id],"native hungry bubble accepts original BBQ invitation for blue only")
	await picture("blue-hungry-invite")
	check(Cook.job(w,"human",{"intent":"gather_wood","tree_count":1}),"real wood for feedback meal")
	const BBQ=preload("res://tests/barbecue_fixture.gd")
	check(BBQ.approach(w),"real human route to camp")
	check(w.life.fireside.light_host().ok,"real fuel consumed")
	check(w.life.fireside.invite([id]).ok,"blue explicitly invited to actual meal")
	check(w.life.fireside.roast_host("single:mushroom").ok,"real ingredients consumed")
	for i in 1200:
		game._process(.1)
		if i%100==0:await process_frame
		if id in w.life.fireside.state.current.eaters:break
	check(id in w.life.fireside.state.current.eaters,"blue genuinely eats")
	w.life.fireside.end_circle("meal complete")
	delivered=false
	for i in 1200:
		game._process(.1)
		if i%100==0:await process_frame
		if game.view.speech_by_actor.get(id,{}).get("context")=="need_satisfied":delivered=true;break
	check(delivered,"real meal causes happy feedback through original gates")
	game.view.center=w.point(w.actors[id]);game.view.queue_redraw();await picture("blue-real-happy")
	print("RESORT_HAPPY_INPUT ",checks," failed=",failed)
	game.queue_free();await process_frame;quit(1 if failed else 0)
