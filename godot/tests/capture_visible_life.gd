extends "res://tests/probe_first_hour.gd"

var output:=""
var is_before:=false
var frame_samples:Array=[]
var last_frame_us:=0
var setup_seconds:=0.0

func shot_frame(path:String)->void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(path,.92)

func record(name:String,duration:float)->void:
	var dest:String=output.path_join(name)
	DirAccess.make_dir_recursive_absolute(dest)
	if is_before:g.island_hud.ui_root.hide()
	else:
		g.island_hud.watch_requested=true
		g.island_hud.watch_idle=10
	for i in roundi(duration*10):
		var now:=Time.get_ticks_usec()
		if last_frame_us>0 and i>0:frame_samples.append(float(now-last_frame_us)/1000)
		last_frame_us=now
		for sub in 3:
			g._process(1.0/30)
			g.view._process(1.0/30)
			g.life_archive.tick(1.0/30)
		if i%20==0:capture()
		if is_before:g.island_hud.ui_root.hide()
		await shot_frame(dest.path_join("%05d.jpg"%i))
		if i==180 and name=="day":
			g.island_hud.ui_root.show()
			var pat:bool=await open_care("codex")
			receipt("pat","selected",pat)
			if not is_before:g.island_hud.watch_requested=true
	seconds+=duration
	g.island_hud.ui_root.show()
	if not is_before:
		g.island_hud.watch_requested=false
		g.island_hud.watch_idle=0
		g.island_hud.tick_watch(1)
	var sorted:Array=frame_samples.duplicate();sorted.sort()
	var os_rss:Array=[]
	OS.execute("ps",["-o","rss=","-p",str(OS.get_process_id())],os_rss)
	print("CAPTURE ",name," frames=",roundi(duration*10)," p95-with-encoding-ms=",sorted[int(.95*(sorted.size()-1))]," rss-KiB=",os_rss[0].strip_edges() if not os_rss.is_empty() else "")
	frame_samples.clear()

func run()->void:
	output=OS.get_environment("HABITAT_VISIBLE_EVIDENCE")
	var directory:String=OS.get_environment("HABITAT_DATA_DIR")
	if output.is_empty() or not directory.contains("youqi-test-visible-") or DisplayServer.get_name()=="headless":quit(2);return
	is_before=OS.get_environment("HABITAT_VISIBLE_BEFORE")=="1"
	OS.set_environment("HABITAT_OPENING","standard")
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	seed(8027)
	await prepare_scene(directory,true)
	g.view.set_process(false)
	w.weather.weather_seed=4291531408
	w.fishing.rng.seed=8027
	for i in IDS.size():w.director.routines[IDS[i]].rng.seed=8027+i
	await greeting()
	await shot_frame(output.path_join("hud.jpg"))
	g.view.follow_player=true
	var duration:float=float(OS.get_environment("HABITAT_VISIBLE_DURATION"))
	if duration<=0:duration=180
	await record("morning",duration)
	if not is_before and g.steward.folded:
		await UI.click(self,g.steward.heading_button)
	receipt("steward","start",await begin_steward())
	w.days.origin=w.forest.clock-w.days.day_seconds*.29
	g.steward.director_camera=true
	await record("day",duration)
	if g.steward.active:g.steward.stop()
	w.days.origin=w.forest.clock-w.days.day_seconds*.74
	var camp:Vector2=w.point(w.life.station)
	if not w.standard.ready("home.barbecue"):await provision_camp()
	if w.standard.ready("home.barbecue"):await dinner("single:mushroom")
	aim(camp)
	await record("evening",duration)
	print("VISIBLE_RECEIPTS ",JSON.stringify({"actions":actions,"events":events,"symbols":w.hearts.symbol_counts,"failures":failures}))
	g.queue_free();await process_frame;quit(1 if failures else 0)
