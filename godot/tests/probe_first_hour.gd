extends "res://tests/test_company_input.gd"
## Human inputs go through the viewport. Only the clock, camera and isolated
## save's wall anchor are controlled by the harness.
var seconds:=0.0
var events:Array=[]
var seen:Dictionary={}
var invitations:Dictionary={}
var actions:Array=[]
var occurrences:Dictionary={}
var card_seen_at:Dictionary={}
var accept_next:=true
var manual_clock:=true
var wall_start:=0
var last_clock:=0.0
const IDS=["codex","companion-2","npc.mira","npc.nora"]
const Fish=preload("res://tests/fishing_fixture.gd")

func mark(kind:String,proof:Dictionary={},repeat:bool=false)->void:
	if seen.has(kind) and not repeat:return
	seen[kind]=true
	events.append({"t":snappedf(seconds,.1),"kind":kind,"proof":proof.duplicate(true)})

func observe_once(kind:String,key:String,proof:Dictionary={})->void:
	if occurrences.has(kind+":"+key):return
	occurrences[kind+":"+key]=true
	mark(kind,proof,true)

func receipt(action:String,stage:String,ok:bool)->void:
	actions.append({"t":snappedf(seconds,.1),"action":action,"stage":stage,"ok":ok,"status":g.status.text})

func capture()->void:
	for row in w.memories.records:
		if row.kind in ["first_meeting","first_shared_meal","favorite_taste","story_chapter"]:
			mark(row.kind,{"event":row.id})
		if row.kind=="meal":mark("first_meal",{"event":row.id})
	for row in c.trace:
		if row.kind in ["care","night_line","night_question","promise_accepted","return_summary"]:
			mark(row.kind,{"actor":row.get("actor","")})
	for row in g.life_archive.daily.invitation_trace:
		if row.event=="heart_player_card":observe_once("player_invitation",str(row.at)+":"+row.actor,{"actor":row.actor})
	for row in g.autonomy.meetings.records:
		if row.get("event") in ["peer_delivered","peer_together"]:mark("peer_invitation")
	for camp in w.barbecues.values():
		for key in camp.fireside.dialogue.scene_deliveries:
			if ":heart_mushroom_" in key:mark("mushroom",{"speech_receipt":key})
	for id in g.view.speech_by_actor:
		var row:Dictionary=g.view.speech_by_actor[id]
		var context:String=row.get("context","")
		var contexts:Dictionary={"heart_mushroom":"mushroom","banter":"tease","heart_visit":"approached","peer_invitation":"peer_invitation"}
		for key in contexts:
			if key in context:mark(contexts[key],{"actor":id,"text":row.get("text","")})
	for b in w.director.brains.values():
		for row in b.interactions.receipts:
			if row.event=="peer_invite":mark("peer_invitation",{"actor":row.actor,"listener":row.listener})
			if row.event=="interaction":
				if row.scene in ["idle","circles","sprint","hungry_idle","no_chat"]:mark("tease",{"actor":row.actor,"text":row.zh})
				mark("approached",{"actor":row.actor,"text":row.zh})
	for id in IDS:
		var glyph:String=w.hearts.symbol(id,w.forest.clock)
		if not glyph.is_empty():mark("mood_symbol",{"actor":id,"symbol":glyph})
	if not c.camera.last_photo.is_empty():mark("photo")
	if w.standard.ready("home.barbecue"):mark("camp_built")

func tick_for(duration:float)->void:
	var stop:float=seconds+duration
	while seconds+.001<stop:
		if manual_clock:
			var dt:float=minf(.1,stop-seconds)
			var clock:float=w.forest.clock
			g._process(dt);g.view._process(dt);g.life_archive.tick(dt);g.memory_life._process(dt)
			seconds+=maxf(0,w.forest.clock-clock)
		else:
			await create_timer(.15).timeout
			seconds+=maxf(0,w.forest.clock-last_clock);last_clock=w.forest.clock
		if int((seconds+.001)*10)%10==0 or not manual_clock:
			capture()
			await answer_cards()
		if manual_clock and int((seconds+.001)*10)%30==0:await process_frame

