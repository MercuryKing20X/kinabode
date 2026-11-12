extends "res://tests/test_intent_input.gd"
## DIRECTION: “任何一位伙伴都能当本地总管…不需要连接和管事权”.
func run()->void:
	root.size=Vector2i(1280,800)
	OS.set_environment("HABITAT_OPENING",OS.get_environment("HABITAT_ENTRY_OPENING") if not OS.get_environment("HABITAT_ENTRY_OPENING").is_empty() else "standard")
	game=load("res://scenes/main_v3.tscn").instantiate()
	game.dialogue_adapter_factory=func(_id,_scope):return IntentFake.new()
	root.add_child(game);game.save_enabled=false;game.set_process(false);game.memory_life.set_process(false)
	await process_frame;await process_frame
	for pair in [["codex","ai-gpt"],["companion-2","ai-deepseek"],["npc.mira","ai-claude"]]:
		check(game.world.assign_appearance(pair[0],pair[1]),"nondefault appearance "+pair[1])
	for who in game.steward.Pool.IDS:
		game.world.director.set_controller(who,"local")
		game.steward.pool.set_management(who,false)
		check(who in game.steward.candidates(),"local candidate "+who)
	game.chat.hide()
	for i in 10:await process_frame
	await UI.click(self,game.steward.toggle)
	if not is_instance_valid(game.steward.setup_choice):
		check(false,"mouse opens setup");game.queue_free();quit(1);return
	check(game.steward.setup_choice.selected==0,"first manager defaults Snow")
	await UI.click(self,game.steward.setup_button)
	check(game.steward.active and game.steward.local_only,"mouse starts local management")
	for i in 30:game._process(.1)
	check(game.steward.pending.is_empty(),"local steward sends no planning request")
	check(not game.steward.timeline.is_empty(),"local queue exists")
	game.steward.stop()
	check(not game.steward.assign("codex",[{"action":"chop"}],"direct").ok,"inactive local cannot delegate")
	game.queue_free();await process_frame
	print("LOCAL_STEWARD_ENTRY ",checks," failed=",failed);quit(1 if failed else 0)
