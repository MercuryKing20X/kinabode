extends "res://tests/test_overnight_player.gd"
## Native-input story acceptance: no actor position assignments, no granted materials.
func press(button:BaseButton)->bool:return await WardrobeUI.click(self,button)
func walk(at:Vector2)->void:
	game.view.center=at;game.view.follow_player=false;await process_frame
	print("STORY_WALK_HIT ",at," hit=",game.view.hit(game.view.screen(at)))
	await mouse(game.view.screen(at));check(await wait_route(),"native walk "+str(at))
func run()->void:
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	var temp:String=OS.get_environment("HABITAT_DATA_DIR")
	captures=OS.get_environment("HABITAT_ISLAND_STORY_CAPTURE")
	OS.set_environment("HABITAT_OPENING","standard")
	w=World.new("res://content/home-v3/world.json");w.world_id="00000000-0000-4000-8000-000000001027";w.residents.provision(w)
	w.library=Library.new();w.library.configure(temp.path_join("works"));check(Opening.apply(w,w.library,"standard").ok,"fresh actual standard opening")
	w.intelligence.activate_presets();w.hunger.start()
	# Repeat the same authored local-life scenario; do not draw a new set of
	# idle routes and speech candidates from wall time on every suite run.
	w.weather.weather_seed=1027
	var seed_index:=0
	for id in w.director.routines:
		w.director.routines[id].rng.seed=1027+seed_index;seed_index+=1
	# Appearance assignments are the user's explicitly permitted temporary fixture.
	for pair in [["codex","ai-gpt"],["companion-2","ai-deepseek"],["npc.mira","ai-claude"],["npc.nora","ai-glm"]]:w.actors[pair[0]].appearance_id=pair[1]
	game=load("res://scenes/main_v3.tscn").instantiate();game.world=w;root.add_child(game)
	game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.island_hud.set_process(false)
	ui=UI.new();ui.game=game;ui.w=w
	await process_frame;await process_frame;game.chat.hide()
	for pair in [["codex","ai-gpt"],["companion-2","ai-deepseek"],["npc.mira","ai-claude"],["npc.nora","ai-glm"]]:
		w.actors[pair[0]].appearance_id=pair[1]
		check(w.actors[pair[0]].appearance_id==pair[1],"temporary alternate appearance "+pair[0])
	check(not w.their_island.ready(),"formal start does not unlock island story")
	var trees:Array=w.objects.values().filter(func(o):return o.kind=="tree" and o.status=="mature")
	trees.sort_custom(func(a,b):return w.point(a).distance_squared_to(w.point(w.actors.human))<w.point(b).distance_squared_to(w.point(w.actors.human)))
	var required_wood:int=w.leisure.cost(w.leisure.sites[w.standard.site_for("home.barbecue")])+6
	var clicked:=false
	for tree in trees:
		if w.storage.count("wood")>=required_wood:break
		game.view.center=w.point(tree);game.view.follow_player=false
		var this_tree:=false
		for lift in [40,80,120,160,200]:
			var pixel:Vector2=game.view.screen(w.point(tree))-Vector2(0,lift)
			if game.view.hit(pixel)!=tree.id:continue
			await mouse(pixel);clicked=true;this_tree=true;break
		if not this_tree:continue
		for frame in range(5000):
			await advance()
			if not w.work.jobs.has("human"):break
	check(clicked and w.storage.count("wood")>=required_wood,"native tree harvesting funds unchanged camp plus three real ignitions")
	var center:Vector2=w.point(w.barbecues["home.barbecue"].station)
	game.view.center=center;await mouse(game.view.screen(center));await process_frame
	var builders:Array=WardrobeUI.descendants(game.leisure_panel).filter(func(n):return n is Button and n.text=="选择建造者 · 施工")
	check(builders.size()==1,"camp construction button")
	if builders.is_empty():await end_story();return
	check(await press(builders[0]),"native construction picker")
	for id in game.participant_picker.toggles:
		var box:CheckBox=game.participant_picker.toggles[id]
		if box.button_pressed!=(id=="human"):check(await press(box),"choose host builder")
	check(await press(game.participant_picker.get_ok_button()),"confirm construction")
	for frame in range(8000):
		await advance()
		if not w.work.jobs.has("human"):break
	check(w.standard.ready("home.barbecue"),"real paid camp built");game.leisure_panel.hide()
	# A real extra mushroom batch feeds all four before their shared first visit.
	var gathered:bool=false
	for patch in w.life.patches.values():
		if int(patch.get("remaining",patch.get("amount",4)))<=0:continue
		game.view.center=w.point(patch);game.view.follow_player=false;await process_frame
		for lift in [0,12,24,36]:
			var pixel:Vector2=game.view.screen(w.point(patch))-Vector2(0,lift)
			if game.view.hit(pixel)!=patch.id:continue
			await mouse(pixel)
			for frame in range(5000):
				await advance()
				if not w.work.jobs.has("human"):break
			gathered=w.storage.count("mushroom")>=9;break
		if gathered:break
	check(gathered,"native real mushroom gathering funds three meals including all four visiting companions")
	for meal in range(3):
		await walk(center+Vector2(0,8))
		game.view.center=center;await process_frame
		print("CAMP_HIT ",game.view.hit(game.view.screen(center)))
		await mouse(game.view.screen(center));await wait_route();await advance();await process_frame;await process_frame
		var panel:Node=ui.shown_script(CampPanel)
		if panel==null:
			# Observe the actual fire hit after diners/needs changed the overlay.
			for offset in [Vector2(0,-18),Vector2(-12,-8),Vector2(12,-8),Vector2(0,-30)]:
				var pixel:Vector2=game.view.screen(center)+offset
				if game.view.hit(pixel)!="home.barbecue":continue
				await mouse(pixel);await wait_route();await advance();await process_frame
				panel=ui.shown_script(CampPanel)
				if panel!=null:break
		if panel==null:check(false,"fire panel meal "+str(meal));await end_story();return
		if not w.barbecues["home.barbecue"].fireside.burning():check(await press(panel.light_button),"real ignition")
		check(await press(panel.roast_button),"native barbecue")
		var invite:Node=ui.shown_script(Invite)
		if invite==null:check(false,"invitation");break
		for who in invite.checks:
			if invite.checks[who].disabled:
				check((meal==2 or who=="companion-2") and (who in invite.life.fireside.selected_guests or who in invite.life.fireside.state.get("invited",[])),"native retained real invitation "+who)
				continue
			if invite.checks[who].button_pressed!=(meal==2 or who=="companion-2"):check(await press(invite.checks[who]),"native chosen real invitation "+who)
		check(await press(invite.get_ok_button()),"confirm invitation")
		var menu:Node=ui.shown_script(Menu)
		if menu==null:check(false,"menu");break
		var expand:Button=WardrobeUI.descendants(menu).filter(func(n):return n is Button and n.get_meta("expand_basics",false))[0]
		check(await press(expand),"native expands basic grills")
		var mushroom_button:Button=WardrobeUI.descendants(menu).filter(func(n):return n is Button and n.get_meta("menu_id","")=="single:mushroom")[0]
		menu.scroll.ensure_control_visible(mushroom_button);await process_frame;await process_frame
		check(await press(mushroom_button),"native selects exact real mushroom")
		check(await press(menu.start_button),"start real meal")
		for frame in range(2500):
			await advance()
			if w.barbecues["home.barbecue"].fireside.state.current.get("eaten",0)>=(5 if meal==2 else 2):break
		check(w.barbecues["home.barbecue"].fireside.state.current.get("eaten",0)==(5 if meal==2 else 2),"all intended diners actually finish meal "+str(meal))
		print("STORY_MEAL_DIAGNOSTIC ",meal," ",JSON.stringify(w.barbecues["home.barbecue"].fireside.state.current))
		game.island_hud.refresh();await process_frame
		var end_buttons:Array=WardrobeUI.descendants(game.island_hud.task).filter(func(n):return n is Button and n.text=="×")
		check(end_buttons.size()==1 and await press(end_buttons[0]),"native end completed circle")
		await advance()
		check(w.memories.records.filter(func(e):return e.kind=="shared_barbecue" and e.facts.get("version")==2).size()==meal+1,"real committed meal "+str(meal+1))
	print("STORY_MEAL_FACTS ",JSON.stringify(w.memories.records.filter(func(e):return e.kind=="shared_barbecue")))
	check(w.their_island.ready(),"third actual meal unlocks")
	for frame in range(1200):
		await advance()
		if w.their_island.introduced:break
	if not w.their_island.introduced:
		var state:Dictionary={}
		for id in w.director.routines:
			var r:RefCounted=w.director.routines[id];state[id]={"kind":r.kind,"held":r.held,"rank":w.hunger.rank(id),"route":w._routes.has(id),"owns_route":r.owns_route,"quiet_until":r.visual_quiet_until,"time":r.time,"busy":w.their_island.story_busy(r)}
		print("STORY_INTRO_DIAGNOSTIC ",JSON.stringify({"actors":state,"intro_actor":w.their_island.intro_actor,"unlocked":w.their_island.unlocked,"started":w.their_island.story_started}))
	check(w.their_island.introduced,"nearest fed companion delivers southern intro")
	var intro_events:Array=w.director.events.filter(func(e):return e.get("context")=="island_intro")
	check(not intro_events.is_empty(),"actual intro speech event retained")
	if not intro_events.is_empty():
		var speaker:String=intro_events[-1].actor_id
		check(w.actors[speaker].facing=="down" and not w._routes.has(speaker),"speaker stopped and faces south at delivery")
	await screenshot("standard-third-meal-intro")
	await handbook_evidence()
	check(await press(game.gathering_button),"native four-follow menu")
	if not game.follow_ui.all_box.button_pressed:check(await press(game.follow_ui.all_box),"native select all four")
	check(await press(game.follow_ui.menu.get_ok_button()) and w.activities.following.size()==4,"native exactly four follow")
	for point in [Vector2(81,105),Vector2(93,185),Vector2(93,208)]:await walk(point)
	check(w.home_island.here(),"host crosses real long bridge")
	for territory in w.home_island.config.their_island.territories:
		if territory.owner_id=="shared":continue
		await walk(Vector2(territory.sign[0],territory.sign[1])+Vector2(0,5))
		for frame in range(1200):
			await advance()
			if territory.owner_id in w.their_island.arrivals:break
		if territory.owner_id not in w.their_island.arrivals:
			var r:RefCounted=w.director.routines[territory.owner_id]
			print("STORY_MISSING_AT_VISIT ",territory.owner_id," ",JSON.stringify({"position":w.actors[territory.owner_id].position,"human":w.actors.human.position,"kind":r.kind,"held":r.held,"rank":w.hunger.rank(territory.owner_id),"route":w._routes.has(territory.owner_id),"job":w.work.jobs.get(territory.owner_id,{}),"busy":w.their_island.story_busy(r),"next_speech":r.next_speech,"speech_after":w.director.speech_after,"time":r.time,"started":w.their_island.story_started.get(territory.owner_id)}))
		await screenshot("arrival-"+territory.owner_id)
		if territory.owner_id=="companion-2":
			for locale in ["zh_CN","en"]:
				TranslationServer.set_locale(locale);preload("res://scripts/localization.gd").events.changed.emit()
				for dimensions in [Vector2i(1280,800),Vector2i(960,640)]:
					root.size=dimensions;await process_frame;await process_frame
					await screenshot("sign-"+locale+"-"+str(dimensions.x))
			TranslationServer.set_locale("zh_CN");preload("res://scripts/localization.gd").events.changed.emit();root.size=Vector2i(1280,800)
	# Shared vacation arrival is asynchronous; validate all four after the same native tour.
	# The last territory's resident may already have spoken while we visited an
	# earlier sign. Still let the other real followers settle and pass the
	# original shared speech gate before checking their actual delivered facts.
	for frame in range(1200):
		if w.their_island.arrivals.size()==4:break
		await advance()
	for resident_id in w.standard.config.companions:check(resident_id in w.their_island.arrivals,"actual arrival speech "+resident_id)
	check(w.memories.records.filter(func(e):return e.kind=="island_arrival").size()==4,"four actual arrival facts")
	var human_diary:Dictionary=w.memories.query("human",{"kind":"island_arrival"})
	check(human_diary.ok and human_diary.total==4,"our days shows all four actually heard arrival facts")
	await our_days_evidence()
	await end_story()