func answer_cards()->void:
	var daily:RefCounted=g.life_archive.daily
	if c.night.turn.get("kind")=="promise" and (not seen.has("promise_accepted")):
		await UI.click(self,c.night.card.get_node_or_null("body/answer_0"))
	if c.night.turn.get("kind")=="night":
		await UI.click(self,c.night.card.get_node_or_null("body/answer_0"))
	for id in daily.cards.keys():
		var card:Dictionary=daily.cards.get(id,{})
		if card.is_empty():continue
		if not card_seen_at.has(card.token):card_seen_at[card.token]=seconds
		if seconds-float(card_seen_at[card.token])<1.0:continue
		if not invitations.has(card.token):
			invitations[card.token]={"t":seconds,"choice":"yes" if accept_next else "ignore","clicked":false,"tries":0}
			accept_next=not accept_next
		var attempt:Dictionary=invitations[card.token]
		if attempt.choice!="yes" or attempt.clicked or attempt.tries>=2 or w.forest.clock>=float(card.until)-1.5:continue
		attempt.tries+=1
		await UI.click(self,card.panel.get_node_or_null("body/answer_yes"))
		attempt.clicked=daily.invitation_trace.any(func(e):return e.event=="heart_player_resolved" and e.invitation_id==card.token and e.get("click")=="yes")

func aim(point:Vector2)->void:
	g.view.follow_player=false;g.view.center=point;g.view.peek_elapsed=0
	g.view.zoom=maxf(1,g.view.zoom)

func point_click(at:Vector2,button:int=MOUSE_BUTTON_LEFT)->void:
	root.grab_focus()
	var motion:=InputEventMouseMotion.new()
	motion.position=at;motion.global_position=at;root.push_input(motion,true)
	for down in [true,false]:
		var event:=InputEventMouseButton.new()
		event.pressed=down;event.button_index=button;event.position=at;event.global_position=at
		event.button_mask=(MOUSE_BUTTON_MASK_RIGHT if button==MOUSE_BUTTON_RIGHT else MOUSE_BUTTON_MASK_LEFT) if down else 0
		root.push_input(event,true)
		await process_frame
	await frames()

func click_world(point:Vector2,button:int=MOUSE_BUTTON_LEFT)->void:
	aim(point)
	await point_click(g.view.screen(point),button)

func prepare_scene(directory:String,from_title:bool)->void:
	OS.set_environment("HABITAT_DATA_DIR",directory)
	var pool:Node=Pool.obtain(self,directory);pool.factory=func(_id):return OfflineLink.new()
	if from_title:
		var title:Node=load("res://scenes/title.tscn").instantiate()
		root.add_child(title);current_scene=title
		await frames()
		await UI.click(self,title.menu.get_node("new"))
		for i in 240:
			await process_frame
			if is_instance_valid(current_scene) and current_scene.get("company")!=null:break
		g=current_scene
	else:
		g=load("res://scenes/main_v3.tscn").instantiate()
		g.dialogue_adapter_factory=func(_id,_scope):return OfflineLink.new()
		root.add_child(g);current_scene=g
	w=g.world;c=g.company
	g.save_enabled=false;g.set_process(not manual_clock)
	g.memory_life.set_process(not manual_clock);g.life_archive.set_process(not manual_clock)
	last_clock=w.forest.clock
	await frames()

func greeting()->void:
	for i in 35:
		if g.welcome.phase=="greeting":break
		await tick_for(.5)
	for i in 4:
		await point_click(Vector2(640,365))
		await tick_for(.8)
	for i in 30:
		if g.welcome.phase in ["card","done"]:break
		await tick_for(.5)
	if g.welcome.phase=="card":
		await create_timer(.4).timeout
		check(await UI.click(self,g.welcome.card.get_node_or_null("body/answer_no")),"declines opening stewardship")
	check(seen.has("first_meeting"),"opening completed")

func open_care(id:String)->bool:
	if w.actors[id].region_id!=g.view.region_id:return false
	var p:Vector2=w.point(w.actors[id])
	aim(p)
	await point_click(g.view.screen(p)+Vector2(0,-24)*g.view.zoom,MOUSE_BUTTON_RIGHT)
	if not c.care_buttons.has("pat"):return false
	return await UI.click(self,c.care_buttons.pat)

