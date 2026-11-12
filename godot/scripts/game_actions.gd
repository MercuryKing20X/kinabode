class_name GameActions
extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
const GESTURES := {"wave":("system.game_actions.wave"),"stretch":("system.game_actions.stretch")}
static func describe(world: RefCounted,actor_id: String) -> Dictionary:
	if not world.actors.has(actor_id):return {"ok":false,"error":"unknown_resident"}
	var busy: bool=world.work.jobs.has(actor_id) or world._routes.has(actor_id) or world.farms.active(actor_id) or world.projects.active(actor_id)
	var held: bool=not world.fishing.held(actor_id).is_empty()
	var near: bool=not world.fishing.shore(actor_id).is_empty()
	var work: bool=world.residents.supports(world.actors[actor_id],"fish")
	var chess: bool=world.gomoku.active(actor_id)
	var result: Dictionary={"ok":true,"contract_version":2,"self_actor_id":actor_id,"world_id":world.world_id,"actions":[
		{"id":"fish","name":LocalText.text("system.game_actions.fish"),"category":"functional","available":work and near and not busy and not held,"reason":LocalText.text("system.game_actions.go_to_the_coast_before_trying_to_fish") if not near else LocalText.text("system.game_actions.place_the_fish_you_are_holding_first") if held else LocalText.text("system.game_actions.finish_or_stop_your_current_action_first") if busy else "","arguments":{}},
		{"id":"move","name":LocalText.text("system.game_actions.walk"),"category":"functional","available":not world.work.jobs.has(actor_id),"arguments":{"x":"number","y":"number","region_id":"optional string"}},
		{"id":"stock_fish","name":LocalText.text("system.game_actions.place_in_a_pen"),"category":"functional","available":held and not busy,"arguments":{"fish_id":"owned pending fish","pen_id":"fishery id"}},
		{"id":"release_fish","name":LocalText.text("system.game_actions.release"),"category":"functional","available":held and not busy,"arguments":{"fish_id":"owned fish"}},
		{"id":"stop","name":LocalText.text("system.game_actions.stop_current_action"),"category":"functional","available":true,"arguments":{}},
		{"id":"gesture","name":LocalText.text("system.game_actions.wave_stretch"),"category":"daily","available":not busy and not held,"arguments":{"gesture":["wave","stretch"]}},
		{"id":"gomoku_read","name":LocalText.text("system.game_actions.read_the_gomoku_board"),"category":"functional","available":true,"arguments":{"site_id":"chess table id"}},
		{"id":"gomoku_join","name":LocalText.text("system.game_actions.confirm_invited_seat"),"category":"functional","available":chess,"arguments":{"site_id":"table id","match_id":"current match id","revision":"current board revision"}},
		{"id":"gomoku_move","name":LocalText.text("system.game_actions.play_a_gomoku_move"),"category":"functional","available":chess,"arguments":{"site_id":"table id","match_id":"current match id","revision":"current board revision","x":"integer 0–14","y":"integer 0–14","speech":"optional one truthful chess line, max30 characters"}},
		{"id":"gomoku_leave","name":LocalText.text("system.game_actions.pause_and_leave"),"category":"functional","available":chess,"arguments":{"site_id":"table id","match_id":"current match id","revision":"current board revision"}},
		{"id":"gomoku_resign","name":LocalText.text("system.game_actions.resign_from_gomoku"),"category":"functional","available":chess,"arguments":{"site_id":"table id","match_id":"current match id","revision":"current board revision"}},
		{"id":"journal_read","name":LocalText.text("system.game_actions.read_your_fish_journal"),"category":"functional","available":true,"arguments":{"species_id":"optional species id","color_id":"optional color id","size_id":"optional size id","status":"optional all / caught","offset":"optional integer","limit":"optional 1–32","revision":"required for subsequent pages"}}]}
	result.actions.append({"id":"island_propose","name":LocalText.text("theirs.card"),"category":"social","available":world.their_island.ready() and actor_id in world.their_island.config.presets,"arguments":{"template_id":world.their_island.config.templates.duplicate(),"x":"own territory coordinate","y":"own territory coordinate","name":"single line <=40","reason":"exact offered memory summary <=128"},"memory_reasons":world.their_island.memory_reasons(actor_id)})
	result.actions.append({"id":"resident_plan","name":LocalText.text("intent.plan"),"category":"functional","available":actor_id!="human" and not busy,"arguments":{"steps":"1-5 ordered own structured intentions; action plus validated target/item/crop/guest/coordinate fields"},"intention_actions":preload("res://scripts/resident_intentions.gd").ACTIONS.duplicate(),"requires":"current explicit human request or enabled budgeted autonomy; host validates every real step"})
	var plan: Dictionary=world.homestead.plans.get(actor_id,{})
	var live: bool=plan.get("status") in world.homestead.LIVE
	result.actions.append_array([
		{"id":"homestead_read","name":LocalText.text("system.game_actions.read_the_homestead_project"),"category":"functional","available":true,"arguments":{}},
		{"id":"homestead_start","name":LocalText.text("system.game_actions.collect_and_deliver_your_materials_in_batches"),"category":"functional","available":work and not busy and not live and not world.homestead.completed(),"arguments":{"site_id":"from homestead summary","wood_limit":"optional integer","crop_limit":"optional integer"}},
		{"id":"homestead_resume","name":LocalText.text("system.game_actions.explicitly_continue_your_project"),"category":"functional","available":work and live and not busy,"arguments":{"plan_id":"own current plan id","wood_limit":"optional integer","crop_limit":"optional integer"}},
		{"id":"homestead_build","name":LocalText.text("system.game_actions.build_once_your_materials_are_ready"),"category":"functional","available":work and live and not busy and world.homestead.funded(),"arguments":{"plan_id":"own current plan id"}},
		{"id":"homestead_cancel","name":LocalText.text("system.game_actions.cancel_your_paused_project"),"category":"functional","available":work and live and not busy,"arguments":{"plan_id":"own current plan id"}}])
	result.actions.append({"id":"propose","name":LocalText.text("system.game_actions.suggest_an_activity_and_wait_for_the_player"),"category":"social","available":actor_id!="human","arguments":{"text":"up to40 characters","activity":world.proposals.config.activities.keys(),"target_id":"existing target","ttl_seconds":"optional, at most600"}})
	result.actions.append({"id":"promise","name":LocalText.text("system.game_actions.register_your_future_promise"),"category":"social","available":actor_id!="human","arguments":{"action_type":world.promises.config.actions.keys(),"target_id":"existing target","day":"future DayCycle day","phase":"existing phase id","valid_seconds":"optional <=600"}})
	result.actions.append({"id":"promise_cancel","name":LocalText.text("system.game_actions.cancel_your_promise"),"category":"social","available":true,"arguments":{"promise_id":"own promise id"}})
	result.actions.append({"id":"give","name":LocalText.text("system.game_actions.give_items_you_are_actually_carrying"),"category":"social","available":not busy,"arguments":{"receiver_id":"nearby other resident","item_id":"own carried item","quantity":"positive whole count, receiver must have space"}})
	for action in ["invite_barbecue","start_project","open_chess"]:
		result.actions.append({"id":action,"name":action,"category":"functional","available":not busy,"arguments":{},"requires":"current explicit host instruction; engine derives all targets from original player text"})
	for action in ["plant","harvest","water","chop","gather","follow","unfollow","go_to","gather_at","hand_over","query_state"]:
		result.actions.append({"id":action,"name":action,"category":"functional","available":(not busy and (work or action not in ["plant","harvest","water","chop","gather"])) or action=="query_state","arguments":{"target_id":"real own authorized target"} if action in ["harvest","water","chop","gather"] else {"target_id":"real authorized plot","crop_id":"valid crop"} if action=="plant" else {"x":"number","y":"number","region_id":"optional string"} if action in ["go_to","gather_at"] else {}})
	for action in result.actions:
		if action.id in ["plant","harvest","water","chop","gather","fish","follow","unfollow","go_to","gather_at","hand_over","invite_barbecue","start_project","open_chess","stop","query_state"]:action.arguments["actor_ids"]="optional exact original host recipients; when present, omit other arguments; not allowed in autonomy"
	if world.gomoku.ai_active(actor_id):
		for action in result.actions:
			if action.id not in ["gomoku_read","gomoku_move","gomoku_join","gomoku_leave","gomoku_resign","stop"]:action.available=false;action.reason=LocalText.text("system.game_actions.a_match_is_running_pause_it_first")
	return result
static func gesture(world: RefCounted,actor_id: String,args: Dictionary) -> Dictionary:
	if args.keys().any(func(key):return key not in ["intent","gesture"]) or args.get("gesture") not in GESTURES:return world._error("invalid_gesture")
	if world.work.jobs.has(actor_id) or world._routes.has(actor_id) or world.farms.active(actor_id) or world.projects.active(actor_id):return world.work.fail("busy",LocalText.text("system.game_actions.finish_your_current_action_before_making_a_little"))
	world.work.serial+=1
	world.work.jobs[actor_id]={"id":"job-%s"%world.work.serial,"intent":"gesture","phase":"gesture_work","gesture":args.gesture,"time":0.0}
	world.revision+=1
	return {"ok":true,"status":"accepted","job_id":world.work.jobs[actor_id].id}
static func tick(world: RefCounted,actor_id: String,job: Dictionary,delta: float) -> void:
	world.actors[actor_id].activity="gesture_"+str(job.gesture);job.time+=delta
	if job.time>=1.8:world.work._finish(actor_id,LocalText.text("system.game_actions.a_little_gesture_is_finished"))
