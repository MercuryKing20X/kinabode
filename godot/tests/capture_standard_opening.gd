extends SceneTree
const World=preload("res://scripts/world_state.gd")
const F=preload("res://tests/standard_fixture.gd")
var game:Node
var f:RefCounted
var output:String
func _initialize()->void:call_deferred("run")
func fresh()->void:
	if is_instance_valid(game):game.queue_free();await process_frame
	game=load("res://scenes/main_v3.tscn").instantiate();game.world=World.new("res://content/home-v3/world.json");root.add_child(game);game.save_enabled=false;game.set_process(false);game.view.sound_enabled=false
	f=F.new();f.w=game.world;game.view.follow_player=false;game.view.zoom=1
	await process_frame
func pair(name:String)->void:
	for size in [Vector2i(1280,800),Vector2i(960,640)]:
		DisplayServer.window_set_size(size);root.size=size;root.content_scale_size=Vector2i.ZERO
		game.island_hud.refresh();game.view.queue_redraw()
		for e in f.w.director.events:
			if f.w.director.time-float(e.time)<8:game.view.say(e.text,"local_rules",e.actor_id)
		await process_frame;await process_frame;await RenderingServer.frame_post_draw
		var im:=root.get_texture().get_image();assert(im.get_size()==size);assert(im.save_png(output.path_join(name+"-%sx%s.png"%[size.x,size.y]))==OK)
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"));OS.set_environment("HABITAT_OPENING","standard");output=OS.get_environment("HABITAT_STANDARD_EVIDENCE")
	await fresh();game.choose_opening();await pair("01-opening-choice");game.opening_dialog.hide();game.opening_dialog.queue_free()
	game.view.center=f.w.point(f.w.actors.human)+Vector2(3,-1);await pair("02-standard-first-look")
	game._show_opening_board();await pair("03-notice-board")
	for node in game.get_children():
		if node is AcceptDialog:node.hide();node.queue_free()
	game.view.center=f.w.point(f.w.life.station)+Vector2(3,0);game.leisure_panel.open_site("play.standard.camp");await pair("04-camp-to-build");game.leisure_panel.hide()
	assert(f.build_first())
	var w:RefCounted=f.w;var at:Vector2=w.point(w.life.station)
	var BBQ=preload("res://tests/barbecue_fixture.gd")
	assert(BBQ.start(w,"single:mushroom",["human"]+w.standard.config.companions,"home.barbecue",f.tick).ok)
	for frame in range(1200):
		f.tick()
		if w.work.jobs.values().any(func(job):return job.get("phase")=="fire_eat"):break
	assert(w.work.jobs.values().any(func(job):return job.get("phase")=="fire_eat"))
	game.view.center=at+Vector2(7,4);await pair("05-first-real-meal")
	assert(BBQ.finish(w,["human"]+w.standard.config.companions,"home.barbecue",f.tick));f.advance(180)
	game.memory_panel.open();assert(game.memory_panel.page.ok);game.memory_panel.hide()
	game.view.center=at;await pair("07-resident-new-rows")
	await fresh()
	while f.elapsed<1800:f.tick(.5)
	var center:Array=f.w.map_anchor("plaza.center");assert(f.job({"intent":"move","x":center[0]+10,"y":center[1]+8}));f.advance(100)
	game.view.center=f.w.point(f.w.actors.human)-Vector2(0,2);await pair("06-neglected-followers")
	print("Standard opening: 14 actual viewport screenshots complete")
	game.queue_free();await process_frame;await create_timer(.4).timeout;quit()
