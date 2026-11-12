extends "res://tests/test_simple_connection_input.gd"
func run()->void:
	OS.set_environment("HABITAT_OPENING","standard")
	var dir:String=OS.get_environment("HABITAT_DATA_DIR")
	var pool:Node=preload("res://scripts/connection_session_pool.gd").obtain(self,dir)
	pool.factory=func(_id):return Stub.new()
	pool.connect_ai("codex")
	await frames()
	var game:Node=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game)
	game.save_enabled=false;game.set_process(false);game.memory_life.set_process(false)
	await frames(2);game.chat.hide();game.chat_input.release_focus()
	var w:RefCounted=game.world
	var origin:Vector2=w.point(w.actors.codex)
	for i in range(20):
		game._simple_connection_action("codex","connect")
		var original:Node=pool.links.codex
		game._simple_connection_action("codex","connect")
		check(pool.links.codex==original and original.starts==1,"connect is idempotent "+str(i))
		for j in range(5):game._process(.1)
		game.connection_overview.open();game.connection_overview.hide()
		game._simple_connection_action("codex","disconnect")
		check(not game.links.has("codex") and game.link==null and not game._resident_chat_busy("codex"),"references cleared before free "+str(i))
		await frames(1)
		game._process(.1)
	check(w.point(w.actors.codex).distance_to(origin)>2,"World movement throughout connect/disconnect")
	for i in range(3):
		for mode in ["codex","openai"]:
			pool.set_api("codex",mode);game._simple_connection_action("codex","connect");await frames(1)
			check(pool.valid("codex"),"switch mode "+mode)
			pool.receive("codex",{"kind":"state","state":"disconnected"});pool.retry_due.codex=0;pool._process(.1);await frames(1)
			check(pool.states.codex.state=="ready","fault retry with same owned connection")
		game._simple_connection_action("codex","disconnect")
	# Simulate invalid foreign reference: per-frame gates must treat it as absent.
	var stale:=Stub.new();game.links.codex=stale;stale.free()
	check(not game._resident_chat_busy("codex"),"freed reference safely ignored")
	game._process(.1);game.links.erase("codex")
	game.queue_free();await frames(1)
	print("OWNERSHIP ",checks," failed=",failed);quit(1 if failed else 0)
