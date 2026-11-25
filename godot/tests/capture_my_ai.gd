extends "res://tests/capture_world_placement.gd"

const Locale=preload("res://scripts/localization.gd")
var frames_dir:=""

func shot(label:String)->void:
	if frames_dir.is_empty():return
	await process_frame
	root.get_texture().get_image().save_png(frames_dir.path_join(label+".png"))

func wait_wall(test:Callable,seconds:float)->bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		if test.call():return true
		await process_frame
	return test.call()

func run()->void:
	var data:=OS.get_environment("HABITAT_DATA_DIR")
	if not (data.begins_with("/tmp/kinabode-r9.") or data.begins_with("/tmp/kinabode-r10.")) or OS.get_environment("HABITAT_THINKER_FAKE_DIR").is_empty():quit(2);return
	frames_dir=OS.get_environment("MY_AI_FRAMES")
	root.size=Vector2i(1280,800)
	Pool.obtain(self,data).factory=func(_id):return Stub.new()
	var opening:=OS.get_environment("MY_AI_OPENING")
	if opening.is_empty():opening="standard"
	if OS.get_environment("MY_AI_ENTRY")=="title":
		var title:Node=load("res://scenes/title.tscn").instantiate()
		root.add_child(title);current_scene=title
		await hold(8)
		await shot("title")
		verify(await UI.click(self,title.menu.get_node("connections")),"opened My AI from title")
		await hold(8)
		await shot("title-panel")
		verify(await UI.click(self,title.connection_panel.move_in),"saved title selection via input")
		verify(await UI.click(self,title.menu.get_node("new")),"entered opening")
		await wait_wall(func():return is_instance_valid(current_scene) and current_scene.get("island_ai")!=null,12)
		game=current_scene
	else:
		await start_game(opening)
		await hold(12)
		if game.island_change_panel.visible:
			verify(await UI.click(self,game.island_change_panel.get_ok_button()),"dismissed the return summary")
			await hold(10)
		if OS.get_environment("MY_AI_MOON_PLAYER")=="1":await walk_to_moon()
		await shot("island")
		if OS.get_environment("MY_AI_REOPEN")!="1" and OS.get_environment("MY_AI_SCREEN_ONLY")!="1":
			await choose_from_hud()
	if OS.get_environment("MY_AI_HUD_MATRIX")=="1":
		for resolution in [Vector2i(960,640),Vector2i(1280,800)]:
			root.size=resolution
			for language in ["zh","en"]:
				Locale.select(data,language)
				await key(KEY_SPACE)
				await hold(10)
				if game.island_change_panel.visible:
					await UI.click(self,game.island_change_panel.get_ok_button())
					await hold(10)
				await shot("%s-%s-%d"%[opening,language,resolution.x])
				var visible_text:String=game.day_label.text
				verify(not preload("res://tests/visible_locale_audit.gd").raw_key(visible_text) and str(world().days.day()) in visible_text,"localized visible date: "+visible_text)
	if OS.get_environment("MY_AI_SCREEN_ONLY")=="1":
		quit(0)
		return
	var duration:=OS.get_environment("MY_AI_SECONDS").to_int()
	if OS.get_environment("MY_AI_RECOVERY")=="1":
		await recovery()
		quit(1 if failures else 0)
		return
	if duration>0:
		if OS.get_environment("MY_AI_BOXES")=="1":
			if not verify(await wait_wall(func():return game.island_ai.rows.get("codex",{}).get("last",-1)>=0,120),"resident is living here before recording"):quit(1);return
			await capture_hud_boxes(60)
		await observe_life(duration)
		quit(1 if failures else 0)
		return
	verify(game.island_ai.rows.has("codex"),"restored selected resident")
	verify(await wait_wall(func():
		var row:Dictionary=game.island_ai.rows.get("codex",{})
		return int(row.get("last",-1))>=0 or int(row.get("failures",0))>0,60),"received CLI result")
	print("MY_AI_RESULT ",game.island_ai.status_text(true)," / ",game.island_ai.rows.get("codex",{}).get("error",""))
	verify(game.island_ai.rows.get("codex",{}).get("last",-1)>=0,"valid plan accepted")
	await wait_wall(func():return not game.world.director.brains.codex.intention.basic.result.is_empty(),15)
	print("MY_AI_ACTION ",game.world.director.brains.codex.intention.basic.result)
	await shot("connected")
	quit(1 if failures else 0)

