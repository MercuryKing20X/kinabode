extends "res://tests/test_intelligence_core_input.gd"
class Handshake extends "res://tests/test_simple_connection_input.gd".Stub:
	func probe_connection()->bool:
		starts+=1;return true
	func is_busy()->bool:return true
func run()->void:
	OS.set_environment("HABITAT_OPENING","standard")
	var dir:String=OS.get_environment("HABITAT_DATA_DIR")
	var pool:Node=preload("res://scripts/connection_session_pool.gd").obtain(self,dir)
	pool.factory=func(_id):return Handshake.new()
	pool.settings.set_value("enabled","codex",true)
	pool.connect_ai("codex")
	root.size=Vector2i(1280,800)
	game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game)
	game.save_enabled=false;game.set_process(false);game.memory_life.set_process(false)
	await process_frame;await process_frame
	game.chat.hide();game.chat_input.release_focus()
	var w:RefCounted=game.world
	var origin:Vector2=w.point(w.actors.codex)
	var distance:float=origin.distance_to(w.point(w.actors.human))
	for i in range(50):game._process(.1)
	print("CONNECTING_BODY before=",distance," after=",w.point(w.actors.codex).distance_to(w.point(w.actors.human))," held=",w.director.routines.codex.held)
	check(not w.director.routines.codex.held,"handshake never holds local body")
	check(w.point(w.actors.codex).distance_to(origin)>2,"real World movement during handshake")
	check(w.point(w.actors.codex).distance_to(w.point(w.actors.human))<distance-2,"opening approaches host before handshake completes")
	pool.links.codex.turn_key="real-turn";game._refresh_conversation_holds()
	check(w.director.routines.codex.held,"real model turn still held")
	pool.links.codex.turn_key="";game.questions.codex={"id":"question"};game._refresh_conversation_holds()
	check(w.director.routines.codex.held,"real question still held")
	game.questions.clear();pool.disconnect_ai("codex");game.queue_free();await process_frame
	print("CONNECTING_BODY ",checks," failed=",failed);quit(1 if failed else 0)
