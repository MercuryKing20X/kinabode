extends "res://tests/test_intelligence_core_input.gd"
func run()->void:
	OS.set_environment("HABITAT_OPENING","showcase")
	game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false);game.memory_life.set_process(false)
	await process_frame;await process_frame
	var w:RefCounted=game.world
	w.director.set_controller("codex","model")
	check(game.intentions.submit("codex",[{"action":"roast","item_id":"single:mushroom","target_id":"home.barbecue"}],"direct:codex").ok,"actual mushroom meal accepted")
	var fire:RefCounted=w.barbecues["home.barbecue"].fireside
	for i in range(1000):
		game._process(.1)
		if fire.state.get("current",{}).has("meal_remaining"):break
	check(fire.state.current.get("meal_duration")==30.0,"mushroom whole gathering thirty seconds")
	game._process(10.0)
	var left:float=fire.state.current.meal_remaining
	check(left<=20.0 and left>19,"actual advance reduces remaining time")
	var dir:=OS.get_environment("HABITAT_DATA_DIR").path_join("timer-save")
	var save=preload("res://scripts/save_store.gd")
	check(save.save_world(w,dir),"timed meal saves through real validator")
	var restored:RefCounted=w
	var result:Dictionary=save.load_world(restored,dir)
	print("TIMER_LOAD ",result)
	check(result.get("loaded",false),"timed meal reload accepted")
	if not result.ok:game.queue_free();await process_frame;quit(1);return
	var saved_fire:RefCounted=restored.barbecues["home.barbecue"].fireside
	check(saved_fire.state.suspended and not saved_fire.state.consent and saved_fire.jobs.is_empty(),"reload paused no routes or invitations resumed")
	check(is_equal_approx(saved_fire.state.current.meal_remaining,left),"reload retains countdown")
	var elapsed:float=saved_fire.state.current.elapsed
	saved_fire.tick(20)
	check(is_equal_approx(saved_fire.state.current.meal_remaining,left) and saved_fire.state.current.elapsed==elapsed,"paused timer and cooking do not advance")
	var station:Vector2=w.point(fire.life.station)
	check(w.command("human",{"intent":"move","region_id":"home","x":station.x,"y":station.y+2}).ok,"explicit host return for resume")
	for i in range(800):
		w.advance(.1)
		if not w._routes.has("human"):break
	check(saved_fire.resume_meal().ok,"explicit resume without rebuying meal")
	var before:int=w.storage.count("wood")
	await process_frame;await process_frame
	if game.watch_ui!=null:game.watch_ui._process(.1)
	await picture("meal-countdown")
	for i in range(600):game._process(.1)
	check(fire.circle_closed and not fire.state.consent and fire.jobs.is_empty(),"deadline releases actual jobs and seats")
	check(fire.state.current.eaten+fire.state.current.wasted==fire.state.current.total,"expired meal conserves all portions")
	check(w.storage.count("wood")==before,"expiry never charges extra wood")
	if game.watch_ui!=null:
		game.watch_ui._process(.1)
		check(not game.watch_ui.meal_countdown.visible,"countdown disappears at end")
	await create_timer(5).timeout
	check(game.status.text not in [game.T("system.fireside.this_meal_has_finished"),game.T("system.fireside.the_fireside_ended_this_does_not_mean_the")],"end status cleared within five wall seconds")
	await picture("meal-ended-five-seconds")
	if DisplayServer.get_name()!="headless" and not OS.get_environment("HABITAT_UI_EVIDENCE").is_empty():root.get_texture().get_image().save_png(OS.get_environment("HABITAT_UI_EVIDENCE").path_join("meal-ended-five-seconds.png"))
	var id:="companion-2"
	w.command(id,{"intent":"stop"});w.activities.release_follow(id);w.director.routines[id].interrupt(0)
	var origin:Vector2=w.point(w.actors[id]);var target:=origin+Vector2(1,0)
	if not w.walkable(w.actors[id].region_id,target):target=origin+Vector2(0,1)
	check(w.command(id,{"intent":"move","region_id":w.actors[id].region_id,"x":target.x,"y":target.y}).ok,"short route uses World")
	check(w.is_running(id),"one tile route runs without twelve tile threshold")
	print("MEAL_TIMER_RUNNING ",checks," failed=",failed)
	game.queue_free();await process_frame;quit(1 if failed else 0)