func choose_from_hud()->void:
	await key(KEY_SPACE)
	await hold(4)
	if OS.get_environment("MY_AI_WARDROBE")=="1":
		if game.island_hud.residents_collapsed:await UI.click(self,game.island_hud.collapse_residents)
		verify(await change_appearance(),"picked non-default wardrobe work")
		await hold(8)
	verify(await UI.click(self,game.island_hud.my_ai_button),"opened My AI from HUD")
	await hold(8)
	var panel:Control=game.world_door_dialog
	if OS.get_environment("MY_AI_PROVIDER")=="claude":
		await UI.click(self,panel.sources)
		var popup:PopupMenu=panel.sources.get_popup()
		var viewport:Viewport=popup
		var click:=Vector2(popup.size.x*.5,1.5*float(popup.size.y)/panel.sources.item_count)
		if popup.is_embedded():click+=Vector2(popup.position);viewport=root
		var motion:=InputEventMouseMotion.new();motion.position=click;motion.global_position=click;viewport.push_input(motion,true)
		for down in [true,false]:
			var event:=InputEventMouseButton.new()
			event.button_index=MOUSE_BUTTON_LEFT;event.position=click;event.global_position=click;event.pressed=down
			viewport.push_input(event,true)
			await process_frame
		verify(panel.sources.get_selected_metadata()=="claude","selected Claude Code from its real popup")
	await shot("island-panel")
	verify(await UI.click(self,panel.move_in),"moved in via input")
	var close:Button=panel.body.get_child(0).get_child(1)
	await UI.click(self,close)

func walk_to_moon()->void:
	var anchor:Array=world().map_anchor("moon.lookout")
	if not verify(anchor.size()==2,"found authored Crescent Island destination"):return
	var point:=Vector2(anchor[0],anchor[1])
	for i in 3:
		if in_view(point):break
		await pan_to(point)
	if not verify(in_view(point),"brought Crescent Island into view using mouse"):return
	for offset in [Vector2(0,2),Vector2(2,0),Vector2(-2,0),Vector2(1,3),Vector2(0,-3)]:
		var at:Vector2=point+offset
		if not world().walkable("home",at) or not in_view(at) or not game.view.hit(game.view.screen(at)).is_empty():continue
		await mouse(game.view.screen(at))
		if await wait_wall(func():return world().point(world().actors.human).distance_to(at)<3,22):
			verify(true,"player walked across the bridge");return
	verify(false,"player walked across the bridge")

func capture_hud_boxes(seconds:int)->void:
	var hud:Control=game.island_hud
	var watched:Array=[hud.my_ai_button,hud.residents_panel]
	watched.append_array(hud.resident_rows.values())
	var baseline:Array=watched.map(func(control):return control.get_global_rect())
	var maximum:=0.0
	var offsets:Dictionary={}
	var hidden:=0
	var frames:=0
	var started:=Time.get_ticks_msec()
	var next_shot:=started
	while Time.get_ticks_msec()-started<seconds*1000:
		await RenderingServer.frame_post_draw
		frames+=1
		for i in watched.size():
			var rect:Rect2=watched[i].get_global_rect()
			var offset:=maxf(rect.position.distance_to(baseline[i].position),rect.end.distance_to(baseline[i].end))
			maximum=maxf(maximum,offset)
			offsets[i]=maxf(offsets.get(i,0.0),offset)
			if not watched[i].is_visible_in_tree():hidden+=1
		if Time.get_ticks_msec()>=next_shot and not frames_dir.is_empty():
			root.get_texture().get_image().save_jpg(frames_dir.path_join("hud-%07d.jpg"%(Time.get_ticks_msec()-started)),.8)
			next_shot=Time.get_ticks_msec()+100
	print("MY_AI_HUD_BOXES ",JSON.stringify({"frames":frames,"duration_ms":Time.get_ticks_msec()-started,"max_offset_px":maximum,"hidden_control_frames":hidden,"controls":watched.size(),"offsets":offsets}))
	verify(maximum==0 and hidden==0,"right-side HUD and resident rows stayed visible and fixed")

