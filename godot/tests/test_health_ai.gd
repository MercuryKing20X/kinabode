extends "res://tests/test_intelligence_core_input.gd"
class Fake extends "res://scripts/companion_link.gd":
	var sent:Array=[]
	func _start()->bool:return true
	func _send(message:Dictionary)->bool:sent.append(message.duplicate(true));return true
func fresh()->void:
	OS.set_environment("HABITAT_OPENING","showcase")
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	game=load("res://scenes/main_v3.tscn").instantiate()
	game.world=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json")
	root.add_child(game)
	game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.island_hud.set_process(false);game.chat.hide()
	await process_frame;await process_frame
func run()->void:
	await fresh()
	var w:RefCounted=game.world
	var F=preload("res://tests/cooking_fixture.gd")
	var plot:Dictionary=w.farms.plots.values().filter(func(p):return w.farms.ready(p.farm_id) and p.crop_id.is_empty() and "turnip" in w.farms.farms[p.farm_id].crop_ids)[0]
	check(w.command("human",{"intent":"assign_farm","farm_id":plot.farm_id,"manager_id":"human"}).ok,"host assigns actual farm")
	check(F.job(w,"human",{"intent":"plant","target_id":plot.id,"crop_id":"turnip"}),"real seed planted")
	check(F.job(w,"human",{"intent":"water","target_id":plot.id}),"real first water")
	w.advance(float(w.farms.crops.turnip.seconds)+1)
	check(F.job(w,"human",{"intent":"forage","target_id":"home.mushrooms.1"}),"real mushroom gathered for meal")
	check(preload("res://tests/barbecue_fixture.gd").meal(w,"single:mushroom",["codex"]),"real meal restores appetite before autonomous labor")
	check(w.farms.stage(plot)=="mature","real advance matures crop")
	w.director.set_controller("codex","model")
	check(w.activities.set_followers(w.activities.following.keys().filter(func(who):return who!="codex")).ok and not w.activities.following.has("codex"),"host explicitly leaves Snow by the nearby labor opportunity before testing idle autonomy")
	var approached:bool=false
	for angle in 16:
		var at:Vector2=w.point(plot)+Vector2.from_angle(angle*TAU/16)*3
		if not w.walkable(plot.region_id,at):continue
		var move:Dictionary=w.command("codex",{"intent":"move","x":at.x,"y":at.y})
		if move.ok and F.wait(w,"codex"):approached=true;break
		print("AI_MOVE ",move)
	check(approached,"World routes Snow to crop")
	if game.links.has("codex"):game.links.codex.queue_free();game.links.erase("codex")
	game.dialogue_adapter_factory=func(_id,_scope):return Fake.new()
	game._ensure_link("codex")
	var connection:Node=game.links.codex
	var prefs:RefCounted=game.resident_connections.preferences
	prefs.choose("codex","high");prefs.enable_autonomy("codex",true);prefs.runtime_supported.codex=true
	# Match the existing authoritative clock to wall time without elapsed hunger.
	var shift:float=Time.get_unix_time_from_system()-w.forest.clock
	w.forest.clock+=shift;w.days.origin+=shift
	game.autonomy.scheduler.reset();game.autonomy.player_input()
	for tick in 100:
		game._process(.1)
		if game.autonomy.scheduler.active.has("codex"):break
	if not game.autonomy.scheduler.active.has("codex"):print("HEALTH_PROBE gates=",game.autonomy.status("codex")," route=",w._routes.get("codex")," routeowner=",w.hunger.owned_routes.get("codex")," held=",w.activities.held," position=",w.actors.codex.position," target=",plot.position)
	check(game.autonomy.scheduler.active.has("codex"),"enabled high wakes from nearby real labor within ten seconds")
	var key:String=connection.turn_key
	connection._accept_event({"kind":"action","id":"health-harvest","turn_key":key,"command":{"intent":"harvest","target_id":plot.id}})
	check(connection.sent[-1].get("result",{}).get("ok",false),"reserved model stub action accepted by host")
	connection._accept_event({"kind":"state","state":"ready","turnComplete":true,"turn_key":key})
	for tick in 2000:
		game._process(.1)
		if w.farms.orders.get("codex",{}).get("status")=="completed":break
	check(w.farms.orders.get("codex",{}).get("status")=="completed" and w.storage.count("turnip")>0,"stub harvest completes into real warehouse")
	game.queue_free();await process_frame
	for failure in ["disconnect","timeout","budget"]:
		await fresh()
		w=game.world
		w.director.set_controller("codex","model")
		w.activities.dismiss("codex")
		var nearby:Vector2=Vector2.INF
		for offset in [Vector2(2,0),Vector2(-2,0),Vector2(0,2),Vector2(0,-2)]:
			var candidate:Vector2=w.point(w.actors.human)+offset
			if w.walkable("home",candidate) and not w.find_route("codex",candidate).is_empty():nearby=candidate;break
		check(nearby.is_finite() and F.job(w,"codex",{"intent":"move","x":nearby.x,"y":nearby.y}),failure+" prepares real nearby listener without weakening speech distance")
		w.activities.set_followers(w.actors.keys().filter(func(who):return who!="human"))
		if game.links.has("codex"):game.links.codex.queue_free();game.links.erase("codex")
		game.dialogue_adapter_factory=func(_id,_scope):return Fake.new()
		game._ensure_link("codex");game.chat_actor="codex"
		connection=game.links.codex
		game._send_direct("codex","小白跟我来")
		var failure_key:String=connection.turn_key
		if failure=="timeout":
			if game.model_fallback_requests.has("codex"):game.model_fallback_requests.codex.deadline=Time.get_ticks_msec()-1
			game._process(.1)
		elif failure=="disconnect":connection._accept_event({"kind":"state","state":"disconnected","turn_key":failure_key})
		else:connection._accept_event({"kind":"error","message":"stub budget exhausted","turn_key":failure_key})
		check(w.activities.following.has("codex") and not game.model_fallback_requests.has("codex"),failure+" falls back and executes original instruction")
		var explained:bool=false
		for tick in 360:
			game._process(.5);game.local_host_commands._process(.5);game.view._process(.5)
			if game.view.speech_by_actor.get("codex",{}).get("text","").contains("熟悉的办法"):
				explained=true;break
			if tick%20==0:await process_frame
		if not explained:print("FALLBACK_DEBUG ",failure," focus=",game.chat_input.has_focus()," held=",w.director.routines.codex.held," enabled=",w.director.routines.codex.enabled," routine=",w.director.routines.codex.state()," next=",w.director.routines.codex.next_speech," time=",w.director.time," queue=",game.local_host_commands.speech_queue," speech=",game.view.speech_by_actor.get("codex",{})," events=",w.director.events.slice(-3))
		check(explained,failure+" actually displays natural fallback explanation within original 180-second speech queue lifetime")
		game.queue_free();await process_frame
	await fresh()
	w=game.world
	w.director.set_controller("codex","model")
	if game.links.has("codex"):game.links.codex.queue_free();game.links.erase("codex")
	game.dialogue_adapter_factory=func(_id,_scope):return Fake.new()
	game._ensure_link("codex")
	check(w.command("codex",{"intent":"follow"}).ok,"host restores actual following after model source switch")
	check(w.director.model_controlled("codex") and game.links.codex._pid==-1,"natural need scenario uses model-controlled Snow with stub transport")
	var clicked:bool=false
	for tick in 1200:
		game._process(.5);game.view._process(.5)
		var speech:Dictionary=game.view.speech_by_actor.get("codex",{})
		if speech.get("context")=="need_fish":
			game.view.center=w.point(w.actors.codex);game.view.follow_player=false
			await process_frame
			for entry in game.view.speech_layout():
				if entry.actor_id!="codex":continue
				for down in [true,false]:
					var e:=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.position=entry.box.get_center();e.global_position=e.position;e.pressed=down;root.push_input(e,true);await process_frame
				clicked=true;break
		if clicked:break
		if tick%20==0:await process_frame
	if not clicked:print("HEALTH_NEED_PROBE clicked=",clicked," state=",w.director.routines.codex.state()," events=",w.director.routines.codex.events," gates=",w.activities.held," speech_after=",w.director.speech_after," last=",w.director.routines.codex.needs.last," next=",w.director.routines.codex.next_speech," context=",game.view.speech_by_actor.get("codex",{}))
	check(clicked,"natural fish need appears within original 600 seconds and real bubble input clicks it")
	var thanked:bool=false
	for tick in 600:
		game._process(.5);game.view._process(.5)
		if game.view.speech_by_actor.get("codex",{}).get("context")=="need_satisfied":thanked=true;break
		if tick%20==0:await process_frame
	check(not w.fishing.held("codex").is_empty() and thanked,"clicked need catches own real fish and says happy thanks")
	game.queue_free();await process_frame
	print("HEALTH_AI ",checks," failed=",failed);quit(1 if failed else 0)
