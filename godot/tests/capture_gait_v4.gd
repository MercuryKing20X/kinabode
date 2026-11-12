extends SceneTree
const World=preload("res://scripts/world_state.gd")
const Library=preload("res://scripts/character_library.gd")
const Opening=preload("res://scripts/world_opening.gd")
var w:RefCounted
var view:Node2D
var output:String
var images:Array=[]
var frames:Array=[]
func _initialize()->void:call_deferred("run")
func step(delta:float)->void:
	w.advance(delta);view.clock+=delta
	var running:Dictionary={};var movements:Dictionary={};var gaits:Dictionary={}
	for id in w.actors:running[id]=w.is_running(id);movements[id]=w.motion_state(id);gaits[id]=w.intelligence.gait(id)
	view.motion.advance(delta,w.actors,running,movements,gaits);view.update_ambience();view.queue_redraw()
func wait(id:String)->void:
	for tick in range(6000):
		if not w._routes.has(id) and not w.work.jobs.has(id):return
		step(.05)
	assert(false,"actual gait-capture action timed out")
func move(id:String,p:Vector2)->void:
	assert(w.command(id,{"intent":"move","x":p.x,"y":p.y}).ok);wait(id)
func shot(name:String)->void:
	for size in [Vector2i(1280,800),Vector2i(960,640)]:
		DisplayServer.window_set_size(size);root.size=size;root.content_scale_size=Vector2i.ZERO;view.queue_redraw()
		await process_frame;await process_frame;await RenderingServer.frame_post_draw
		var path:String=output.path_join(name+"-%sx%s.png"%[size.x,size.y]);var im:Image=root.get_texture().get_image()
		assert(im.get_size()==size and im.save_png(path)==OK);images.append(path.get_file())
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"));output=OS.get_environment("HABITAT_STAGE2_EVIDENCE");assert(not output.is_empty())
	w=World.new("res://content/home-v3/world.json");w.residents.provision(w);w.library=Library.new();w.library.configure(OS.get_environment("HABITAT_DATA_DIR"));assert(Opening.apply(w,w.library,"showcase").ok);w.intelligence.activate_presets();w.director.set_all_enabled(false)
	view=preload("res://scripts/island_v3_view.gd").new();view.world=w;view.library=w.library;view.font=load("res://assets/fonts/NotoSansSC.ttf");view.sound_enabled=false;root.add_child(view);view.set_process(false);view.follow_player=false;view.zoom=1
	var center:Array=w.map_anchor("plaza.center");var start:=Vector2(center[0]-3,center[1]+10);var finish:Vector2=start+Vector2(8,0)
	assert(w.walkable("home",start) and w.segment_clear("home",start,finish))
	view.center=start+Vector2(3,-1)
	await process_frame
	for id in w.actors:
		move(id,start)
		assert(w.command(id,{"intent":"move","x":finish.x,"y":finish.y}).ok)
		for index in range(6):
			step(.075)
			var motion:Dictionary=w.motion_state(id);assert(motion.moving)
			frames.append({"actor_id":id,"frame":index,"position":w.actors[id].position.duplicate(),"facing":w.actors[id].facing,"motion":{"facing":motion.facing,"still_seconds":motion.still_seconds},"gait":w.intelligence.gait(id)})
			await shot("gait-"+id+"-"+str(index).pad_zeros(2))
		wait(id)
		var plots:Array=w.catalog.regions.home.layout.residential.filter(func(plot):return plot.owner_id==id)
		assert(not plots.is_empty() and w.command(id,{"intent":"enter","target_id":plots[0].site_id}).ok);wait(id)
	for id in w.actors:
		assert(w.command(id,{"intent":"exit"}).ok);wait(id)
	move("human",start);move("human",start+Vector2(0,-2))
	w.hunger.start();step(1600);w.director.set_all_enabled(true)
	for i in range(2400):step(.05)
	view.center=w.point(w.actors.human)+Vector2(0,3)
	await shot("follow-formation")
	var nearest:String=""
	for id in w.hunger.follow_targets:
		if nearest.is_empty() or w.point(w.actors[id]).distance_to(w.point(w.actors.human))<w.point(w.actors[nearest]).distance_to(w.point(w.actors.human)):nearest=id
	assert(not nearest.is_empty())
	var direction:Vector2=(w.point(w.actors[nearest])-w.point(w.actors.human)).normalized();var target:Vector2=w.point(w.actors[nearest])+direction*3
	assert(w.command("human",{"intent":"move","x":target.x,"y":target.y}).ok)
	for index in range(6):
		step(.12);await shot("follow-cross-"+str(index))
		for id in w.actors:
			var m:Dictionary=w.motion_state(id)
			frames.append({"scenario":"follow_cross","frame":index,"actor_id":id,"position":w.actors[id].position.duplicate(),"facing":w.actors[id].facing,"moving":m.moving,"motion_facing":m.facing,"yielding":w.hunger.follow_targets.get(id,{}).get("yielding",false)})
	var result:Dictionary={"actual_viewport":true,"model_calls":0,"new_character_art":false,"images":images,"frames":frames,"frame_seconds":.075,"gifs":"generated from the actual 1280 viewport crops without rescaling"}
	var file:=FileAccess.open(output.path_join("gait-viewports.json"),FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
	print("Gait v4 actual viewport capture: ",images.size()," images; actual movement records=",frames.size());view.queue_free();await process_frame;quit()
