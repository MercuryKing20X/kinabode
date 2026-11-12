extends "res://tests/test_intent_input.gd"
var evidence:Array=[]
var outputs:="/tmp/youqi-steward-evidence"
func shot(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	await process_frame;RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(outputs.path_join(name+".png"))
func run()->void:
	DirAccess.make_dir_recursive_absolute(outputs)
	# B: The host default is standard; AI preferences no longer force chores in a funded showcase.
	OS.set_environment("HABITAT_OPENING","standard")
	for boss in ["companion-2","npc.mira","npc.nora"]:
		root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
		game=load("res://scenes/main_v3.tscn").instantiate()
		game.dialogue_adapter_factory=func(_id,_scope):return IntentFake.new()
		root.add_child(game);game.save_enabled=false;game.set_process(false);game.memory_life.set_process(false)
		game.local_host_commands.set_process(false)
		await process_frame;await process_frame
		var w:RefCounted=game.world
		for id in game.steward.Pool.IDS:w.director.set_controller(id,"local");w.activities.release_follow(id)
		w.director.set_controller(boss,"model")
		if game.links.has(boss):game.links[boss].queue_free();game.links.erase(boss)
		game.dialogue_adapter_factory=func(_id,_scope):return IntentFake.new()
		game._ensure_link(boss)
		game.connection_ui_states[boss+":direct"]="ready";game.connection_history.set_value("connected",boss,1)
		game.steward.pool.set_management(boss,true)
		var link:Node=game.links[boss]
		game.steward.local_only=false
		game.chat.hide();game.chat_input.release_focus()
		check(game.steward.start(boss),"chosen connected partner can manage "+boss)
		var day:int=w.days.day();var seen_keys:Dictionary={};var replies:Array=[]
		var reached_stars:=false
		for i in range(15500 if boss=="npc.nora" else 1200):
			game._process(.1);game.local_host_commands._process(.1)
			if game.intentions.history.any(func(entry):return entry.action=="stars" and entry.result=="completed"):reached_stars=true
			# C: the provider stub must complete new speech-only game cues as a real provider does.
			if game.steward.pending.is_empty() and link.is_busy() and not link.sent.is_empty() and link.sent[-1].get("world",{}).get("intent_card",{}).has("playground_speech"):
				var speech_key:String=link.turn_key
				link._accept_event({"kind":"intent_result","turn_key":speech_key,"speech":"一起玩吧。","intents":[],"memory":[]})
				link._accept_event({"kind":"state","turn_key":speech_key,"state":"ready","turnComplete":true})
			if not game.steward.pending.is_empty():
				var key:String=game.steward.pending.key
				if not seen_keys.has(key):
					seen_keys[key]=true
					var words:String={"companion-2":"冲呀——大家去砍树！","npc.mira":"先把柴码好，再吃饭。","npc.nora":"……砍树。"}[boss]
					var phase:String=w.days.phase().id
					var anyone_hungry:bool=game.steward.Pool.IDS.any(func(who):return w.hunger.rank(who)>=2)
					var actions:Array=[{"action":"chop","actor_ids":["all"]}] if phase=="morning" and not anyone_hungry else [{"action":"stars","actor_ids":["all"]}] if phase=="night" and not anyone_hungry else [{"action":"roast","actor_ids":[boss],"item_id":"single:mushroom"},{"action":"invite","actor_ids":[boss]}]
					var plan:Array=[{"phase":"now","reason":words,"intents":actions},{"phase":"now","reason":"一起吃饭","intents":[{"action":"roast","actor_ids":[boss],"item_id":"single:mushroom"},{"action":"invite","actor_ids":[boss]}]},{"phase":"night","reason":"一起看星星","intents":[{"action":"stars","actor_ids":["all"]}]}]
					link._accept_event({"kind":"intent_result","turn_key":key,"speech":words,"preference":game.steward.pending.candidates[0].id,"intents":[],"planning":plan})
					link._accept_event({"kind":"usage","turn_key":key,"total_tokens":100,"input_tokens":80,"output_tokens":20,"complete":true})
					link._accept_event({"kind":"state","turn_key":key,"state":"ready","turnComplete":true})
					replies.append({"key":key,"planning":plan,"phase":phase,"candidates":link.sent[-1].world.intent_card.candidates.duplicate(true)})
					if replies.size()==1:await shot(boss+"-arrangement")
			if i%200==0:await process_frame
			if w.days.day()>day:break
		game._process(.01)
		check(replies.size()>=(3 if boss=="npc.nora" else 1) and replies.all(func(reply):return not reply.candidates.is_empty()),"bounded candidate planning over real game day "+boss)
		check(w.work.events.any(func(e):return e.get("status")=="completed" and e.get("actor_id")==boss),"manager does actual work "+boss)
		check(game.steward.events.size()>0,"log observes true committed facts "+boss)
		if boss=="npc.nora":
			check(w.memories.records.any(func(fact):return fact.kind=="shared_barbecue"),"actual shared barbecue facts over the day")
			check(reached_stars,"night stars physically reached")
			check(is_instance_valid(game.steward.summary_card),"day ends with summary card "+boss)
			var summary_label:RichTextLabel=game.steward.summary_card.get_child(0).get_child(0)
			check(summary_label.get_parsed_text().contains("木材已入库"),"summary visibly retains actual wood receipts instead of empty fallback")
			await shot(boss+"-summary")
			if is_instance_valid(game.steward.summary_card):game.steward.summary_card.hide()
		if boss=="npc.nora":
			for size in [Vector2i(960,640),Vector2i(1280,800)]:
				root.size=size
				for level in range(4):
					game.ui_scale.set_level(level,false);await process_frame;await process_frame
					check(game.steward.panel.get_global_rect().end.y<game.island_hud.primary_actions.get_global_rect().position.y,"board and bottom do not overlap")
					await shot("layout-"+str(size.x)+"-"+str(level))
			game.action_dock.toggle_menu();await shot("lightning-four-tabs");game.action_dock.menu.hide()
			for language in ["zh","en"]:
				game.LocalText.select(game.data_dir,language)
				for size in [Vector2i(960,640),Vector2i(1280,800)]:
					root.size=size
					for level in range(4):
						game.ui_scale.set_level(level,false);await process_frame;await process_frame
						check(root.get_visible_rect().encloses(game.journey.map_button.get_global_rect()),"map stays inside viewport "+language+str(level))
						check(game.steward.panel.get_global_rect().end.y<game.island_hud.primary_actions.get_global_rect().position.y,"board and bottom separated "+language+str(level))
						check(not game.journey.bar.visible or game.journey.bar.get_global_rect().end.y<=game.steward.panel.get_global_rect().position.y,"tutorial sits above arrangement "+language+str(level))
						await shot("final-layout-"+language+"-"+str(size.x)+"-"+str(level))
			game.LocalText.select(game.data_dir,"zh")
		evidence.append({"manager":boss,"replies":replies,"timeline":game.steward.timeline.duplicate(true),"events":game.steward.events.duplicate(true),"calls":replies.size()})
		check(game.steward.player("别管了") and not game.steward.active,"explicit stop revokes management session "+boss)
		game.queue_free();await process_frame
	await formal_layouts()
	var file:=FileAccess.open(outputs.path_join("day-results.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"evidence":evidence,"checks":checks,"failed":failed},"\t"));file.close()
	print("STEWARD_DAY ",checks," failed=",failed);quit(1 if failed else 0)

func formal_layouts()->void:
	OS.set_environment("HABITAT_OPENING","standard")
	game=load("res://scenes/main_v3.tscn").instantiate()
	game.dialogue_adapter_factory=func(_id,_scope):return IntentFake.new()
	root.add_child(game);game.save_enabled=false;game.set_process(false);game.memory_life.set_process(false)
	await process_frame;await process_frame
	game.chat.hide();game.journey._process(0)
	check(game.world.standard.active() and game.journey.bar.visible,"formal tutorial really active in layout evidence")
	for language in ["zh","en"]:
		game.LocalText.select(game.data_dir,language)
		for size in [Vector2i(960,640),Vector2i(1280,800)]:
			root.size=size
			for level in range(4):
				game.ui_scale.set_level(level,false);game.journey._process(0);await process_frame;await process_frame
				check(game.journey.bar.get_global_rect().end.y<=game.steward.panel.get_global_rect().position.y,"visible formal tutorial above arrangement")
				check(game.steward.panel.get_global_rect().end.y<game.island_hud.primary_actions.get_global_rect().position.y,"formal arrangement above input")
				await shot("formal-layout-"+language+"-"+str(size.x)+"-"+str(level))
	game.LocalText.select(game.data_dir,"zh");game.queue_free();await process_frame
