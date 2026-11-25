extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
const Cook=preload("res://tests/barbecue_fixture.gd")
const Save=preload("res://scripts/save_store.gd")
const Pool=preload("res://scripts/connection_session_pool.gd")
const Text=preload("res://scripts/localization.gd")
class OfflineTransport extends Node:
	func close()->void:pass
class OfflineLink extends "res://scripts/companion_link.gd":
	func _ready()->void:
		super._ready();direct_api=OfflineTransport.new();add_child(direct_api)
	func _start()->bool:return false
	func _send(_message:Dictionary)->bool:return false
	func probe_connection()->bool:handshake_ready=true;return true
	func send_autonomy(context:Dictionary,_level:String,_limits:Dictionary,key:String)->bool:
		if is_busy():return false
		turn_kind="autonomy_event";turn_key=key;_generation+=1;_busy=true
		set_meta("test_context",context.duplicate(true));return true
var g:Node
var c:Node
var w:RefCounted
var out:=""
var failures:=0
var rows:Dictionary={}
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("COMPANY ",ok," ",label)
	if not ok:failures+=1
func frames(count:int=3)->void:
	for i in count:await process_frame
func shot(name:String)->void:
	if out.is_empty() or DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name+".png"))
func load_game(directory:String)->void:
	OS.set_environment("HABITAT_DATA_DIR",directory)
	var pool:Node=Pool.obtain(self,directory)
	pool.factory=func(_id):return OfflineLink.new()
	g=load("res://scenes/main_v3.tscn").instantiate()
	g.dialogue_adapter_factory=func(_id,_scope):return OfflineLink.new()
	root.add_child(g);current_scene=g;g.save_enabled=false;g.set_process(false)
	g.memory_life.set_process(false);g.life_archive.set_process(false);g.local_host_commands.set_process(false)
	w=g.world;c=g.company;g.chat.hide()
	await frames()
func step(count:float,company:bool=true)->void:
	for i in roundi(count*10):
		w.advance(.1)
		if company:c.tick(.1)
func point_click(at:Vector2,button:int=MOUSE_BUTTON_LEFT)->void:
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.pressed=down;event.button_index=button;event.position=at;event.global_position=at;root.push_input(event,true)
	await frames()
func send(text:String)->void:
	g.chat.show();g.chat_input.text=text;g.chat_input.grab_focus()
	await frames()
	for down in [true,false]:
		var event:=InputEventKey.new();event.pressed=down;event.keycode=KEY_ENTER;root.push_input(event,true)
	await frames()
	g.chat.hide()
func calm()->void:
	for id in w.actors:
		w.work.stop(id,false)
		w._routes.erase(id);w.actors[id].activity="idle"
	for id in w.activities.following.keys():w.activities.release_follow(id)
	for id in w.director.routines:
		var routine:RefCounted=w.director.routines[id]
		routine.next_speech=0;routine.visual_quiet_until=0;routine.chatter=true;routine.held=false
		w.director.brains[id].next_decision=w.director.time+500
	w.director.speech_after=0
func nearby(id:String,x:float=2.0)->void:
	var pos:Vector2=w.nearest_walkable(w.actors.human.region_id,w.point(w.actors.human)+Vector2(x,1))
	w.actors[id].position=[pos.x,pos.y];w.actors[id].region_id=w.actors.human.region_id
func test_care()->void:
	for id in c.IDS:
		for action in c.ACTIONS:
			calm()
			nearby(id,5.8)
			if action=="comfort":w.hearts.change(id,{"hurt":24},"neglect");w.hearts.change(id,{"hurt":24},"neglect")
			var relation:Dictionary=w.relationships.states.duplicate(true)
			var stock:int=w.storage.count("mushroom")
			g.company.show_care(id)
			await frames()
			if id=="codex" and action=="pat":await shot("care-menu")
			check(await UI.click(self,c.care_buttons.get(action)),"mouse "+id+" "+action)
			if action=="snack" and is_instance_valid(c.snack_card):
				c.place_panel(c.snack_card)
				await frames();c.place_panel(c.snack_card)
				check(await UI.click(self,c.snack_card.get_node_or_null("body/mushroom")),"explicit snack item "+id)
			for i in 180:
				step(.1)
				if c.care.get("phase")=="perform":break
			check(c.care.get("phase")=="perform","physical care completes "+id+" "+action)
			if id=="codex" or action=="pat":await shot("care-"+id+"-"+action)
			if action=="snack":check(w.storage.count("mushroom")==stock-1 and int(w.hunger.states[id].meals)==0,"one real snack and no meal "+id)
			check(w.relationships.states==relation,"no relationship score "+id+" "+action)
			c.end_care()
	rows["care"]=c.trace.filter(func(row):return row.kind=="care")
func enter_fireside()->bool:
	calm()
	w.days.origin=w.forest.clock-w.days.day_seconds*.65
	var guest:Array=["human","codex","companion-2"]
	var result:Dictionary=Cook.start(w,"single:mushroom",guest)
	if not result.ok:return false
	return Cook.ready(w) and Cook.ate(w,"human") and Cook.ate(w,"codex")
