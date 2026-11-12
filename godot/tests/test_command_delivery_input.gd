extends "res://tests/test_intelligence_core_input.gd"
func step(seconds:float)->void:
	for i in int(seconds*10):
		game._process(.1);game.local_host_commands._process(.1)
		if i%100==0:await process_frame
		if game.local_host_commands.tracked.is_empty():break
func run()->void:
	await fresh()
	var w:RefCounted=game.world
	await UI.click(self,game.dialogue_button);await process_frame
	var page:Node=game.command_page
	await UI.click(self,page.targets.get_child(0));await picture("targets-all")
	check(page.selected.size()==4 and page.sending.text.contains("小蓝"),"all recipients explicit")
	await UI.click(self,page.targets.get_child(3));await picture("targets-blue")
	check(page.selected==["companion-2"],"avatar single selects blue")
	await UI.click(self,page.targets.get_child(6));await picture("targets-blue-orange")
	check(page.selected==["companion-2","npc.mira"],"checkbox multi selects")
	await text_input("今天天气真好")
	check(game.chat_input.text.is_empty() and not page.tabs.visible,"chat is sent through the same input without switching")
	game.chat_input.clear();page.show_mode(true)
	page.selected=["companion-2"];page.rebuild_targets()
	var histories:Dictionary=game.dialogue.histories.duplicate(true)
	await text_input("去种菜")
	check(w.farms.active("companion-2"),"command input starts real planting")
	check(game.dialogue.histories!=histories and JSON.stringify(game.dialogue.histories).contains("去种菜"),"real command appears in shared message history")
	await picture("plant-started")
	await step(240)
	check(not w.farms.active("companion-2"),"plant work completes")
	check(w.activities.following.has("companion-2"),"plant restores follow")
	if w.point(w.actors["companion-2"]).distance_to(w.point(w.actors.human))>3:
		print("COMMAND_RETURN_DIAGNOSTIC ",JSON.stringify({"clock":w.director.time,"blue":w.actors["companion-2"],"human":w.actors.human,"distance":w.point(w.actors["companion-2"]).distance_to(w.point(w.actors.human)),"tracked":game.local_host_commands.tracked,"route":w._routes.get("companion-2",[]),"follow_target":w.hunger.follow_targets.get("companion-2",{}),"follow_origin":w.hunger.follow_origins.get("companion-2",{}),"order":w.farms.orders.get("companion-2",{}),"delivery":w.deliveries.pending.get("companion-2",{}),"suspended_follow":w.activities.suspended_follow.get("companion-2"),"nearby":game.playground.nearby.get("companion-2",{})}))
	check(w.point(w.actors["companion-2"]).distance_to(w.point(w.actors.human))<=3,"plant returns within three tiles")
	# Advance the crop system itself to prepare genuinely grown produce.
	w.farms.advance(86400)
	await text_input("去收菜")

	check(w.farms.active("companion-2"),"harvest input starts real order")
	await step(200)
	check(not w.farms.active("companion-2") and w.activities.following.has("companion-2"),"harvest completes and follows")
	await picture("harvest-returned")
	# Wood delivery is an independent fresh-world scenario, with original hunger values.
	game.queue_free();await process_frame;await fresh();w=game.world;page=game.command_page
	await text_input("大家砍树")
	check(w.work.jobs.values().filter(func(job):return job.intent=="gather_wood" and job.tree_count==3).size()==4,"all four start three real trees")
	await picture("four-chopping")
	await step(300)
	check(game.local_host_commands.tracked.is_empty(),"all wood orders finish return or report interruption")
	check(w.activities.following.size()==4,"four followers restored after wood")
	TranslationServer.set_locale("en");page.show_mode(true);page.rebuild_targets();page.rebuild();await picture("commands-en")
	game.queue_free();await process_frame
	print("COMMAND_DELIVERY_INPUT ",checks," failed=",failed);quit(1 if failed else 0)
