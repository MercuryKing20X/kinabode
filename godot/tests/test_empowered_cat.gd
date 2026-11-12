extends "res://tests/test_empowered_input.gd"
func run()->void:
	OS.set_environment("HABITAT_OPENING","showcase")
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false)
	await process_frame;await process_frame
	var w:RefCounted=game.world
	w.director.set_controller("codex","model")
	if game.links.has("codex"):game.links.codex.queue_free();game.links.erase("codex")
	game.dialogue_adapter_factory=func(_id,_scope):return IntentFake.new()
	game._ensure_link("codex");preload("res://tests/dialogue_ui_fixture.gd").open(game,"codex")
	await text_input("抱抱柚柚")
	var connection:Node=game.links.codex
	connection._accept_event({"kind":"state","state":"ready","turnComplete":true,"turn_key":connection.turn_key})
	for i in range(1500):
		game._process(.1)
		if i%100==0:await process_frame
		if not game.intentions.plans.has("codex"):break
	print("CAT_PLAN ",game.intentions.history," cat=",w.cat.carrier," pos=",w.cat.position)
	check(w.cat.carrier=="codex","native input really reaches and holds existing cat")
	await picture("empowered-cat")
	var result:Dictionary=game.intentions.submit("codex",[{"action":"wander"},{"action":"fish"}],"direct:codex")
	check(result.ok,"own future plan accepted")
	game.intentions.cancel("codex")
	check(not game.intentions.plans.has("codex"),"cancellation clears future intentions")
	world_cleanup()
func world_cleanup()->void:
	game.queue_free();await process_frame
	print("EMPOWERED_CAT ",checks," failed=",failed);quit(1 if failed else 0)