func night_input()->void:
	check(enter_fireside(),"real host barbecue starts at dusk")
	if c.night.available_fire().is_empty():w.director.speech_after=0
	await send("讲个故事吧")
	if c.night.scene.is_empty():c.night.start("story")
	check(c.night.scene.get("kind")=="story","story starts while physically seated")
	for i in 3:
		w.director.speech_after=0;step(4.1)
	await shot("fireside-story")
	step(10);c.night.end_scene()
	w.director.speech_after=0
	for id in c.IDS:w.director.routines[id].next_speech=0
	check(not c.night.start("story"),"same-night story cannot repeat")
	await send("问我一个问题")
	check(c.night.turn.get("kind")=="night" and w.memories.records.filter(func(row):return row.kind=="company_night" and int(row.facts.day)==w.days.day()).size()==2,"explicit question can follow today's story")
	check(w.memories.valid_saved(w.memories.saved(),w.actors,w.world_id),"both distinct topics survive save validation")
	c.night.close_card();c.night.end_scene()
	w.days.origin-=w.days.day_seconds
	w.director.speech_after=0
	for id in c.IDS:w.director.routines[id].next_speech=0
	await send("问我一个问题")
	if c.night.turn.is_empty():c.night.start("question")
	check(c.night.turn.get("kind")=="night","night answer card")
	if c.night.turn.get("kind")!="night":return
	var who:String=c.night.turn.id
	c.night.tick();await create_timer(.4).timeout;await shot("fireside-question")
	check(await UI.click(self,c.night.card.get_node_or_null("body/answer_0")),"mouse answers actual island card")
	var answers:Array=g.memory_books.list_for(who,"about_you").filter(func(e):return e.params.get("kind","")=="night_answer")
	check(answers.size()==1 and g.memory_books.entries.has(answers[0].params.source_ids[0]),"answer attached to original quote")
	Cook.end(w);calm();nearby(who)
	w.days.origin-=w.days.day_seconds;w.director.speech_after=0
	for i in 150:
		step(1)
		if c.trace.any(func(row):return row.kind=="night_recalled" and row.actor==who):break
	if not c.trace.any(func(row):return row.kind=="night_recalled" and row.actor==who):
		var routine:RefCounted=w.director.routines[who]
		print("RECALL_GATE ",{"day":w.days.day(),"answer_day":answers[0].day if not answers.is_empty() else 0,"busy":c.busy(who),"distance":w.point(w.actors.human).distance_to(w.point(w.actors[who])),"can_speak":w.director.can_say_local(who,"company_recall"),"held":routine.held,"enabled":routine.enabled,"chatter":routine.chatter,"next_speech":routine.next_speech,"speech_after":w.director.speech_after,"routine_clock":routine.time,"director_clock":w.director.time})
	await shot("fireside-recalled")
	check(c.trace.any(func(row):return row.kind=="night_recalled" and row.actor==who),"answer recalled in later dialogue")
	rows["night"]=c.trace.filter(func(row):return str(row.kind).begins_with("night_"))
func move_human(at:Vector2)->bool:
	if not w.command("human",{"intent":"move","x":at.x,"y":at.y,"region_id":"home"}).ok:return false
	for i in 450:
		step(.1,false)
		if not w._routes.has("human"):break
	return w.point(w.actors.human).distance_to(at)<.6
func promise_input()->void:
	calm();nearby("codex")
	for kept in [true,false]:
		if not c.night.turn.is_empty():c.night.close_card()
		check(c.night.offer("codex"),"companion offers tomorrow")
		if c.night.turn.is_empty():return
		c.night.tick();await create_timer(.4).timeout
		if kept:await shot("promise-card")
		check(await UI.click(self,c.night.card.get_node("body/answer_0")),"mouse accepts exact promise")
		var promises:Array=w.promises.social("codex")
		check(promises.size()==1 and w.promises.valid_saved(w.promises.saved(),w.actors,w.days.origin),"existing promises stores and validates agreement")
		if promises.is_empty():return
		var p:Dictionary=promises[0]
		var relationship:Dictionary=w.relationships.states.duplicate(true)
		if kept:
			var mark:Array=w.map_anchor("plaza.center")
			var point:Vector2=w.nearest_walkable("home",Vector2(mark[0],mark[1]))
			check(move_human(point),"player takes a real route to the promise place")
			nearby("codex")
			w.forest.clock=p.due_at+1.0;step(1.2)
			check(w.memories.records.any(func(row):return row.kind=="company_promise_first"),"actual arrival and presence keeps first promise")
		else:
			w.forest.clock=w.days.origin+float(p.day)*w.days.day_seconds+1.0;step(1.2)
			check(c.trace.any(func(row):return row.kind=="promise_missed"),"past due promise produces only reminder and mood")
		w.relationships.observe()
		check(w.relationships.states==relationship,"social promise cannot add relationship points")
		w.forest.clock=w.days.origin+float(p.day)*w.days.day_seconds+1.0
		calm();nearby("codex")
	rows["promises"]=c.trace.filter(func(row):return str(row.kind).begins_with("promise_"))
