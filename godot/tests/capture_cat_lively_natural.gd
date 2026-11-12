extends SceneTree
var game:Node
var output:String
var seen:Dictionary={}
var observed_pairs:Dictionary={}
func _initialize()->void:call_deferred("run")
func shot(name:String)->void:
	if DisplayServer.get_name()=="headless" or output.is_empty():return
	game.view.queue_redraw()
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name+".png"))
func run()->void:
	output=OS.get_environment("HABITAT_LIFE_CAPTURE")
	OS.set_environment("HABITAT_OPENING","showcase")
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	var fixture=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json")
	fixture.residents.provision(fixture);fixture.library=preload("res://scripts/character_library.gd").new();fixture.library.configure(OS.get_environment("HABITAT_DATA_DIR"))
	assert(preload("res://scripts/world_opening.gd").apply(fixture,fixture.library,"showcase").ok)
	assert(preload("res://scripts/save_store.gd").save_world(fixture,OS.get_environment("HABITAT_DATA_DIR")))
	game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game)
	game.save_enabled=false;game.set_process(false)
	for i in range(30):await process_frame
	game.chat.hide();game.chat_input.release_focus();game.world.intelligence.activate_presets();game.world.director.set_all_enabled(true)
	game.view.follow_player=false;game.view.zoom=2
	var w:RefCounted=game.world
	# A real paid breakfast is a preparation phase, not a hunger override.
	var BBQ=preload("res://tests/barbecue_fixture.gd")
	assert(BBQ.approach(w))
	assert(BBQ.start(w,"single:mushroom",w.director.routines.keys()).ok)
	for tick in range(6000):
		w.advance(.1)
		if w.director.routines.keys().all(func(id):return id in w.life.fireside.state.current.get("eaters",[])):break
	assert(w.director.routines.keys().all(func(id):return id in w.life.fireside.state.current.get("eaters",[])))
	w.life.fireside.end_circle("host ends preparation breakfast")
	var near_seconds:=0.0
	var elapsed:=0.0
	for frame in range(1200):

		game._process(.5);elapsed+=.5
		if w.actors["npc.mira"].region_id==w.actors.human.region_id and w.point(w.actors["npc.mira"]).distance_to(w.point(w.actors.human))<=8:near_seconds+=.5
		for id in w.cat.interactions:
			if not seen.has(id):
				seen[id]={"at":elapsed,"count":w.cat.interactions[id]}
				game._process(.01)
				game.view.show_region(w.actors[id].region_id);game.view.center=w.point(w.actors[id])
				await shot("natural-cat-"+id)
		for action in w.lively.pair_counts:
			if not observed_pairs.has(action):
				observed_pairs[action]={"at":elapsed,"count":w.lively.pair_counts[action]}
				for id in w.lively.active:
					if w.lively.active[id].action==action:game.view.center=w.point(w.actors[id]);break
				await shot("natural-pair-"+action)
		if frame%120==0:await process_frame
	var result:Dictionary={"controller":"Main._process","seconds":elapsed,"cat":seen,"pairs":observed_pairs,"orange_within8_percent":near_seconds/elapsed*100,"counts":w.lively.counts,"pair_counts":w.lively.pair_counts}
	var report:String=OS.get_environment("HABITAT_LIFE_REPORT")
	if not report.is_empty():
		var f:=FileAccess.open(report,FileAccess.WRITE);f.store_string(JSON.stringify(result,"\t"));f.close()
	print("NATURAL_LIFE ",JSON.stringify(result))
	var complete:bool=w.director.routines.keys().all(func(id):return seen.has(id)) and w.lively.config.pairs.all(func(action):return observed_pairs.has(action))
	if not complete:push_error("Natural observation did not cover every resident contact and all six interactions")
	game.queue_free();await process_frame
	quit(0 if complete else 1)
