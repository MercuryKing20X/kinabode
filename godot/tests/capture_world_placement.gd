extends SceneTree

const UI=preload("res://tests/barbecue_ui_fixture.gd")
const Pool=preload("res://scripts/connection_session_pool.gd")
const Words=preload("res://scripts/world_creations.gd")
class Stub extends "res://scripts/companion_link.gd":
	func _start()->bool:return false
	func _send(_payload:Dictionary)->bool:return false

var game:Node
var failures:=0
var mode:=""
var at_frame:=0
var snapshots_taken:=0
func _initialize()->void:run.call_deferred()
func verify(ok:bool,label:String)->bool:
	print("PLACEMENT_CAPTURE ", "PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
	return ok

func start_game(opening:String)->void:
	if not opening.is_empty():set_meta("title_opening",opening)
	elif has_meta("title_opening"):remove_meta("title_opening")
	game=load("res://scenes/main_v3.tscn").instantiate()
	game.dialogue_adapter_factory=func(_id,_scope):return Stub.new()
	root.add_child(game);current_scene=game
	await hold(4)

func hold(count:int)->void:
	for i in count:
		await process_frame
		at_frame+=1
		var duration_frames:=OS.get_environment("PLACEMENT_RELEASE_FRAMES").to_int()
		var output:=OS.get_environment("PLACEMENT_FRAME_DIR")
		if duration_frames>0 and not output.is_empty() and snapshots_taken<6 and at_frame>=roundi(float(duration_frames)*(snapshots_taken+.5)/6):
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_jpg(output.path_join("%s-%02d.jpg"%[OS.get_environment("PLACEMENT_CLIP"),snapshots_taken+1]),.9)
			snapshots_taken+=1

func mouse(p:Vector2,button:int=MOUSE_BUTTON_LEFT)->void:
	var motion:=InputEventMouseMotion.new()
	motion.position=p;motion.global_position=p;root.push_input(motion,true)
	await hold(2)
	for pressed in [true,false]:
		var e:=InputEventMouseButton.new()
		e.position=p;e.global_position=p;e.button_index=button;e.pressed=pressed
		e.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed and button==MOUSE_BUTTON_LEFT else 0
		root.push_input(e,true);await hold(1)

func key(code:Key,frames:int=1)->void:
	for pressed in [true,false]:
		var e:=InputEventKey.new();e.keycode=code;e.physical_keycode=code;e.pressed=pressed
		Input.parse_input_event(e)
		await hold(frames if pressed else 1)

func world()->RefCounted:return game.world
func layer()->RefCounted:return world().flower_creation.creations

func open_palette()->bool:
	if is_instance_valid(game.company.care_card):
		await UI.click(self,game.company.care_card.get_node("body/close"))
	return await UI.click(self,game.island_hud.find_child("WorldPlacement",true,false)) and game.world_placement.visible

func in_view(p:Vector2)->bool:
	var screen:Vector2=game.view.screen(p)
	return Rect2(22,130,root.size.x-350,root.size.y-245).has_point(screen)

func pan_to(p:Vector2)->void:
	var cursor:=Vector2(550,390)
	await mouse(cursor,MOUSE_BUTTON_WHEEL_DOWN)
	var drag:=InputEventMouseButton.new()
	drag.position=cursor;drag.global_position=cursor;drag.button_index=MOUSE_BUTTON_MIDDLE;drag.pressed=true
	root.push_input(drag,true);await hold(1)
	var push:=InputEventMouseMotion.new()
	push.position=cursor;push.global_position=cursor;push.button_mask=MOUSE_BUTTON_MASK_MIDDLE
	push.relative=cursor-game.view.screen(p)
	root.push_input(push,true);await hold(1)
	drag=InputEventMouseButton.new()
	drag.position=cursor;drag.global_position=cursor;drag.button_index=MOUSE_BUTTON_MIDDLE
	root.push_input(drag,true);await hold(1)

func wait_until(test:Callable,frames_count:int)->bool:
	for i in frames_count:
		if test.call():return true
		await hold(1)
	return test.call()

func change_appearance()->bool:
	var hud:Control=game.island_hud
	if not await UI.click(self,hud.appearance_buttons.codex):return false
	var wardrobe:Control=hud.wardrobe
	var matches:Array=UI.descendants(wardrobe.grid).filter(func(n):return n is Button and n.get_meta("work_id","")=="ai-gpt")
	if matches.is_empty():return false
	var option:Button=matches[0]
	var scroll:Control=wardrobe.grid.get_parent()
	for i in 35:
		if scroll.get_global_rect().has_point(option.get_global_rect().get_center()):break
		await mouse(scroll.get_global_rect().get_center(),MOUSE_BUTTON_WHEEL_DOWN)
	if not await UI.click(self,option):return false
	var confirm:Array=UI.descendants(wardrobe).filter(func(n):return n is Button and n.text in ["确定","Confirm"])
	if confirm.is_empty() or not await UI.click(self,confirm[0]):return false
	var close:Array=UI.descendants(wardrobe).filter(func(n):return n is Button and n.text in ["关闭","Close"])
	if wardrobe.visible and not close.is_empty():await UI.click(self,close[0])
	if not hud.residents_collapsed:await UI.click(self,hud.collapse_residents)
	return world().actors.codex.appearance_id=="ai-gpt"

func cell(id:String,item:String,range_limit:int=13,exclude:Vector2=Vector2.INF)->Vector2:
	var w:=world()
	var origin:Vector2=w.point(w.actors[id]).round()
	for radius in range(2,range_limit):
		for y in range(-radius,radius+1):
			for x in range(-radius,radius+1):
				if maxi(absi(x),absi(y))!=radius:continue
				var p:=origin+Vector2(x,y)
				if p==exclude:continue
				if (id=="human" and not in_view(p)) or (mode=="moon" and p.x>-30):continue
				if layer().check(id,"place_piece",{"item":item,"position":[p.x,p.y]}).is_empty():
					if not layer().approach(id,p).is_empty():return p
	return Vector2.INF

func player_piece(item:String,p:Vector2=Vector2.INF)->Vector2:
	if not await UI.click(self,game.world_placement.choices[item]):return Vector2.INF
	if not p.is_finite():p=cell("human",item)
	if not p.is_finite():return Vector2.INF
	await mouse(game.view.screen(p))
	var k:String=world().flower_creation.key("home",p)
	var placed:=await wait_until(func():return layer().pieces.get(k,{}).get("owner")=="human",240)
	await hold(10)
	return p if placed else Vector2.INF

func player_remove(p:Vector2)->bool:
	if not p.is_finite() or not await UI.click(self,game.world_placement.choices.remove_piece):return false
	if not in_view(p):await pan_to(p)
	await mouse(game.view.screen(p))
	var k:String=world().flower_creation.key("home",p)
	return await wait_until(func():return not layer().pieces.has(k),240)

func harvest_wood(quantity:int)->bool:
	var w:=world()
	for attempt in 7:
		if w.storage.count("wood")>=quantity:return true
		var trees:Array=w.objects.values().filter(func(obj):return obj.kind=="tree" and obj.status=="mature" and obj.region_id=="home")
		trees.sort_custom(func(a,b):return w.point(a).distance_squared_to(w.point(w.actors.human))<w.point(b).distance_squared_to(w.point(w.actors.human)))
		var started:=false
		for tree in trees.slice(0,8):
			var point:Vector2=w.point(tree)
			if not in_view(point):await pan_to(point)
			for offset in [Vector2(0,-30),Vector2(0,-55),Vector2(-22,-80),Vector2(22,-80),Vector2(0,-9)]:
				var hit:Vector2=game.view.screen(point)+offset
				if game.view.hit(hit)!=tree.id:continue
				await mouse(hit)
				if w.work.jobs.has("human"):started=true;break
			if started:break
		if not started:
			await mouse(Vector2(440,365),MOUSE_BUTTON_WHEEL_DOWN)
			continue
		await wait_until(func():return not w.work.jobs.has("human"),480)
	await key(KEY_SPACE)
	return w.storage.count("wood")>=quantity

func move_map(p:Vector2)->bool:
	var w:=world()
	if not in_view(p):await pan_to(p)
	var screen:Vector2=game.view.screen(p)
	if not Rect2(20,115,root.size.x-55,root.size.y-228).has_point(screen):return false
	await mouse(screen)
	return await wait_until(func():return w.point(w.actors.human).distance_to(p)<1.0,360)

func cross_moon(landing_only:bool=false)->bool:
	for anchor in ["moon.bridge.east","moon.bridge.west","moon.lookout"]:
		var v:Array=world().map_anchor(anchor)
		var dest:=Vector2(v[0],v[1])
		if landing_only and anchor=="moon.lookout":dest=Vector2(-39,45.5)
		var reached:=false
		for offset in [Vector2.ZERO,Vector2(0,.5),Vector2(0,-.5),Vector2(1,0),Vector2(-1,0),Vector2(0,-2)]:
			var p:Vector2=dest+offset
			if not world().walkable("home",p):continue
			if not in_view(p):await pan_to(p)
			if not game.view.hit(game.view.screen(p)).is_empty():continue
			if await move_map(p):reached=true;break
		print("PLACEMENT_CROSS ",anchor," ",reached," pos=",world().point(world().actors.human))
		if not reached:return false
	return world().point(world().actors.human).x< -35

func command(name:String,args:Dictionary)->Dictionary:
	var request:=HTTPRequest.new();request.timeout=15
	root.add_child(request)
	var url:="http://127.0.0.1:%s/world"%game.world_door.PORT
	var headers:=PackedStringArray(["Content-Type: application/json","Authorization: Bearer "+game.world_door.token])
	if request.request(url,headers,HTTPClient.METHOD_POST,JSON.stringify({"command":name,"arguments":args}))!=OK:
		request.queue_free();return {}
	var reply:Array=await request.request_completed
	request.queue_free()
	var result:Variant=JSON.parse_string(reply[3].get_string_from_utf8())
	return result if result is Dictionary else {}

func client_scene()->void:
	verify(await UI.click(self,game.island_hud.find_child("WorldDoor",true,false)),"mouse opened door panel")
	var buttons:Array=UI.descendants(game.world_door_dialog).filter(func(node):return node is Button)
	if not verify(buttons.size()>1 and await UI.click(self,buttons[1]) and game.world_door.server.is_listening(),"mouse opened listener"):return
	await hold(12)
	await UI.click(self,buttons[0])
	var claimed:=await command("claim",{"resident":"codex","client":"Placement script"})
	if not verify(claimed.has("lease"),"script claimed 小白"):return
	var lease:String=claimed.lease
	var tiles:Array[Vector2]=[]
	for item in ["sign","path","lamp"]:
		var p:=cell("codex",item,25)
		if not verify(p.is_finite(),"script found clear "+item):return
		if not in_view(p):await pan_to(p)
		var placed:=await command("act",{"lease":lease,"steps":[{"action":"place_piece","item":item,"position":[p.x,p.y]}],"reason":"Placement recording"})
		if not verify(placed.get("ok",false),"script action accepted "+item):return
		var k:String=world().flower_creation.key("home",p)
		if not verify(await wait_until(func():return layer().pieces.get(k,{}).get("owner")=="codex",300),"script committed "+item):return
		tiles.append(p)
		await hold(12)
	verify(await open_palette(),"player opened palette for removal")
	if not verify(await player_remove(tiles[0]),"player removed resident piece"):return
	var events:=await command("events",{"lease":lease,"after":0})
	verify(events.get("events",[]).any(func(row):return row.type=="piece_removed" and row.data.actor=="human"),"script got actual removal event")
	if world().point(world().actors.codex).distance_to(world().point(world().actors.human))>7:
		var approach:=await command("act",{"lease":lease,"steps":[{"action":"go_to","target":"human"}],"reason":"Reply in person"})
		verify(approach.get("ok",false) and await wait_until(func():return world().point(world().actors.codex).distance_to(world().point(world().actors.human))<=7,360),"resident walked over to reply")
	await wait_until(func():return world().director.can_say_local("codex","world_door","human"),600)
	var line:=await command("say",{"lease":lease,"target":"human","text":"看到啦，我那块牌子拆下来了。"})
	verify(line.get("ok",false),"script spoke after event "+str(line.get("error","")))

func act_wait(lease:String,step:Dictionary,did_finish:Callable,frames:int=900)->bool:
	var result:=await command("act",{"lease":lease,"steps":[step],"reason":"Round four world recording"})
	if not result.get("ok",false):
		print("WORLD_RECORDING_REJECT ",step.action," ",result.get("error",""))
		return false
	if not await wait_until(did_finish,frames):return false
	for _i in 12:
		var events:=await command("events",{"lease":lease,"after":0})
		for event in events.get("events",[]):
			if event.type=="action_finished" and event.data.id==result.action_id:
				return event.data.status=="completed"
		await hold(30)
	return false

func formal_scene()->void:
	var w:=world()
	verify(await change_appearance(),"actual wardrobe confirmed alternate appearance")
	if not verify(await UI.click(self,game.island_hud.find_child("WorldDoor",true,false)),"opened door panel"):return
	if not verify(await UI.click(self,game.world_door_dialog.toggle) and game.world_door.server.is_listening(),"started local script listener"):return
	await UI.click(self,game.island_hud.find_child("WorldDoor",true,false))
	var claimed:=await command("claim",{"resident":"codex","client":"Round four script"})
	if not verify(claimed.get("ok",false),"script claimed Xiaobai"):return
	var lease:String=claimed.lease
	for _i in 6:
		if w.storage.count("wood")>=29:break
		var before:int=w.storage.count("wood")
		if not verify(await act_wait(lease,{"action":"chop_and_haul","target":""},func():return w.storage.count("wood")>before,2400),"script chopped and stored real wood"):return
		await hold(35)
	if not verify(w.storage.count("wood")>=29,"real stock for camp builds and ground paint"):return
	for id in ["home.barbecue","moon.barbecue"]:
		if not w.standard.ready(id):
			var plan:String=w.standard.site_for(id)
			if not verify(await act_wait(lease,{"action":"build","target":plan},func():return w.standard.ready(id),1600),"built "+id):return
			await hold(8)
	var camp: Dictionary=w.barbecues["home.barbecue"].station
	var former:Vector2=w.point(camp)
	if not in_view(former):await pan_to(former)
	if not verify(await act_wait(lease,{"action":"remove_structure","target":camp.id},func():return not w.standard.ready(camp.id),1600),"script dismantled the old camp"):return
	await hold(8)
	var at:=Vector2.INF
	for r in range(3,17):
		for offset in [Vector2(r,0),Vector2(-r,0),Vector2(0,r),Vector2(0,-r)]:
			var candidate:Vector2=former.round()+offset
			if layer().check("codex","place_piece",{"item":"fence","position":[candidate.x,candidate.y]},true).is_empty() and w.barbecues[camp.id].activity_rules.seat_offsets.all(func(seat):return w.walkable("home",candidate+Vector2(seat[0],seat[1]))):
				at=candidate
				break
		if at.is_finite():break
	if not verify(at.is_finite(),"new camp site found"):return
	if not verify(await act_wait(lease,{"action":"rebuild_camp","target":camp.id,"position":[at.x,at.y]},func():return w.standard.ready(camp.id) and w.point(camp)==at),"script rebuilt the camp at a different location"):return
	for item in ["path","flowerbed"]:
		await hold(8)
		var first:=cell("codex",item,25)
		if not first.is_finite():verify(false,"ground cell for "+item);continue
		var last:=first+Vector2(1,0)
		if not layer().check("codex","place_piece",{"item":item,"position":[last.x,last.y]}).is_empty():last=first+Vector2(-1,0)
		var key:String=w.flower_creation.key("home",last)
		var painted:=await act_wait(lease,{"action":"paint_line","item":item,"position":[first.x,first.y],"end":[last.x,last.y]},func():return layer().pieces.get(key,{}).get("item")==item)
		verify(painted,"script painted "+item)
	var help:=await command("ask_help",{"lease":lease,"resident":"companion-2","steps":[{"action":"chop_and_haul","target":""}]})
	verify(help.get("ok",false) or help.get("error")=="help_declined","script asked Xiao Cheng for help")
	await command("release",{"lease":lease})

func before_live_door()->bool:return true

func run()->void:
	var data:=OS.get_environment("HABITAT_DATA_DIR")
	if not (data.begins_with("/tmp/") or data.begins_with("/var/folders/")):quit(2);return
	mode=OS.get_environment("PLACEMENT_RECORDING")
	root.size=Vector2i(1280,800);root.gui_embed_subwindows=true
	Pool.obtain(self,data).factory=func(_id):return Stub.new()
	var selected_opening:=OS.get_environment("PLACEMENT_OPENING")
	await start_game("" if OS.get_environment("PLACEMENT_READ_EXISTING")=="1" else selected_opening if not selected_opening.is_empty() else "standard" if mode in ["standard","formal"] else "showcase")
	await hold(20)
	if mode=="readback":
		game.save_enabled=false
		var target:=OS.get_environment("PLACEMENT_CLIP")
		verify(world().actors.codex.appearance_id=="ai-gpt","alternate appearance persisted")
		if target in ["A","B"]:
			var owner:="codex" if target=="A" else "human"
			for item in (["sign","fence"] if target=="A" else ["sign","fence","barrel","lamp"]):
				verify(layer().pieces.values().any(func(row):return row.owner==owner and row.item==item and (target!="A" or item!="sign" or row.label=="你好")),"persisted "+item)
		elif target=="C":verify(world().leisure.sites["play.moon.bench.1"].complete,"restored bench persisted")
		game.game_audio.shutdown()
		await create_timer(.15,true,false,true).timeout
		quit(1 if failures else 0)
		return
	if mode=="map":
		var out:=OS.get_environment("PLACEMENT_FRAME_DIR")
		game.view.focus_location(Vector2(42,26))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_jpg(out.path_join(selected_opening+"-home.jpg"),.92)
		await key(KEY_SPACE)
		verify(await cross_moon(selected_opening=="standard"),"walked across the real bridge for map visual")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_jpg(out.path_join(selected_opening+"-moon.jpg"),.92)
		game.game_audio.shutdown()
		await create_timer(.15,true,false,true).timeout
		quit(1 if failures else 0)
		return
	if mode=="live":
		if game.island_change_panel.visible:await UI.click(self,game.island_change_panel.get_ok_button())
		if OS.get_environment("PLACEMENT_READ_EXISTING")=="1":
			for node in UI.descendants(game):
				if node is Button and node.is_visible_in_tree() and node.text in ["收起","Dismiss"]:
					if await UI.click(self,node):break
			await mouse(Vector2(850,680),MOUSE_BUTTON_RIGHT)
			await key(KEY_ESCAPE)
			print("CAPTURE_START_WINDOWS ",UI.descendants(game).filter(func(node):return node is Window and node.visible).map(func(node):return node.title))
			if not OS.get_environment("PLACEMENT_FRAME_DIR").is_empty():
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_jpg(data.path_join("opening-diagnostic.jpg"),.85)
		if not verify(await change_appearance(),"actual wardrobe confirmed alternate appearance"):quit(1);return
		if not await before_live_door():quit(1);return
		if not verify(await UI.click(self,game.island_hud.find_child("WorldDoor",true,false)),"opened door panel"):quit(1);return
		if world().director.model_controlled("codex"):
			var picker:OptionButton=game.world_door_dialog.controls.codex[1]
			await UI.click(self,picker)
			picker.get_popup().set_focused_item(0)
			await key(KEY_ENTER)
			if not verify(not world().director.model_controlled("codex"),"player switched Xiaobai to local in copied save"):quit(1);return
		if game.world_door.server.is_listening():await UI.click(self,game.world_door_dialog.toggle)
		if not verify(await UI.click(self,game.world_door_dialog.toggle) and game.world_door.server.is_listening(),"enabled isolated door"):quit(1);return
		var client:=OS.get_environment("PLACEMENT_CLIENT")
		if client in ["claude","codex","copy"]:
			var clipboard_button:Button=game.world_door_dialog.copies.get_child({"copy":0,"claude":1,"codex":2}[client])
			if not verify(await UI.click(self,clipboard_button),"copied actual panel instructions"):quit(1);return
		var ready:=FileAccess.open(data.path_join("capture-terminal-ready"),FileAccess.WRITE)
		ready.store_string("ready");ready.close()
		if not await wait_until(func():return FileAccess.file_exists(data.path_join("capture-terminal-read")),2400):quit(1);return
		if not verify(await UI.click(self,game.world_door_dialog.copies.get_child(0)),"copied the actual AI instructions"):quit(1);return
		ready=FileAccess.open(data.path_join("capture-prompt-ready"),FileAccess.WRITE)
		ready.store_string("ready");ready.close()
		await UI.click(self,game.island_hud.find_child("WorldDoor",true,false))
		var deadline:=Time.get_ticks_msec()+300000
		var seen_speech:=false
		var seen_guest:=false
		while Time.get_ticks_msec()<deadline:
			await hold(1)
			var on_screen:bool=root.get_visible_rect().has_point(game.view.screen(world().point(world().actors.codex)))
			if on_screen and world().actors.codex.has("world_door_client") and game.view.follow_actor=="codex":seen_guest=true
			if on_screen and game.view.speech_by_actor.get("codex",{}).get("context","")=="world_door":seen_speech=true
			if FileAccess.file_exists(data.path_join("capture-stop")):break
		var author:=OS.get_environment("PLACEMENT_AUTHOR")
		if not author.is_empty():
			verify(game.world_door.knocks.any(func(row):return row.result=="claimed" and row.actor=="codex" and row.client==author),"external claim by "+author)
			for item in (["sign"] if OS.get_environment("PLACEMENT_GREETING_ONLY")=="1" else ["sign","fence"]):
				verify(layer().changes.any(func(row):return row.actor=="codex" and row.controller==author and row.action=="placed" and row.item==item),"authored change: "+item)
		verify(layer().pieces.values().any(func(row):return row.owner=="codex" and row.item=="sign" and row.get("label","")=="你好" and (author.is_empty() or row.get("author","")==author)),"sign committed with requested text and author")
		if OS.get_environment("PLACEMENT_GREETING_ONLY")!="1":
			verify(layer().pieces.values().any(func(row):return row.owner=="codex" and row.item=="fence"),"fence committed")
		verify(seen_speech,"world speech bubble")
		verify(seen_guest,"claimed resident sampled in the tracking viewport")
		verify(not game.world_door.owners.has("codex"),"resident released")
		if OS.get_environment("PLACEMENT_GREETING_ONLY")=="1":
			for row in layer().pieces.values():
				if row.item!="sign" or row.get("author","")!=author or row.label!="你好":continue
				var point:Vector2=world().point(row)
				if not in_view(point):await pan_to(point)
				await hold(20)
				var pointer:=InputEventMouseMotion.new()
				pointer.position=game.view.screen(point);pointer.global_position=pointer.position
				root.push_input(pointer,true)
				await hold(30)
				break
		await hold(20)
		if OS.get_environment("PLACEMENT_READ_EXISTING")=="1" and failures==0 and OS.get_environment("PLACEMENT_GREETING_ONLY")!="1":
			while Time.get_ticks_msec()-game.island_change_panel.last_input<301000:await hold(1)
			await key(KEY_J)
			var away:AcceptDialog=game.island_change_panel
			verify(away.visible,"away changes opened on return input")
			var places:Array=UI.descendants(away.rows).filter(func(node):return node is Button and node.text in ["去看看","Go see"])
			if not places.is_empty():verify(await UI.click(self,places[-1]) and away.inspecting,"Go see focused the recorded change")
			else:verify(false,"away card contains a Go see button")
	elif mode=="formal":
		await formal_scene()
	elif mode=="standard":
		verify(await change_appearance(),"actual wardrobe confirmed alternate appearance")
		verify(await harvest_wood(11),"actual work supplied enough wood")
		await key(KEY_SPACE)
		verify(await open_palette(),"opened palette")
		var placed:Array[Vector2]=[]
		for item in ["path","fence","sign","barrel","lamp"]:
			var p:=await player_piece(item)
			verify(p.is_finite(),"player placed "+item)
			placed.append(p)
		verify(await player_remove(placed[0]),"player removed one")
		var points:Dictionary=layer().key_points()
		var doors:Array=points.keys().filter(func(name):return "门口" in name or " door" in name)
		if not doors.is_empty():
			var p:Vector2=points[doors[0]].round()
			if not in_view(p):
				await key(KEY_ESCAPE)
				await pan_to(p)
				await open_palette()
			await UI.click(self,game.world_placement.choices.fence)
			await mouse(game.view.screen(p))
			verify("堵住" in game.world_placement.notice.text or "block the way" in game.world_placement.notice.text,"visible door refusal")
		else:verify(false,"built door exists")
		if OS.get_environment("PLACEMENT_CLIP")=="B":
			await key(KEY_ESCAPE)
			await key(KEY_SPACE)
			verify(await UI.click(self,game.dialogue_button),"opened player dialogue for a work request")
			game.chat_input.grab_focus()
			for character in ["小","白","帮","我","砍","树"]:
				for down in [true,false]:
					var event:=InputEventKey.new()
					event.unicode=character.unicode_at(0);event.pressed=down
					root.push_input(event,true)
					await hold(1)
			await UI.click(self,game.chat_send_button)
			verify(await wait_until(func():return world().work.jobs.get("codex",{}).get("intent","") in ["chop","gather_wood"],180),"Xiaobai took a real work order")
	elif mode=="restore":
		verify(await change_appearance(),"actual wardrobe confirmed alternate appearance")
		verify(await UI.click(self,game.gathering_button),"opened follow options")
		verify(await UI.click(self,game.follow_ui.all_box),"invited companions to follow")
		await UI.click(self,game.follow_ui.menu.get_ok_button())
		if not verify(await cross_moon(),"mouse crossed bridge"):quit(1);return
		var w:=world()
		await wait_until(func():return w.point(w.actors.codex).distance_to(w.point(w.actors.human))<=10,720)
		var id:="play.moon.bench.1"
		var p:Vector2=w.point(w.leisure.sites[id])
		if not in_view(p):await pan_to(p)
		verify(await open_palette(),"opened placement panel on Crescent")
		await UI.click(self,game.world_placement.choices.remove_structure)
		await mouse(game.view.screen(p))
		if not verify(await wait_until(func():return not w.leisure.sites[id].complete,360),"player dismantled existing Crescent bench"):quit(1);return
		await key(KEY_ESCAPE)
		w.forest.advance(w.days.day_seconds)
		await hold(8)
		verify(game.world_checkpoints.working() or w.gathering.start("codex",{"intent":"gather_wood","tree_count":8}).ok,"work in progress before restore")
		await UI.click(self,game.handbook_menu)
		var menu:PopupMenu=game.handbook_menu.get_popup()
		for i in menu.item_count:
			if menu.get_item_metadata(i)=="world_checkpoints":
				menu.set_focused_item(i)
				await key(KEY_ENTER)
				break
		var panel:AcceptDialog=game.world_checkpoints_panel
		if not verify(panel.visible,"opened Return to yesterday from menu"):quit(1);return
		var list:ItemList=panel.days
		var offset:=Vector2(panel.position) if panel.is_embedded() else Vector2.ZERO
		await mouse(list.global_position+list.get_item_rect(list.item_count-1).get_center()+offset)
		print("CHECKPOINT_CAPTURE rows=",list.item_count," selection=",list.get_selected_items())
		await UI.click(self,panel.get_ok_button())
		var confirm:ConfirmationDialog
		for child in panel.get_children():
			if child is ConfirmationDialog and child.visible:confirm=child
		if not verify(is_instance_valid(confirm) and game.world_checkpoints.working(),"stop work confirmation appeared while work still active"):quit(1);return
		await hold(32)
		await UI.click(self,confirm.get_ok_button())
		verify(not w.work.jobs.has("codex"),"confirmed stop cleared the gathering job")
		print("CHECKPOINT_CAPTURE listener_distances=",w.director.routines.keys().map(func(who):return [who,w.point(w.actors[who]).distance_to(w.point(w.actors.human))]))
		print("CHECKPOINT_CAPTURE result=",panel.error.text)
		verify(await wait_until(func():return w.leisure.sites[id].complete,360),"restored the removed bench")
		verify(await wait_until(func():return w.director.events.any(func(e):return e.context=="world_restored"),1200),"resident spoke of the restoration")
		await hold(96)
	elif mode=="moon":
		verify(await cross_moon(),"mouse crossed bridge")
		verify(await open_palette(),"opened palette on Crescent")
		var placed:Array[Vector2]=[]
		for item in ["fence","lamp","sign"]:
			var p:=await player_piece(item)
			verify(p.is_finite() and p.x< -30,"placed on Crescent "+item)
			if p.is_finite():placed.append(p)
		var previous:Dictionary=layer().pieces.duplicate(true)
		game.queue_free()
		await hold(15)
		await start_game("")
		verify(placed.size()==3 and placed.all(func(p):return layer().pieces.get(world().flower_creation.key("home",p),{}) == JSON.parse_string(JSON.stringify(previous.get(world().flower_creation.key("home",p),{})))),"scene exit saved and new scene restored three Crescent pieces")
	else:
		await client_scene()
	var duration:=OS.get_environment("PLACEMENT_RELEASE_FRAMES").to_int()
	var length:=duration if duration>0 else 1440 if mode=="client" else 2160
	if failures==0 and (mode!="live" or duration>0):await hold(maxi(20,length-at_frame))
	if is_instance_valid(game.game_audio):
		game.game_audio.shutdown()
		await create_timer(.15,true,false,true).timeout
	print("PLACEMENT_CAPTURE_COMPLETE ",mode," failures=",failures," frames=",at_frame)
	quit(1 if failures else 0)
