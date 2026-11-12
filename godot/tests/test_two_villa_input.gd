extends "res://tests/test_resort_holiday_input.gd"
func run()->void:
	await fresh()
	await UI.click(self,game.island_hud.collapse_residents)
	await text_input("大家跟我来");game.chat.hide()
	await click_point(Vector2(81,178));await advance_until_idle()
	await click_point(Vector2(93,208));await advance_until_idle()
	check(game.world.point(game.world.actors.human).distance_to(Vector2(93,208))<1,"actual World reaches shared front courtyard")
	check(game.world.resort.config.villas.size()==2,"exactly two villas")
	check(game.world.resort.activities.values().filter(func(a):return a.kind=="pool").size()==1,"one shared large pool")
	await capture_scene("two-villas-one-pool",Vector2(77,207),.23)
	var stock_before:Dictionary=game.world.storage.saved()
	await choose_activity("resort.human.pool",false)
	for i in 500:
		game._process(.1)
		if i%50==0:await process_frame
		if game.world.actors.keys().all(func(id):return game.world.resort.using(id)=="pool"):break
	check(game.world.actors.keys().all(func(id):return game.world.resort.using(id)=="pool"),"five real occupants of the shared front pool")
	var points:Array=game.world.actors.values().map(func(actor):return game.world.point(actor))
	for i in points.size():
		for j in range(i+1,points.size()):check(points[i].distance_to(points[j])>=2,"five pool bodies own distinct physical slots")
	check(game.world.storage.saved()==stock_before,"shared leisure consumes no materials")
	await capture_scene("shared-pool-five",Vector2(57,223),.75)
	print("TWO_VILLA_INPUT ",checks," failed=",failed)
	game.queue_free();await process_frame;quit(1 if failed else 0)
