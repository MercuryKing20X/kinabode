extends "res://tests/test_intelligence_core_input.gd"
var captured:Array=[]
var rounds:Array=[]
func record(e:Dictionary)->void:
	var clean:Dictionary={"kind":e.get("kind"),"seconds":Time.get_ticks_msec()/1000.0}
	for k in ["message","text","state","total_tokens","input_tokens","output_tokens","complete","command","world_chars","world_fields","system_chars","native_tools_chars","turn_limit","original_world_chars","result"]:
		if e.has(k):clean[k]=e[k]
	captured.append(clean)
	print("AI_EVENT ",JSON.stringify(clean))
func run()->void:
	if OS.get_environment("HABITAT_LIVE_TEST")!="1" or not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-habitat-live-test-"):quit(2);return
	var accounting:=ConfigFile.new()
	accounting.load(OS.get_environment("HABITAT_DATA_DIR").path_join("resident-intelligence-ui.cfg"))
	var spent:int=0
	var calls:int=0
	for section in accounting.get_sections():
		var ledger:Dictionary=accounting.get_value(section,"autonomy_accounting",{})
		spent+=int(ledger.get("tokens",0));calls+=ledger.get("turns",[]).size()
	# Reserve 100k because a reported tool cycle may overshoot the bridge's 64k gate.
	if spent+250000>6000000 or calls>=150:print("LIVE_BUDGET_STOP tokens=",spent," calls=",calls);quit(0);return
	var phrase:String=OS.get_environment("HABITAT_LIVE_PHRASE")
	if phrase.is_empty():print("Explicit single phrase required");quit(2);return
	await fresh()
	game._select_chat("codex")
	game.resident_connections.open("codex")
	await process_frame;await process_frame
	game.resident_connections.details_scroll.ensure_control_visible(game.controller_picker)
	await process_frame;await process_frame
	await picture("connection-before")
	game.resident_connections.details_scroll.ensure_control_visible(game.controller_picker)
	await process_frame;await process_frame
	print("PICKER ",game.controller_picker.is_visible_in_tree()," parent ",game.controller_picker.get_parent().visible)
	await UI.click(self,game.controller_picker)
	print("POPUP ",game.controller_picker.get_popup().visible," ",game.controller_picker.get_popup().position," ",game.controller_picker.get_popup().size)
	await picture("popup")
	await choose(game.controller_picker,0)
	print("MODEL_ON ",game.world.director.model_controlled("codex"))
	game.resident_connections.tabs.current_tab=2;game.resident_connections._show_section()
	await process_frame;await process_frame
	game.resident_connections.details_scroll.ensure_control_visible(game.resident_connections.level_picker)
	await process_frame;await process_frame
	await UI.click(self,game.resident_connections.level_picker)
	await choose(game.resident_connections.level_picker,2)
	game.resident_connections.details_scroll.ensure_control_visible(game.resident_connections.autonomy_toggle)
	await process_frame;await process_frame
	check(await UI.click(self,game.resident_connections.autonomy_toggle),"native autonomy toggle")
	print("AI_CONFIG ",JSON.stringify(game.resident_connections.preferences.preference("codex")))
	game.resident_connections.close_panel()
	game._ensure_link("codex")
	game.links.codex.event_received.connect(record)
	check(await UI.click(self,game.dialogue_button),"open chat")
	check(await UI.click(self,game.command_page.tabs.get_child(1)),"native Talk channel")
	game._select_chat("codex")
	var requests:Array=phrase.split("|")
	for request in requests:
		captured.clear()
		if request.begins_with("@"):
			await scenario(request);continue
		if request=="叫小蓝和你一起去浇水":await dry_plants()
		game._select_chat("codex")
		if not game.chat.visible:await UI.click(self,game.dialogue_button)
		if game.command_page.commands_mode:await UI.click(self,game.command_page.tabs.get_child(1))
		game._select_chat("codex")
		var current_cfg:=ConfigFile.new();current_cfg.load(OS.get_environment("HABITAT_DATA_DIR").path_join("resident-intelligence-ui.cfg"))
		var current_total:int=0;var current_turns:int=0
		for section in current_cfg.get_sections():
			var account:Dictionary=current_cfg.get_value(section,"autonomy_accounting",{})
			current_total+=int(account.get("tokens",0));current_turns+=account.get("turns",[]).size()
		if current_total+250000>6000000 or current_turns>=150:print("LIVE_BUDGET_STOP ",current_total);break
		var started:int=Time.get_ticks_msec()
		await text_input(request,true)
		print("REQUEST_STATUS ",request," ",game.status.text," direct=",not game.group_chat," commands=",game.command_page.commands_mode)
		var deadline:int=Time.get_ticks_msec()+(125000 if game.links.codex.is_busy() else 1000)
		while Time.get_ticks_msec()<deadline:
			await create_timer(.1).timeout
			game._process(.1)
			if captured.any(func(e):return e.kind=="error"):break
			if captured.any(func(e):return e.kind=="assistant") and not game.links.codex.is_busy():break
		for tick in 6000:
			game._process(.1)
			if not game.world.work.jobs.has("codex") and not game.world.work.jobs.has("companion-2") and game.local_host_commands.tracked.is_empty():break
			if tick%30==0:await process_frame
		await picture("action-"+str(rounds.size()))
		rounds.append({"input":request,"seconds":(Time.get_ticks_msec()-started)/1000.0,"events":captured.duplicate(true),"positions":{"codex":game.world.actors.codex.position.duplicate(),"human":game.world.actors.human.position.duplicate()},"pending_fish":game.world.fishing.held("codex").duplicate(true),"wood":game.world.storage.count("wood"),"seed_turnip":game.world.storage.count("seed.turnip"),"orders":game.world.farms.orders.size(),"work_events":game.world.work.events.duplicate(true),"plots":game.world.farms.plots.duplicate(true),"farm_orders":game.world.farms.orders.duplicate(true),"ledger_tokens":game.autonomy.scheduler.usage("codex").get("tokens",0)})
		var f:=FileAccess.open(OS.get_environment("HABITAT_DATA_DIR").path_join("actions-sanitized.json"),FileAccess.WRITE)
		f.store_string(JSON.stringify(rounds,"  "));f.close()
		if captured.any(func(e):return e.kind=="error"):break
	game.links.codex.shutdown();game.queue_free();await process_frame
	quit(0)

