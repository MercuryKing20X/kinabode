extends "res://tests/test_intelligence_core_input.gd"
class Fake extends "res://scripts/companion_link.gd":
	var sent:Array=[]
	func _start()->bool:return true
	func _send(message:Dictionary)->bool:sent.append(message.duplicate(true));return true
func text_input(text:String,send_by_button:bool=false)->void:
	var target:String=game.Channels.ALL if game.group_chat else game.chat_actor
	if not game.chat.visible:check(await UI.click(self,game.dialogue_button),"native opens model dialogue")
	if game.command_page.commands_mode:check(await UI.click(self,game.command_page.tabs.get_child(1)),"native selects Talk for model stub dialogue")
	game._select_chat(target)
	await super.text_input(text,send_by_button)
func run()->void:
	await fresh()
	var w:RefCounted=game.world
	var id:String="companion-2"
	w.director.set_controller(id,"model")
	if game.links.has(id):game.links[id].queue_free();game.links.erase(id)
	game.dialogue_adapter_factory=func(_id,_scope):return Fake.new()
	game._ensure_link(id);game.chat_actor=id
	preload("res://tests/dialogue_ui_fixture.gd").open(game,id)
	var connection:Node=game.links[id]
	var phrases:Array=["小蓝跟我来","小蓝别跟了","Skye follow me","Skye stop following","小蓝跟牢我","小蓝自由活动","Skye come with me","Skye unfollow","小蓝跟着我走","小蓝散了"]
	for index in phrases.size():
		await text_input(phrases[index])
		var key:String=connection.turn_key
		check(not key.is_empty() and not connection.sent.is_empty(),"raw host words reach fake model "+str(index))
		connection._accept_event({"kind":"action","id":"stub-action-"+str(index),"turn_key":key,"command":{"intent":"follow" if index%2==0 else "unfollow"}})
		connection._accept_event({"kind":"state","state":"ready","turnComplete":true,"turn_key":key})
		check(w.activities.following.has(id)==(index%2==0),"accepted bound model action really changes selected follower "+str(index))
		check(not game.model_fallback_requests.has(id),"successful model action never gets duplicate local fallback")
	connection._accept_event({"kind":"action","id":"illegal-self-human","command":{"intent":"follow","actor_id":"human"}})
	check(connection.sent[-1].get("result",{}).get("ok",true)==false,"illegal cross-actor arguments return rejection to stub")
	connection._accept_event({"kind":"state","state":"ready","turnComplete":true})
	await text_input("小蓝跟我来")
	var mismatch_key:String=connection.turn_key
	connection._accept_event({"kind":"action","id":"mismatched-host-scope","turn_key":mismatch_key,"command":{"intent":"start_project"}})
	check(connection.sent[-1].get("result",{}).get("error")=="host_instruction_mismatch","model cannot turn a follow request into a material purchase")
	connection._accept_event({"kind":"error","turn_key":mismatch_key,"message":"fake model budget unavailable"})
	check(w.activities.following.has(id) and not game.model_fallback_requests.has(id),"budget error immediately falls back to original host follow instruction")
	await text_input("别干了")
	await text_input("小白小橙跟我来")
	var delegated_key:String=connection.turn_key
	connection._accept_event({"kind":"action","id":"explicit-named-delegation","turn_key":delegated_key,"command":{"intent":"follow","actor_ids":["codex","npc.mira"]}})
	check(w.activities.following.size()==2 and w.activities.following.has("codex") and w.activities.following.has("npc.mira"),"bound model can dispatch exact other residents named by the host, without inferring for them")
	connection._accept_event({"kind":"state","state":"ready","turnComplete":true,"turn_key":delegated_key})
	await text_input("小蓝种萝卜")
	var plant_key:String=connection.turn_key
	var plots:Array=w.farms.plots.values().filter(func(plot):return w.farms.ready(plot.farm_id) and plot.crop_id.is_empty() and "turnip" in w.farms.farms[plot.farm_id].crop_ids)
	var before_seeds:int=w.storage.count("seed.turnip")
	connection._accept_event({"kind":"action","id":"host-authorized-real-plant","turn_key":plant_key,"command":{"intent":"plant","target_id":plots[0].id,"crop_id":"turnip"}})
	if not connection.sent[-1].get("result",{}).get("ok",false):print("PLANT_SCOPE_DEBUG ",connection.sent[-1]," grants=",game.host_turn_grants," activity=",w.actors[id]," jobs=",w.work.jobs)
	check(connection.sent[-1].get("result",{}).get("ok",false),"model uses original host-scoped real farm order without permanent work capability")
	connection._accept_event({"kind":"state","state":"ready","turnComplete":true,"turn_key":plant_key})
	for tick in 6000:
		game._process(.1)
		if w.farms.orders.get(id,{}).get("status")=="completed":break
	check(w.farms.plots[plots[0].id].watered and w.storage.count("seed.turnip")==before_seeds-1,"stub-driven plant spends exactly one real seed and first-waters actual plant")
	game.resident_connections.preferences.enable_autonomy(id,false)
	connection.turn_kind="autonomy_event";connection.turn_key="unreserved-off-probe";connection._busy=true;connection.autonomy_tool_limit=6;connection.autonomy_tool_calls=0
	connection._accept_event({"kind":"action","id":"unreserved-auto-work","turn_key":"unreserved-off-probe","command":{"intent":"chop","target_id":"home.tree.01"}})
	check(connection.sent[-1].get("result",{}).get("error")=="autonomy_not_authorized" and not w.work.jobs.has(id),"autonomy off or missing real reservation cannot grant daily labor")
	connection._accept_event({"kind":"state","state":"ready","turnComplete":true,"turn_key":"unreserved-off-probe"})
	await text_input("小蓝帮我砍点木头")
	var revoked_key:String=connection.turn_key
	check(game.model_fallback_requests.has(id),"timeout fallback is tied to actual turn")
	await create_timer(30.1).timeout
	game._process(.1)
	check(w.work.jobs.get(id,{}).get("intent")=="gather_wood","actual wall timeout revokes model turn and starts local real work")
	var job:String=w.work.jobs.get(id,{}).get("id","")
	connection._accept_event({"kind":"action","id":"late-after-timeout","turn_key":revoked_key,"command":{"intent":"stop"}})
	check(w.work.jobs.get(id,{}).get("id","")==job,"revoked late model action cannot stop fallback work")
	connection._accept_event({"kind":"question","id":"late-question-after-fallback","turn_key":revoked_key,"text":"现在还要继续吗？"})
	check(not game.questions.has(id) and w.work.jobs.get(id,{}).get("id","")==job,"revoked late question cannot freeze fallback work")
	check(not game._fallback_actions_revoked(id,"group",{"turn_key":revoked_key},connection),"revocation is bound to its original scope")
	var late_text:String="我想好了，还是先陪你把眼前的事做完。"
	connection._accept_event({"kind":"assistant","turn_key":revoked_key,"text":late_text})
	check(game.dialogue.histories[game.Channels.direct(id)].any(func(row):return row.sender_id==id and row.text==late_text),"late assistant reply survives action revocation")

	await text_input("别干了")
	check(w.work.jobs.is_empty() and game.model_fallback_requests.is_empty(),"host stop cancels cloud and local work immediately")
	await text_input("小蓝跟我来")
	var future_key:String=connection.turn_key
	check(not future_key.is_empty() and future_key!=revoked_key,"later explicit input receives a fresh turn lease")
	connection._accept_event({"kind":"action","id":"new-follow-after-fallback","turn_key":future_key,"command":{"intent":"follow"}})
	check(w.activities.following.has(id),"revoked older turn does not disable a newer authorized turn")
	connection._accept_event({"kind":"state","state":"ready","turnComplete":true,"turn_key":future_key})
	await text_input("别干了")

	game.group_chat=true
	var direct_count:int=game.dialogue.histories.get("direct:"+id,[]).size()
	await text_input("小蓝跟我来")
	var group_connection:Node=game.group_links[id]
	check(game.model_fallback_requests.get(id,{}).get("scope")=="group","group host request has its own turn binding")
	group_connection._accept_event({"kind":"error","turn_key":group_connection.turn_key,"message":"fake group provider unavailable"})
	check(w.activities.following.has(id) and game.dialogue.histories.get("direct:"+id,[]).size()==direct_count,"group fallback executes without writing or cancelling private history")
	game.queue_free();await process_frame
	print("ONE_LINE_CLOUD_STUB ",checks," failed=",failed);quit(1 if failed else 0)
