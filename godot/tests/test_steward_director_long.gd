extends "res://tests/test_intent_input.gd"
var local_first_day_done:=0
var local_first_day_participation:Dictionary={}
func run()->void:
	if OS.get_environment("HABITAT_DIRECTOR_REPORT_REPLAY")=="1":
		var evidence:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("HABITAT_DIRECTOR_EVIDENCE").path_join("local.json")))
		var director=preload("res://scripts/steward_director.gd").new()
		for event in evidence.events:
			if event.kind=="report":director.reported_goals[event.goal]=true
		var fresh:Array=director.new_goal_reports(evidence.goals,"")
		check(fresh.size()==1 and fresh[0].id=="dusk","real retained long-run facts reveal the one unreported passive dusk goal")
		check(director.new_goal_reports(evidence.goals,"").is_empty(),"committed goal reports never replay twice")
		quit(1 if failed else 0);return
	if OS.get_environment("HABITAT_DIRECTOR_CAPTURE_ONLY")=="1":
		await capture_owner_meal();return
	root.size=Vector2i(1280,800)
	var base:String=OS.get_environment("HABITAT_DATA_DIR")
	var evidence:String=OS.get_environment("HABITAT_DIRECTOR_EVIDENCE")
	if not evidence.is_empty():DirAccess.make_dir_recursive_absolute(evidence)
	var local_timeline:Array=[]
	for ai in [false,true]:
		seed(60112)
		var directory:String=base.path_join("ai" if ai else "local")
		DirAccess.make_dir_recursive_absolute(directory);OS.set_environment("HABITAT_DATA_DIR",directory)
		OS.set_environment("HABITAT_OPENING","standard")
		game=load("res://scenes/main_v3.tscn").instantiate()
		game.dialogue_adapter_factory=func(_id,_scope):return IntentFake.new()
		root.add_child(game);game.save_enabled=false;game.set_process(false);game.memory_life.set_process(false);game.local_host_commands.set_process(false)
		await process_frame;await process_frame
		game.chat.hide()
		for i in 10:await process_frame
		# Both fresh fixtures start at the same simulation epoch. Forest's normal
		# wall-clock floor must not turn different resource-loading times into
		# different first advances or owner-question deadlines.
		check(game.world.forest.elapsed==0 and game.world.work.jobs.is_empty() and game.world.work.events.is_empty() and game.world.drops.is_empty(),"shared epoch applies only before any fresh-world work or advance")
		check(game.world.objects.values().filter(func(o):return o.kind=="tree").all(func(tree):return tree.status=="mature" and not tree.has("sprout_at") and not tree.has("mature_at")) and game.world.days.spoken.is_empty() and game.world.days.small.is_empty(),"shared epoch has no retained growth or day facts to rewrite")
		game.world.forest.clock=2000000000.0
		game.world.days.origin=2000000000.0
		await UI.click(self,game.steward.toggle)
		await UI.click(self,game.steward.setup_button)
		check(game.steward.active and game.steward.manager=="codex","mouse chooses Xiaobai and starts stewardship")
		game.steward.local_only=not ai
		if ai:
			game.world.director.set_controller("codex","model");game._ensure_link("codex")
			game.connection_ui_states["codex:direct"]="ready";game.connection_history.set_value("connected","codex",1);game.steward.pool.set_management("codex",true)
		var w:RefCounted=game.world
		w.weather.weather_seed=60112;w.fishing.rng.seed=60112;w.gomoku.rng.seed=60112;game.playground.rope_rng.seed=60112
		for index in game.steward.Pool.IDS.size():w.director.routines[game.steward.Pool.IDS[index]].rng.seed=60112+index
		seed(60112)
		w.storage.audit_enabled=true
		var duration:float=w.days.day_seconds*(1 if ai else 3)
		var short:bool=not OS.get_environment("HABITAT_DIRECTOR_SECONDS").is_empty()
		if short:duration=minf(float(OS.get_environment("HABITAT_DIRECTOR_SECONDS")),w.days.day_seconds if ai else INF)
		var elapsed:=0.0;var maximum:=0.0;var total:=0.0;var count:=0
		var delivered:Dictionary={};var timeline:Array=[];var pending_progress:=0
		var participation:Dictionary={}
		var participation_stages:Dictionary={}
		for id in game.steward.Pool.IDS:participation[id]={"eligible":0,"active":0,"watch":0}
		var human_start:Dictionary=w.actors.human.duplicate(true)
		var baseline:float=w.forest.clock
		var wood_initial:int=wood_account(w)
		var produced_wood:=0
		var tree_states:Dictionary={}
		for object in w.objects.values():
			if object.kind=="tree":tree_states[object.id]=object.status
		var wood_conserved:=true
		var captured_question:=false;var captured_meal:=false
		var fishing_formation:Array=[]
		while elapsed<duration:
			game._process(.5);game.local_host_commands._process(.5);elapsed+=.5
			for id in game.steward.Pool.IDS:
				var d:RefCounted=game.steward.body_director
				if d.batch.is_empty() or w._routes.has(id):continue
				participation[id].eligible+=1
				var stage:String=str(d.batch.step.action)+":"+str(d.batch.phase)
				if not participation_stages.has(stage):participation_stages[stage]={}
				if not participation_stages[stage].has(id):participation_stages[stage][id]={"active":0,"watch":0}
				var participating:bool=w.work.jobs.has(id) or w.farms.active(id) or w.deliveries.active(id) or id in game.playground.members or w.gomoku.active(id)
				participation_stages[stage][id]["active" if participating else "watch"]+=1
				if w.work.jobs.has(id) or w.farms.active(id) or w.deliveries.active(id) or id in game.playground.members or w.gomoku.active(id):participation[id].active+=1
				else:participation[id].watch+=1
			if fishing_formation.is_empty() and game.steward.Pool.IDS.all(func(id):return w.work.jobs.get(id,{}).get("intent")=="fish" and w.work.jobs[id].phase!="fish_approach"):
				for id in game.steward.Pool.IDS:fishing_formation.append({"id":id,"position":w.actors[id].position.duplicate(),"leader_distance":w.point(w.actors[id]).distance_to(w.point(w.actors.codex))})
				if not evidence.is_empty() and DisplayServer.get_name()!="headless":
					game.view.follow_player=false;game.view.follow_actor="";game.view.center=(w.point(w.actors.codex)+w.point(w.actors["npc.nora"]))/2;game.view.zoom=1.0;game.view.queue_redraw()
					await process_frame;RenderingServer.force_draw(false)
					root.get_texture().get_image().save_png(evidence.path_join(("ai-" if ai else "local-")+"fishing-row.png"))

			for object in w.objects.values():
				if object.kind!="tree":continue
				if tree_states.get(object.id,object.status)=="mature" and object.status=="stump":produced_wood+=int(w.forest.settings.large_wood if int(object.wood_yield)>8 else w.forest.settings.normal_wood)
				tree_states[object.id]=object.status
			if wood_account(w)!=wood_initial+produced_wood:wood_conserved=false
			if ai and not game.steward.pending.is_empty():
				var pending:Dictionary=game.steward.pending
				if not game.steward.body_director.tasks.is_empty():pending_progress+=1
				if w.forest.clock-float(pending.started)>=90 and not delivered.has(pending.key):
					delivered[pending.key]=true
					game.links.codex._accept_event({"kind":"intent_result","turn_key":pending.key,"speech":"也许……","preference":"home","planning":[{"phase":"now","intents":[{"action":"home"},{"action":"go_to","x":999,"y":999}]}]})
					game.links.codex._accept_event({"kind":"state","state":"ready","turn_key":pending.key,"turnComplete":true})
			if int(elapsed*2)%20==0:
				var actors:Array=[]
				for id in game.steward.Pool.IDS:
					var distance:float=w.point(w.actors[id]).distance_to(w.point(w.actors.codex))
					var traveling:bool=w._routes.has(id) or game.steward.body_director.tasks.get(id,{}).get("traveling",false)
					total+=distance;count+=1
					if not traveling:maximum=maxf(maximum,distance)
					actors.append({"id":id,"distance":distance,"traveling":traveling,"position":w.actors[id].position.duplicate(),"task":game.steward.body_director.tasks.get(id,{}).duplicate(true),"idle":game.steward.body_director.idle(game,id),"job":w.work.jobs.get(id,{}).duplicate(true),"plan":game.intentions.plans.get(id,{}).duplicate(true),"all_plans":game.intentions.plans.duplicate(true),"held":w.activities.held.get(id,false),"chat":game._resident_chat_busy(id)})
				timeline.append({"elapsed":elapsed,"phase":game.steward.body_director.batch.get("phase",""),"goal":game.steward.body_director.batch.get("goal",{}).get("id",""),"pending":not game.steward.pending.is_empty(),"weather":w.weather.summary(),"actors":actors,"goals":w.standard.board_completed.duplicate(true)})
			if not ai and elapsed==w.days.day_seconds:
				local_first_day_done=w.standard.goals.rows(w).filter(func(row):return row.done).size()
				local_first_day_participation=participation.duplicate(true)
			if not evidence.is_empty() and DisplayServer.get_name()!="headless":
				var director:RefCounted=game.steward.body_director
				var question_visible:bool=is_instance_valid(director.card) and director.card.visible and director.question_until>0
				var eating:bool=w.actors.values().filter(func(actor):return actor.id!="human" and actor.activity=="fire_eat").size()>=4
				if not captured_question and question_visible or not captured_meal and eating:
					game.view.follow_player=false;game.view.center=w.point(w.actors.codex);game.view.queue_redraw()
					await process_frame;RenderingServer.force_draw(false)
					root.get_texture().get_image().save_png(evidence.path_join(("ai-" if ai else "local-")+("question.png" if question_visible else "meal.png")))
					if question_visible:captured_question=true
					else:captured_meal=true
			if int(elapsed*2)%240==0:
				print("DIRECTOR_PROGRESS ",ai," ",elapsed," done=",w.standard.goals.rows(w).filter(func(row):return row.done).size()," batch=",game.steward.body_director.batch)
				await process_frame
		var director:RefCounted=game.steward.body_director
		var goals:Array=w.standard.goals.rows(w)
		var interruptions:Array=director.receipts.filter(func(row):return row.reason=="work_interrupted")
		var ledger_ok:=true
		for receipt in w.storage.audit:
			var expected:Dictionary=receipt.before.duplicate(true)
			for item in receipt.items:expected[item]=int(expected.get(item,0))+(1 if receipt.kind=="add" else -1)*int(receipt.items[item])
			for item in expected:
				if int(expected[item])!=int(receipt.after.get(item,0)) or int(expected[item])<0:ledger_ok=false
			for item in receipt.after:
				if int(receipt.after[item])!=int(expected.get(item,0)):ledger_ok=false
		var labor_on_vacation:Array=director.history.filter(func(row):return row.kind=="dispatch" and row.vacation and row.step.action in ["chop","gather","plant","harvest","water","build"])
		var report:Dictionary={"fishing_formation":fishing_formation,"participation":participation,"participation_stages":participation_stages,"weather_days":[w.weather.for_day(1).id,w.weather.for_day(2).id,w.weather.for_day(3).id],"ai":ai,"seconds":w.forest.clock-baseline,"goals":goals,"first_meal":w.standard.first_meal,"average_distance":total/maxi(1,count),"max_nontravel_distance":maximum,"questions":director.questions,"reports":director.reports,"invitations":director.invitations,"faults":director.faults,"failures":director.failures,"matches":w.gomoku.sessions.duplicate(true),"stops":w.work.stop_audit.duplicate(true),"interruptions":interruptions,"wood_conserved":wood_conserved,"wood_initial":wood_initial,"wood_produced":produced_wood,"wood_final_account":wood_account(w),"ledger_ok":ledger_ok,"ledger_transactions":w.storage.audit.size(),"labor_on_vacation":labor_on_vacation,"ai_ignored":director.ai_ignored,"ai_replies":delivered.size(),"pending_body_samples":pending_progress,"timeline":timeline,"events":director.history,"batch":director.batch,"paused":director.paused,"stock":w.storage.saved(),"actors":w.actors.duplicate(true)}
		report.seed=60112;report.first_day_participation=local_first_day_participation.duplicate(true);report.first_body_divergence={}
		if not ai:local_timeline=timeline.duplicate(true)
		else:
			for index in mini(timeline.size(),local_timeline.size()):
				if body_signature(timeline[index])!=body_signature(local_timeline[index]):
					report.first_body_divergence={"elapsed":timeline[index].elapsed,"local":body_signature(local_timeline[index]),"ai":body_signature(timeline[index])};break
			check(report.first_body_divergence.is_empty(),"same seed local/slow AI body task table identical every ten seconds")
		if not evidence.is_empty():
			var file:=FileAccess.open(evidence.path_join("ai.json" if ai else "local.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report));file.close()
			var traces:String=game.data_dir.path_join("steward-traces")
			for filename in DirAccess.get_files_at(traces):DirAccess.copy_absolute(traces.path_join(filename),evidence.path_join(("ai-" if ai else "local-")+filename))
		var concise:Dictionary=report.duplicate();for field in ["timeline","events","actors"]:concise.erase(field)
		print("DIRECTOR_RESULT ",JSON.stringify(concise))
		if not short:
			if not ai:
				var labor:Dictionary={};var labor_total:=0
				for id in game.steward.Pool.IDS:
					var rows:Array=director.history.filter(func(e):return e.kind=="task_start" and e.get("actor")==id and e.action in ["chop","gather","build","build_supply","plant","water","harvest","fish"])
					labor[id]=rows.size();labor_total+=rows.size()
				for id in game.steward.Pool.IDS:
					var metric:Dictionary=participation[id]
					check(float(metric.active)/maxi(1,metric.eligible)>=.7,"participation >=70% "+id)
					check(float(metric.watch)/maxi(1,metric.eligible)<=.2,"watch <=20% "+id)
					check(float(labor[id])/maxi(1,labor_total)<=.4,"labor share <=40% "+id)
					if id!=game.steward.manager:
						for action in ["chop","build_supply","plant","fish"]:check(director.history.any(func(e):return e.kind=="task_start" and e.get("actor")==id and e.action==action),"participated "+id+" "+action)
				check(goals.all(func(row):return row.done),"all 16 actual tutorial goals complete in three days")
			else:
				for id in game.steward.Pool.IDS:
					var metric:Dictionary=participation[id]
					var local_metric:Dictionary=local_first_day_participation[id]
					check(absf(float(metric.active)/maxi(1,metric.eligible)-float(local_metric.active)/maxi(1,local_metric.eligible))<=.05,"same seed/window slow AI participation within 5 percentage points "+id)
				check(goals.filter(func(row):return row.done).size()>=local_first_day_done,"slow invalid AI keeps local first-day progress")
				check(director.ai_ignored==delivered.size() and delivered.size()>0,"every home/out-of-candidate suggestion ignored")
				check(pending_progress>0,"body tasks advance during 90-second planner lease")
			check(not w.standard.first_meal.is_empty(),"real first meal committed")
			check(maximum<=15,"nontravel squad radius <=15")
			check(director.faults.is_empty(),"zero stalls and oscillations")
			check(director.failures.values().all(func(value):return value<=2),"at most two failures per goal")
			check(director.questions>=floor(duration/float(game.steward.trace_config.owner_question_seconds))-1,"owner question cadence from configured 150 seconds")
			check(wood_conserved,"real tree output equals carried/dropped/stored/invested/burnt wood on every advance")
			check(ledger_ok and not w.storage.audit.is_empty(),"all actual storage debits/credits conserve quantities")
			check(labor_on_vacation.is_empty(),"no labor dispatch on vacation island")
			check(w.actors.human.position==human_start.position and w.actors.human.region_id==human_start.region_id,"timeout and AI never move human")
			check(w.actors.values().all(func(actor):return actor.carry.values().reduce(func(total,value):return total+int(value),0)<=20),"each real carry stays within capacity")
		game.queue_free();await process_frame
	print("DIRECTOR_LONG ",checks," failed=",failed);quit(1 if failed else 0)

func capture_owner_meal()->void:
	root.size=Vector2i(1280,800)
	OS.set_environment("HABITAT_OPENING","standard")
	game=load("res://scenes/main_v3.tscn").instantiate()
	game.dialogue_adapter_factory=func(_id,_scope):return IntentFake.new()
	root.add_child(game);game.save_enabled=false;game.set_process(false);game.memory_life.set_process(false);game.local_host_commands.set_process(false)
	await process_frame;await process_frame
	game.chat.hide()
	for i in 10:await process_frame
	await UI.click(self,game.steward.toggle)
	await UI.click(self,game.steward.setup_button)
	var accepted:=false;var captured:=false
	var evidence:String=OS.get_environment("HABITAT_DIRECTOR_EVIDENCE")
	for i in 1800:
		game._process(.5);game.local_host_commands._process(.5)
		var director:RefCounted=game.steward.body_director
		if not accepted and not director.batch.is_empty() and director.batch.step.action=="roast" and is_instance_valid(director.invitation_card) and director.invitation_card.visible:
			await process_frame;await process_frame
			var key:String=director.batch.key
			await UI.click(self,director.invitation_card.get_child(0).get_child(1));accepted=director.invited.get(key,false)
		var fire:RefCounted=game.world.barbecues["home.barbecue"].fireside
		if not captured and accepted and fire.steward_human_join and fire.jobs.size()>=5 and game.world.actors.human.activity=="fire_eat" and float(game.world.work.jobs.get("human",{}).get("time",0))>=1:
			game.resident_connections.modulate.a=0;game.steward.panel.modulate.a=0;game.action_dock.modulate.a=0;game.chat.hide()
			game.view.follow_player=false;game.view.follow_actor="";game.view.center=game.world.point(game.world.barbecues["home.barbecue"].station);game.view.queue_redraw()
			await process_frame
			game.resident_connections.hide();game.steward.panel.hide();game.action_dock.hide()
			RenderingServer.force_draw(false)
			root.get_texture().get_image().save_png(evidence.path_join("owner-shared-meal.png"));captured=true
		if captured and int(fire.state.get("current",{}).get("eaten",0))==5:break
		if i%40==0:await process_frame
	print("CAPTURE_OWNER ",{"accepted":accepted,"captured":captured,"invited":game.steward.body_director.invited,"meal":game.world.barbecues["home.barbecue"].fireside.state,"jobs":game.world.barbecues["home.barbecue"].fireside.jobs})
	check(accepted and captured and int(game.world.barbecues["home.barbecue"].fireside.state.get("current",{}).get("eaten",0))==5,"real mouse acceptance alone navigates human into the five-person real meal")
	game.steward.panel.modulate.a=1;game.steward.panel.show()
	await process_frame;await process_frame
	await UI.click(self,game.steward.toggle)
	await process_frame
	check(not game.steward.active and game.steward.body_director.invitation_for.is_empty(),"host stop revokes invitation binding")
	check(not is_instance_valid(game.steward.body_director.invitation_card),"host stop removes invitation widget")
	game.queue_free();await process_frame;quit(1 if failed else 0)

func wood_account(w:RefCounted)->int:
	var total:int=w.storage.count("wood")
	for actor in w.actors.values():total+=int(actor.carry.get("wood",0))
	for drop in w.drops.values():total+=int(drop.get("wood",0))
	for site in w.leisure.sites.values():total+=int(site.get("invested",0))
	for camp in w.barbecues.values():total+=int(camp.station.get("fuel_used",0))
	return total

func body_signature(row:Dictionary)->String:
	var bodies:Array=[]
	for actor in row.actors:bodies.append([actor.id,actor.position,actor.job.get("intent",""),actor.job.get("phase",""),actor.plan.get("current",{}),actor.held,actor.task.get("action","")])
	return JSON.stringify([row.goal,row.phase,bodies])
