extends "res://tests/capture_my_ai.gd"

func run()->void:
	var data:=OS.get_environment("HABITAT_DATA_DIR")
	var fake:=OS.get_environment("HABITAT_THINKER_FAKE_DIR")
	if not (data.begins_with("/tmp/kinabode-r11-ui.") or data.begins_with("/tmp/kinabode-r12-ui.")) or fake.is_empty():quit(2);return
	frames_dir=OS.get_environment("MY_AI_FRAMES")
	root.size=Vector2i(1280,800)
	Pool.obtain(self,data).factory=func(_id):return Stub.new()
	var opening:=OS.get_environment("MY_AI_OPENING")
	await start_game(opening)
	await hold(12)
	if game.island_change_panel.visible:await UI.click(self,game.island_change_panel.get_ok_button())
	if OS.get_environment("MY_AI_MAIL")=="1":
		await mailbox_evidence(data)
		quit(1 if failures else 0)
		return
	if OS.get_environment("MY_AI_MOON_PLAYER")=="1":await walk_to_moon()
	if OS.get_environment("MY_AI_WARDROBE")=="1":
		verify(await change_appearance(),"Xiaobai switched to non-default appearance through wardrobe")
	var busy:=OS.get_environment("MY_AI_BUSY")=="1"
	if busy:
		verify(await UI.click(self,game.dialogue_button),"opened real command input")
		await mouse(game.chat_input.get_global_rect().get_center())
		var line:="小白帮我砍一棵树"
		for index in line.length():
			for down in [true,false]:
				var event:=InputEventKey.new()
				event.unicode=line.unicode_at(index);event.pressed=down
				root.push_input(event,true)
				await process_frame
		verify(game.chat_input.text==line,"typed the scoped wood command")
		await key(KEY_ENTER)
		verify(await wait_wall(func():return world().work.jobs.get("codex",{}).get("intent")=="gather_wood",10),"real command started a wood job")
		if game.chat.visible:await key(KEY_ESCAPE)
	await key(KEY_SPACE)
	verify(await UI.click(self,game.island_hud.my_ai_button),"opened My AI from HUD")
	var panel:Control=game.world_door_dialog
	if OS.get_environment("MY_AI_PROVIDER")=="claude":
		verify(await UI.click(self,panel.sources),"opened provider menu")
		var popup:PopupMenu=panel.sources.get_popup()
		var at:=Vector2(popup.size.x*.5,1.5*float(popup.size.y)/panel.sources.item_count)
		if popup.is_embedded():await mouse(at+Vector2(popup.position))
		else:
			for down in [true,false]:
				var event:=InputEventMouseButton.new()
				event.button_index=MOUSE_BUTTON_LEFT;event.position=at;event.pressed=down
				popup.push_input(event,true)
				await process_frame
		verify(panel.sources.get_selected_metadata()=="claude","selected Claude through provider menu")
	var expected:=OS.get_environment("MY_AI_EXPECT_ERROR")
	verify(panel.cli_timeout.text.contains("90") and panel.cli_timeout.text.contains("60"),"panel discloses both CLI deadlines")
	if busy:
		verify(await wait_wall(func():return world().actors.codex.activity=="chopping",30),"Xiaobai is actually chopping before connection")
	var job_id:String=world().work.jobs.get("codex",{}).get("id","")
	var started_at:=Time.get_ticks_msec()
	verify(await UI.click(self,panel.move_in),"clicked Move in")
	if not expected.is_empty():
		verify(await wait_wall(func():return panel.retry_button.visible,97 if expected=="timeout" else 20),"first failure exposed Reconnect within its deadline")
		var reasons:={"missing":"找不到命令","arguments":"命令参数不被接受","auth":"未登录","timeout":"等待超时","invalid_key":"服务商拒绝了 API 密钥","network":"连不上服务商","model_missing":"服务商没有此模型"}
		verify(panel.summary.text.contains(reasons[expected]),"correct first-failure reason: "+panel.summary.text)
		if expected in ["auth","timeout","invalid_key","network","model_missing"]:
			verify(panel.recovery.visible and not panel.recovery.text.is_empty(),"matching recovery advice is visible")
		if expected=="auth" and panel.sources.get_selected_metadata()=="claude":
			verify(panel.recovery.text.contains("打开终端运行 claude"),"Claude login instructions name its CLI")
			var clipboard:=DisplayServer.clipboard_get()
			verify(await UI.click(self,panel.auth_copy) and DisplayServer.clipboard_get()=="claude","copy button copies only claude")
			DisplayServer.clipboard_set(clipboard)
		print("R11_FIRST_FAILURE_MS ",Time.get_ticks_msec()-started_at)
		await shot("first-failure")
		if expected in ["auth","invalid_key","network","model_missing"]:
			await test_button(panel,expected)
		var mode_file:=FileAccess.open(fake.path_join("mode"),FileAccess.WRITE)
		mode_file.store_string("success");mode_file.close()
		if expected=="missing":
			verify(FileAccess.set_unix_permissions(fake.path_join(str(panel.sources.get_selected_metadata())),448)==OK,"installed the test executable before explicit retry")
		verify(await UI.click(self,panel.retry_button),"clicked Reconnect")
		started_at=Time.get_ticks_msec()
	verify(await wait_wall(func():return "住着" in panel.summary.text or "Living here" in panel.summary.text,15),"visible Living here within fifteen seconds")
	print("R11_LIVING_MS ",Time.get_ticks_msec()-started_at)
	if not job_id.is_empty() and busy:
		verify(world().work.jobs.get("codex",{}).get("id","")==job_id,"same real wood job is still in progress after reply")
		verify(not game.island_ai.rows.codex.pending.is_empty(),"first plan is queued while wood job is busy")
	await shot("living")
	var button:Button=panel.body.get_child(0).get_child(1)
	verify(await UI.click(self,button),"closed panel without changing selection")
	verify(await wait_wall(func():return game.island_ai.rows.codex.get("receipt",{}).get("status")=="completed",100 if busy else 45),"first plan completed through world action")
	var brain:RefCounted=world().director.brains.codex
	print("R11_RECEIPT ",game.island_ai.rows.codex.receipt," BASIC ",brain.intention.basic.result,
		" PENDING ",not game.island_ai.rows.codex.pending.is_empty()," BUSY ",brain.busy(),
		" ELIGIBLE ",brain.eligible(true)," CURRENT ",brain.current.get("action",""),
		" JOB ",world().work.jobs.get("codex",{}).get("intent",""))
	await shot("first-action")
	if OS.get_environment("MY_AI_TEST_PROBE")=="1":
		await UI.click(self,game.island_hud.my_ai_button)
		await test_button(panel,"ok")
	if OS.get_environment("MY_AI_TEST_RUNTIME")=="1":
		await runtime_failures(fake)
	quit(1 if failures else 0)