func end_story()->void:
	for id in w.director.routines:
		var r:RefCounted=w.director.routines[id]
		print("STORY_RESIDENT_DIAGNOSTIC ",id," ",JSON.stringify({"actor":w.actors[id],"kind":r.kind,"held":r.held,"rank":w.hunger.rank(id),"route":w._routes.has(id),"job":w.work.jobs.get(id,{}),"quiet_until":r.visual_quiet_until,"time":r.time,"busy":w.their_island.story_busy(r),"started":w.their_island.story_started.get(id),"next_speech":r.next_speech,"chat":game.chat.visible,"chat_actor":game.chat_actor}))
	print("THEIR ISLAND STORY INPUT checks=",checks," failed=",failures)
	print("STORY_CHECKS ",JSON.stringify(check_rows))
	print("STORY_STATE ",JSON.stringify({"human":w.actors.human,"fire":w.barbecues["home.barbecue"].fireside.state,"intro":w.their_island.introduced,"arrivals":w.their_island.arrivals,"routines":w.director.routines.keys()}))
	game.queue_free();ui.free();await process_frame;quit(1 if failures else 0)

func key_to(viewport:Viewport,code:Key)->void:
	for down in [true,false]:
		var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=down
		viewport.push_input(event,true);await process_frame
func handbook_evidence()->void:
	var pop:PopupMenu=game.handbook_menu.get_popup()
	var index:=-1
	for i in pop.item_count:
		if str(pop.get_item_metadata(i))=="opening_board":index=i
	check(index>=0,"handbook exposes island goals")
	if index<0:return
	for locale in ["zh_CN","en"]:
		# Locale/viewport are presentation fixtures, never world/player actions.
		TranslationServer.set_locale(locale);preload("res://scripts/localization.gd").events.changed.emit()
		for dimensions in [Vector2i(1280,800),Vector2i(960,640)]:
			root.size=dimensions;await process_frame;await process_frame
			check(await press(game.handbook_menu),"native handbook popup")
			print("GOAL_POPUP ",pop.visible," pos=",pop.position," size=",pop.size," focused=",pop.get_focused_item()," index=",index)
			var target:Vector2=Vector2(pop.position)+Vector2(float(pop.size.x)/2,float(pop.size.y)-14)
			await mouse(target)
			var dialogs:Array=game.get_children().filter(func(n):return n is AcceptDialog and n.visible and n.title==preload("res://scripts/localization.gd").text("ui.main.noticeboard_island_life"))
			check(dialogs.size()==1,"native handbook goal panel")
			if dialogs.is_empty():continue
			var goal:String=preload("res://scripts/localization.gd").text("theirs.goal")
			check(WardrobeUI.descendants(dialogs[0]).any(func(n):return n is RichTextLabel and goal in n.text),"localized southern goal visible")
			await screenshot("handbook-"+locale+"-"+str(dimensions.x))
			check(await press(dialogs[0].get_ok_button()),"native close handbook")
	TranslationServer.set_locale("zh_CN");preload("res://scripts/localization.gd").events.changed.emit();root.size=Vector2i(1280,800)

