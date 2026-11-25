extends "res://tests/test_company_input.gd"

func key_h()->void:
	var key:=InputEventKey.new();key.pressed=true;key.keycode=KEY_H;root.push_input(key,true)

func run()->void:
	var dir:String=OS.get_environment("HABITAT_DATA_DIR")
	if not dir.contains("youqi-test-visible-"):quit(2);return
	out=OS.get_environment("HABITAT_VISIBLE_EVIDENCE")
	OS.set_environment("HABITAT_OPENING","standard")
	await load_game(dir)
	var hud:Control=g.island_hud
	check(hud.residents_collapsed and hud.notices_collapsed and g.journey.folded and g.steward.folded,"compact defaults")
	for dim in [Vector2i(960,640),Vector2i(1280,800)]:
		root.size=dim;root.content_scale_size=Vector2i.ZERO
		for lang in ["zh_CN","en"]:
			Text.select(dir,lang)
			for size in range(4):
				g.ui_scale.set_level(size,false);hud.refresh()
				await frames()
				var bounds:=Rect2(Vector2.ZERO,Vector2(root.size)).grow(1)
				check(bounds.encloses(hud.stock_button.get_global_rect()) and bounds.encloses(hud.watch_button.get_global_rect()) and bounds.encloses(hud.settings_menu.get_global_rect()),"reachable UI %s %s %d"%[dim,lang,size])
				await shot("hud-%d-%s-%d"%[dim.x,lang,size])
	key_h();hud.tick_watch(.3)
	check(not hud.ui_root.visible,"H hides HUD")
	await shot("watch")
	var move:=InputEventMouseMotion.new();move.position=Vector2(50,50);move.relative=Vector2(1,0);root.push_input(move,true)
	hud.tick_watch(.3)
	check(hud.ui_root.visible,"mouse restores HUD")
	hud.tick_watch(10.5)
	check(not hud.ui_root.visible,"idle hides HUD")
	var dialog:=AcceptDialog.new();g.add_child(dialog);dialog.popup()
	hud.tick_watch(.1)
	check(hud.ui_root.visible,"modal restores HUD")
	dialog.queue_free()
	calm()
	if not out.is_empty() and DisplayServer.get_name()!="headless":await visual_samples()
	var home:Dictionary={}
	for candidate in w.objects.values():
		if candidate.kind=="construction_site" and int(candidate.stage_index)==5:
			home=candidate;break
	if not home.is_empty():
		var before:Dictionary=w.storage.saved()
		var job:Dictionary=w.command("codex",{"intent":"enter","target_id":home.id})
		check(job.get("ok",false),"entry uses original interior command")
		for i in 600:
			w.advance(.1)
			if not w.work.jobs.has("codex"):break
		var room:String=w.interior.room_for(home.id)
		check(w.actors.codex.region_id==room,"physical doorway reached")
		w.days.origin=w.forest.clock-w.days.day_seconds*.92
		g.view.center=w.point(home);g.view.follow_player=false;g.view.zoom=1.15;g.view.update_ambience()
		await shot("occupied-house")
		check(Save.save_world(w,dir),"save indoor position")
		var restored=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json")
		check(Save.load_world(restored,dir).ok and restored.actors.codex.region_id==room and restored.work.jobs.is_empty(),"reload indoor position without task")
		check(w.storage.saved()==before,"door crossing does not use materials")
	g.queue_free();await frames();quit(1 if failures else 0)

func visual_samples()->void:
	var spot:Vector2=w.point(w.actors.human)+Vector2(0,-2)
	for n in range(4):
		var id:String=c.IDS[n]
		var p:Vector2=spot+Vector2(float(n)*2.5-3.75,0)
		w.actors[id].position=[p.x,p.y]
		w.actors[id].activity="idle"
		w.actors[id].facing="down"
	g.view.center=spot;g.view.follow_player=false;g.view.zoom=1.20
	var id:String="companion-2"
	var actors:Dictionary=w.actors
	for cue in ["pat","happy","hurt","surprise","shy","sleep"]:
		w.hearts.react(id,cue)
		w.hearts.reactions[id].at=float(w.director.time)-(.34 if cue!="hurt" else .74)
		g.view.queue_redraw()
		await shot("reaction-"+cue)
	w.hearts.reactions.clear()
	g.view.center=spot+Vector2(0,-.6)
	g.island_hud.ui_root.hide()
	var destination:String=out.path_join("play")
	DirAccess.make_dir_recursive_absolute(destination)
	for i in range(200):
		for n in range(4):
			var who:String=c.IDS[n]
			var phase:float=fposmod(i/14.0+float(n)*.08,1)
			g.view.motion.play_poses[who]="play_cute" if i<70 else "play_squat" if i>=140 else ""
			g.view.motion.play_phases[who]=phase
			if i>=70 and i<140:actors[who].facing=["down","left","up","right"][int(phase*4)]
		g.view._process(.1)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_jpg(destination.path_join("%05d.jpg"%i),.92)
	g.view.motion.play_poses.clear();g.view.motion.play_phases.clear()
	g.island_hud.ui_root.show()
