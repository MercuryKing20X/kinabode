extends "res://tests/test_intelligence_core_input.gd"
## UI/Integration, BLOCKING behavior + ADVISORY screenshots; original World routes.
func click_point(at:Vector2)->void:
	game.view.center=at;game.view.follow_player=false;game.view.queue_redraw();await process_frame;await process_frame
	var p:Vector2=game.view.screen(at)
	var motion:=InputEventMouseMotion.new();motion.position=p;motion.global_position=p;root.push_input(motion,true)
	for down in [true,false]:
		var e:=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0;e.position=p;e.global_position=p;e.pressed=down;root.push_input(e,true);await process_frame
func advance_until_idle(limit:float=180)->void:
	for i in int(limit*10):
		game._process(.1)
		if i%50==0:await process_frame
		if i>20 and not game.world._routes.has("human"):break
func button_named(node:Node,title:String)->Button:
	for item in node.find_children("*","Button",true,false):
		if item.text==title:return item
	return null
func capture_scene(name:String,at:Vector2,z:float=1)->void:
	game.chat.hide();game.view.center=at;game.view.zoom=z;game.view.follow_player=false;game.view.queue_redraw();await picture(name)
func choose_activity(id:String,blue_only:bool)->void:
	var a:Dictionary=game.world.resort.activities[id]
	await click_point(Vector2(a.position[0],a.position[1]))
	var ui:Node=game.get_node("ResortUI")
	check(is_instance_valid(ui.menu) and ui.menu.visible,"native opens activity invitation "+id)
	if not is_instance_valid(ui.menu):return
	if blue_only:
		for actor in ui.checks:
			if ui.checks[actor].button_pressed!=(actor=="companion-2"):await UI.click(self,ui.checks[actor])
	var name:String={"lounge":"躺一会儿","pool":"下水玩","swing":"一起荡秋千","hammock":"一起荡吊床"}[a.kind]
	var b:Button=button_named(ui.menu,name)
	check(b!=null,"activity action exists "+id)
	if b!=null:await UI.click(self,b)
	await advance_until_idle()
	for i in 100:game._process(.1)
func run()->void:
	await fresh()
	await text_input("大家跟我来");game.chat.hide()
	await click_point(Vector2(81,178));await advance_until_idle()
	check(game.world.home_island.here(),"native original bridge traversal arrives on southern island")
	await capture_scene("bridge-arrived",Vector2(81,178))
	# Continue on the original World route into the new connected southern extension.
	await click_point(Vector2(80,310));await advance_until_idle()
	check(game.world.point(game.world.actors.human).distance_to(Vector2(80,310))<1,"native reaches villa extension without teleport")
	for i in 200:game._process(.1)
	for v in game.world.resort.config.villas:
		await capture_scene("villa-"+v.key+"-day",Vector2(v.position[0],v.position[1]),.45)
	await choose_activity("resort.human.lounge",true)
	check(game.world.resort.using("human")=="lounge" and game.world.resort.using("companion-2")=="lounge","human and blue lie down after native invitation and arrival")
	await capture_scene("blue-lounging",Vector2(80,359),1)
	await click_point(Vector2(80,354));await advance_until_idle()
	check(game.world.resort.using("human").is_empty(),"native elsewhere click gets up")
	await text_input("大家跟我来");game.chat.hide()
	await choose_activity("resort.human.pool",false)
	check(game.world.actors.keys().all(func(id):return game.world.resort.using(id)=="pool"),"all five arrive and play in pool")
	await capture_scene("all-pool",Vector2(92,359),1)
	await click_point(Vector2(80,354));await advance_until_idle()
	await text_input("大家跟我来");game.chat.hide()
	await choose_activity("resort.human.hammock",false)
	check(game.world.resort.using("human")=="hammock","native hammock use arrives")
	await capture_scene("hammock",Vector2(68,359),1)
	await click_point(Vector2(80,354));await advance_until_idle()
	await text_input("小蓝去砍树")
	check(game.world.work.jobs.get("companion-2",{}).get("intent")!="gather_wood","vacation command does not start work")
	await picture("vacation-work-refused")
	game.chat.hide()
	for id in ["resort.villa.human","resort.villa.companion-2"]:
		var v:Dictionary=game.world.resort.villa(id)
		await click_point(Vector2(v.door[0],v.door[1]))
		var ui:Node=game.get_node("ResortUI")
		var enter:Button=button_named(ui.menu,"进去坐坐") if is_instance_valid(ui.menu) else null
		check(enter!=null,"villa native door shows enter "+id)
		if enter!=null:await UI.click(self,enter)
		await advance_until_idle()
		check(game.world.actors.human.region_id=="room."+id,"original interior enter arrives "+id)
		game.view.show_region(game.world.actors.human.region_id);game.view.queue_redraw()
		await picture("interior-"+v.key)
		if game.world.actors.human.region_id.begins_with("room."):
			game.world.command("human",{"intent":"exit"});await advance_until_idle();game.view.show_region("home")
	print("RESORT_HOLIDAY_INPUT ",checks," failed=",failed)
	game.queue_free();await process_frame;quit(1 if failed else 0)
