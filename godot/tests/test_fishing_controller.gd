# DIRECTION 2026-11-07: 主角鱼直接入库；以原真实实例验证后续流程。
extends SceneTree
const Talk=preload("res://tests/dialogue_ui_fixture.gd")
const Places=preload("res://scripts/map_locations.gd")
const Fixture=preload("res://tests/fishing_fixture.gd")
const Channels=preload("res://scripts/dialogue_channels.gd")
class FakeAdapter extends "res://scripts/companion_link.gd":
	var sent: Array=[]
	func _start() -> bool:return true
	func _send(message: Dictionary) -> bool:sent.append(message.duplicate(true));return true
var checks:=0
var failed:=false
var game: Node
var output:=""
func _initialize() -> void:call_deferred("run")
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failed=true;push_error(label)
func api(operation: String,query: Dictionary) -> Dictionary:
	var token: String=""
	for key in game.endpoint.bindings:
		if game.endpoint.bindings[key]=="codex":token=key;break
	return game.endpoint.handle({"session":game.endpoint.session,"token":token,"expires":Time.get_unix_time_from_system()+10,"operation":operation,"query":query,"request_id":Crypto.new().generate_random_bytes(12).hex_encode()})
func reply_identity(packet: Dictionary,event_id: String,event: Dictionary) -> Dictionary:
	var query: Dictionary={"event_id":event_id,"event":event}
	for key in ["world_id","resident_id","scope","session","generation","request_id"]:query[key]=packet[key]
	return query