func send(text:String)->void:
	if not g.chat.visible:await UI.click(self,g.dialogue_button)
	if not g.chat.visible:return
	await point_click(g.chat_input.get_global_rect().get_center())
	if not g.chat_input.has_focus():return
	for index in text.length():
		var event:=InputEventKey.new();event.pressed=true;event.unicode=text.unicode_at(index)
		root.push_input(event,true)
		await process_frame
	for down in [true,false]:
		var enter:=InputEventKey.new();enter.pressed=down;enter.keycode=KEY_ENTER;root.push_input(enter,true)
		await process_frame
	if g.chat.visible:
		var escape:=InputEventKey.new();escape.pressed=true;escape.keycode=KEY_ESCAPE;root.push_input(escape,true)
	await frames()

func provision_camp()->void:
	var origin:Vector2=w.point(w.actors.human)
	var trees:Array=w.objects.values().filter(func(o):return o.kind=="tree" and o.status=="mature")
	trees.sort_custom(func(a,b):return origin.distance_squared_to(w.point(a))<origin.distance_squared_to(w.point(b)))
	for tree in trees.slice(0,5):
		var pt:Vector2=w.point(tree)
		await click_world(pt)
		if w.work.jobs.get("human",{}).get("intent")=="chop":
			await tick_for(30)
			mark("chopped_tree")
			break
	for drop in w.drops.values():
		await click_world(w.point(drop));await tick_for(25)
		break
	var panel:Node=g.leisure_panel
	await click_world(w.point(w.life.station))
	if not panel.visible or panel.site_id!="play.standard.camp":
		await click_world(w.point(w.leisure.sites["play.standard.camp"]))
	if panel.visible:
		var button:Variant=UI.descendants(panel).filter(func(n):return n is Button and n.get_meta("panels_locale","")=="panels.choose_builder_build").front()
		if is_instance_valid(button):await UI.click(self,button)
		await frames()
		var picker:Node=g.participant_picker
		if picker.visible and picker.toggles.has("human"):
			for id in picker.toggles:
				if picker.toggles[id].button_pressed!=(id=="human"):await UI.click(self,picker.toggles[id])
			await UI.click(self,picker.get_ok_button())
		var close:Array=UI.descendants(panel).filter(func(n):return n is Button and n.text=="×")
		if panel.visible and not close.is_empty():await UI.click(self,close[0])
		await tick_for(45)
	check(w.standard.ready("home.barbecue"),"player builds camp")

func dinner(menu_id:String)->void:
	if not w.standard.ready("home.barbecue"):return
	var camp:Vector2=w.point(w.life.station)
	for offset in [Vector2(0,-.9),Vector2(-.82,-1.4),Vector2(.82,-1.4),Vector2(-.9,-.4),Vector2(.9,-.4),Vector2.ZERO]:
		var point:Vector2=camp+offset
		aim(point)
		var screen_point:Vector2=g.view.screen(point)
		if g.view.hit(screen_point)!=w.life.station.id:continue
		if IDS.any(func(id):return w.actors[id].region_id==g.view.region_id and Rect2(g.view.screen(w.point(w.actors[id]))+Vector2(-22,-85)*g.view.zoom,Vector2(44,90)*g.view.zoom).has_point(screen_point)):continue
		await point_click(screen_point)
		if not g.pending_camp.is_empty() or UI.shown(g,"res://scripts/fireside_panel.gd")!=null:break
	for i in 35:
		if UI.shown(g,"res://scripts/fireside_panel.gd")!=null:break
		await tick_for(1)
	var panel:Node=UI.shown(g,"res://scripts/fireside_panel.gd")
	receipt(menu_id,"panel",panel!=null)
	if panel==null:return
	if not w.life.fireside.burning():
		await UI.click(self,panel.light_button)
		receipt(menu_id,"light",w.life.fireside.burning())
	if not await UI.click(self,panel.roast_button):return
	var invite:Node=UI.shown(g,"res://scripts/fireside_invitation.gd")
	receipt(menu_id,"invitation",invite!=null)
	if invite==null:return
	await UI.click(self,invite.all_box)
	if not await UI.click(self,invite.get_ok_button()):return
	var menu:Node=UI.shown(g,"res://scripts/fireside_menu.gd")
	receipt(menu_id,"menu",menu!=null)
	if menu==null:return
	for btn in UI.descendants(menu):
		if btn is Button and btn.has_meta("expand_basics"):await UI.click(self,btn);break
	var choices:Array=UI.descendants(menu).filter(func(n):return n is Button and n.get_meta("menu_id","")==menu_id)
	receipt(menu_id,"recipe",not choices.is_empty() and not choices[0].disabled)
	if choices.is_empty() or choices[0].disabled:
		if menu.has_method("get_cancel_button"):await UI.click(self,menu.get_cancel_button())
		return
	menu.scroll.ensure_control_visible(choices[0])
	await frames()
	await UI.click(self,choices[0]);await UI.click(self,menu.start_button)
	receipt(menu_id,"cooking",not w.life.fireside.state.get("current",{}).is_empty())

