extends "res://tests/capture_chess_tricolumn.gd"
func run()->void:
	var directory:String=OS.get_environment("HABITAT_DATA_DIR");var output:String=OS.get_environment("HABITAT_PLAYTEST_CAPTURE")
	if not directory.contains("youqi-") or output.is_empty():quit(1);return
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	var fixture:RefCounted=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json")
	fixture.residents.provision(fixture);fixture.library=preload("res://scripts/character_library.gd").new();fixture.library.configure(directory)
	check(preload("res://scripts/world_opening.gd").apply(fixture,fixture.library,"showcase").ok,"showcase fixture")
	fixture.intelligence.activate_presets();fixture.hunger.start()
	var point:Vector2=fixture.point(fixture.leisure.sites["play.gomoku"]);fixture.actors.human.position=[point.x,point.y+2]
	fixture.actors["companion-2"].appearance_id="ai-deepseek";fixture.actors["companion-2"]["custom_appearance"]=true
	check(preload("res://scripts/save_store.gd").save_world(fixture,directory),"saved voice fixture")
	OS.set_environment("HABITAT_OPENING","showcase")
	game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game)
	for frame in range(20):await process_frame
	game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.island_hud.set_process(false);game.chat.hide()
	game.jieqi_panel.bubble_delivered.connect(func(event):events.append(event.duplicate(true)))
	await bottom();await select_jieqi("standard","companion-2")
	for hand in range(8):
		if game.world.jieqi.phase!="playing":break
		await jieqi_human_move()
		for tick in range(100):
			step(.1)
			if game.world.jieqi.game.turn==1:break
		for tick in range(42):step(.1)
		await process_frame
	var voices:Array=game.game_audio.trace.filter(func(row):return row.action=="scheduled" and str(row.get("key","")).begins_with("chess-bubble:"))
	check(voices.size()>=2,"actual board bubbles scheduled at least two voice events")
	for index in range(1,voices.size()):check(float(voices[index].time)-float(voices[index-1].time)>=7.999,"same actor voices at least eight seconds apart")
	for event in events:check(event.world_gate_before==event.world_gate_after and event.personal_gate_before==event.personal_gate_after,"actual bubble left world speech gates intact")
	var file:=FileAccess.open(output.path_join("voice-proof.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"events":events,"voices":voices,"failures":failures},"\t"));file.close()
	print("Actual board voice proof: ",voices.size()," voices, failures=",failures)
	quit(1 if failures else 0)