func choose(picker:OptionButton,index:int)->void:
	var pop:PopupMenu=picker.get_popup()
	var at:Vector2=Vector2(pop.position)+Vector2(30, 8+32*index+16)
	var motion:=InputEventMouseMotion.new();motion.position=at;motion.global_position=at;root.push_input(motion,true);await process_frame
	for down in [true,false]:
		var e:=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;e.position=at;e.global_position=at;root.push_input(e,true);await process_frame

func dry_plants()->void:
	# Real seeds and actual plant commits; stop before first water. No crop mutation.
	game.chat.hide()
	game._select_chat("companion-2")
	if not game.chat.visible:await UI.click(self,game.dialogue_button)
	if game.command_page.commands_mode:await UI.click(self,game.command_page.tabs.get_child(1))
	game._select_chat("companion-2")
	await text_input("帮我种萝卜",true)
	for tick in 6000:
		game._process(.05);game.local_host_commands._process(.05)
		if game.world.farms.plots.values().any(func(p):return not str(p.crop_id).is_empty() and not p.watered):break
	await text_input("别干了",true)
	game._select_chat("codex")

func step_time(seconds:float)->void:
	for tick in int(seconds*10):
		game._process(.1);game.local_host_commands._process(.1);game.view._process(.1)
		if tick%20==0:await process_frame
func map_click(point:Vector2)->void:
	game.chat.hide();game.view.follow_player=false;game.view.center=point;await process_frame;await process_frame
	var at:Vector2=game.view.screen(point)
	for down in [true,false]:
		var e:=InputEventMouseButton.new();e.position=at;e.global_position=at;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;root.push_input(e,true);await process_frame
