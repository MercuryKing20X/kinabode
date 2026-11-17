extends "res://tests/test_resort_holiday_input.gd"
# DIRECTION 2026-11-11：“五座别墅只留一座”“泳池、躺椅、吊床等拿掉”“旧‘度假状态’取消”。
func run()->void:
	await fresh()
	await UI.click(self,game.island_hud.collapse_residents)
	await text_input("大家跟我来");game.chat.hide()
	await click_point(Vector2(81,178));await advance_until_idle()
	await click_point(Vector2(93,208));await advance_until_idle()
	check(game.world.point(game.world.actors.human).distance_to(Vector2(93,208))<1,"actual World reaches shared front courtyard")
	# DIRECTION 2026-11-11: one greenhouse replaces the villas; the pool and vacation state are removed.
	check(game.world.resort.config.villas.size()==1,"exactly one Flower Isle greenhouse")
	check(game.world.resort.activities.values().all(func(a):return a.kind!="pool"),"retired pool is absent")
	await capture_scene("flower-isle-one-greenhouse",Vector2(77,207),.23)
	var stock_before:Dictionary=game.world.storage.saved()
	var refused:Dictionary=game.world.resort.begin("resort.human.pool",game.world.actors.keys())
	check(not refused.ok and refused.get("error")=="vacation_retired","old pool cannot start a vacation task")
	check(game.world.actors.keys().all(func(id):return not game.world.resort.vacation(id) and game.world.resort.using(id).is_empty()),"all five actors remain outside retired vacation activities")
	check(game.world.actors.values().all(func(actor):return game.world.walkable(actor.region_id,game.world.point(actor))),"all actual arrivals remain walkable")
	check(game.world.storage.saved()==stock_before,"retired leisure creates or consumes no materials")
	print("TWO_VILLA_INPUT ",checks," failed=",failed)
	game.queue_free();await process_frame;quit(1 if failed else 0)
