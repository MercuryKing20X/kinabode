extends SceneTree
const Audio=preload("res://scripts/game_audio.gd")
const Helper=preload("res://tests/test_barbecue_v2.gd")
var checks:=0
var failed:=false
func check(ok:bool,msg:String)->void:
	checks+=1
	if not ok:failed=true;push_error(msg)
func _initialize()->void:call_deferred("run")
func played(audio:Node,id:String)->bool:return audio.trace.any(func(e):return e.action=="scheduled" and e.event==id)
func run()->void:
	var temp:String=OS.get_environment("HABITAT_DATA_DIR");assert(temp.contains("youqi-test-"))
	var helper:=Helper.new();var w:RefCounted=helper.fresh(temp);w.intelligence.activate_presets()
	var view:Node=preload("res://scripts/island_v3_view.gd").new();view.world=w;view.library=w.library;view.font=load("res://assets/fonts/NotoSansSC.ttf");view.sound_enabled=false;root.add_child(view);view.set_process(false);view.ambience_enabled=false
	view.center=w.point(w.actors.human)
	var audio:=Audio.new();root.add_child(audio);audio.setup(w,view,temp)
	check(audio.error.is_empty(),"environment current manifest loads")
	var observer:RefCounted=audio.observer;var rev:int=w.revision;var fish_rng:int=w.fishing.rng.state;var weather_seed:int=w.weather.weather_seed
	check(observer.surface("home",w.point(w.actors.human)) in ["grass","sand","stone","wood"],"surface reads actual continuous material")
	var found:Dictionary={}
	for surface in ["grass","sand","stone"]:
		for command in view.terrain.commands:
			if command.kind!="surface" or (not str(command.material).begins_with("grass") if surface=="grass" else not str(command.material).begins_with("sand") if surface=="sand" else not str(command.material).begins_with("slab")):continue
			var center:=Vector2.ZERO
			for p in command.shape:center+=p
			center/=command.shape.size()*32.0
			if observer.surface("home",center)==surface:found[surface]=center;break
		check(found.has(surface),"actual rendered "+surface+" polygon selected")
	for dock in w.catalog.regions.home.layout.dock_surfaces:
		if dock.id=="moon.platform":continue
		var center:=Vector2.ZERO
		for p in dock.polygon:center+=Vector2(p[0],p[1])
		center/=dock.polygon.size()
		check(observer.surface("home",center)=="wood","actual dock/bridge chooses wood "+dock.id)
	for i in range(20):audio.advance(.1)
	check(played(audio,"ambience.wind") and played(audio,"ambience.birds"),"real day ambient loops start")
	check(w.revision==rev and w.fishing.rng.state==fish_rng and w.weather.weather_seed==weather_seed,"environment modifies no World/RNG state")
	check(not played(audio,"ambience.fire") and not played(audio,"ambience.sizzle"),"cold fire and absent food stay silent")
	var source:Dictionary=w.catalog.regions.home;var shore:Vector2=observer.coast_shapes[0][0];view.center=shore;audio.advance(.3)
	check(played(audio,"ambience.waves"),"real coastline enables waves")
	var first_gain:float=0
	for item in audio.active:
		if item.event=="ambience.waves":first_gain=item.gain
	check(first_gain<1,"new loops fade from zero")
	view.center=w.point(w.life.station)
	check(helper.pickup(w,"wood",2) and helper.pickup(w,"mushroom",1) and helper.approach(w,w.life),"real physical fire fixture")
	check(w.life.fireside.light_host().ok and w.life.fireside.invite(["codex"]).ok and w.life.fireside.roast_host("single:mushroom").ok,"explicit fire and food")
	audio.advance(.3);check(played(audio,"ambience.fire") and played(audio,"ambience.sizzle"),"real burning food enables fire and sizzle")
	for i in range(60):w.advance(.1);audio.advance(.1)
	check(audio.active.all(func(a):return a.event!="ambience.sizzle" or a.target==0),"sizzle fades away once actual food ready")
	var before:int=audio.trace.filter(func(e):return e.action=="scheduled" and str(e.event).begins_with("step.")).size()
	var target:Vector2=w.point(w.actors.human)+Vector2(5,0)
	check(w.command("human",{"intent":"move","x":target.x,"y":target.y}).ok,"movement uses real World route")
	for i in range(100):w.advance(.05);view.center=w.point(w.actors.human);audio.advance(.05)
	check(audio.trace.filter(func(e):return e.action=="scheduled" and str(e.event).begins_with("step.")).size()>before,"actual displacement emits steps")
	var night_seen:=false
	for i in range(4000):
		w.advance(.5);audio.advance(.5)
		if w.days.phase().id=="night":night_seen=true;break
	check(night_seen and audio.active.any(func(a):return a.event=="ambience.insects" and a.target>0),"actual DayCycle reaches night and insects switch")
	check(audio.active.all(func(a):return a.event!="ambience.birds" or a.target==0),"night birds fade down")
	audio.enabled=false;audio.apply_mix()
	for p in audio.get_children():
		if p is AudioStreamPlayer:p.stop();p.stream=null
	await process_frame;await create_timer(.1).timeout;audio.queue_free();view.queue_free();helper.free();await process_frame;await create_timer(.1).timeout
	print("Audio environment: ",checks," checks; real-advance geometry fixture, not player mouse acceptance");quit(1 if failed else 0)
