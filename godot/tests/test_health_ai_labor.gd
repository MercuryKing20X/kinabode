extends "res://tests/test_health_ai.gd"
func run()->void:
	var F=preload("res://tests/cooking_fixture.gd")
	for action in ["water","chop"]:
		await fresh()
		var w:RefCounted=game.world
		w.director.set_all_enabled(false)
		var target:Dictionary
		if action=="water":
			target=w.farms.plots.values().filter(func(p):return w.farms.ready(p.farm_id) and p.crop_id.is_empty() and "turnip" in w.farms.farms[p.farm_id].crop_ids)[0]
			check(w.command("human",{"intent":"assign_farm","farm_id":target.farm_id,"manager_id":"human"}).ok,"host assigns actual dry-field fixture")
			check(F.job(w,"human",{"intent":"plant","target_id":target.id,"crop_id":"turnip"}) and w.farms.stage(target)=="dry","one real seed creates actual dry plot")
		else:
			target=w.objects.values().filter(func(o):return o.kind=="tree" and o.status=="mature" and o.region_id=="home" and not w.work.claims.has(o.id))[0]
		w.director.set_controller("codex","model")
		check(w.activities.set_followers(w.activities.following.keys().filter(func(who):return who!="codex")).ok and not w.activities.following.has("codex"),"host explicitly keeps labor observer at the real nearby target without changing idle or inference gates")
		var arrived:bool=false
		for angle in 16:
			var at:Vector2=w.point(target)+Vector2.from_angle(angle*TAU/16)*3
			if w.walkable(target.region_id,at) and F.job(w,"codex",{"intent":"move","x":at.x,"y":at.y}):arrived=true;break
		check(arrived,"World route reaches nearby "+action+" opportunity")
		if game.links.has("codex"):game.links.codex.queue_free();game.links.erase("codex")
		game.dialogue_adapter_factory=func(_id,_scope):return Fake.new()
		game._ensure_link("codex")
		var connection:Node=game.links.codex
		var prefs:RefCounted=game.resident_connections.preferences
		prefs.choose("codex","high");prefs.enable_autonomy("codex",false);prefs.runtime_supported.codex=true
		var shift:float=Time.get_unix_time_from_system()-w.forest.clock
		w.forest.clock+=shift;w.days.origin+=shift
		var scheduler:RefCounted=game.autonomy.scheduler
		scheduler.reset();scheduler.input_received()
		for tick in 20:game._process(.5)
		check(scheduler.active.is_empty() and scheduler.usage("codex").calls==0,action+" opportunity with autonomy off makes zero calls")
		prefs.enable_autonomy("codex",true)
		preload("res://tests/dialogue_ui_fixture.gd").open(game,"codex");game.chat_input.grab_focus()
		for tick in 20:game._process(.5)
		check(scheduler.active.is_empty() and scheduler.usage("codex").calls==0,action+" opportunity honors actual conversation focus hold")
		game.chat_input.release_focus();game.chat.hide()
		for tick in 20:
			game._process(.5)
			if scheduler.active.has("codex"):break
		if not scheduler.active.has("codex"):print("LABOR_PROBE ",action," gates=",game.autonomy.status("codex")," route=",w._routes.get("codex")," owner=",w.hunger.owned_routes.get("codex")," target=",target.position," actor=",w.actors.codex.position," held=",w.activities.held)
		check(scheduler.active.has("codex"),action+" opportunity wakes high stub after original held gate releases")
		var token:String=connection.turn_key
		var before:int=w.storage.count("wood")
		var seeds:int=w.storage.count("seed.turnip")
		var expected:int=int(w.forest.settings.large_wood if action=="chop" and int(target.wood_yield)>8 else w.forest.settings.normal_wood)
		connection._accept_event({"kind":"action","id":"health-labor-"+action,"turn_key":token,"command":{"intent":action,"target_id":target.id}})
		check(connection.sent[-1].get("result",{}).get("ok",false),action+" stub action accepted only through bound reservation")
		connection._accept_event({"kind":"usage","turn_key":token,"total_tokens":0,"input_tokens":0,"output_tokens":0,"complete":true})
		connection._accept_event({"kind":"state","state":"ready","turnComplete":true,"turn_key":token})
		for tick in 2000:
			game._process(.2)
			if (action=="water" and w.farms.orders.get("codex",{}).get("status")=="completed") or (action=="chop" and not w.work.jobs.has("codex") and not w._routes.has("codex") and not w.deliveries.active("codex")):break
		if action=="water":
			check(target.watered and w.farms.orders.get("codex",{}).get("status")=="completed" and w.storage.count("seed.turnip")==seeds,"real watering finishes without duplicate seeds or harvest")
		else:
			check(target.status=="stump" and w.storage.count("wood")==before+expected and not w.work.jobs.has("codex"),"real single-tree chop and physical delivery finish with exact configured wood")
		# Pass the unchanged 240-second high cooldown with genuine presence.
		# Existing trees and model-caused movement/completion must not form a chain.
		for tick in 600:
			if tick%100==0:scheduler.input_received()
			game._process(.5)
		if scheduler.usage("codex").calls!=1 or not scheduler.active.is_empty():print("LABOR_PROBE_FINAL ",action," status=",game.autonomy.status("codex")," route=",w._routes.get("codex"))
		check(scheduler.usage("codex").calls==1 and scheduler.active.is_empty(),action+" completion and existing opportunities never chain-wake after actual cooldown")
		game.queue_free();await process_frame
	print("HEALTH_AI_LABOR ",checks," failed=",failed);quit(1 if failed else 0)
