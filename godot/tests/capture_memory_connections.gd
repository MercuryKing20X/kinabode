extends "res://tests/test_intelligence_core_input.gd"
class HandshakeStub extends "res://scripts/companion_link.gd":
	var starts:=0
	var messages:=0
	func _start()->bool:
		starts+=1;_emit({"kind":"state","state":"ready"});return true
	func send_message(_text:String,_snapshot:Dictionary)->void:messages+=1
func run()->void:
	await fresh();game.memory_life.set_process(false)
	var ids:Array=["codex","companion-2","npc.mira","npc.nora"]
	for id in ids:game.world.director.set_controller(id,"model" if id!="codex" else "local")
	game.connection_ui_states["companion-2:direct"]="connecting";game.connection_ui_states["npc.mira:direct"]="ready";game.connection_ui_states["npc.nora:direct"]="error"
	game.island_hud.refresh();await picture("four-lights-stub")
	game.connection_overview.open();await picture("overview-stub")
	game.dialogue_adapter_factory=func(_id,_scope):return HandshakeStub.new()
	if game.links.has("npc.mira"):game.links["npc.mira"].queue_free();game.links.erase("npc.mira")
	game._ensure_link("npc.mira")
	var test_button:Button=game.connection_overview.rows.get_child(3).get_child(1)
	check(await UI.click(self,test_button),"native test-connection button clicked")
	check(game.links["npc.mira"].starts==1 and game.links["npc.mira"].messages==0,"one handshake and zero chat/model sends")
	check(game._connection_light("npc.mira").state=="ready","successful handshake updates connection light")
	game.connection_overview.hide()
	game.queue_free();await process_frame
	var title:Node=load("res://scenes/title.tscn").instantiate();root.add_child(title);await process_frame;title.connection_panel.open();await picture("title-connections")
	root.size=Vector2i(960,640);DisplayServer.window_set_size(root.size);await process_frame;await picture("title-connections-960")
	title.queue_free();await process_frame;print("MEMORY_CONNECTION_PROBE ",checks," failed=",failed);quit(1 if failed else 0)
