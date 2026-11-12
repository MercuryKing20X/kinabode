extends SceneTree
var game:Node
var output:String
var evidence:Array=[]
var performance:Array=[]
func _initialize()->void:call_deferred("run")
func phase(id:String,weather_id:String="sunny")->void:
	var current:float=game.world.forest.clock-game.world.days.origin
	var item:Dictionary=game.world.days.config.phases.filter(func(p):return p.id==id)[0]
	var target:float=floor(current/game.world.days.day_seconds)*game.world.days.day_seconds+(float(item.start)+.07)*game.world.days.day_seconds
	if target<current:target+=game.world.days.day_seconds
	while game.world.forest.clock-game.world.days.origin<target-.0001:game.world.advance(minf(1,target-(game.world.forest.clock-game.world.days.origin)))
	for seed in range(1000):
		game.world.weather.weather_seed=seed
		if game.world.weather.current().id==weather_id:break
	game.view.clock+=1;game.view.atmosphere.refresh_houses(game.view,true);game.view.update_ambience()
func camera(key:String,factor:int)->void:
	var at:Array=game.world.catalog.regions.home.layout.art_cameras[key]
	game.view.show_region("home");game.view.follow_player=false;game.view.center=Vector2(at[0],at[1]);game.view.overview=factor>1;game.view.overview_factor=factor;game.view.zoom=1
func snap(name:String,size:Vector2i,key:String,factor:int,time:String,weather_id:String="sunny",ui:bool=false)->void:
	root.size=size
	for child in game.get_children():
		if child is CanvasLayer:child.visible=ui
	phase(time,weather_id);camera(key,factor);game.view.update_ambience()
	if key=="plaza":
		var at:Array=game.world.map_anchor("plaza.center")
		assert(preload("res://tests/cooking_fixture.gd").job(game.world,"human",{"intent":"move","x":at[0],"y":at[1]}))
	game.island_hud._process(6);game.island_hud.refresh();game.view.motion.advance(.1,game.world.actors);game.view.queue_redraw();game.view.emission.queue_redraw()
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var image:Image=root.get_texture().get_image();assert(image.get_size()==size);assert(image.save_png(output.path_join(name+".png"))==OK)
	evidence.append({"file":name+".png","size":[size.x,size.y],"phase":game.world.days.phase().id,"weather":game.world.weather.current().id,"day":game.world.days.day(),"camera":key,"zoom":game.view.zoom,"actual_viewport":true})
func probe(key:String,factor:int,enabled:bool)->void:
	root.size=Vector2i(1280,800);camera(key,factor);game.view.ambience_enabled=enabled;game.view.set_process(true)
	var samples:Array=[]
	for i in range(144):
		var start:int=Time.get_ticks_usec();game.world.advance(1.0/60)
		await process_frame;await RenderingServer.frame_post_draw
		if i>=24:samples.append((Time.get_ticks_usec()-start)/1000.0)
	game.view.set_process(false);samples.sort()
	var total:float=samples.reduce(func(a,b):return a+b,0.0)
	performance.append({"camera":key,"ambience":enabled,"viewport":[1280,800],"frames":samples.size(),"fps":1000.0/(total/samples.size()),"mean_ms":total/samples.size(),"p95_ms":samples[int(samples.size()*.95)],"vsync":"disabled","world_advance_per_frame":1.0/60,"models":0})
func run()->void:
	output=OS.get_environment("HABITAT_UI_POLISH_EVIDENCE")
	if output.is_empty() or not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):quit(1);return
	game=load("res://scenes/main_v3.tscn").instantiate();game.world=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");root.add_child(game)
	game.save_enabled=false;game.set_process(false);game.set_process_input(false);game.island_hud.set_process(false);game.view.set_process(false);game.view.set_process_unhandled_input(false);game.view.sound_enabled=false;game.world.director.set_all_enabled(false)
	await snap("01-plaza-afternoon",Vector2i(1280,800),"plaza",1,"afternoon","sunny",true)
	await snap("02-plaza-night",Vector2i(1280,800),"plaza",1,"night","sunny",true)
	await snap("03-houses-afternoon",Vector2i(1280,800),"street",2,"afternoon")
	await snap("04-houses-night",Vector2i(1280,800),"street",2,"night")
	await snap("05-island-afternoon",Vector2i(1280,800),"island",6,"afternoon")
	await snap("06-dock-fishery",Vector2i(1280,800),"dock",1,"afternoon")
	await snap("07-plaza-960x640-residents",Vector2i(960,640),"plaza",1,"afternoon","sunny",true)
	game.island_hud.toggle_residents()
	await snap("08-plaza-960x640-collapsed",Vector2i(960,640),"plaza",1,"afternoon","sunny",true)
	# Weather overlay paths must also draw without errors for cloudy and fog at night.
	for weather_id in ["cloudy","fog"]:
		phase("night",weather_id);game.view.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
	phase("afternoon");DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);Engine.max_fps=0
	for key in ["island","plaza"]:
		for enabled in [false,true]:await probe(key,6 if key=="island" else 1,enabled)
	assert(game.view.static_bakes==1) # Day/night/camera/actors did not rebuild static land.
	var before:int=game.world.revision;var builds:int=game.view.terrain.cache_builds
	game.view.ground_config=game.view.ground_config.duplicate(true);game.view.ground_config.formal_plaza.ring_tint="#787365";game.view.invalidate_static_cache()
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	assert(game.view.static_bakes==2 and game.view.terrain.cache_builds==builds+1 and game.world.revision==before)
	for link in game.links.values():assert(link._pid<=0)
	var file:=FileAccess.open(output.path_join("viewports.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"screenshots":evidence,"model_calls":0,"temporary_data":true,"emitter_limits":game.view.atmosphere.stats(),"static_bakes_after_explicit_invalidation":game.view.static_bakes,"idle_static_bakes":1,"gpu_cache_invalidation_verified":true,"farm_bakes":game.view.farm_bakes,"decor_bakes":game.view.decor_bakes},"  "))
	file=FileAccess.open(output.path_join("performance.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"samples":performance,"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"mode":"actual viewport + World.advance; dialogue/UI polling disabled; no gameplay tick changes"},"  "))
	print("Ambience: eight actual viewports and four performance samples");quit()
