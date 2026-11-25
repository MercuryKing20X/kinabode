extends "res://tests/test_dialogue_bar_input.gd"
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-"))
	OS.set_environment("HABITAT_OPENING","showcase")
	var game:Node=load("res://scenes/main_v3.tscn").instantiate()
	game.dialogue_adapter_factory=func(_id,_scope):return preload("res://tests/test_intent_input.gd").IntentFake.new()
	root.add_child(game);game.save_enabled=false;game.set_process(false);await frames()
	var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/companions/local-dialogue.json"))
	var total:=0
	for id in source.residents:
		for pair in [["thought",30],["sense",25],["host",25]]:
			check(source.residents[id][pair[0]].size()>=int(pair[1]),"content minimum "+id+" "+pair[0]);total+=source.residents[id][pair[0]].size()
		for rows in source.residents[id].values():
			check(rows.all(func(row):return not row.zh.is_empty() and not row.en.is_empty()),"bilingual "+id)
	var combinations:Dictionary={}
	for group in source.pairs:
		var key:String=",".join(group.actors);combinations[key]=int(combinations.get(key,0))+1;total+=group.lines.size()
	check(combinations.size()==6 and combinations.values().all(func(n):return n>=10),"six pairs ten groups")
	check(total>=400 and total<=600,"400-600 dialogue lines")
	# Real viewport key event. No command, no forced routes, no editing player data.
	var key:=InputEventKey.new();key.keycode=KEY_SPACE;key.pressed=true;root.push_input(key,true);await frames()
	key=InputEventKey.new();key.keycode=KEY_SPACE;key.pressed=false;root.push_input(key,true)
	# Reach a real natural coast through viewport mouse input, then observe without input.
	var arrived:=false
	for shore in game.world.fishing.nearby_shores("human",32):
		var at:=Vector2(shore.position[0],shore.position[1]);game.view.center=at;game.view.follow_player=false
		if not game.view.hit(game.view.screen(at)).is_empty():continue
		for down in [true,false]:
			var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=down;click.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0;click.position=game.view.screen(at);click.global_position=click.position;root.push_input(click,true)
		for tick in range(900):game._process(.1);game.view._process(.1)
		await frames(2)
		if not game.world.fishing.shore("human").is_empty():arrived=true;break
	check(arrived,"real mouse World route to natural sea before observation")
	var dialogue:RefCounted=game.world.director.local_dialogue
	var observation_started:float=game.world.director.time
	var pair_windows:=0;var snapshots:Array=[]
	var seen:Dictionary={};var counts:Dictionary={"thought":0,"sense":0,"host":0,"dialogue":0,"dialogue_group":0};var processed:=0;var duplicate:=0;var thought_screenshot:=false
	for tick in range(6000):
		game._process(.1);game.view._process(.1)
		if tick%100==0:
			var actors:Dictionary={}
			for id in source.residents:
				actors[id]={"position":game.world.actors[id].position.duplicate(),"idle":dialogue.idle(id),"route":game.world._routes.has(id),"activity":game.world.actors[id].activity,"state":game.world.director.state(id).effective,"speech_due":game.world.director.routines[id].next_speech,"time":game.world.director.routines[id].time,"owns_local_route":game.world.director.routines[id].owns_route,"hunger_quiet_until":game.world.hunger.quiet_until.get(id,0),"visual_quiet_until":game.world.director.routines[id].visual_quiet_until}
			snapshots.append({"at":game.world.director.time,"actors":actors,"pending":dialogue.pending.duplicate(true),"pair_served":dialogue.pair_served.duplicate(),"solo_served":dialogue.solo_served.duplicate()})
		for group in source.pairs:
			if dialogue.pair_allowed(group.actors[0],group.actors[1]):pair_windows+=1;break
		for row in dialogue.delivered:
			if float(row.at)<=observation_started:continue
			var serial:String=str(row.at)+":"+row.id
			if seen.has("event:"+serial):continue
			seen["event:"+serial]=true
			counts[row.kind]=int(counts.get(row.kind,0))+1
			if row.kind=="dialogue_group":continue
			var identity:String=str(row.day)+":"+row.actor_id+":"+row.text
			if seen.has(identity):duplicate+=1
			seen[identity]=true;processed+=1
		if not thought_screenshot and not dialogue.thoughts.is_empty() and tick%10==0:
			game.view.queue_redraw();await frames(2)
			if not game.view.thought_rendered.is_empty():await capture("thought-clouds");thought_screenshot=true
		if tick%1000==0:await frames(2)
	check(thought_screenshot,"real viewport drew at least one thought cloud")
	check(duplicate==0,"zero daily repeated deliveries")
	check(counts.thought>0,"natural thoughts in ten minutes")
	check(counts.dialogue_group>0,"natural completed idle paired exchange")
	check(counts.sense>0,"natural seashore reflection")
	check(counts.host>0,"natural host-directed speech")
	var fresh_observer:RefCounted=preload("res://scripts/local_dialogue.gd").new(game.world)
	var retained:Array=dialogue.delivered.filter(func(e):return e.kind!="dialogue_group" and e.day==game.world.days.day())
	check(not retained.is_empty(),"natural delivered receipts available")
	if not retained.is_empty():
		var proof:Dictionary=retained.back();var row:Dictionary={}
		for rows in source.residents[proof.actor_id].values():
			for option in rows:
				if option.id==proof.id:row=option
		for group in source.pairs:
			for option in group.lines:
				if option.id==proof.id:row=option
		check(not row.is_empty() and not fresh_observer.unused(proof.actor_id,row),"reload preserves actual daily no-repeat receipt")
	# Disable/stop/held/task barriers reject even a previously valid pair.
	var a:String="codex";var b:String="companion-2"
	game.world.director.set_held(a,true);check(not dialogue.pair_allowed(a,b),"held blocks pair");game.world.director.set_held(a,false)
	game.world.director.command_received(a,"stop");check(not dialogue.idle(a),"stop quiet blocks thought and pair")
	var evidence:String=OS.get_environment("HABITAT_UI_EVIDENCE")
	if not evidence.is_empty():
		var file:=FileAccess.open(evidence.path_join("dialogue-stats.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"seconds":600,"counts":counts,"duplicates":duplicate,"pair_diagnostics":dialogue.pair_diagnostics,"content":total,"pair_windows":pair_windows,"snapshots":snapshots,"observation_started":observation_started,"delivered":dialogue.delivered.filter(func(row):return float(row.at)>observation_started)},"  "));file.close()
	print("LOCAL_DIALOGUE ",checks," failed=",failed," ",counts);game.queue_free();await frames();quit(1 if failed else 0)
