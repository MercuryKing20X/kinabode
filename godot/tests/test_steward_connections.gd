extends "res://tests/test_simple_connection_input.gd"
func run()->void:
	var dir:String=OS.get_environment("HABITAT_DATA_DIR");assert(dir.contains("youqi-"))
	var world:RefCounted=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json")
	world.residents.provision(world)
	for id in ["npc.mira","npc.nora"]:world.actors[id].role="npc";world.actors[id].controller="local"
	var before:Dictionary=world.storage.saved().duplicate(true)
	var saved_memories:Dictionary=world.memories.saved().duplicate(true)
	var Save=preload("res://scripts/save_store.gd")
	check(Save.save_world(world,dir),"actual old npc/local fixture saved")
	var restored:RefCounted=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json")
	var result:Dictionary=Save.load_world(restored,dir)
	check(result.ok and result.loaded,"old npc/local fixture accepted by strict validator")
	for id in ["npc.mira","npc.nora"]:
		check(restored.actors[id].role=="companion" and restored.actors[id].controller=="local","old role normalized without auto connection "+id)
	check(restored.storage.saved()==before,"identity normalization grants no inventory")
	check(restored.memories.saved()==saved_memories,"retained memory unchanged")
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	var pool:Node=preload("res://scripts/connection_session_pool.gd").obtain(self,dir);pool.factory=func(_id):return Stub.new()
	var panel:Node=preload("res://scripts/connection_overview.gd").new();root.add_child(panel);panel.setup(dir);panel.open();await frames()
	for id in pool.IDS:
		panel.refresh();await frames()
		check(await UI.click(self,panel.buttons[id]),"actual connect button on row "+id)
		await frames()
		check(pool.states[id].state=="ready","stub handshake ready "+id)
		check(pool.links[id].persona_card.persona_id==id,"own persona card "+id)
		check(pool.links[id].starts==1 and pool.links[id].chats==0,"handshake never pretends inference "+id)
		var invitations:Array=panel.get_children().filter(func(n):return n is ConfirmationDialog and n.visible)
		if not invitations.is_empty():check(await UI.click(self,invitations[0].get_cancel_button()),"dismiss new stewardship offer before connecting next resident")
		pool.set_management(id,true)
		check(pool.management(id),"independent management opt-in "+id)
	var cfg:=ConfigFile.new();cfg.load(dir.path_join("connection-mode.cfg"))
	for id in pool.IDS:
		check(cfg.get_value("management",id,false),"opt-in survives local cfg reload "+id)
		# DIRECTION 2026-11-09: 取消 AI 的每日上限、单回合上限与托管每日上限，默认“不限”。
		check(pool.daily_limit(id)==0 and pool.turn_limit(id)==0,"new token limits default unlimited "+id)
	panel.queue_free();pool.queue_free();await frames()
	print("STEWARD_CONNECTIONS ",checks," failed=",failed);quit(1 if failed else 0)
