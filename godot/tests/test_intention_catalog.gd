extends "res://tests/test_empowered_input.gd"
# DIRECTION 2026-11-11：“五座别墅只留一座”“泳池、躺椅、吊床等拿掉”“旧‘度假状态’取消”。
var rows:Array=[]
var base_dir:String
func make()->void:
	OS.set_environment("HABITAT_OPENING","showcase")
	game=load("res://scenes/main_v3.tscn").instantiate()
	game.dialogue_adapter_factory=func(_id,_scope):return IntentFake.new()
	root.add_child(game);current_scene=game;game.save_enabled=false;game.set_process(false)
	await process_frame;await process_frame
	game.world.director.set_controller("codex","model")
	game._ensure_link("codex");game.chat.hide();game.chat_input.release_focus()
func close()->void:
	game.queue_free();await process_frame
func run()->void:
	base_dir=OS.get_environment("HABITAT_DATA_DIR")
	var cases:Array=["wander","home","go_to","follow","unfollow","stop","pet_cat","sit","lounge","swing","stars","chop","gather","plant","build","water","harvest","hand_over","chess"]
	var chosen:String=OS.get_environment("HABITAT_INTENTION_CASES")
	if not chosen.is_empty():cases=cases.filter(func(action):return action in chosen.split(","))
	for action in cases:
		print("CATALOG_CASE ",action)
		OS.set_environment("HABITAT_DATA_DIR",base_dir.path_join(action));DirAccess.make_dir_recursive_absolute(base_dir.path_join(action))
		await make()
		var w:RefCounted=game.world
		var step:Dictionary={"action":action}
		if action=="go_to":step.target_id="human"
		if action=="build":step.target_id="outdoor-chair"
		if action in ["water","harvest"]:
			var plot:Dictionary={};var crop:String=""
			for farm in w.farms.farms.values():
				if not w.farms.ready(farm.id):continue
				for option in farm.crop_ids:
					if w.storage.count("seed."+option)<1:continue
					for candidate in w.farms.farm_plots(farm.id):
						if candidate.crop_id.is_empty():plot=candidate;crop=option;break
					if not plot.is_empty():break
				if not plot.is_empty():break
			check(not plot.is_empty(),"real initial seed and empty plot available")
			if not plot.is_empty():
				var planted:Dictionary=w.command("human",{"intent":"plant","target_id":plot.id,"crop_id":crop})
				print("PREP_CROP ",planted)
				check(planted.ok,"prepare actual dry crop")
				for i in range(2500):
					game._process(.1)
					if not w.work.jobs.has("human"):break
				if action=="harvest":
					check(w.command("human",{"intent":"water","target_id":plot.id}).ok,"prepare actual first water")
					for i in range(1000):
						game._process(.1)
						if not w.work.jobs.has("human"):break
					w.farms.advance(float(w.farms.crops[crop].seconds)+1)
				step.target_id=plot.farm_id

		if action=="hand_over":
			check(w.host_text_command("codex",{"intent":"gather_wood","tree_count":1}).ok,"prepare actual carried wood")
			for i in range(3000):
				w.advance(.1)
				if int(w.actors.codex.carry.get("wood",0))>0:break
			check(int(w.actors.codex.carry.get("wood",0))>0,"genuine pickup before delivery")
			w.work.stop("codex",false)
		if action=="chess":
			game.connection_ui_states["codex:direct"]="ready"
			game.resident_connections.preferences.choose("codex","medium")
			print("CHESS_PRE ",w.gomoku._available("codex")," ",w.gomoku._available("companion-2")," held=",w.director.routines.codex.held," routes=",w._routes.keys())
		var initial:Vector2=w.point(w.actors.codex)
		var result:Dictionary=game.intentions.submit("codex",[step],"direct:codex")
		var moved:=false
		for i in range(30):
			game._process(.1)
			if w.point(w.actors.codex)!=initial or w.actors.codex.activity not in ["idle","walking"]:moved=true
		var history:Array=game.intentions.history.duplicate(true)
		var completed:bool=history.any(func(row):return row.result=="completed")
		var failure:String=str(game.intentions.last_failure.get("codex",result.get("error","")))
		rows.append({"action":action,"accepted":result.ok,"started_within_3":moved or completed,"failure":failure})
		# DIRECTION 2026-11-11: remove the villas, loungers, hammocks and swings; cancel vacation state.
		if action in ["lounge","swing"]:
			check(not completed and failure in ["unknown_resort_activity","vacation_retired"],"retired vacation furniture is explicitly rejected "+action)
			check(not w.work.jobs.values().any(func(job):return job.get("intent")=="resort"),"retired action creates no resort job "+action)
		else:
			check(result.ok or completed,"catalog has real executable task "+action+" "+failure)
			check(moved or completed,"catalog starts actual motion/action by three seconds "+action+" "+failure)
		await close()
	var dir:String=base_dir
	FileAccess.open(dir.path_join("catalog-results.json"),FileAccess.WRITE).store_string(JSON.stringify(rows,"  "))
	print("CATALOG_ROWS ",rows)
	print("INTENTION_CATALOG ",checks," failed=",failed);quit(1 if failed else 0)
