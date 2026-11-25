extends SceneTree

const Pool=preload("res://scripts/connection_session_pool.gd")
const UI=preload("res://tests/barbecue_ui_fixture.gd")
const Text=preload("res://scripts/localization.gd")
const PEOPLE=["codex","companion-2","npc.mira","npc.nora"]
class OfflineLink extends "res://scripts/companion_link.gd":
	func _start()->bool:return false
	func _send(_message:Dictionary)->bool:return false
	func probe_connection()->bool:return false

func _initialize()->void:run.call_deferred()

func run()->void:
	var data:String=OS.get_environment("HABITAT_DATA_DIR")
	var output:String=OS.get_environment("HABITAT_OPEN_EVIDENCE")
	var number:int=int(OS.get_environment("HABITAT_TEST_SEED"))
	var baseline:bool=OS.get_environment("HABITAT_OPEN_BASELINE")=="1"
	var movie:bool=OS.get_environment("HABITAT_OPEN_MOVIE")=="1"
	var stewarded:bool=OS.get_environment("HABITAT_OPEN_STEWARD")=="1"
	if not data.contains("youqi-test-") or output.is_empty() or (movie and DisplayServer.get_name()=="headless"):quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	OS.set_environment("HABITAT_OPENING","standard")
	OS.set_environment("HABITAT_WORLD_SEED",str(number))
	OS.set_environment("HABITAT_BRAIN_SEED",str(number))
	root.size=Vector2i(1280,800)
	root.content_scale_size=Vector2i.ZERO
	seed(number)
	set_meta("title_fresh",true);set_meta("title_new_intro",true);set_meta("title_opening","standard")
	Pool.obtain(self,data).factory=func(_id):return OfflineLink.new()
	var game:Node=load("res://scenes/main_v3.tscn").instantiate()
	game.dialogue_adapter_factory=func(_id,_scope):return OfflineLink.new()
	root.add_child(game);current_scene=game
	game.save_enabled=false;game.set_process(false);game.view.set_process(false)
	game.life_archive.set_process(false);game.memory_life.set_process(false);game.local_host_commands.set_process(false)
	game.chat.hide();await process_frame;await process_frame
	var w:RefCounted=game.world
	w.forest.clock=1795046400.0;w.days.origin=w.forest.clock
	w.weather.weather_seed=absi(hash("weather:"+str(number)))
	w.fishing.rng.seed=number
	for id in PEOPLE:
		w.director.routines[id].rng.seed=hash("routine:"+str(number)+":"+id)
		w.director.routines[id].set_enabled(true)
	var host:Dictionary=w.actors.human.duplicate(true)
	var choices:Dictionary={};var since:Dictionary={};var stale:Dictionary={}
	for id in PEOPLE:choices[id]=[];since[id]=0.0;stale[id]=0.0
	var faults:Array=[];var bubbles:Dictionary={}
	var launched:=false;var accounted:Dictionary={};var meal_seen:=false
	var limit:int=3000 if movie else 6000
	var long_run:bool=OS.get_environment("HABITAT_OPEN_LONG")=="1"
	var dt:float=.1 if not long_run else .5
	if long_run:limit=9000
	var origin:float=w.forest.clock
	var wood_initial:int=wood_account(w)
	var wood_produced:=0
	var tree_states:Dictionary={}
	for obj in w.objects.values():
		if obj.kind=="tree":tree_states[obj.id]=obj.status
	var wood_valid:=true
	var capacity_valid:=true
	var vacation_valid:=true
	w.storage.audit_enabled=long_run
	if movie:DirAccess.make_dir_recursive_absolute(output.path_join("frames"))
	for i in range(limit):
		if stewarded and i==roundi(11.0/dt):
			game.island_hud.watch_requested=false;game.island_hud.watch_idle=0
			game.island_hud.tick_watch(1)
			await process_frame
			if DisplayServer.get_name()=="headless":
				game.steward.start("codex")
			else:
				await UI.click(self,game.watch_ui.toggle)
				if is_instance_valid(game.steward.setup_button):await UI.click(self,game.steward.setup_button)
			launched=game.steward.active
		game._process(dt);game.local_host_commands._process(dt);game.life_archive.tick(dt);game.view._process(dt)
		if long_run:
			for obj in w.objects.values():
				if obj.kind!="tree":continue
				if tree_states.get(obj.id)=="mature" and obj.status=="stump":wood_produced+=int(w.forest.settings.large_wood if int(obj.wood_yield)>8 else w.forest.settings.normal_wood)
				tree_states[obj.id]=obj.status
			wood_valid=wood_valid and wood_account(w)==wood_initial+wood_produced
			capacity_valid=capacity_valid and w.actors.values().all(func(row):return row.carry.values().reduce(func(total,n):return total+int(n),0)<=20)
		for fact in game.view.speech_by_actor.values():
			var key:String=fact.text
			if not bubbles.has(key):bubbles[key]=snappedf(float(i)/10,.1)
		if long_run or i%roundi(1.0/dt)==0:
			for id in PEOPLE:
				var brain:RefCounted=w.director.brains[id]
				var task:Dictionary=w.work.jobs.get(id,{})
				var provenance:String=str(task.get("intent",""))
				if not provenance.is_empty() and provenance in ["chop","gather_wood","forage","build_facility","plant","harvest","water"]:
					if not accounted.has(task.id):
						accounted[task.id]=id
						if w.resort.vacation(id):vacation_valid=false
						var approved:bool=game.steward.active and game.intentions.plans.get(id,{}).get("sponsor","")==game.steward.manager
						# DIRECTION: “有人搬料有人建”；“劳动要同意（托管安排即同意）”。
						if task.get("step") in ["squad_pickup","squad_delivery"]:
							var assignment:Dictionary=game.steward.body_director.tasks.get(id,{})
							var builder:String=task.builder
							var parent:Dictionary=w.work.jobs.get(builder,{})
							approved=game.steward.active and builder==game.steward.manager and game.intentions.plans.get(builder,{}).get("sponsor","")==builder and assignment.get("source")==builder and assignment.get("job_id")==task.id and parent.get("id")==task.build_job and parent.get("target_id")==task.target_id and parent.get("supplier",{})=={"actor":id,"job":task.id}
						if not approved:faults.append(["unapproved_labor",id,task.id])
						if w.hunger.rank(id)>=3:faults.append(["very_hungry_labor",id,task.id])
				var action:String=str(brain.current.get("action",w.actors[id].activity))
				if not provenance.is_empty():action=provenance
				if i%roundi(5.0/dt)==0:choices[id].append(action)
				if action in ["idle","quiet"] and not w._routes.has(id):since[id]=float(since[id])+(dt if long_run else 1.0)
				else:since[id]=0
				stale[id]=maxf(float(stale[id]),float(since[id]))
			if w.actors.human.position!=host.position or w.actors.human.region_id!=host.region_id:faults.append(["human_moved",i])
		if movie:
			var elapsed:float=float(i)/10.0
			var target:String="human" if elapsed<28 else PEOPLE[int((elapsed-28)/64)%PEOPLE.size()]
			if stewarded and game.steward.active and game.steward.body_director.tasks.has(game.steward.manager):target=game.steward.manager
			game.view.follow_player=false;game.view.peek_elapsed=0
			game.view.center=game.view.center.lerp(w.point(w.actors[target]),.10)
			game.island_hud.ui_root.hide()
			await RenderingServer.frame_post_draw
			var shot:=root.get_texture().get_image()
			shot.save_jpg(output.path_join("frames/%05d.jpg"%i),.89)
			if stewarded and not meal_seen and w.actors.values().any(func(a):return a.id!="human" and a.activity=="fire_eat"):
				shot.save_png(output.path_join("first-meal.png"));meal_seen=true
			game.island_hud.ui_root.show()
		elif i%120==0:await process_frame
	var trace:Array=game.welcome.trace if game.welcome!=null else []
	var meeting:Array=w.memories.records.filter(func(row):return row.kind=="first_meeting")
	var history:Array=game.steward.body_director.history
	if long_run:
		var ledger_valid:bool=not w.storage.audit.is_empty()
		for receipt in w.storage.audit:
			var expected:Dictionary=receipt.before.duplicate(true)
			for item in receipt.items:expected[item]=int(expected.get(item,0))+(1 if receipt.kind=="add" else -1)*int(receipt.items[item])
			for item in expected.keys()+receipt.after.keys():
				if int(expected.get(item,0))!=int(receipt.after.get(item,0)) or int(expected.get(item,0))<0:ledger_valid=false
		# DIRECTION / 开放的小世界: “每个人仍按自己的大脑和心事行动。”
		if stale.values().any(func(seconds):return seconds>120):faults.append("prolonged_idle")
		# DIRECTION: “伙伴干劳动活仍需玩家命令或托管安排。”
		if not launched or accounted.is_empty():faults.append("no_accepted_real_labor")
		if not wood_valid or not ledger_valid or not capacity_valid or not vacation_valid:faults.append(["invariants",wood_valid,ledger_valid,capacity_valid,vacation_valid])
		if history.any(func(row):return row.kind in ["consult_start","batch_start","rest"]):faults.append("scripted_squad")
	var snap:Dictionary={"seed":number,"baseline":baseline,"steward":launched,"choices":choices,"greeting":trace,"meeting":meeting,"coordination":history,"labor_count":accounted.size(),"faults":faults,"max_idle_seconds":stale,"game_seconds":w.forest.clock-origin,"bubbles":bubbles,"meal":meal_seen,"wood":w.storage.count("wood")}
	var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(snap,"  "));file.close()
	print("OPEN_ISLAND ",number," seconds=",snap.game_seconds," labor=",snap.labor_count," greeting=",trace.size()," faults=",faults)
	game.queue_free();await process_frame;quit(1 if not faults.is_empty() else 0)

func wood_account(w:RefCounted)->int:
	var total:int=w.storage.count("wood")
	for actor in w.actors.values():total+=int(actor.carry.get("wood",0))
	for drop in w.drops.values():total+=int(drop.get("wood",0))
	for site in w.leisure.sites.values():total+=int(site.get("invested",0))
	for camp in w.barbecues.values():total+=int(camp.station.get("fuel_used",0))
	return total