func our_days_evidence()->void:
	var pop:PopupMenu=game.handbook_menu.get_popup()
	var index:=-1
	for i in pop.item_count:
		if str(pop.get_item_metadata(i))=="memory_books":index=i
	check(index>=0,"handbook has the single Memory entry (DIRECTION 2026-11-10)")
	if index<0:return
	check(await press(game.handbook_menu),"native open handbook for Our Days")
	await process_frame;await process_frame
	check(pop.visible,"actual handbook popup stays visible")
	var height:float=(float(pop.size.y)-8.0)/float(pop.item_count)
	var target:=Vector2(pop.position)+Vector2(float(pop.size.x)/2.0,4.0+(float(index)+.5)*height)
	await mouse(target)
	check(game.book_panel.visible,"native Our Days panel opens")
	if not game.book_panel.visible:return
	var arrivals:Array=game.memory_books.entries.values().filter(func(e):return e.params.get("legacy",{}).get("kind","")=="island_arrival")
	check(arrivals.size()==4,"Memory book retains four actual arrivals")
	for id in ["codex","companion-2","npc.mira","npc.nora"]:
		check(arrivals.any(func(e):return e.params.legacy.facts.resident_id==id and "human" in e.participants),"Memory retains actual heard plan "+id)
		game.book_panel.partner.select(game.book_panel.residents.find(id));game.book_panel.refresh()
		var retained:Array=game.memory_books.list_for(id,"facts").filter(func(e):return e.params.get("legacy",{}).get("kind","")=="island_arrival")
		if retained.size()==1:
			var all_facts:Array=game.memory_books.list_for(id,"facts")
			game.book_panel.offset=(all_facts.find_custom(func(e):return e.id==retained[0].id)/10)*10;game.book_panel.refresh()
		check(retained.size()==1 and WardrobeUI.descendants(game.book_panel.rows).any(func(n):return (n is Label or n is RichTextLabel) and game.memory_books.render(retained[0]) in n.text),"Memory visible row retains actual plan "+id)
	await screenshot("our-days-four-arrival-plans")
	await key_to(root,KEY_ESCAPE)
	check(not game.book_panel.visible,"native Escape closes Our Days")
