extends "res://tests/test_basic_plan.gd"

func run()->void:
	var dir:String=OS.get_environment("HABITAT_DATA_DIR")
	if not dir.contains("youqi-test-") or DisplayServer.get_name()=="headless":quit(2);return
	OS.set_environment("HABITAT_OPENING","standard")
	OS.set_environment("HABITAT_WORLD_SEED","8027")
	set_meta("title_fresh",true);set_meta("title_opening","standard")
	preload("res://scripts/connection_session_pool.gd").obtain(self,dir).factory=func(_id):return Offline.new()
	var game:Node=load("res://scenes/main_v3.tscn").instantiate()
	game.dialogue_adapter_factory=func(_id,_scope):return Offline.new()
	root.add_child(game);current_scene=game
	game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.welcome=null
	await process_frame
	var w:RefCounted=game.world
	var notes:RefCounted=w.island_notes
	var doorstep:Vector2=notes.places().get("doorstep",Vector2.INF)
	var fish:=preload("res://tests/fishing_fixture.gd")
	w.director.set_all_enabled(false)
	if not preload("res://tests/backpack_fixture.gd").wood(w,1,"human") or not fish.walk(w,"human",[43,210]) or not w.host_command("human",{"intent":"trade_flowers","quantity":2,"color":"red"}).ok:quit(3);return
	var near:Vector2=w.nearest_walkable("home",doorstep+Vector2(2,3))
	if not fish.walk(w,"human",[near.x,near.y]):quit(4);return
	near=w.nearest_walkable("home",doorstep+Vector2(-2,1))
	if not fish.walk(w,"codex",[near.x,near.y]):quit(5);return
	game.chat.hide();game.view.center=doorstep;game.view.follow_player=false;game.view.zoom=1
	w.director.set_all_enabled(true)
	var b:RefCounted=w.director.brains.codex
	b.clock=w.director.time
	if not b.intention.basic.accept({"reason":"想让你一回家就看见花。","steps":[{"action":"pick_up","item":"rose_red"},{"action":"go_to","target":"doorstep"},{"action":"put_down","item":"rose_red"},{"action":"write_note","target":"human","place":"doorstep","text":"花放在门边。你回来时应该就看得见呀。","en":"I left a rose by the door where you'll spot it on your way home."}]},"local"):quit(6);return
	for frame in 200:
		game._process(.067);game.view._process(.067);game.view.queue_redraw()
		if frame==90 and not notes.rows.is_empty():
			click(game.view.note_rect(notes.rows.values()[0],false).get_center())
		if frame==130:
			for node in game.get_children():
				if node is AcceptDialog and node.visible:node.hide();node.queue_free()
		if frame==140 and not notes.gifts.is_empty():click(game.view.note_rect(notes.gifts.values()[0],true).get_center())
		await RenderingServer.frame_post_draw
	print("DOORSTEP_CLIP ",notes.first.keys()," collected=",notes.gifts.is_empty())
	quit(0 if notes.first.size()==2 and notes.gifts.is_empty() else 1)

func click(at:Vector2)->void:
	for down in [true,false]:
		var event:=InputEventMouseButton.new()
		event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.position=at;event.global_position=at
		root.push_input(event,true)
