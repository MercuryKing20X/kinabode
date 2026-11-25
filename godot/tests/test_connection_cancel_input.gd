extends "res://tests/test_intent_input.gd"
func run()->void:
	await fresh()
	var w:RefCounted=game.world
	w.director.set_controller("codex","model")
	game.dialogue_adapter_factory=func(_id,_scope):return IntentFake.new()
	# Main preallocates a lazy compatibility link; replace it before any real input.
	if game.links.has("codex"):game.links.codex.queue_free();game.links.erase("codex")
	game._ensure_link("codex");game.link=game.links.codex
	check(game.links.codex is IntentFake,"all mixed inputs use isolated model stub rather than lazy production bridge")
	game.connection_ui_states["codex:direct"]="ready"
	preload("res://tests/dialogue_ui_fixture.gd").open(game,"codex")
	var link:Node=game.links.codex
	var cancelled:Array=[]
	link.event_received.connect(func(e):
		if e.get("state") in ["cancelling","cancelled"]:cancelled.append(e))
	if OS.get_environment("HABITAT_CANCEL_CAPTURE")=="1":
		await UI.click(self,game.island_hud.settings_menu);await process_frame;await picture("settings-restored")
		game.queue_free();await process_frame;quit();return
	for level in ["ultra","lifeblood"]:
		game.resident_connections.preferences.choose("codex",level)
		for text in ["去砍树","你在干嘛","过来","跟我走","今天天气不错"]:
			preload("res://tests/dialogue_ui_fixture.gd").open(game,"codex")
			await text_input(text,true)
			if OS.get_environment("HABITAT_CANCEL_BASELINE")=="1":
				game.autonomy.scheduler.active.codex={"id":"old-autonomy"}
				# Frozen pre-fix membership-only branch, without changing production source.
				if game.autonomy.scheduler.active.has("codex"):link.cancel_turn()
				print("BASELINE_MEMBERSHIP_CANCEL ",cancelled)
				game.autonomy.scheduler.active.erase("codex")
				game.queue_free();await process_frame;quit();return
			var key:String=link.turn_key
			check(not key.is_empty(),level+" real input dispatched: "+text)
			# Stale scheduler bookkeeping must never cancel a newer player turn.
			game.autonomy.scheduler.active.codex={"id":"old-autonomy"}
			game.autonomy.cancel("codex")
			check(link.turn_key==key and not link._cancelling,"exact turn ownership protects player")
			game.autonomy.scheduler.active.erase("codex")
			link._accept_event({"kind":"intent_result","turn_key":key,"speech":"好，我听见啦。","intents":[]})
			link._accept_event({"kind":"state","turn_key":key,"state":"ready","turnComplete":true})
	check(cancelled.is_empty(),"ten mixed inputs zero cancellation")
	await UI.click(self,game.island_hud.settings_menu);await process_frame
	check(game.island_hud.settings_menu.get_popup().visible,"settings opens via real input")
	await picture("cancel-settings")
	print("CANCEL_INPUT ",checks," failed=",failed)
	game.queue_free();await process_frame;quit(1 if failed else 0)
