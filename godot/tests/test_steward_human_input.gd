extends "res://tests/test_intent_input.gd"
var samples:Array=[]
func run()->void:
	OS.set_environment("HABITAT_OPENING","showcase")
	root.size=Vector2i(1280,800)
	game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false);game.memory_life.set_process(false)
	await process_frame;await process_frame
	var w:RefCounted=game.world
	for id in game.steward.Pool.IDS:w.director.set_controller(id,"local");w.activities.release_follow(id)
	w.director.set_controller("codex","model")
	game.dialogue_adapter_factory=func(_id,_scope):return IntentFake.new()
	game._ensure_link("codex");game.connection_ui_states["codex:direct"]="ready";game.connection_history.set_value("connected","codex",1);game.steward.pool.set_management("codex",true)
	game.chat.hide();game.chat_input.release_focus()
	check(game.steward.start("codex"),"manager starts")
	game.steward.reasons.clear();game.steward.refresh()
	await process_frame;await process_frame
	await UI.click(self,game.steward.level_button);await process_frame
	check(game.steward.level_button.get_popup().visible and not game.steward.folded,"five-level popup keeps board expanded")
	await picture("steward-level-menu")
	game.steward.level_button.get_popup().hide()
	check(await UI.click(self,game.steward.fold_button),"arrow real input folds")
	check(game.steward.folded,"folded")
	await UI.click(self,game.steward.fold_button)
	check(not game.steward.folded,"arrow unfolds")
	game.steward.active=false
	game._select_chat("codex");game.command_page.selected=["codex"]
	await text_input("请烧烤蘑菇，叫大家来吃")
	var connection:Node=game.links.codex
	if connection.is_busy():
		connection._accept_event({"kind":"intent_result","turn_key":connection.turn_key,"speech":"一起吃吧。","intents":[{"action":"roast","item_id":"single:mushroom"},{"action":"invite"}],"memory":[]})
		connection._accept_event({"kind":"state","turn_key":connection.turn_key,"state":"ready","turnComplete":true})
	game.chat.hide();game.chat_input.release_focus()
	var fire:RefCounted
	var original:Dictionary={};var changed:=0
	for i in range(1400):
		if connection.is_busy():
			connection._accept_event({"kind":"intent_result","turn_key":connection.turn_key,"speech":"好。","intents":[],"memory":[]})
			connection._accept_event({"kind":"state","turn_key":connection.turn_key,"state":"ready","turnComplete":true})
		game._process(.1)
		for life in w.barbecues.values():
			if life.fireside.state.get("roast_by")=="codex" and not life.fireside.state.get("current",{}).is_empty():fire=life.fireside
		if fire!=null:
			for id in ["codex","npc.mira"]:
				if fire.jobs.has(id):
					if original.has(id) and original[id]!=fire.jobs[id]:changed+=1
					original[id]=fire.jobs[id]
			samples.append({"at":w.forest.clock,"jobs":fire.jobs.duplicate(),"seats":fire.seats.duplicate(),"claims":w.work.claims.duplicate(),"activity":[w.actors.codex.activity,w.actors["npc.mira"].activity],"eaters":fire.state.current.eaters.duplicate()})
			if "codex" in fire.state.current.eaters and "npc.mira" in fire.state.current.eaters:break
		if i%100==0:await process_frame
	check(fire!=null,"real input commits meal")
	if fire!=null:
		check("codex" in fire.state.current.eaters,"cook really eats")
		check("npc.mira" in fire.state.current.eaters,"orange really eats")
		check(changed==0,"zero replacement seat jobs before eating")
		var locked:Dictionary=game.steward.assign("codex",[{"action":"sit","actor_ids":["codex","npc.mira"]}],"direct:codex")
		check(not locked.ok,"steward cannot displace diners")
		await picture("steward-real-meal")
	var file:=FileAccess.open(OS.get_environment("HABITAT_DATA_DIR").path_join("human-results.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failed":failed,"history":game.intentions.history,"failures":game.intentions.last_failure,"work_events":w.work.events,"busy":connection.is_busy(),"held":w.director.routines.codex.held,"held_activity":w.activities.held,"hunger":w.hunger.states,"fire":fire.state if fire!=null else {},"timeline":samples},"\t"));file.close()
	game.queue_free();await process_frame;print("STEWARD_HUMAN ",checks," failed=",failed);quit(1 if failed else 0)
