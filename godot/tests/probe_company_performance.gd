extends "res://tests/probe_first_hour.gd"
## A disposable fixture positions the camera over both busy parts of the island.

func rss_mib()->float:
	var rss:Array=[]
	OS.execute("/bin/ps",["-o","rss=","-p",str(OS.get_process_id())],rss)
	return float(int(str(rss[0]).strip_edges()))/1024.0 if not rss.is_empty() else 0.0

func seed_flowers()->Vector2:
	var system:RefCounted=w.flower_creation
	for y in range(180,226):
		for x in range(25,100):
			var codes:Array=[]
			for yy in 10:
				for xx in 10:codes.append(Vector2(x+xx,y+yy))
			if not codes.all(func(p):return system.space("home",p)):continue
			for i in codes.size():
				var p:Vector2=codes[i]
				system.flowers[system.key("home",p)]={"position":[int(p.x),int(p.y)],"region_id":"home","color":["red","white","pink","yellow"][i%4],"actor_id":"human","pattern_id":"single","label":"single"}
			return Vector2(x+4.5,y+4.5)
	return Vector2.INF

func sample(label:String,count:int)->Dictionary:
	var frames_ms:Array=[]
	var total:=0.0
	var overlap:=0
	var draw_cpu:Array=[]
	var started:int=Time.get_ticks_usec()
	for i in count:
		await RenderingServer.frame_post_draw
		var end:int=Time.get_ticks_usec()
		var measured:float=float(end-started)/1000
		started=end
		if i!=0:
			frames_ms.append(measured);total+=measured
		if g.steward.active and c.night.used_fireside():overlap+=1
		draw_cpu.append(float(Performance.get_monitor(Performance.TIME_PROCESS))*1000)
	frames_ms.sort();draw_cpu.sort()
	var avg:float=total/frames_ms.size()
	return {"scene":label,"frames":frames_ms.size(),"avg_ms":avg,"avg_fps":1000.0/avg,
		"p95_ms":frames_ms[ceili(frames_ms.size()*.95)-1],"worst_ms":frames_ms[-1],
		"process_p95_ms":draw_cpu[ceili(draw_cpu.size()*.95)-1],"rss_mib":rss_mib(),
		"window_px":[root.size.x,root.size.y],"flowers":w.flower_creation.flowers.size(),"steward_and_night_frames":overlap,
		"photo":not c.camera.last_photo.is_empty(),"actors":IDS.size()}

func run()->void:
	var directory:String=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-") or DisplayServer.get_name()=="headless":quit(2);return
	OS.set_environment("HABITAT_OPENING","showcase")
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	await prepare_scene(directory,false)
	var flowers_at:Vector2=seed_flowers()
	check(flowers_at.is_finite() and w.flower_creation.flowers.size()==100,"100 rendered flowers in validated cells")
	var rss_before:=rss_mib()
	await UI.click(self,g.island_hud.camera_button)
	await frames(12)
	var rss_preview:=rss_mib()
	if c.camera.active:
		var controls:Array=UI.descendants(c.camera.overlay)
		for name in ["Shutter","Close"]:
			var button:Array=controls.filter(func(node):return node.name==name)
			if not button.is_empty():await UI.click(self,button[0])
			await frames(6)
	var rss_closed:=rss_mib()
	check(not c.camera.last_photo.is_empty(),"native shutter wrote the disposable PNG")
	calm()
	w.days.origin=w.forest.clock-w.days.day_seconds*.64
	var result:Dictionary=Cook.start(w,"single:mushroom",["human","codex","companion-2","npc.mira","npc.nora"])
	check(result.ok and Cook.ready(w) and Cook.ate(w,"human") and Cook.ate(w,"codex"),"fixture physically prepares fireside with original seats and wood")
	for i in 4:step(.1,false)
	w.director.speech_after=0
	for id in IDS:w.director.routines[id].next_speech=0
	check(c.night.start("story"),"actual fireside story starts")
	check(g.steward.start("codex"),"local stewardship starts")
	aim(w.point(w.life.station))
	g.steward.manual_camera=true
	g.set_process(true)
	g.memory_life.set_process(true)
	g.life_archive.set_process(true)
	var camp:Dictionary=await sample("camp",240)
	aim(flowers_at);g.view.zoom=.8
	var flowers:Dictionary=await sample("flower_isle",240)
	var output:String=OS.get_environment("HABITAT_HOUR_RESULT")
	var file:=FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"camp":camp,"flower_isle":flowers,"checks_failed":failures,
		"photo_rss":{"before":rss_before,"preview":rss_preview,"closed":rss_closed}},"  "));file.close()
	g.queue_free();await frames();quit(1 if failures else 0)
