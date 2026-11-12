extends "res://tests/test_simple_connection_input.gd"
var game:Node
func run()->void:
	var dir:String=OS.get_environment("HABITAT_DATA_DIR");assert(dir.contains("youqi-"))
	OS.set_environment("HABITAT_OPENING","standard")
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	var pool:Node=preload("res://scripts/connection_session_pool.gd").obtain(self,dir);pool.factory=func(_id):return Stub.new()
	game=load("res://scenes/main_v3.tscn").instantiate();game.dialogue_adapter_factory=func(_id,_scope):return Stub.new()
	root.add_child(game);game.save_enabled=false;game.set_process(false);game.memory_life.set_process(false)
	await frames()
	check(not pool.management("codex") and not game.world.director.model_controlled("codex") and (not pool.links.has("codex") or (pool.links.codex is Stub and pool.links.codex.starts==0 and pool.links.codex.chats==0)),"fresh local preallocated stub has no handshake, chat or management")
	for dimensions in [Vector2i(960,640),Vector2i(1280,800)]:
		root.size=dimensions;await frames()
		game.island_hud.layout_primary_actions();await frames()
		var rect:Rect2=game.watch_ui.bar.get_global_rect()
		var error:float=absf(rect.get_center().x-dimensions.x/2.0)/dimensions.x
		print("CENTER ",dimensions," ",error," ",rect)
		check(error<=.02,"bottom center within two percent")
		await shot("center-"+str(dimensions.x))
	check(await UI.click(self,game.watch_ui.toggle),"click 1 always enabled opens setup")
	await frames();await shot("setup")
	check(is_instance_valid(game.steward.setup_card) and game.steward.setup_card.visible,"requirements card visible")
	check(await UI.click(self,game.steward.setup_button),"click 2 connects and appoints")
	await frames();game.steward.finish_setup();await frames()
	check(game.steward.active and not game.steward.ai_manager("codex"),"host appoints local director without model handshake or authority")
	game.world.director.set_controller("codex","model");game._ensure_link("codex")
	pool.states["codex"]={"state":"ready"};game.connection_ui_states["codex:direct"]="ready"
	game.connection_history.set_value("connected","codex",1)
	await shot("appointed")
	game.steward.stop();pool.set_management("codex",false)
	game.group_chat=false;game.chat_actor="codex";await enter_message("所有人去砍树");await frames()
	check(game.steward.setup_card.visible and not game.world.work.jobs.has("codex"),"everyone without authority offers setup without own-only work")
	check(await UI.click(self,game.steward.setup_button),"grant authority from conversation")
	game.steward.finish_setup();pool.set_management("codex",true);game.steward.reasons.clear();await frames()
	game.steward.stop() # Explicit host takeover ends the director before manual delegated work.
	var result:Dictionary=game.steward.assign("codex",[{"action":"chop","actor_ids":["all"]}],"direct:codex")
	check(result.ok and result.accepted.size()==4,"original executor accepts four real recipients")
	game.steward.reasons.clear()
	var prior:Dictionary={};var distances:Dictionary={}
	for id in pool.IDS:prior[id]=game.world.point(game.world.actors[id]);distances[id]=0.0
	for tick in range(2400):
		game.world.advance(.1);game.local_host_commands._process(.1);game.intentions.advance(.1)
		for id in pool.IDS:
			var at:Vector2=game.world.point(game.world.actors[id]);distances[id]+=at.distance_to(prior[id]);prior[id]=at
		if tick%100==0:await process_frame
	print("DISTANCES ",distances)
	for id in pool.IDS:check(distances[id]>0,"real movement "+id)
	game.world.standard.tutorial_step=6;game.journey._process(.1);await frames();await shot("suggestion")
	check(not game.journey.suggestion_key().is_empty(),"completed tutorial derives real suggestion")
	game.steward.stop();pool.set_management("codex",false);pool.settings.set_value("steward_prompt","codex",false)
	game.steward.offer_connection();await frames()
	var offers:Array=game.get_children().filter(func(n):return n is ConfirmationDialog and n.visible and n.dialog_text==preload("res://scripts/localization.gd").text("repair.offer"))
	check(offers.size()==1,"connected resident offers stewardship once")
	if offers.size()==1:check(await UI.click(self,offers[0].get_ok_button()),"real yes click accepts stewardship")
	check(game.steward.active and pool.management("codex"),"offer acceptance grants authority and starts")
	print("REPAIR_INPUT ",checks," failed=",failed);game.queue_free();await frames();quit(1 if failed else 0)

func enter_message(message:String)->void:
	preload("res://tests/dialogue_ui_fixture.gd").open(game,"codex");await frames()
	game.chat_input.grab_focus()
	for character in message:
		for down in [true,false]:
			var key:=InputEventKey.new();key.unicode=character.unicode_at(0);key.pressed=down;root.push_input(key,true);await process_frame
	check(game.chat_input.text==message,"real keyboard message entered")
	await UI.click(self,game.chat_send_button)
	await frames()
