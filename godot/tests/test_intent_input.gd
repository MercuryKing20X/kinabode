extends "res://tests/test_intelligence_core_input.gd"
class IntentFake extends "res://scripts/companion_link.gd":
	var sent:Array=[]
	func uses_intents()->bool:return true
	func _start()->bool:return true
	func _send(message:Dictionary)->bool:sent.append(message.duplicate(true));return true
func run()->void:
	await fresh()
	var w:RefCounted=game.world
	w.director.set_controller("codex","model")
	if game.links.has("codex"):game.links.codex.queue_free();game.links.erase("codex")
	game.dialogue_adapter_factory=func(_id,_scope):return IntentFake.new()
	game._ensure_link("codex");game.chat_actor="codex"
	preload("res://tests/dialogue_ui_fixture.gd").open(game,"codex")
	if game.command_page.commands_mode:await UI.click(self,game.command_page.tabs.get_child(1))
	await text_input("帮我种萝卜")
	check(int(game.immediate_turns.get("codex",{}).get("local_ms",1000))<1000,"native submit-to-local first response below one second")
	print("LOCAL_FIRST_REPLY_MS ",game.immediate_turns.get("codex",{}).get("local_ms"))
	check(w.farms.orders.has("codex"),"real local farm order starts before AI")
	var connection:Node=game.links.codex
	var key:String=connection.turn_key
	check(connection.sent[-1].world.has("intent_card"),"small card sent")
	connection._accept_event({"kind":"intent_result","turn_key":key,"speech":"我会照看这些萝卜。","intents":[]})
	var count:int=w.storage.count("seed.turnip")
	connection._accept_event({"kind":"intent_result","turn_key":key,"speech":"","intents":[{"text":"帮我种萝卜","replace":false}]})
	check(w.storage.count("seed.turnip")==count,"duplicate intent cannot consume extra seed")
	connection._accept_event({"kind":"intent_result","turn_key":key,"speech":"","intents":[{"text":"小蓝去砍树","replace":true}]})
	check(not w.work.jobs.has("companion-2"),"out of scope intention rejected")
	connection._accept_event({"kind":"state","state":"ready","turnComplete":true,"turn_key":key})
	await picture("intent-started")
	w.command("codex",{"intent":"stop"});w.activities.release_follow("codex")
	await text_input("今天天气不错")
	connection._accept_event({"kind":"intent_result","turn_key":connection.turn_key,"speech":"","intents":[{"text":"跟着我","replace":false}]})
	check(not w.activities.following.has("codex"),"ordinary conversation never grants unsolicited work or movement")
	var channel:String=game.Channels.direct("codex")
	var source:Dictionary=game.dialogue.histories[channel].filter(func(row):return row.sender_id=="human" and row.text=="帮我种萝卜")[0]
	var history_count:int=game.dialogue.histories[channel].size()
	check(game.memory_books.remove(("codex|"+w.world_id+"|"+source.message_id+"|facts").sha256_text()),"exact source memory can be deleted")
	check(game.dialogue.histories[channel].size()==history_count,"one resident forgetting does not rewrite shared host dialogue history")
	check(not JSON.stringify(game._snapshot_for_chat("codex",channel,["codex"],"next")).contains("帮我种萝卜"),"forgotten source is absent from both next context and memory card")
	print("INTENT_INPUT ",checks," failed=",failed);game.queue_free();await process_frame;quit(1 if failed else 0)
