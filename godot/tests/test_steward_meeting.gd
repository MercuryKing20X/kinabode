extends "res://tests/test_intelligence_core_input.gd"
func run()->void:
	OS.set_environment("HABITAT_OPENING","showcase")
	game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false);game.memory_life.set_process(false)
	await process_frame;await process_frame
	var w:RefCounted=game.world
	w.director.set_controller("codex","model")
	check(game.intentions.submit("codex",[{"action":"roast","item_id":"single:mushroom","target_id":"home.barbecue"}],"direct:codex").ok,"host meal accepted")
	var fire:RefCounted=w.barbecues["home.barbecue"].fireside
	var seated:Dictionary={};var departed:Dictionary={};var origins:Dictionary={};var roast_at:=-1.0
	for who in w.actors:origins[who]=w.point(w.actors[who])
	for i in range(1500):
		game._process(.1)
		for who in w.actors:
			if who!="human" and not departed.has(who) and origins[who]!=w.point(w.actors[who]):departed[who]={"at":w.forest.clock,"running":w.is_running(who)}
		if i==3:
			game.view.follow_player=false;game.view.center=w.point(w.actors.codex);await picture("gather-running")
		for who in fire.jobs:
			if w.work.jobs.get(who,{}).get("phase","")=="fire_sit" and not seated.has(who):seated[who]=w.forest.clock
		if not fire.state.get("current",{}).is_empty():roast_at=w.forest.clock;break
		if i%100==0:await process_frame
	print("MEETING_HISTORY ",game.intentions.history," FAILURE ",game.intentions.last_failure)
	print("MEETING_DEPARTED ",departed)
	print("MEETING_SEATED ",seated," ROAST_AT ",roast_at," INVITED ",fire.state.get("invited",[]))
	check(seated.size()==4,"all four guests seated before roast")
	check(roast_at>0 and seated.values().all(func(at):return at<=roast_at),"roast after last seat")
	game.queue_free();await process_frame
	print("MEETING_CHECKS ",checks," failed=",failed);quit(1 if failed else 0)
