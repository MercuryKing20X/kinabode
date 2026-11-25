extends "res://tests/capture_world_placement.gd"

const Locale=preload("res://scripts/localization.gd")

func capture(name:String)->void:
	var directory:=OS.get_environment("PLACEMENT_FRAME_DIR")
	if directory.is_empty():return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(directory.path_join(name+".jpg"),.92)

func before_live_door()->bool:
	Locale.select(game.data_dir,"zh");await hold(8);await capture("A-hud-zh")
	Locale.select(game.data_dir,"en");await hold(8);await capture("A-hud-en")
	Locale.select(game.data_dir,"zh");await hold(8)
	return await catch_and_stock(false)

func matching(parent:Node,key:String)->Array:
	return UI.descendants(parent).filter(func(node):return node is Button and node.is_visible_in_tree() and node.text==Locale.text(key))

func catch_and_stock(moon:bool)->bool:
	var w:=world()
	var start:Vector2=w.point(w.actors.human)
	var shores:Array=w.fishing.coast_points.filter(func(spot):return (w.point(spot).x < -30)==moon)
	shores.sort_custom(func(a,b):return start.distance_squared_to(w.point(a))<start.distance_squared_to(w.point(b)))
	var arrived:bool=not w.fishing.shore("human").is_empty() and (start.x < -30)==moon
	for spot in ([] if arrived else shores.slice(0,30)):
		var point:Vector2=w.point(spot)
		if w.find_route("human",point).is_empty():continue
		if not in_view(point):await pan_to(point)
		if not in_view(point) or not game.view.hit(game.view.screen(point)).is_empty():continue
		await mouse(game.view.screen(point))
		if await wait_until(func():return not w.fishing.shore("human").is_empty() and w.point(w.actors.human).distance_to(point)<1.1,1200):
			arrived=true;break
	if not verify(arrived,"walked to a real shore"):return false
	await key(KEY_SPACE)
	await hold(3)
	var fish:=matching(game.island_hud.context,"hud.shore_fishing")
	if fish.is_empty():
		if not verify(await UI.click(self,game.actions_button),"opened actions from shore"):return false
		await hold(3)
		var tabs:TabContainer=game.action_dock.action_tabs
		if tabs.current_tab!=0:await UI.tab(self,tabs,0)
		fish=matching(game.action_dock.menu,"activities.fish")
	if not verify(not fish.is_empty() and await UI.click(self,fish[0]) and game.action_dock.popup.visible,"opened fishing invitation"):
		print("ROUND8_FISH_BUTTONS ",UI.descendants(game.action_dock.menu).filter(func(n):return n is Button).map(func(n):return [n.text,n.is_visible_in_tree()]))
		return false
	var before:Array=w.fishing.fish.keys()
	if not verify(await UI.click(self,game.action_dock.popup.get_ok_button()),"confirmed fishing"):return false
	if not verify(w.work.jobs.get("human",{}).get("intent")=="fish","started the real fishing job"):return false
	var catch_id:=func():
		for entry in w.fishing.unplaced_fish():
			if entry.owner_id=="human" and entry.id not in before:return entry.id
		return ""
	var finished:=func():return not w.work.jobs.has("human") or not catch_id.call().is_empty()
	await wait_until(finished,3180)
	var fish_id:String=catch_id.call()
	if not verify(not fish_id.is_empty(),"caught one real fish"):
		print("ROUND8_CATCH_FAILED job=",w.work.jobs.get("human",{})," status=",game.status.text)
		return false
	await key(KEY_SPACE)
	await hold(18)
	var stock:=matching(game.island_hud.notifications,"hud.stock_all")
	if stock.is_empty():stock=matching(game.island_hud.notifications,"hud.stock_fish")
	if not verify(not stock.is_empty(),"caught fish has a stock button"):return false
	await UI.click(self,stock[0])
	var pen:String=w.fishing.fish[fish_id].location
	if not verify(w.fishing.pens.has(pen) and (not moon or pen=="home.fishery.west"),"the same fish reached the local pen"):return false
	print("ROUND8_CATCH ",fish_id," pen=",pen," coast=",w.point(w.actors.human))
	await hold(36)
	return true

