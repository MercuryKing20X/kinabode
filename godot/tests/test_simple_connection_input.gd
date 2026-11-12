extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
const Cards=preload("res://scripts/persona_cards.gd")
class Stub extends Node:
	signal event_received(event:Dictionary)
	var resident_id:="codex"
	var world_id:=""
	var helper_filename:=""
	var conversation_scope:="direct"
	var starts:=0
	var chats:=0
	var persona_card:Dictionary={}
	var failure:=""
	var turn_key:=""
	func probe_connection()->bool:
		starts+=1;persona_card=Cards.card(resident_id)
		complete.call_deferred();return true
	func complete()->void:
		if not failure.is_empty():event_received.emit({"kind":"error","message":failure})
		else:event_received.emit({"kind":"state","state":"ready","turnComplete":false})
	func is_busy()->bool:return false
	func shutdown()->void:pass
	func cancel_turn()->void:pass
	func uses_intents()->bool:return true
	func autonomy_capabilities()->Dictionary:return {"supported":false,"reason":"model stub","levels":[]}
var checks:=0
var failed:=0
func check(ok:bool,message:String)->void:
	checks+=1
	print("CHECK ",ok," ",message)
	if not ok:failed+=1
func _initialize()->void:call_deferred("run")
func frames(count:int=10)->void:
	for i in range(count):await process_frame
