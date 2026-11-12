extends "res://tests/test_dialogue_bar_input.gd"
func run()->void:
	var logic=preload("res://scripts/playground.gd").new();root.add_child(logic)
	var roster:Array=["codex","companion-2","npc.mira","npc.nora"]
	var seen_pairs:Dictionary={};var seen_slots:Dictionary={};var stable:=true;var valid:=true;var no_repeat:=true
	for seed_value in range(1,41):
		logic.members=roster.duplicate();logic.members.append("human");logic.rope_assignment.clear();logic.rope_rng.seed=seed_value
		var previous:Array=[]
		for round_value in range(30):
			logic.assign_rope_roles()
			var roles:Array=logic.rope_roles();var actual:Array=roles.duplicate();actual.sort();var expected:Array=roster.duplicate();expected.sort()
			valid=valid and roles.size()==4 and actual==expected
			var pair:Array=roles.slice(2,4);pair.sort();no_repeat=no_repeat and (previous.is_empty() or pair!=previous);previous=pair
			seen_pairs[JSON.stringify(pair)]=true
			for i in roles.size():seen_slots[str(roles[i])+":"+str(i)]=true
			var before:int=logic.rope_rng.state
			var copy:Array=logic.rope_roles();copy.clear()
			for read in range(10):stable=stable and logic.rope_roles()==roles
			stable=stable and logic.rope_rng.state==before
	check(valid,"1200 assignments: four unique real residents, no human")
	check(no_repeat,"jumping pair changes every round, including left/right swaps")
	check(stable,"getters cannot change roles or RNG, returned copy isolated")
	check(seen_pairs.size()==6,"all six pair combinations reachable")
	check(seen_slots.size()==16,"every resident can take every slot")
	logic.members=["codex","companion-2","human"];logic.assign_rope_roles();check(logic.rope_roles().is_empty(),"less than four real residents fails closed")
	logic.queue_free();await frames()
	OS.set_environment("HABITAT_OPENING","showcase")
	var game:Node=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false);await frames()
	game.playground.rope_rng.seed=127
	await UI.click(self,game.dialogue_button);await UI.tab(self,game.action_dock.action_tabs,1)
	var entries:Array=UI.descendants(game.watch_ui.menu_column).filter(func(n):return n is Button and n.text==preload("res://scripts/localization.gd").text("play.choose"))
	await UI.reveal(self,entries[0]);await UI.click(self,entries[0])
	var cards:Array=game.get_children().filter(func(n):return n.has_meta("play_selector"))
	var buttons:Array=UI.descendants(cards[0]).filter(func(n):return n.get_meta("play_kind","")=="rope")
	check(await UI.click(self,buttons[0]),"real mouse starts random rope")
	game.chat.hide();game.view.follow_player=false;game.view.center=game.playground.anchor;game.view.zoom=1.1
	var physical_valid:=true;var ready_samples:=0
	var seen_round:=-1
	for tick in range(1201):
		game.world.advance(.1);game.playground.tick(.1)
		if game.playground.kind.is_empty():break
		if not game.playground.rope_ready:continue
		var roles:Array=game.playground.rope_roles()
		var targets:Array=[Vector2(-3.5,0),Vector2(3.5,0),Vector2(-.5,0),Vector2(.5,0)]
		for i in range(4):physical_valid=physical_valid and game.world.point(game.world.actors[roles[i]]).distance_to(game.playground.anchor+targets[i])<=.25
		ready_samples+=1
		if game.playground.rope_round!=seen_round:
			seen_round=game.playground.rope_round;await frames(2);await capture("round-"+str(seen_round))
	check(ready_samples>0 and physical_valid,"every ready round reaches unique assigned World slot")
	check(game.playground.rope_swaps>=2,"multiple real random swaps completed")
	check(game.playground.completed.any(func(e):return e.game=="rope"),"real 120s finish and original completion")
	var history:Array=game.playground.rope_assignments.duplicate(true)
	check(game.playground.rope_roles().is_empty() and not game.playground.rope_ready,"finish clears transient roles")
	check(game.playground.start("rope").ok and game.playground.rope_assignments.size()==1,"new game gets a fresh opening assignment")
	game.playground.stop();check(game.playground.rope_roles().is_empty(),"explicit stop clears assignment")
	var file:=FileAccess.open(OS.get_environment("HABITAT_UI_EVIDENCE").path_join("rotation.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failed":failed,"history":history,"ready_samples":ready_samples,"physical_valid":physical_valid}));file.close()
	game.queue_free();await frames();print("ROTATION ",checks," failed=",failed);quit(1 if failed else 0)
