extends "res://tests/test_resort_holiday_input.gd"
func run()->void:
	await fresh()
	await text_input("大家跟我来");game.chat.hide()
	await click_point(Vector2(81,178));await advance_until_idle()
	await click_point(Vector2(81,199));await advance_until_idle()
	for i in 200:game._process(.1)
	await text_input("小蓝去砍树")
	var w:RefCounted=game.world
	check(not w.work.jobs.has("companion-2"),"vacation rejects labor without creating a job")
	game.chat.hide()
	var delivered:=false
	for i in 1800:
		game._process(.1);game.local_host_commands._process(.1)
		if i%50==0:await process_frame
		if w.director.events.any(func(e):return e.actor_id=="companion-2" and e.text==w.resort.line()):delivered=true;break
	check(delivered,"blue delivers actual vacation refusal through original speech gates")
	await capture_scene("vacation-refusal-spoken",w.point(w.actors["companion-2"]),1)
	await UI.click(self,game.dialogue_button);await process_frame
	var page:Node=game.command_page
	page.category=0;page.rebuild()
	check(page.entries.filter(func(row):return row.has("resort_kind")).any(func(row):return row.zh==page.grid.get_child(0).text),"holiday commands appear first on island")
	page.category=2;page.rebuild()
	check(page.grid.get_children().all(func(b):return b.disabled),"labor command buttons disabled on island")
	await picture("vacation-work-disabled")
	print("RESORT_REFUSAL_INPUT ",checks," failed=",failed)
	game.queue_free();await process_frame;quit(1 if failed else 0)