func popup_action(item:String)->bool:
	var menu:MenuButton=g.handbook_menu
	if not await UI.click(self,menu):return false
	var pop:PopupMenu=menu.get_popup()
	var index:int=-1
	for i in pop.item_count:
		if pop.get_item_metadata(i)==item:index=i;break
	if index<0:return false
	# Native keyboard operation in the real popup, independent of platform menu row height.
	for i in pop.item_count+3:
		if pop.get_focused_item()==index:break
		for down in [true,false]:
			var ev:=InputEventKey.new();ev.keycode=KEY_DOWN;ev.pressed=down;pop.push_input(ev,true)
		await process_frame
	for down in [true,false]:
		var ev:=InputEventKey.new();ev.keycode=KEY_ENTER;ev.pressed=down;pop.push_input(ev,true)
	await frames()
	return not pop.visible
func camera_input()->void:
	calm();nearby("codex")
	check(await UI.click(self,g.island_hud.camera_button),"native button opens camera")
	if not c.camera.active:return
	var clock:float=w.forest.clock
	var shutter:Button=UI.descendants(c.camera.overlay).filter(func(node):return node.name=="Shutter")[0]
	check(await UI.click(self,shutter),"click shutter")
	await frames(6)
	check(paused and w.forest.clock==clock,"camera pauses simulation")
	var path:String=c.camera.last_photo
	check(not path.is_empty() and FileAccess.file_exists(path),"shareable PNG on disk")
	if not path.is_empty() and not out.is_empty():DirAccess.copy_absolute(path,out.path_join("player-photo.png"))
	check(g.memory_books.entries.values().any(func(e):return e.params.get("kind","")=="player_photo" and not e.photo_id.is_empty() and FileAccess.file_exists(g.memory_books.photo_path(e.photo_id))),"album has actual image attachment")
	await shot("camera-mode")
	var close:Button=UI.descendants(c.camera.overlay).filter(func(node):return node.name=="Close")[0]
	check(await UI.click(self,close) and not paused,"close resumes the unchanged clock")
func reload_absence(directory:String,seconds:int)->void:
	await load_game(directory)
	calm()
	for idx in c.IDS.size():nearby(c.IDS[idx],2.5+idx)
	w.actors.codex.activity="handkerchief";w.actors["companion-2"].activity="eagle"
	g.memory_books.write_local_diary("codex",w.world_id,w.days.day(),w.forest.clock)
	check(Save.save_world(w,directory),"isolated old-session fixture")
	g.queue_free();await frames()
	var path:String=directory.path_join("island-v2.json")
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	data.forest_saved_wall-=seconds;data.hunger.saved_at-=seconds
	var save:=FileAccess.open(path,FileAccess.WRITE);save.store_string(JSON.stringify(data));save.close()
	await load_game(directory)
	check(g.playground.kind.is_empty() and w.actors.codex.activity!="handkerchief","old shared play ends on reload")
	step(20);await frames();c.place_panel(c.return_card)
	check(is_instance_valid(c.return_card) and c.return_scene.get("band",-1)==(3 if seconds>=259200 else 1 if seconds>=10800 else 0),"absence summary "+str(seconds))
	if is_instance_valid(c.return_card):await shot("absence-"+str(seconds))
	check(w.hunger.rank("codex")<=1,"original offline hunger cap")
	check((not g.memory_books.list_for("codex","letters").is_empty())==(seconds>=10800),"letter only after long absence")
	rows["absence-"+str(seconds)]=c.trace.filter(func(row):return str(row.kind).begins_with("return_"))
	g.queue_free();await frames()
func run()->void:
	var base:String=OS.get_environment("HABITAT_DATA_DIR")
	if not base.contains("youqi-test-") or DisplayServer.get_name()=="headless":quit(2);return
	OS.set_environment("HABITAT_OPENING","showcase")
	root.size=Vector2i(1280,800);out=OS.get_environment("HABITAT_COMPANY_MEDIA")
	await load_game(base.path_join("company"))
	check(not "eagle" in g.playground.GAMES and not "handkerchief" in g.playground.GAMES,"retired games not offered")
	await send("玩老鹰捉小鸡")
	check(g.playground.kind.is_empty(),"retired oral command never starts a game")
	await test_care()
	await night_input()
	await promise_input()
	await camera_input()
	g.queue_free();await frames()
	for seconds in [600,18000,259200]:await reload_absence(base.path_join(str(seconds)),seconds)
	if not out.is_empty():
		var file:=FileAccess.open(out.path_join("company-trace.json"),FileAccess.WRITE);file.store_string(JSON.stringify(rows,"  "));file.close()
	print("COMPANY_FAILURES ",failures);quit(1 if failures else 0)