func shot(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	await process_frame;RenderingServer.force_draw(false)
	var out:String=OS.get_environment("HABITAT_UI_EVIDENCE")
	if out.is_empty():out=OS.get_environment("HABITAT_DATA_DIR")
	root.get_texture().get_image().save_png(out.path_join(name+".png"))
func run()->void:
	var dir:String=OS.get_environment("HABITAT_DATA_DIR");assert(dir.contains("youqi-"))
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	var cfg:=ConfigFile.new();cfg.set_value("connection","external_residents",{"codex":true,"companion-2":true});cfg.save(dir.path_join("connection-mode.cfg"))
	var pool:Node=preload("res://scripts/connection_session_pool.gd").obtain(self,dir)
	pool.factory=func(_id):return Stub.new()
	var title:Node=load("res://scenes/title.tscn").instantiate();root.add_child(title);current_scene=title;await frames()
	check(await UI.click(self,title.menu.get_node("connections")),"1: title connection page mouse click")
	await frames();var panel:Node=title.connection_panel
	check(not pool.external("codex") and not pool.settings.get_value("connection","shared_test",true),"retired transports normalized on load")
	check(UI.descendants(panel).filter(func(n):return n is OptionButton and str(n.name).begins_with("api_")).all(func(n):return n.item_count==3),"three choices per resident")
	check(await UI.click(self,panel.buttons.codex),"3: connect click")
	await frames();check(pool.states.codex.state=="ready" and pool.states.codex.greeting=="我在呢～","green plus authored greeting")
	var reconnect_link:Node=pool.links.codex
	pool.receive("codex",{"kind":"state","state":"disconnected"})
	check(pool.settings.get_value("enabled","codex",false) and pool.retry_due.has("codex"),"unexpected disconnect retains desire and retries")
	pool.retry_due.codex=0;pool._process(.1);await frames()
	check(pool.states.codex.state=="ready" and pool.links.codex==reconnect_link,"runtime retry reuses bound link and recovers")
	var original:Node=pool.links.codex
	check(original.starts==2 and original.chats==0,"one handshake, zero chat/token requests")
	check(pool.auto_enabled("codex"),"auto connect defaults on")
	panel.refresh();await frames();await shot("connected-three-clicks")
	# Enter the actual game; title-owned connection remains in the root pool.
	title.queue_free();await frames()
	var game:Node=load("res://scenes/main_v3.tscn").instantiate();game.dialogue_adapter_factory=func(_id,_scope):return Stub.new()
	root.add_child(game);current_scene=game;await frames(30)
	game.save_enabled=false;game.memory_life.set_process(false)
	check(game.links.codex==original and original.starts==2,"enter game reuses same session without starting")
	for dialog in game.get_children():
		if dialog is ConfirmationDialog and dialog.dialog_text==game.T("repair.offer"):dialog.hide()
	game.connection_overview.open();await frames();await shot("in-game-connections");game.connection_overview.hide()
	game.resident_connections.open("codex");await frames()
	check(await UI.click(self,game.resident_connections.connect_button),"in-game card disconnect click")
	await frames();check(not game.world.director.model_controlled("codex"),"disconnect restores local")
	check(await UI.click(self,game.resident_connections.connect_button),"in-game card reconnect click")
	await frames();check(game._connection_light("codex").state=="ready","reconnect actual status green")
	for bad in ["```python\nprint(1)\n```","https://example.com","作为 AI 模型，我无法回答。","一。二。三。四。"]:
		check(game._persona_speech(bad,"codex")==game.T("simple.fallback"),"unsafe output replaced")
		game._bound_companion_event({"kind":"assistant","text":bad},"codex")
		check(game.dialogue.histories["direct:codex"][-1].text==game.T("simple.fallback"),"host event hides raw unsafe output")
	check(game._persona_speech("工作累了吗？过来坐一会儿吧，火还暖着。","codex").begins_with("工作"),"persona reply preserved")
	var card:Dictionary=game._intent_card("codex",{"dialogue":{"channel_id":"direct:codex","recipient_ids":["codex"]}},"direct:codex")
	check(card.self.persona_id=="codex" and card.self.has("personality"),"persona id plus existing personality")
	game.queue_free();await frames()
	var failpanel:Node=preload("res://scripts/connection_overview.gd").new();root.add_child(failpanel);failpanel.setup(dir);failpanel.open();await frames()
	for failure in ["Codex not found","需要登录 Codex"]:
		pool.disconnect_ai("codex");pool.factory=func(_id):var stub:=Stub.new();stub.failure=failure;return stub
		failpanel.test_connection("codex");await frames()
		check(pool.states.codex.state=="error","failure red "+failure)
		check("安装" in pool.states.codex.error if "found" in failure else "登录" in pool.states.codex.error,"actionable failure "+failure)
		failpanel.refresh();await frames()
		await shot("failure-missing" if "found" in failure else "failure-login")
	pool.disconnect_ai("codex");pool.factory=func(_id):return Stub.new()
	pool.settings.set_value("enabled","codex",true);pool.persist();pool.start_saved();await frames()
	check(pool.states.codex.state=="ready" and pool.links.codex.chats==0,"saved auto-connect handshakes without inference")
	check(not pool.external("companion-2") and not pool.settings.get_value("enabled","companion-2",false) and (not pool.links.has("companion-2") or (pool.links["companion-2"] is Stub and pool.links["companion-2"].starts==0 and pool.links["companion-2"].chats==0)),"legacy external never starts handshake or inference even when a lazy compatibility stub is preallocated")
	failpanel.advanced=true;failpanel.refresh();await frames()
	check(not UI.descendants(failpanel).any(func(n):return n is Button and n.text==failpanel.Text.text("simple.copy")),"advanced has no external configuration")
	pool.retries.erase("codex")
	for attempt in range(7):
		pool.retry_due.erase("codex");pool.schedule_retry("codex")
	check(pool.retries.codex==7,"reconnection does not stop after three attempts")
	pool.disconnect_ai("codex")
	check(not pool.retry_due.has("codex") and not pool.settings.get_value("enabled","codex",true),"explicit disconnect cancels retries")
	var config:Dictionary=pool.configuration("codex")
	check(config.mcpServers.youqi.args.has("--resident"),"external configuration binds resident")
	var export:Dictionary={}
	for id in pool.IDS:
		for lang in ["zh","en"]:export[id+"."+lang]=Cards.card(id,lang)
	var file:=FileAccess.open(dir.path_join("persona-godot.json"),FileAccess.WRITE);file.store_string(JSON.stringify(export));file.close()
	print("SIMPLE_CONNECTION_RESULT checks=",checks," failed=",failed," click_count=3")
	failpanel.queue_free();pool.queue_free();await frames();quit(1 if failed else 0)
