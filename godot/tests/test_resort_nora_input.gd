extends "res://tests/test_intelligence_core_input.gd"
## UI/Integration — controlled genuine-state speech delivery fixture — BLOCKING click binding.
## Does not prove spontaneous selection frequency. No stock/position/hunger injections.
func click_bubble(id:String)->void:
	game.view.center=game.world.point(game.world.actors[id]);game.view.follow_player=false;game.view.queue_redraw()
	await process_frame;await process_frame
	var entries:Array=game.view.speech_layout().filter(func(e):return e.actor_id==id)
	for i in 40:
		if not entries.is_empty():break
		game._process(.1);await process_frame
		entries=game.view.speech_layout().filter(func(e):return e.actor_id==id)
	if entries.is_empty():print("NEED_LAYOUT_DIAG ",id," speech=",game.view.speech_by_actor.get(id,{})," clock=",game.view.clock," speech_actor=",game.view.speech_actor," until=",game.view.speech_until," cue=",game.world.hunger.visible_cue(id)," entries=",game.view.speech_layout())
	check(not entries.is_empty(),"real rendered need bubble exists for "+id)
	if entries.is_empty():return
	var at:Vector2=entries[0].box.get_center()
	var motion:=InputEventMouseMotion.new();motion.position=at;motion.global_position=at;root.push_input(motion,true)
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=at;event.global_position=at;event.pressed=down;event.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0;root.push_input(event,true);await process_frame
func run()->void:
	await fresh()
	var w:RefCounted=game.world
	var id:String="npc.nora"
	var needs:RefCounted=w.director.routines[id].needs
	var delivered:bool=false
	await text_input("大家跟我来");game.chat.hide()
	id="npc.nora";needs=w.director.routines[id].needs
	delivered=false
	for i in 6000:
		game._process(.1)
		if i%100==0:await process_frame
		if game.view.speech_by_actor.get(id,{}).get("context")=="need_fish":delivered=true;break
	check(delivered,"spontaneous genuine Nora fishing bubble")
	game.view.center=w.point(w.actors[id]);game.view.queue_redraw();await picture("nora-real-fish-need")
	await click_bubble(id)
	check(w.work.jobs.get(id,{}).get("intent")=="fish","native fish bubble creates exact real Nora fish job")
	await picture("nora-real-fish-invite")
	print("RESORT_NEEDS_INPUT ",checks," failed=",failed)
	game.queue_free();await process_frame;quit(1 if failed else 0)