func favorite_fish()->void:
	var clicked_water:=Vector2.INF
	for shore in w.fishing.nearby_shores("human",32):
		var point:=Vector2(shore.position[0],shore.position[1])
		var hook:=Vector2(shore.hook[0],shore.hook[1])
		var direction:Vector2=(hook-point).normalized()
		var choice:=Vector2.INF
		for offset in [1.0,2.0,3.0,4.0,5.0]:
			var water:Vector2=point+direction*float(offset)
			if w.fishing._ocean("home",water):choice=water;break
		if not choice.is_finite():continue
		aim(choice)
		if not g.view.hit(g.view.screen(choice)).is_empty():continue
		await click_world(choice)
		if not w._routes.has("human"):continue
		for step_index in 45:
			await tick_for(1)
			if not w._routes.has("human"):break
		if not w.fishing.shore("human").is_empty():
			clicked_water=choice
			break
	var reached:bool=not w.fishing.shore("human").is_empty()
	receipt("favorite_fish","shore",reached)
	if not reached:return
	if clicked_water.is_finite():await click_world(clicked_water)
	if not g.action_dock.popup.visible:
		await UI.click(self,g.actions_button)
		if not is_instance_valid(g.action_dock.menu):return
		if "我自己"==g.action_dock.action_tabs.get_tab_title(2):
			var tabbar:TabBar=g.action_dock.action_tabs.get_tab_bar()
			await point_click(tabbar.get_global_rect().position+tabbar.get_tab_rect(2).get_center())
		var fish_buttons:Array=UI.descendants(g.action_dock.menu).filter(func(n):return n is Button and n.is_visible_in_tree() and n.text==Text.text("activities.fish"))
		if fish_buttons.is_empty() or not await UI.click(self,fish_buttons[0]):return
	receipt("favorite_fish","confirmation",g.action_dock.popup.visible)
	if not await UI.click(self,g.action_dock.popup.get_ok_button()):return
	for step_index in 90:
		await tick_for(1)
		if not Fish.unplaced(w).is_empty():break
	var fish:Dictionary=Fish.unplaced(w)
	receipt("favorite_fish","catch",not fish.is_empty())
	if fish.is_empty():return
	var buttons:Array=UI.descendants(g.island_hud.notifications).filter(func(n):return n is Button and n.text==Text.text("hud.grill"))
	if buttons.is_empty() or not await UI.click(self,buttons[0]):return
	var dialogs:Array=g.get_children().filter(func(n):return n is ConfirmationDialog and n.visible and n.title==Text.text("ui.main.choose_a_campfire"))
	if dialogs.size()!=1:return
	await UI.click(self,dialogs[0].get_ok_button())
	if is_instance_valid(dialogs[0]) and dialogs[0].visible:
		await UI.click(self,dialogs[0].get_ok_button())
	for step_index in 45:
		await tick_for(1)
		if not w.fishing.fish.has(fish.id):break
	var exact:bool=w.life.fireside.state.get("current",{}).get("fish",{}).get("id","")==fish.id
	receipt("favorite_fish","same_fish_on_fire",exact)
	if not exact:return
	var panel:Node=UI.shown(g,"res://scripts/fireside_panel.gd")
	if panel==null or not await UI.click(self,panel.invite_button):return
	var invites:Node=UI.shown(g,"res://scripts/fireside_invitation.gd")
	if invites==null or not await UI.click(self,invites.checks.get("companion-2")):return
	await UI.click(self,invites.get_ok_button())
	receipt("favorite_fish","blue_invited","companion-2" in w.life.fireside.state.invited)

