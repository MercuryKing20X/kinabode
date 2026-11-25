extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
var checks:=0
var failed:=false
var prefix:=""
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:call_deferred("run")
func click(button:BaseButton)->bool:
	if button==null:return false
	await process_frame;await process_frame
	var count:Dictionary={"pressed":0};button.pressed.connect(func():count.pressed+=1,CONNECT_ONE_SHOT)
	var viewport:Viewport=button.get_viewport();var at:Vector2=button.get_global_rect().get_center()
	if viewport is Window and viewport.is_embedded():at+=Vector2(viewport.position);viewport=root
	var motion:=InputEventMouseMotion.new();motion.position=at;motion.global_position=at;viewport.push_input(motion,true)
	# Keep one synthetic click together so native window input cannot interleave its halves.
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0;event.position=at;event.global_position=at;viewport.push_input(event,true)
	await process_frame
	if count.pressed!=1:print("Fishing mouse rejected ",button.text," at=",at)
	return count.pressed==1
func click_at(pos:Vector2)->void:
	for down in [true,false]:
		var e:=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;e.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0;e.position=pos;e.global_position=pos;root.push_input(e,true);await process_frame
func capture(name:String)->void:
	var output:=OS.get_environment("HABITAT_PLAYTEST_CAPTURE")
	if output.is_empty():return
	await process_frame;await process_frame;RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(output.path_join(prefix+"-"+name+".png"))
func mouse(at:Vector2)->void:
	await click_at(at)
func advance(game:Node,seconds:float)->void:
	for step in range(ceili(seconds/.1)):
		game._process(.1);game.view._process(.1)
		if not game.world._routes.has("human"):break
	await process_frame
func fishing(game:Node,all_first:bool)->void:
	var w:RefCounted=game.world
	for node in game.get_children():
		if node is Window:node.hide()
	var shores:Array=w.fishing.nearby_shores("human",32)
	check(not shores.is_empty(),"natural shore available")
	if shores.is_empty():return
	var shore:Dictionary=shores[0];var at:=Vector2(shore.position[0],shore.position[1]);game.view.center=at;game.view.follow_player=false
	await mouse(game.view.screen(at));await advance(game,90)
	check(not w.fishing.shore("human").is_empty(),"mouse walks to natural shore")
	var before:Dictionary={}
	for round_index in range(2):
		check(await click(game.actions_button),"actions open fishing")
		check(await UI.tab(self,game.action_dock.action_tabs,2),"native Myself tab for fishing")
		var buttons:Array=UI.descendants(game.action_dock.menu).filter(func(n):return n is Button and n.text=="钓鱼")
		buttons=buttons.filter(func(button):return button.is_visible_in_tree())
		if buttons.is_empty():check(false,"fish action exists");return
		check(await click(buttons[0]),"open fishing invitation")
		var all:bool=all_first or round_index==1
		if all:check(await click(game.action_dock.all_fishers),"all fishing skips previous")
		else:
			var boxes:Array=game.action_dock.choices.get_children().filter(func(n):return n is CheckButton)
			for index in range(mini(2,boxes.size())):check(await click(boxes[index]),"individual fishing selection")
		for id in before:
			var boxes:Array=game.action_dock.choices.get_children().filter(func(n):return n is CheckButton and n.get_meta("actor_id")==id)
			check(boxes.size()==1 and boxes[0].disabled,"fisher disabled on repeat "+id)
		check(await click(game.action_dock.popup.get_ok_button()),"confirm fishing invitation")
		for id in before:check(w.work.jobs.get(id,{}).get("id")==before[id],"repeat preserves exact original fishing job "+id)
		for id in w.work.jobs:
			if id!="human" and w.work.jobs[id].get("intent")=="fish":before[id]=w.work.jobs[id].id
	var record:Dictionary={"count":before.size(),"actors":before.keys(),"feedback":game.action_dock.feedback,"all_first":all_first};print("FISH_INVITE_RESULT ",JSON.stringify(record))
	check(before.size()==4,"four unique invited fishing jobs")
func wardrobe(game:Node)->void:
	var assignments:Dictionary={"codex":"ai-gpt","companion-2":"ai-deepseek","npc.mira":"ai-claude","npc.nora":"ai-glm"}
	if game.island_hud.residents_collapsed:
		check(await UI.click(self,game.island_hud.collapse_residents),"actual mouse expands resident roster for wardrobe")
	for id in assignments:
		game.island_hud.refresh();await process_frame;await process_frame
		check(await click(game.island_hud.appearance_buttons[id]),"wardrobe open "+id)
		var panel:Node=game.island_hud.wardrobe
		var matches:Array=UI.descendants(panel.grid).filter(func(n):return n is Button and n.get_meta("work_id","")==assignments[id])
		check(matches.size()==1,"appearance exists "+id)
		if matches.is_empty():continue
		var target:Button=matches[0];var scroll:ScrollContainer=panel.grid.get_parent()
		for attempt in range(30):
			if scroll.get_global_rect().has_point(target.get_global_rect().get_center()):break
			var at:Vector2=scroll.get_global_rect().get_center()
			for down in [true,false]:
				var event:=InputEventMouseButton.new();event.position=at;event.global_position=at;event.button_index=MOUSE_BUTTON_WHEEL_DOWN;event.pressed=down;root.push_input(event,true);await process_frame
		check(await click(target),"select appearance "+id)
		var confirm:Array=UI.descendants(panel).filter(func(n):return n is Button and n.text=="确定")
		check(confirm.size()==1 and await click(confirm[0]),"confirm wardrobe "+id)
		check(game.world.actors[id].appearance_id==assignments[id],"actual appearance bound "+id)
func run()->void:
	root.gui_embed_subwindows=true
	OS.set_environment("HABITAT_OPENING","legacy");root.size=Vector2i(1280,800)
	var base_dir:String=OS.get_environment("HABITAT_DATA_DIR")
	for station in ["home.barbecue","moon.barbecue"]:
		for all_first in [true,false]:
			OS.set_environment("HABITAT_DATA_DIR",base_dir.path_join(station+str(all_first)))
			DisplayServer.window_set_size(Vector2i(1280,800))
			var game:Node=UI.init_game(self);await process_frame;await process_frame
			await wardrobe(game)
			var w:RefCounted=game.world
			var camp:Dictionary=w.barbecues[station].station
			var destination:=Vector2.INF
			for offset in [Vector2(8,0),Vector2(-8,0),Vector2(0,8),Vector2(0,-8)]:
				var point:Vector2=w.point(camp)+offset;game.view.center=point;game.view.follow_player=false
				if w.walkable("home",point) and game.view.hit(game.view.screen(point)).is_empty() and not w.find_route("human",point).is_empty():destination=point;break
			check(destination.is_finite(),"reachable island coast approach")
			if destination.is_finite():await mouse(game.view.screen(destination));await advance(game,130)
			await fishing(game,all_first)
			game.queue_free();await process_frame;await process_frame
	print("Fishing repeat input: ",checks," checks failed=",failed);quit(1 if failed else 0)