func run()->void:
	var scenario:=OS.get_environment("ROUND8_SCENE")
	if scenario=="A":
		await super.run()
		return
	var data:=OS.get_environment("HABITAT_DATA_DIR")
	if not data.contains("youqi-r8-") or DisplayServer.get_name()=="headless":quit(2);return
	root.size=Vector2i(1280,800);root.gui_embed_subwindows=true
	Pool.obtain(self,data).factory=func(_id):return Stub.new()
	if scenario=="A-local":
		await start_game("")
		await hold(25)
		if game.island_change_panel.visible:await UI.click(self,game.island_change_panel.get_ok_button())
		for attempt in 4:
			var dismiss:=UI.descendants(game).filter(func(node):return node is Button and node.is_visible_in_tree() and node.text in ["收起","Dismiss"] and node.size.x>200)
			if dismiss.is_empty():break
			await mouse(dismiss[0].get_global_rect().get_center())
		var already_changed:bool=world().actors.codex.appearance_id!="ai-codex"
		verify(await change_appearance() or already_changed,"copied save displays a non-default Xiaobai appearance")
		var result:=await before_live_door()
		await hold(40)
		game.game_audio.shutdown()
		await hold(4)
		quit(0 if result and failures==0 else 1)
		return
	var moon:=scenario=="B"
	await start_game("standard" if moon else "showcase")
	await hold(20)
	if not verify(await change_appearance(),"changed Xiaobai's appearance using the wardrobe"):quit(1);return
	await capture(scenario+"-appearance")
	if moon and not verify(await cross_moon(true),"crossed to Crescent Island by mouse"):quit(1);return
	if moon:await capture("B-crescent")
	if not await catch_and_stock(moon):quit(1);return
	await capture(scenario+"-stocked")
	if moon:
		if verify(await walk_to_open_ground(),"walked back to open ground for the summon"):
			await summon_chopper()
	else:
		verify(await open_palette(),"opened the placement catalogue")
		verify(not game.world_placement.choices.keys().any(func(id):return "fish" in id or "pen" in id),"no fish pen in the placement catalogue")
		await capture("C-placement")
	await hold(60)
	game.game_audio.shutdown()
	await hold(4)
	quit(1 if failures else 0)

func walk_to_open_ground()->bool:
	var w:=world()
	for point in [Vector2(75,45),Vector2(60,46),Vector2(36,49)]:
		if not w.walkable("home",point) or w.find_route("human",point).is_empty():continue
		if not in_view(point):await pan_to(point)
		if not in_view(point) or not game.view.hit(game.view.screen(point)).is_empty():continue
		await mouse(game.view.screen(point))
		if await wait_until(func():return w.point(w.actors.human).distance_to(point)<1.0,1500):return true
	return false

func summon_chopper()->void:
	var w:=world()
	var chopping:=func():
		for id in w.director.brains:
			if w.director.brains[id].owns_local_job() and w.actors[id].activity=="chopping" and w.point(w.actors[id]).distance_to(w.point(w.actors.human))>5:return id
		return ""
	if not verify(await wait_until(func():return not chopping.call().is_empty(),3000),"background life started a physical chop"):return
	var actor:String=chopping.call()
	var previous:String=w.work.jobs.get(actor,{}).get("id","")
	var avatar:Button=game.island_hud.avatar_buttons[actor]
	var point:=avatar.get_global_rect().get_center()
	await mouse(point)
	await capture("B-autonomous-chop")
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.global_position=point
		event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.double_click=down
		event.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0
		root.push_input(event,true);await hold(1)
	if not verify(game.chat.visible and game.chat_actor==actor and game.chat_input.has_focus(),"opened direct chat with the chopper"):return
	if not verify(w.work.jobs.get(actor,{}).get("id","")==previous and w.actors[actor].activity=="chopping","original job still chopping at Enter"):return
	var line:="过来"
	for i in line.length():
		for down in [true,false]:
			var event:=InputEventKey.new();event.unicode=line.unicode_at(i);event.pressed=down
			root.push_input(event,true)
	await key(KEY_ENTER)
	if not verify(await wait_until(func():return w.work.jobs.get(actor,{}).get("id","")!=previous,60),"player's instruction paused the chop"):return
	await capture("B-player-order")
	await key(KEY_ESCAPE)
	await key(KEY_SPACE)
	var arrived:=await wait_until(func():return w.point(w.actors[actor]).distance_to(w.point(w.actors.human))<=4,1800)
	verify(arrived,"the resident came to the player")
	print("ROUND8_SUMMON ",actor," previous=",previous," arrived=",arrived," resident=",w.point(w.actors[actor])," player=",w.point(w.actors.human)," following=",w.activities.following.has(actor))
	await capture("B-resident-arrived")
