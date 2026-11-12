extends SceneTree
const F=preload("res://tests/cooking_fixture.gd")
var game:Node
var output:String
var evidence:Array=[]
func _initialize()->void:call_deferred("run")
func snap(name:String,size:Vector2i,camera:String,factor:int,show_ui:bool)->void:
	root.size=size
	for child in game.get_children():
		if child is CanvasLayer:child.visible=show_ui
	var at:Array=game.world.catalog.regions.home.layout.art_cameras[camera]
	game.view.show_region("home");game.view.follow_player=false;game.view.center=Vector2(at[0],at[1]);game.view.overview=factor>1;game.view.overview_factor=factor;game.view.zoom=1
	game.island_hud.refresh();game.view.motion.advance(.1,game.world.actors);game.view.queue_redraw()
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var filename:String=name+".png";var im:=root.get_texture().get_image();assert(im.get_size()==size);assert(im.save_png(output.path_join(filename))==OK)
	evidence.append({"file":filename,"pixels":[size.x,size.y],"camera":at,"zoom":game.view.zoom,"actual_viewport":true,"residential_half_sampling_authorized":camera=="street","ui":show_ui})
func run()->void:
	output=OS.get_environment("HABITAT_LAYOUT_EVIDENCE")
	if output.is_empty() or not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):quit(1);return
	game=load("res://scenes/main_v3.tscn").instantiate();game.world=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");root.add_child(game)
	game.save_enabled=false;game.set_process(false);game.set_process_input(false);game.island_hud.set_process(false);game.view.set_process(false);game.view.set_process_unhandled_input(false);game.view.sound_enabled=false;game.world.director.set_all_enabled(false)
	for seed in range(1000):
		game.world.weather.weather_seed=seed
		if game.world.weather.current().id=="sunny":break
	await snap("01-island-1280x800",Vector2i(1280,800),"island",6,false)
	await snap("02-houses-1280x800",Vector2i(1280,800),"street",2,false)
	var at:Array=game.world.map_anchor("plaza.center")
	assert(F.job(game.world,"human",{"intent":"move","x":at[0],"y":at[1]}))
	assert(game.world.host_command("npc.mira",{"intent":"use_facility","target_id":"play.chess.bench"}).ok)
	for frame in range(2000):
		game.world.advance(.1)
		if game.world.actors["npc.mira"].activity=="seated":break
	await snap("03-plaza-1280x800",Vector2i(1280,800),"plaza",1,true)
	await snap("04-plaza-960x640",Vector2i(960,640),"plaza",1,true)
	await snap("05-forest-reserve-1280x800",Vector2i(1280,800),"logging",1,false)
	await snap("06-dock-fishery-1280x800",Vector2i(1280,800),"dock",1,false)
	for link in game.links.values():assert(link._pid<=0)
	var f:=FileAccess.open(output.path_join("viewports.json"),FileAccess.WRITE);f.store_string(JSON.stringify({"screenshots":evidence,"model_calls":0,"temporary_data":true},"  "))
	print("Layout evidence: six actual viewport screenshots");quit()
