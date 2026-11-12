extends "res://tests/test_intelligence_core_input.gd"
func run()->void:
	OS.set_environment("HABITAT_OPENING","standard")
	root.size=Vector2i(1280,800)
	game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false);game.memory_life.set_process(false);game.local_host_commands.set_process(false)
	await process_frame;await process_frame
	var w:RefCounted=game.world
	w.director.set_controller("codex","model");game.connection_ui_states["codex:direct"]="ready";game.connection_history.set_value("connected","codex",1);game.steward.pool.set_management("codex",true)
	var prior_level:String=game.resident_connections.preferences.preference("codex").level
	check(game.steward.start("codex"),"new standard starts steward")
	check(game.resident_connections.preferences.preference("codex").level==prior_level,"steward does not silently upgrade to Ultra")
	if game.links.has("codex"):game.links.codex.queue_free();game.links.erase("codex")
	DirAccess.make_dir_recursive_absolute("/tmp/youqi-long-host-final")
	game.memory_books.atomic("/tmp/youqi-long-host-final/initial.json",game.steward.island_checklist())
	game.steward.reasons.clear();game.steward.preset()
	var clicked:=false
	for i in range(9200):
		game.local_host_commands._process(.5)
		game._process(.5)
		if is_instance_valid(game.steward.body_director.invitation_card) and game.steward.body_director.invitation_card.visible and not clicked:
			print("BEFORE_APPROVAL ",game.steward.queue," PLANS ",game.intentions.plans," FAILURE ",game.intentions.last_failure)
			var yes:Button=UI.descendants(game.steward.body_director.invitation_card).filter(func(node):return node is Button and node.text in ["好","Okay"])[0]
			check(await UI.click(self,yes),"real viewport mouse approves")
			clicked=true
			check(game.steward.timeline.back().status=="running","approval dispatches without next game tick")
		if i%200==0:await process_frame
		if w.days.day()>=4:break
	check(w.days.day()>=4,"three real-advance days completed")
	check(clicked,"opening reaches invitation")
	check(w.standard.ready("home.barbecue"),"real camp built")
	DirAccess.make_dir_recursive_absolute("/tmp/youqi-long-host-final")
	game.memory_books.atomic("/tmp/youqi-long-host-final/long-host.json",{"day":w.days.day(),"events":game.steward.events,"work":w.work.events,"history":game.intentions.history,"watchdogs":game.steward.watchdog_count,"timeline":game.steward.timeline,"meals":w.hunger.statistics.meals,"checklist":game.steward.island_checklist()})
	print("FINAL_TIMELINE ",game.steward.timeline," FAILURE ",game.intentions.last_failure," MEALS ",w.hunger.statistics.meals," CHECKLIST ",game.steward.island_checklist())
	check(w.hunger.statistics.meals>=4,"four companions actually ate")
	game.queue_free();await process_frame
	print("LONG_HOST ",checks," failed=",failed);quit(1 if failed else 0)