func scenario(key:String)->void:
	var w:RefCounted=game.world
	if key=="@camp":
		await map_click(w.point(w.leisure.sites["play.standard.camp"]))
		var buttons:Array=UI.descendants(game.leisure_panel).filter(func(n):return n is Button and n.text.contains("建造"))
		if buttons.is_empty():print("SCENARIO camp builder missing");return
		await UI.click(self,buttons[0]);await process_frame
		if not game.participant_picker.toggles["npc.mira"].button_pressed:await UI.click(self,game.participant_picker.toggles["npc.mira"])
		for id in game.participant_picker.toggles:
			if id!="npc.mira" and game.participant_picker.toggles[id].button_pressed:await UI.click(self,game.participant_picker.toggles[id])
		await UI.click(self,game.participant_picker.get_ok_button());game.leisure_panel.hide();await step_time(90)
		print("SCENARIO camp ",w.leisure.sites["play.standard.camp"].complete)
	elif key=="@forage":
		# Host map action performs real collection; no stock fixture.
		for patch in w.life.patches.values():
			await map_click(w.point(patch));await step_time(90)
			if w.storage.count("mushroom")>=3:break
		print("SCENARIO mushrooms ",w.storage.count("mushroom"))
	elif key=="@meal":
		await map_click(w.point(w.life.station));await step_time(40)
		var panel:Node=UI.shown(game,"res://scripts/fireside_panel.gd")
		if panel==null:print("SCENARIO meal missing fire panel");return
		await UI.click(self,panel.light_button);await UI.click(self,panel.roast_button)
		var invite:Node=UI.shown(game,"res://scripts/fireside_invitation.gd")
		if invite==null:print("SCENARIO meal missing invite");return
		for guest in invite.checks:
			if not invite.checks[guest].button_pressed and not invite.checks[guest].disabled:await UI.click(self,invite.checks[guest])
		await UI.click(self,invite.get_ok_button())
		var menu:Node=UI.shown(game,"res://scripts/fireside_menu.gd")
		if menu==null:return
		for b in UI.descendants(menu):
			if b is Button and b.has_meta("expand_basics"):await UI.click(self,b);break
		for b in UI.descendants(menu):
			if b is Button and b.has_meta("menu_id") and not b.disabled:
				menu.scroll.ensure_control_visible(b);await process_frame;await UI.click(self,b);break
		await UI.click(self,menu.start_button);await step_time(40)
		print("SCENARIO meal ",JSON.stringify(w.life.fireside.state))
	elif key=="@mature":await step_time(1210)
	elif key=="@autonomy":
		game.chat.hide();game.chat_input.release_focus()
		for tick in 6000:
			if game.links.codex.is_busy():await create_timer(.1).timeout
			elif tick%20==0:await process_frame
			game._process(.1);game.view._process(.1)
		print("SCENARIO autonomy ",JSON.stringify(game.autonomy.status("codex")))
	elif key=="@command":
		if not game.chat.visible:await UI.click(self,game.dialogue_button)
		await UI.click(self,game.command_page.tabs.get_child(0));game.command_page.selected=["codex"];game.command_page.category=0;game.command_page.rebuild_targets();game.command_page.rebuild()
		for b in game.command_page.buttons.values():
			if b is Button and b.text.contains("你在干嘛") and not b.disabled:await UI.click(self,b);print("SCENARIO command preset ",game.command_page.records.text);break
		await step_time(10);await picture("command-preset")
		await UI.click(self,game.command_page.tabs.get_child(1));game._select_chat("codex")
	elif key=="@chess":
		if not game.chat.visible:await UI.click(self,game.dialogue_button)
		if game.command_page.commands_mode:await UI.click(self,game.command_page.tabs.get_child(1))
		if w.storage.count("wood")<26:
			game._select_chat("companion-2");await text_input("帮我砍九棵树",true);await step_time(400)
		game.chat.hide()
		await map_click(w.point(w.leisure.sites["play.gomoku"]));await step_time(40)
		if game.chess_choice.visible:
			for b in game.chess_choice.column.get_children():
				if b is Button and b.get_meta("chess_key","")=="ui.main.gomoku":await UI.click(self,b);break
		var p:Node=game.gomoku_panel
		var table_id:String="play.gomoku"
		print("CHESS_PREVIEW ",p.card.visible," build ",p.build_button.visible," wood ",w.storage.count("wood"))
		if p.build_button.visible and not p.build_button.disabled:
			await UI.click(self,p.build_button)
			for id in game.participant_picker.toggles:
				var b:CheckBox=game.participant_picker.toggles[id]
				if b.button_pressed!=(id=="companion-2") and not b.disabled:await UI.click(self,b)
			await UI.click(self,game.participant_picker.get_ok_button());await step_time(10)
		print("CHESS_BUILD_RESULT ",JSON.stringify(w.leisure.sites["play.gomoku"])," status ",game.status.text)
		if not w.leisure.sites[table_id].complete:
			p.card.hide();game.participant_picker.hide();game.chess_choice.hide()
			var spot:=Vector2.INF
			for y in range(4,124,2):
				for x in range(4,156,2):
					var at:=Vector2(x+.5,y+.5)
					if w.leisure.validate_place("play-gomoku",at).ok and w.leisure.chess_space_clear({"id":"preview","position":[at.x,at.y],"region_id":"home"},w.library.artworks["play-gomoku"].recreation):spot=at;break
				if spot.is_finite():break
			if spot.is_finite():
				game.leisure_panel.open_site("play.gomoku")
				for index in game.leisure_panel.templates.item_count:
					if game.leisure_panel.templates.get_item_metadata(index)=="play-gomoku":game.leisure_panel.templates.select(index);break
				for b in UI.descendants(game.leisure_panel):
					if b is Button and b.text.contains("摆放"):await UI.click(self,b);break
				print("CHESS_ALT_SPOT ",spot," placing ",game.placing_facility)
				var before:Array=w.leisure.sites.keys();await map_click(spot-Vector2(.5,.5))
				print("CHESS_ALT_PLACED ",game.status.text," serial ",w.leisure.serial)
				for id in w.leisure.sites:
					if id not in before:table_id=id;break
				game.leisure_panel.open_site(table_id)
				for b in UI.descendants(game.leisure_panel):
					if b is Button and b.text.contains("建造"):await UI.click(self,b);break
				for id in game.participant_picker.toggles:
					var b:CheckBox=game.participant_picker.toggles[id]
					if b.button_pressed!=(id=="companion-2") and not b.disabled:await UI.click(self,b)
				await UI.click(self,game.participant_picker.get_ok_button());game.leisure_panel.hide();await step_time(10)
				await map_click(w.point(w.leisure.sites[table_id]));await step_time(40)
				if game.chess_choice.visible:
					for b in game.chess_choice.column.get_children():
						if b is Button and b.get_meta("chess_key","")=="ui.main.gomoku":await UI.click(self,b);break
		game.participant_picker.hide();game.chess_choice.hide();p.open(table_id);await process_frame;await process_frame
		await UI.click(self,p.mode);await choose(p.mode,1)
		await picture("chess-before-start")
		print("CHESS_MODE ",p.mode.selected," opponent ",p.opponent.selected," disabled ",p.start_button.disabled," table ",table_id," complete ",w.leisure.sites[table_id].complete," status ",game.status.text," message ",p.message.text)
		p.card.z_index=150
		await UI.click(self,p.start_button);await step_time(60)
		for move in 60:
			var accounting:=ConfigFile.new();accounting.load(OS.get_environment("HABITAT_DATA_DIR").path_join("resident-intelligence-ui.cfg"))
			var spent:int=0
			for section in accounting.get_sections():spent+=int(accounting.get_value(section,"autonomy_accounting",{}).get("tokens",0))
			if spent+250000>6000000:
				if p.pause_button.visible:await UI.click(self,p.pause_button)
				print("LIVE_BUDGET_STOP chess ",spent);break
			var g:Dictionary=w.gomoku.sessions.get(table_id,{})
			if g.is_empty() or g.phase in ["paused","finished"]:break
			if w.gomoku._turn(g)=="human":
				var square:=Vector2i(-1,-1)
				for y in 15:
					for x in 15:
						if not g.history.any(func(stone):return int(stone[0])==x and int(stone[1])==y):square=Vector2i(x,y);break
					if square.x>=0:break
				var geom:Dictionary=p.board.geometry()
				var at:Vector2=p.board.get_global_rect().position+geom.origin+Vector2(square)*geom.step
				for down in [true,false]:
					var e:=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;e.position=at;e.global_position=at;root.push_input(e,true);await process_frame
			else:
				var previous_hand:int=g.history.size()
				await UI.click(self,p.model_button)
				var deadline:int=Time.get_ticks_msec()+65000
				while game.links.codex.is_busy() and Time.get_ticks_msec()<deadline:
					await create_timer(.1).timeout;game._process(.1)
				if g.history.size()==previous_hand:print("CHESS_MODEL_NO_MOVE stop without replay");break
			game._process(.1);p.refresh()
		print("SCENARIO chess ",JSON.stringify(w.gomoku.sessions));await picture("model-chess")
	elif key=="@disconnect":
		game.gomoku_panel.card.hide();game.chess_choice.hide();game.participant_picker.hide();game.chat.hide();game.resident_connections.open("codex");game.resident_connections.tabs.current_tab=0;game.resident_connections._show_section()
		game.resident_connections.details_scroll.ensure_control_visible(game.controller_picker);await process_frame;await process_frame
		await UI.click(self,game.controller_picker);await choose(game.controller_picker,1)
		print("DISCONNECT_PICKER ",game.controller_picker.selected)
		game.resident_connections.close_panel()
		await UI.click(self,game.dialogue_button)
		if game.command_page.commands_mode:await UI.click(self,game.command_page.tabs.get_child(1))
		game._select_chat("codex");await text_input("帮我砍一棵树",true);await step_time(150)
		print("SCENARIO disconnect ",w.director.model_controlled("codex")," ",JSON.stringify(w.work.events.slice(-3)))
	elif key=="@timeout":
		game.gomoku_panel.card.hide();game.chess_choice.hide();game.participant_picker.hide()
		if not game.chat.visible:await UI.click(self,game.dialogue_button)
		if game.command_page.commands_mode:await UI.click(self,game.command_page.tabs.get_child(1))
		game._select_chat("codex");await text_input("帮我砍一棵树",true)
		await create_timer(1.0).timeout;game._process(.1)
		var own_pid:int=game.links.codex._pid
		if own_pid>0:OS.execute("/bin/kill",["-STOP",str(own_pid)])
		var until:int=Time.get_ticks_msec()+45000
		while Time.get_ticks_msec()<until:
			await create_timer(.2).timeout;game._process(.2)
		if own_pid>0:OS.execute("/bin/kill",["-CONT",str(own_pid)])
		await step_time(180)
		print("SCENARIO timeout ",JSON.stringify(captured)," events ",JSON.stringify(w.work.events.slice(-4)))
	elif key=="@needs":
		game.chat.hide();game.chat_input.release_focus()
		var delivered:Dictionary={}
		for tick in 6000:
			game._process(.1);game.view._process(.1)
			var speech:Dictionary=game.view.speech_by_actor.get("codex",{})
			if speech.get("context")=="need_fish":
				game.view.center=w.point(w.actors.codex);game.view.follow_player=false;game.view.queue_redraw();await process_frame
				for entry in game.view.speech_layout():
					if entry.actor_id!="codex":continue
					delivered=speech.duplicate(true)
					var at:Vector2=entry.box.get_center()
					for down in [true,false]:
						var e:=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.position=at;e.global_position=at;e.pressed=down;root.push_input(e,true);await process_frame
					break
			if not delivered.is_empty():break
			if tick%20==0:await process_frame
		await step_time(150)
		print("SCENARIO needs ",JSON.stringify(delivered)," heldfish ",JSON.stringify(w.fishing.held("codex"))," jobs ",JSON.stringify(w.work.events.slice(-3)))