func observe_life(seconds:int)->void:
	var started_at:=Time.get_ticks_msec()
	var next_sample:=started_at
	var previous:Dictionary={}
	var quiet:=0
	var max_quiet:=0
	var previous_position:Vector2=world().point(world().actors.codex)
	var number:=0
	while Time.get_ticks_msec()-started_at<seconds*1000:
		await process_frame
		var now:=Time.get_ticks_msec()
		if now<next_sample:continue
		next_sample=now+1000
		var actor:Dictionary=world().actors.codex
		var position:Vector2=world().point(actor)
		var brain:RefCounted=world().director.brains.codex
		var row:Dictionary=game.island_ai.rows.get("codex",{})
		var state:={"plan":row.get("reason",""),"failure":row.get("error",""),"failures":row.get("failures",0),"result":row.get("receipt",{}).duplicate(true)}
		if previous!=state:
			print("MY_AI_OBSERVED ",now-started_at," ",JSON.stringify(state))
			previous=state
		if game.playground.kind=="shuttlecock" and game.playground.assembly_ready and not game.playground.members.is_empty() and game.playground.beat>=1 and not has_meta("group_play_seen"):
			set_meta("group_play_seen",true)
			print("MY_AI_GROUP_PLAY ",game.playground.members)
		if position.distance_to(previous_position)<.05 and brain.current.is_empty() and not world().work.jobs.has("codex"):quiet+=1
		else:quiet=0
		max_quiet=maxi(quiet,max_quiet)
		previous_position=position
		number+=1
		if number%15==1:print("MY_AI_SAMPLE ",number," position=",position," activity=",brain.current.get("action","")," thinking=",not row.get("flight",{}).is_empty())
		if not frames_dir.is_empty():
			var image:=root.get_texture().get_image()
			if image!=null and not image.is_empty():image.save_jpg(frames_dir.path_join("frame-%04d.jpg"%number),.78)
	print("MY_AI_IDLE_MAX_SECONDS ",max_quiet)

func recovery()->void:
	var row:Dictionary=game.island_ai.rows.codex
	verify(await wait_wall(func():return row.failures>=1,45),"first failure received")
	print("MY_AI_FIRST ",game.island_ai.status_text(true))
	verify(not game.island_ai.disconnected(),"first failure is not disconnected")
	await shot("first-failure")
	verify(await wait_wall(func():return row.failures>=3,115),"three consecutive failures")
	print("MY_AI_THIRD ",game.island_ai.status_text(true))
	verify(game.island_ai.disconnected(),"third failure is disconnected")
	await shot("disconnected")
	var fixture:=FileAccess.open(OS.get_environment("HABITAT_THINKER_FAKE_DIR").path_join("mode"),FileAccess.WRITE)
	fixture.store_string("gesture");fixture.close()
	verify(await UI.click(self,game.island_hud.my_ai_button),"status opens configuration")
	await hold(12)
	var button:Button=game.world_door_dialog.retry_button
	verify(await UI.click(self,button),"one-click reconnect")
	verify(await wait_wall(func():return row.last>=0 and row.failures==0,65),"valid reply restored living state")
	await shot("reconnected")
