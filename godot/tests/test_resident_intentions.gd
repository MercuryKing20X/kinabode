extends "res://tests/test_intelligence_core_input.gd"
func run()->void:
	OS.set_environment("HABITAT_OPENING","showcase")
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game)
	game.save_enabled=false;game.set_process(false);game.memory_life.set_process(false);await process_frame;await process_frame
	var w:RefCounted=game.world
	w.director.set_controller("codex","model")
	game.chat_input.release_focus();game.chat.hide()
	var human:Dictionary=w.actors.human.duplicate(true)
	var result:Dictionary=game.intentions.submit("codex",[{"action":"wander"},{"action":"fish"},{"action":"light"},{"action":"roast"},{"action":"invite"}],"direct:codex")
	check(result.ok,"five-step plan accepted for connected resident")
	for i in range(4000):
		game._process(.1)
		if i%100==0:await process_frame
		if not game.intentions.plans.has("codex"):break
	print("PLAN_HISTORY ",game.intentions.history)
	check(game.intentions.history.filter(func(row):return row.result=="completed").size()==5,"five real steps complete in order")
	check(w.actors.human.position==human.position and w.actors.human.region_id==human.region_id,"resident plan never moves human")
	var meals:Array=w.barbecues.values().filter(func(life):return life.fireside.state.get("roast_by")=="codex" and not life.fireside.state.current.is_empty())
	check(not meals.is_empty(),"own actual catch is put on real grill")
	if not meals.is_empty():
		var fire:RefCounted=meals[0].fireside
		check(not w.fishing.fish.has(fire.state.current.fish.id),"unique fish consumed exactly once")
		check(fire.valid(fire.state,w.actors,meals[0].station),"resident meal preserves strict save conservation")
		for i in range(700):game._process(.1)
		check(fire.state.current.eaten>0,"invited resident actually eats")
	for life in w.barbecues.values():
		if life.fireside.active():life.fireside.end_circle("test finished actual meal")
	await meal_roster_cases(w)
	var directory:String=OS.get_environment("HABITAT_DATA_DIR").path_join("resident-meal-save")
	var save=preload("res://scripts/save_store.gd")
	check(save.save_world(w,directory),"actual resident-hosted meal saves")
	var queued:Dictionary=game.intentions.submit("codex",[{"action":"wander"},{"action":"fish"}],"direct:codex")
	check(queued.ok,"future sequence before reload")
	check(save.load_world(w,directory).ok,"resident roles and conserved fish meal reload")
	game._process(.1)
	check(not game.intentions.plans.has("codex"),"reload never resumes queued future intentions")
	queued=game.intentions.submit("codex",[{"action":"wander"},{"action":"fish"}],"direct:codex")
	check(queued.ok,"fresh sequence for original hunger interruption")
	w.advance(1501);game._process(.1)
	check(w.hunger.rank("codex")>=3 and not game.intentions.plans.has("codex") and game.intentions.last_failure.get("codex")=="very_hungry","actual advance preserves hunger priority and stops future work")
	check(w.fishing.held("codex").is_empty(),"interrupted future fishing creates no fish")
	game.queue_free();await process_frame
	print("RESIDENT_INTENTIONS ",checks," failed=",failed);quit(1 if failed else 0)

func meal_roster_cases(w:RefCounted)->void:
	w.director.set_all_enabled(false)
	for id in ["codex","companion-2"]:
		w.command(id,{"intent":"stop"});w.activities.release_follow(id)
	var tree:String=""
	for object in w.objects.values():
		if object.kind=="tree" and int(object.get("wood",1))>0:tree=object.id;break
	check(w.command("companion-2",{"intent":"chop","target_id":tree}).ok,"busy guest owns real chop before meal")
	var accepted:Dictionary=game.intentions.submit("codex",[{"action":"roast","item_id":"single:mushroom"},{"action":"invite"}],"direct:codex")
	check(accepted.ok,"regular roast plus default invite accepted")
	var fire:RefCounted
	for i in range(1200):
		game._process(.1)
		if not game.intentions.plans.has("codex"):break
		var plan:Dictionary=game.intentions.plans.codex
		if plan.current.action=="invite":fire=w.barbecues[plan.station_id].fireside;break
	if fire==null:
		print("MEAL_ROSTER_PROBE failure=",game.intentions.last_failure," history=",game.intentions.history.slice(-12)," plan=",game.intentions.plans.get("codex")," jobs=",w.work.jobs," held=",w.activities.held," rank=",w.hunger.rank("codex")," quiet=",w.director.routines.codex.visual_quiet_until," time=",w.director.time," stations=",w.barbecues.values().map(func(life):return {"id":life.station.id,"fire":life.fireside.state,"jobs":life.fireside.jobs,"closed":life.fireside.circle_closed}))
	check(fire!=null and "companion-2" not in fire.state.invited,"busy guest excluded from actual committed meal roster")
	if fire==null:return
	var meal_id:String=fire.state.current.id
	game._process(.1)
	check(not game.intentions.plans.has("codex") and not game.intentions.last_failure.has("codex"),"default follow-up invite accepts only same meal's committed guests")
	check(fire.state.current.id==meal_id and "companion-2" not in fire.state.invited,"follow-up never adds skipped worker or replaces food")
	fire.end_circle("test actual meal cancellation")
	w.command("codex",{"intent":"stop"})
	accepted=game.intentions.submit("codex",[{"action":"roast","item_id":"single:mushroom"},{"action":"invite"}],"direct:codex")
	check(accepted.ok,"second real meal chain accepted")
	for i in range(1200):
		game._process(.1)
		if not game.intentions.plans.has("codex"):break
		if game.intentions.plans.codex.current.action=="invite":break
	check(game.intentions.plans.has("codex"),"second chain reaches pending invitation")
	if not game.intentions.plans.has("codex"):return
	var original:String=fire.state.current.id
	fire.end_circle("host explicitly replaces original meal")
	fire.selected_guests=["codex"]
	check(fire.roast_host("single:mushroom","codex").ok and fire.state.current.id!=original,"host spends real food on a different meal")
	game._process(.1)
	check(game.intentions.last_failure.get("codex")=="meal_changed","old chained invitation rejects replaced meal identity")
	fire.end_circle("finish isolated replacement meal")
	w.command("companion-2",{"intent":"stop"})
