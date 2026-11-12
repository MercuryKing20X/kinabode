extends SceneTree
const F=preload("res://tests/cooking_fixture.gd")
var game:Node
var output:String
var records:Array=[]
var commands:Array=[]
func _initialize()->void:call_deferred("run")
func job(id:String,args:Dictionary)->bool:
	var result:bool=F.job(game.world,id,args);commands.append({"actor_id":id,"command":args.duplicate(true),"completed":result})
	if not result:push_error("Viewport setup real action failed "+str(args));quit(1)
	return result
func phase(id:String)->void:
	for tick in range(16000):
		if game.world.days.phase().id==id:return
		game.world.advance(.1)
	push_error("phase not reached");quit(1)
func weather(id:String)->void:
	for seed in range(1000):
		game.world.weather.weather_seed=seed
		if game.world.weather.current().id==id:return
func layers(show_ui:bool)->void:
	for child in game.get_children():
		if child is CanvasLayer:child.visible=show_ui
func shot(name:String,camera:String,show_ui:bool=false)->void:
	layers(show_ui)
	if camera!="room":
		game.view.show_region("home");var at:Array=game.world.catalog.regions.home.layout.art_cameras[camera];game.view.center=Vector2(at[0],at[1])
	game.view.follow_player=false;game.view.zoom=1;game.view.overview=camera=="island"
	for size in [Vector2i(1280,800),Vector2i(960,640)]:
		root.size=size;game.view.overview_factor=5 if size.x==1280 else 6
		game.island_hud.refresh();game.view.motion.advance(.1,game.world.actors);game.view.queue_redraw()
		await process_frame;await process_frame;await RenderingServer.frame_post_draw
		var filename:String=name+"-"+str(size.x)+"x"+str(size.y)+".png"
		var im:=root.get_texture().get_image();assert(im.get_size()==size);assert(im.save_png(output.path_join(filename))==OK)
		records.append({"file":filename,"pixels":[size.x,size.y],"phase":game.world.days.phase().id,"weather":game.world.weather.current().id,"camera":[game.view.center.x,game.view.center.y],"zoom":game.view.zoom,"actual_viewport":true,"ui":show_ui,"human_position":game.world.actors.human.position.duplicate(),"human_region":game.world.actors.human.region_id})
func run()->void:
	output=OS.get_environment("HABITAT_STAGE2_EVIDENCE")
	if output.is_empty() or not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):quit(1);return
	game=load("res://scenes/main_v3.tscn").instantiate();game.world=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");root.add_child(game)
	game.save_enabled=false;game.set_process(false);game.island_hud.set_process(false);game.view.set_process(false);game.view.sound_enabled=false;game.world.director.set_all_enabled(false)
	weather("sunny")
	await shot("06-farms-growth","farm") # genuine opening phases, before time advances them to maturity
	await shot("01-island-overview","island")
	await shot("04-five-houses","street")
	for camera in ["dock","logging","lookout"]:await shot({"dock":"07-main-dock","logging":"08-logging-forest","lookout":"09-lookout"}[camera],camera)
	var house:Dictionary=game.world.objects["home.house.02"]
	if not job("human",{"intent":"enter","target_id":house.id}):return
	game.view.show_region(game.world.actors.human.region_id);game.view.center=game.world.interior.FLOOR.get_center();game.view.zoom=1
	await shot("05-partner-home","room",true)
	if not job("human",{"intent":"exit"}):return
	phase("afternoon");weather("sunny")
	var camp:Array=game.world.map_anchor("plaza.center")
	if not job("human",{"intent":"move","x":camp[0],"y":camp[1]}):return
	for pair in [["codex","play.gazebo"],["npc.mira","play.swing"],["npc.nora","play.chess.bench"]]:
		var result:Dictionary=game.world.host_command(pair[0],{"intent":"use_facility","target_id":pair[1]});assert(result.ok)
	for tick in range(1600):
		game.world.advance(.1)
		if game.world.work.jobs.values().any(func(j):return j.get("step")=="using"):break
	await shot("02-plaza-afternoon","plaza",true)
	for id in game.world.director.routines:game.world.command(id,{"intent":"stop"})
	weather("rain");await shot("10-rain","plaza",true)
	weather("fog");await shot("10-fog","street",true)
	weather("sunny")
	var shore:Array=game.world.map_anchor("dock.south.end")
	if not job("human",{"intent":"move","x":shore[0],"y":shore[1]}) or not job("human",{"intent":"fish"}):return
	game.island_hud.refresh();game.island_hud.show_card("codex")
	await shot("11-avatar-card","dock",true);game.island_hud.resident_card.hide()
	await shot("11-notification-fish","dock",true)
	var fish:Dictionary=game.world.fishing.held("human");assert(game.world.command("human",{"intent":"stock_fish","fish_id":fish.id,"pen_id":"home.fishery.south"}).ok)
	if not job("human",{"intent":"move","x":camp[0],"y":camp[1]+3}):return
	var result:Dictionary=game.world.command("human",{"intent":"move","x":camp[0]-3,"y":camp[1]+4});assert(result.ok);game.world.advance(.2)
	await shot("11-current-task","plaza",true);game.world.command("human",{"intent":"stop"})
	if not job("human",{"intent":"move","x":game.world.life.station.position[0],"y":game.world.life.station.position[1]+3}):return
	await shot("11-onsite-cooking","plaza",true)
	phase("night");weather("sunny")
	assert(job("codex",{"intent":"barbecue","target_id":"home.barbecue"}))
	await shot("03-plaza-night","plaza",true)
	for id in game.links:assert(game.links[id]._pid<=0)
	var f:=FileAccess.open(output.path_join("viewport-records.json"),FileAccess.WRITE);f.store_string(JSON.stringify({"records":records,"real_setup_actions":commands,"real_model_calls":0,"player_save_read":false,"original_works_modified":false},"  "))
	print("Home v3 acceptance: ",records.size()," actual viewport screenshots.");quit()