func runtime_failures(fake:String)->void:
	var mode_file:=FileAccess.open(fake.path_join("mode"),FileAccess.WRITE)
	mode_file.store_string("auth");mode_file.close()
	var row:Dictionary=game.island_ai.rows.codex
	for count in [1,2,3]:
		verify(await wait_wall(func():return row.failures>=count,65),"established connection issued retry %d"%count)
		verify(game.island_ai.disconnected()==(count==3),"established connection disconnects only on failure three")
		print("R11_RUNTIME ",count," ",game.island_ai.status_text(true))

func test_button(panel:Control,expected:String)->void:
	var original:int=game.island_ai.rows.codex.last
	verify(await UI.click(self,panel.test_button),"clicked Test connection")
	verify(await wait_wall(func():return panel.test_job.is_empty(),10),"diagnostic returned")
	verify(panel.test_result==expected,"localized diagnostic: "+panel.test_status.text)
	verify(game.island_ai.rows.codex.last==original,"diagnostic does not change resident connection")
	await shot("test-"+expected)

func mailbox_evidence(data:String)->void:
	var notice:Button=game.memory_life.notice
	var fixed:=notice.name=="MailboxNotice"
	var client_size:=[Vector2i(1280,800),Vector2i(960,640)]
	for dimensions in client_size:
		root.size=dimensions
		for language in ["zh","en"]:
			Locale.select(data,language)
			await key(KEY_SPACE)
			verify(await wait_wall(func():return notice.is_visible_in_tree(),8),"mailbox present in copied player preferences "+language)
			await create_timer(1.2).timeout
			await RenderingServer.frame_post_draw
			var image:=root.get_texture().get_image()
			var rect:=notice.get_global_rect()
			verify(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(rect),"mailbox inside real viewport")
			var label:="mail-%s-%d"%[language,dimensions.x]
			if fixed:
				verify(notice.text.is_valid_int() and notice.icon!=null,"mailbox uses numeric text and a drawn texture")
				verify(notice.tooltip_text==Locale.text("memory.new_mail"),"localized mailbox tooltip")
				var inks:=0
				for y in range(int(rect.position.y),mini(int(rect.end.y),image.get_height())):
					for x in range(int(rect.position.x),mini(int(rect.position.x)+24,image.get_width())):
						var pixel:=image.get_pixel(x,y)
						if pixel.r>.76 and pixel.g>.64 and pixel.b>.43 and pixel.r>pixel.b+.12:inks+=1
				verify(inks>=12,"rendered viewport contains envelope pixels")
			if not frames_dir.is_empty():
				image.save_png(frames_dir.path_join(label+".png"))
				var cut:=image.get_region(Rect2i(0,0,min(430,image.get_width()),min(235,image.get_height())))
				cut.resize(cut.get_width()*3,cut.get_height()*3,Image.INTERPOLATE_NEAREST)
				cut.save_png(frames_dir.path_join(label+"-3x.png"))
			print("R11_MAIL ",label," ",notice.text," ",rect," viewport=",image.get_size()," scale=",preload("res://scripts/ui_scale.gd").factor())
