extends "res://tests/capture_home_v3_ui_polish.gd"
const F=preload("res://tests/cooking_fixture.gd")
func phase(id:String,weather_id:String="sunny")->void:
	if game.world.days.phase().id!=id:
		var item:Dictionary=game.world.days.config.phases.filter(func(p):return p.id==id)[0]
		var target:float=float(item.start)*game.world.days.day_seconds+5
		if game.world.days.within_day()>target:target+=game.world.days.day_seconds
		var remaining:float=target-game.world.days.within_day()
		while remaining>.00001:var step:float=minf(1,remaining);game.world.advance(step);remaining-=step
	for seed in range(1000):
		game.world.weather.weather_seed=seed
		if game.world.weather.current().id==weather_id:break
	game.view.atmosphere.refresh_houses(game.view,true);game.view.update_ambience()
func wait_phase(wanted:String)->void:
	for tick in range(15000):
		game.world.advance(.05)
		if game.world.shared_activity.session.phase==wanted:return
		assert(game.world.shared_activity.session.status!="paused",str(game.world.shared_activity.session))
	assert(false,"activity phase timeout")
func run()->void:
	output=OS.get_environment("HABITAT_MOON_EVIDENCE")
	if output.is_empty() or not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):quit(1);return
	game=load("res://scenes/main_v3.tscn").instantiate();game.world=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");root.add_child(game)
	game.save_enabled=false;game.set_process(false);game.set_process_input(false);game.island_hud.set_process(false);game.view.set_process(false);game.view.set_process_unhandled_input(false);game.view.sound_enabled=false;game.world.director.set_all_enabled(false)
	var layout:Dictionary=game.world.catalog.regions.home.layout
	layout.art_cameras["all"]=game.world.map_anchor("moon.overview");layout.art_cameras["bridge"]=[-5,45.5];layout.art_cameras["moon"]=game.world.map_anchor("moon.camera");layout.art_cameras["lookout"]=game.world.map_anchor("moon.lookout");layout.art_cameras["moon_bbq"]=game.world.map_anchor("moon.camp");layout.art_cameras["home_bbq"]=game.world.map_anchor("camp.stove")
	await snap("01-both-islands",Vector2i(1280,800),"all",9,"afternoon")
	var at:Array=game.world.map_anchor("moon.bridge.east");assert(F.job(game.world,"human",{"intent":"move","x":at[0],"y":at[1]}))
	assert(game.world.command("human",{"intent":"move","x":game.world.map_anchor("moon.bridge.west")[0],"y":game.world.map_anchor("moon.bridge.west")[1]}).ok)
	for tick in range(40):game.world.advance(.1)
	await snap("02-bridge-day",Vector2i(1280,800),"bridge",1,"afternoon")
	assert(F.wait(game.world,"human"))
	await snap("03-moon-day",Vector2i(1280,800),"moon",5,"afternoon")
	while game.world.days.day()<5:game.world.advance(1)
	phase("night")
	await snap("04-moon-full-reflection",Vector2i(1280,800),"moon",5,"night")
	var site:String=game.world.moon.config.platform_sites[0]
	for id in ["human","codex"]:assert(game.world.command(id,{"intent":"use_facility","target_id":site if id=="human" else game.world.moon.config.platform_sites[2]}).ok)
	for tick in range(3000):
		game.world.advance(.1)
		if game.world.moon.last_viewing_day==game.world.days.day():break
	assert(game.world.actors.human.activity=="seated" and game.world.actors.codex.activity=="seated")
	await snap("05-moon-platform-seated",Vector2i(1280,800),"lookout",1,"night")
	for id in ["human","codex"]:game.world.command(id,{"intent":"stop"})
	phase("dusk") # Prepare in the evening; capture early night rather than the dawn transition.
	assert(preload("res://tests/barbecue_fixture.gd").start(game.world,"single:mushroom",["human","codex","companion-2"],"moon.barbecue").ok)
	assert(game.world.barbecues["moon.barbecue"].station.state=="cooking")
	phase("night")
	await snap("06-moon-barbecue-night",Vector2i(1280,800),"moon_bbq",1,"night","sunny",true)
	await snap("09-moon-barbecue-960x640",Vector2i(960,640),"moon_bbq",1,"night","sunny",true)
	game.world.barbecues["moon.barbecue"].fireside.end_circle("host ends capture circle")
	game.world.command("human",{"intent":"stop"});at=game.world.map_anchor("camp.stove");assert(F.job(game.world,"human",{"intent":"move","x":at[0],"y":at[1]+3}))
	game._show_barbecue_menu("home.barbecue")
	await snap("07-home-barbecue-newcomer",Vector2i(1280,800),"home_bbq",1,"afternoon","sunny",true)
	game.chat.hide()
	await snap("08-moon-fog-night",Vector2i(1280,800),"lookout",1,"night","fog")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);Engine.max_fps=0
	phase("afternoon")
	await probe("all",9,true);await probe("plaza",1,true)
	for link in game.links.values():assert(link._pid<=0)
	var file:=FileAccess.open(output.path_join("viewports.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"screenshots":evidence,"models":0,"emitter_limits":game.view.atmosphere.stats(),"moon_viewing_memory":game.world.memories.records.filter(func(e):return e.kind=="moon_viewing"),"actual_viewport":true},"  "))
	file=FileAccess.open(output.path_join("performance.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"samples":performance,"adapter":RenderingServer.get_video_adapter_name(),"method":"same 24 warmup + 120 frames, real World.advance(1/60), no models/UI polling"},"  "))
	print("Moon island: nine actual viewports and final performance samples");quit()