func absence(directory:String,delay:int)->void:
	if not Save.save_world(w,directory):return
	g.queue_free();await frames()
	var path:String=directory.path_join("island-v2.json")
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	data.forest_saved_wall-=delay;data.hunger.saved_at-=delay
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(data));file.close()
	await prepare_scene(directory,false)
	await tick_for(20)
	if is_instance_valid(c.return_card):await UI.click(self,c.return_card.get_node_or_null("body/close"))

func until_time(target:float)->void:
	if seconds<target:await tick_for(target-seconds)

func begin_steward()->bool:
	var toggle:Button=g.watch_ui.toggle if is_instance_valid(g.watch_ui) else g.steward.toggle
	for attempt in 2:
		if is_instance_valid(g.steward.setup_card) and g.steward.setup_card.visible:break
		await UI.click(self,toggle)
		await frames()
	for attempt in 2:
		if g.steward.active or not is_instance_valid(g.steward.setup_card) or not g.steward.setup_card.visible:break
		await UI.click(self,g.steward.setup_button)
		await frames()
	return g.steward.active

func photo()->void:
	if not await UI.click(self,g.island_hud.camera_button):return
	if not c.camera.active:return
	var children:Array=UI.descendants(c.camera.overlay)
	for name in ["Shutter","Close"]:
		var target:Array=children.filter(func(node):return node.name==name)
		if not target.is_empty():await UI.click(self,target[0])
		await frames()
	capture()

func run()->void:
	var directory:String=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-") or DisplayServer.get_name()=="headless":quit(2);return
	OS.set_environment("HABITAT_OPENING","standard")
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	wall_start=Time.get_ticks_msec()
	await prepare_scene(directory,true)
	await greeting()
	await provision_camp()
	await until_time(180);await dinner("single:mushroom")
	await until_time(440);await open_care("codex")
	await until_time(590);await dinner("single:mushroom")
	if OS.get_environment("HABITAT_HOUR_EXTRA_INPUTS")=="1":
		await until_time(690);await favorite_fish()
		await until_time(945);await dinner("single:mushroom")
		for step_index in 105:
			if not c.night.available_fire().is_empty():
				await send("讲个故事吧")
				break
			await tick_for(1)
	else:
		await until_time(790);await dinner("single:mushroom")
		await until_time(907);await dinner("single:mushroom")
	await until_time(1200)
	var managed:bool=await begin_steward()
	check(managed,"clicking the visible stewardship button starts stewardship")
	if managed:mark("steward_on")
	await until_time(1800);await absence(directory,7200)
	await until_time(1825)
	if not g.steward.active:
		check(await begin_steward(),"player reauthorizes stewardship after return")
	await until_time(2400)
	if g.steward.active:
		var toggle:Button=g.watch_ui.toggle if is_instance_valid(g.watch_ui) else g.steward.toggle
		await UI.click(self,toggle)
		check(not g.steward.active,"click returns control to player")
	await until_time(2580)
	var moon:Vector2=w.nearest_walkable("home",Vector2(-16,64))
	if moon.is_finite():await click_world(moon)
	await until_time(2820)
	if w.moon.contains(w.point(w.actors.human)):mark("moon_arrival")
	await click_world(Vector2(43,210))
	await until_time(3000)
	if w.point(w.actors.human).y>175:mark("flower_isle_arrival")
	await photo()
	await until_time(3600)
	var output:String=OS.get_environment("HABITAT_HOUR_RESULT")
	var file:=FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"seconds":seconds,"wall_seconds":float(Time.get_ticks_msec()-wall_start)/1000,"events":events,"input_cards":invitations,"actions":actions,"checks_failed":failures,
		"seeds":{"world":OS.get_environment("HABITAT_TEST_SEED"),"brain":OS.get_environment("HABITAT_BRAIN_SEED"),"weather":w.weather.weather_seed}},"  "))
	file.close()
	g.queue_free();await frames();quit(1 if failures else 0)