func run() -> void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):quit(1);return
	output=OS.get_environment("HABITAT_FISHING_CAPTURE_DIR")
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false);game.view.sound_enabled=false
	await process_frame
	Talk.open(game,"codex")
	game.world.director.set_all_enabled(false);game.world.fishing.rng.seed=101
	for connection in game.links.values():connection.queue_free()
	game.links.clear();game.dialogue_adapter_factory=func(_id,_scope):return FakeAdapter.new()
	game._ensure_link("codex");game._ensure_link("companion-2");game.link=game.links.codex
	check(game.links.values().all(func(connection):return connection._pid==-1),"no model process starts")
	game.actions_button.pressed.emit()
	check(game.action_dock.menu.visible,"bottom action button opens categorized menu")
	await shot("actions")
	var position: Array=game.world.actors.human.position.duplicate()
	var result: Dictionary=game.action_dock.perform({"intent":"fish"})
	check(result.get("error")=="not_near_sea" and game.world.actors.human.position==position,"inland action prompts without a route")
	check(game.action_dock.strip.visible and game.action_dock.status.text.contains("海边"),"small bottom feedback explains coastal condition")
	check(not game.fishing_panel.visible,"instant fishing never opens fishery management")
	check(game.action_dock.perform({"intent":"gesture","gesture":"wave"}).ok,"daily explicit gesture executes separate real action")
	game.world.advance(.4);await shot("daily-wave")
	for i in range(20):game.world.advance(.1)
	check(Fixture.coast(game.world,"human"),"walk to natural coast with real navigation")
	game.view.center=game.world.point(game.world.actors.human)+Vector2(0,-3);game.view.zoom=.72
	check(game.action_dock.perform({"intent":"fish"}).ok,"bottom functional action casts at current coast")
	for i in range(20):game.world.advance(.1)
	await shot("waiting")
	for i in range(1200):
		game.world.advance(.1)
		if not game.world.work.jobs.has("human"):break
	check(not preload("res://tests/fishing_fixture.gd").unplaced(game.world).is_empty(),"actual catch becomes held fish")
	game.action_dock.refresh();await shot("held")
	var fish: Dictionary=preload("res://tests/fishing_fixture.gd").unplaced(game.world)
	check(game.view.fishing_renderer.hold_geometry(game.view,game.world.actors.human).is_empty(),"stored human fish never renders as a phantom held fish")
	check(Fixture.coast(game.world,"codex"),"companion reaches real coast for unchanged held-fish visual coverage")
	var held:Dictionary=Fixture.catch_one(game.world,"codex")
	check(game.world.command("codex",{"intent":"fish"}).get("error")=="holding_fish" and game.world.shared_activity.validate_invitation(["codex"]).get("error")=="hands_full","companion held fish still blocks incompatible tools and invitations")
	var geometry:Dictionary=game.view.fishing_renderer.hold_geometry(game.view,game.world.actors.codex)
	check(not held.is_empty() and geometry.get("fish_id")==held.get("id") and geometry.size.x/game.view.zoom>=game.view.fishing_renderer.actor_height(game.view,game.world.actors.codex),"companion hand-anchored real fish retains authored person-size scale")
	var old_hand:Vector2=geometry.hand
	position=game.world.actors.codex.position.duplicate()
	check(game.world.command("codex",{"intent":"move","x":position[0]+2,"y":position[1]+2}).ok,"held companion fish can walk")
	# Observe the route before 260px/s can finish this real (2,2)-tile step.
	game.world.advance(.15);await shot("held-walk")
	check(game.world.actors.codex.activity=="walking" and game.view.fishing_renderer.hold_geometry(game.view,game.world.actors.codex).hand.distance_to(old_hand)>15,"hand/whole fish follows actual walking companion")
	check(game.world.command("codex",{"intent":"release_fish","fish_id":held.id}).ok,"release exact companion visual fixture fish")
	for i in range(30):game.world.advance(.1)
	var id: String=fish.id;position=game.world.actors.human.position.duplicate()
	check(game.action_dock.perform({"intent":"stock_fish","fish_id":id,"pen_id":"home.fishery.east"}).ok and game.world.actors.human.position==position,"bottom destination places fish without moving catcher")
	game._open_fishing("home.fishery.east")
	check(game.fishing_panel.visible and game.fishing_panel.catch_button==null,"fishery management has no fishing trigger")
	await shot("fishery-management")
	game.fishing_panel.hide()
	var giant: Dictionary={}
	for i in range(45):
		if not Fixture.coast(game.world,"human"):break
		var entry: Dictionary=Fixture.catch_one(game.world,"human")
		if entry.is_empty():break
		if entry.scale>=7:giant=entry;break
		game.world.command("human",{"intent":"release_fish","fish_id":entry.id})
	check(not giant.is_empty(),"real deterministic catches include seven-to-eight-person fish")
	game.view.center=game.world.point(game.world.actors.human)+Vector2(0,-5);game.view.zoom=.6
	game.action_dock.choose("human");game.action_dock.dismissed=false;game.action_dock.refresh();await shot("giant-held")
	# Dynamic invitation, no fixed two spots or five-model routing.
	for number in range(2,9):
		var actor_id: String="companion-%s"%number
		if not game.world.actors.has(actor_id):game.world.add_companion(actor_id,"伙伴%s"%number)
	game.world.director.set_all_enabled(false)
	var options: Array=game.world.fishing.coast_points.duplicate()
	options.sort_custom(func(a,b):return Vector2(a.position[0],a.position[1]).distance_squared_to(Places.point("p_52_10"))<Vector2(b.position[0],b.position[1]).distance_squared_to(Places.point("p_52_10")))
	check(Fixture.walk(game.world,"human",options[0].position),"player carries actual fish to a shared natural shoreline")
	game.view.center=game.world.point(game.world.actors.human)+Vector2(0,-5);game.view.zoom=.6
	game.action_dock.open_invite();await shot("invite")
	for choice in game.action_dock.choices.get_children():
		if choice is CheckButton:choice.button_pressed=true
	game.action_dock.popup.confirmed.emit();game.action_dock.popup.hide()
	var invited: Array=game.world.work.jobs.keys().filter(func(actor_id):return game.world.work.jobs[actor_id].get("intent")=="fish")
	check(invited.size()>=6,"UI invitation supports more than five model residents")
	for i in range(700):
		game.world.advance(.1)
		var at_sea: int=invited.filter(func(actor_id):return game.world.work.jobs.get(actor_id,{}).get("phase") in ["fish_cast","fish_wait","fish_bite","fish_reel"]).size()
		if at_sea>=3:break
	await shot("together")
	var jobs: Dictionary=game.world.work.jobs.duplicate(true)
	game._select_chat(Channels.ALL);Talk.send(game,"这是界面验收用模拟消息：一边钓鱼一边聊聊。")
	check(game.world.work.jobs==jobs,"ordinary group chat never stops accepted fishing")
	var deliveries:=0
	for link in game.group_links.values():deliveries+=link.sent.size()
	game.group_links[invited[0]]._accept_event({"kind":"assistant","text":"验收模拟：我在等浮漂。"})
	game.group_links[invited[1]]._accept_event({"kind":"assistant","text":"验收模拟：这边有鱼影。"})
	check(game.view.speech_by_actor.has(invited[0]) and game.view.speech_by_actor.has(invited[1]),"simultaneous actual adapter replies keep separate resident bubbles")
	var later:=0
	for link in game.group_links.values():later+=link.sent.size()
	check(later==deliveries,"assistant reply cannot recursively wake more models")
	await shot("chat-while-fishing")
	for link in game.group_links.values():link._accept_event({"kind":"state","state":"ready","turnComplete":true})
	var question_actor: String=invited[0]
	game._bound_companion_event({"kind":"question","id":"shore-question","text":"界面测试模拟提问：先歇一会儿吗？","choices":["聊聊"]},question_actor,"group")
	check(not game.world.work.jobs.has(question_actor),"exact essential question stops only its owner's fishing")
	check(invited.slice(1).any(func(actor_id):return game.world.work.jobs.has(actor_id)),"other fishers keep their independent jobs")
	game.group_questions.clear();game.chat.hide()
	# Real external adapter mailbox, tested with synthetic client text; no inference.
	game.ai_connect_panel.open();await shot("ai-connect");game.ai_connect_panel.hide()
	game._bind_external_ai("codex",true,false)
	check(game.links.codex.get_script()==preload("res://scripts/external_dialogue_link.gd"),"host one-click binding selects provider-neutral external adapter")
	var config: Dictionary=game.ai_connect_panel.configuration()
	check(config.mcpServers.youqi.args.has("--world") and config.mcpServers.youqi.args.has(game.world.world_id),"connection configuration pins world and resident")
	game._select_chat("codex");Talk.send(game,"外部适配器验收消息，不是真实推理。")
	var polled: Dictionary=api("dialogue_poll",{})
	check(polled.ok and polled.pending.text.contains("适配器验收"),"external adapter exposes actual queued player message")
	var packet: Dictionary=polled.pending
	check(api("act",{"intent":"stop"}).get("error")=="dialogue_identity_required","external dialogue actions cannot bypass turn identity")
	check(api("read_actions",{}).dialogue_context_required,"action discovery announces external lease requirement")
	var response: Dictionary=api("dialogue_reply",reply_identity(packet,"external-reply",{"kind":"assistant","text":"外部适配器验收回复。"}))
	check(response.ok and game.chat_log.get_parsed_text().contains("外部适配器验收回复"),"exact external reply reaches real in-game channel")
	check(not api("dialogue_reply",reply_identity(packet,"external-reply",{"kind":"assistant","text":"duplicate"})).ok,"duplicate external event rejects")
	check(api("dialogue_reply",reply_identity(packet,"external-question",{"kind":"question","text":"验收用模拟问题","choices":["是"]})).ok,"external adapter can ask actual game question")
	check(not api("dialogue_reply",reply_identity(packet,"early-action",{"kind":"action","command":{"intent":"fish"}})).ok,"external question cannot be bypassed by an action")
	check(not api("dialogue_reply",reply_identity(packet,"early-complete",{"kind":"complete"})).ok,"external model cannot turn unanswered waiting into consent")
	Talk.send(game,"是")
	check(api("dialogue_poll",{}).results["external-question"].answer=="是","explicit answer returns to exact external request")
	check(api("dialogue_reply",reply_identity(packet,"complete",{"kind":"complete"})).ok and not game.links.codex.is_busy(),"explicit external completion releases inference state")
	Talk.send(game,"新的验收轮次")
	check(not api("dialogue_reply",reply_identity(packet,"late",{"kind":"assistant","text":"stale"})).ok,"old generation cannot answer new message")
	game.links.codex.cancel_turn()
	check(not api("dialogue_reply",reply_identity(packet,"cancelled",{"kind":"assistant","text":"stale"})).ok,"cancelled external turn cannot publish text")
	game._bind_external_ai("codex",false,false)
	check(game.links.codex is FakeAdapter,"returning to original adapter uses preserved host factory")
	game.chat.hide();game.action_dock.choose("human");game.action_dock.dismissed=false;game.action_dock.refresh()
	root.size=Vector2i(960,640);await shot("small")
	game.ai_connect_panel.open();await shot("small-ai-connect");game.ai_connect_panel.hide()
	game.chat.show();await shot("small-chat");game.chat.hide()
	check(game.links.values().all(func(connection):return connection._pid==-1),"all controller tests use zero real model processes")
	game.queue_free();await process_frame
	print("Fishing controller: %s checks, %s"%[checks,"FAIL" if failed else "PASS"]);quit(1 if failed else 0)
func shot(name: String) -> void:
	game.action_dock.refresh()
	if output.is_empty():return
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var bounds:=Rect2(Vector2.ZERO,root.get_visible_rect().size)
	for control in [game.dialogue_button,game.actions_button,game.gathering_button]:check(bounds.encloses(control.get_global_rect()),"bottom action fits viewport "+name)
	if game.action_dock.strip.visible:
		check(bounds.encloses(game.action_dock.strip.get_global_rect()),"small fishing status fits viewport "+name)
		check(game.action_dock.strip.size.y<160 and game.action_dock.strip.size.x<380,"fishing feedback remains a small frame "+name)
		if game.chat.visible:check(not game.chat.get_global_rect().intersects(game.action_dock.strip.get_global_rect()),"chat and fishing status do not obscure each other "+name)
	if game.action_dock.menu.visible:check(bounds.encloses(game.action_dock.menu.get_global_rect()),"action menu fits viewport")
	if game.ai_connect_panel.visible:check(game.ai_connect_panel.size.x<=bounds.size.x and game.ai_connect_panel.size.y<=bounds.size.y,"AI connection popup fits viewport")
	root.get_texture().get_image().save_png(output.path_join(name+".png"))
