extends Node
## Host opt-in coordinator. No saved world tasks, no second movement or inventory.
const Text=preload("res://scripts/localization.gd")
const Pool=preload("res://scripts/connection_session_pool.gd")
const DELEGATE=["assemble","plant","harvest","water","chop","gather","hand_over","fish","go_to","follow","unfollow","stop","home","stars","pool","swing","lounge","light","roast","invite","chess","sit","wander","hold_cat","pet_cat","build","place_flower","arrange_flowers","pick_flower","gift_flower","trade_flowers"]
var body_director=preload("res://scripts/steward_director.gd").new()
var next_planning:=0.0
var host:WeakRef
var game:Node:
	get:return host.get_ref()
var pool:Node
var speech_used:Dictionary={}
var speech_day:=0
var steward_speech:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/steward-speech.json"))
var archived_logs:Dictionary={}
var current_goal:Dictionary={}
var tutorial_planner=preload("res://scripts/tutorial_steward.gd").new()
var manager:=""
var active:=false
var queue:Array=[]
var timeline:Array=[]
var events:Array=[]
var recent_activity:Array=[]
var last_player_words:=""
var pending:Dictionary={}
# Reservations outlive a cancelled/semantic-error plan until exact complete usage.
var reservations:Dictionary={}
var reasons:Array=[]
var phase_key:=""
var hunger:Dictionary={}
var seen:Dictionary={}
var retry_used:=false
var rest_until:=0.0
var goal_failures:Dictionary={}
var original_followers:Array=[]
var local_switch:CheckButton
var local_only:=false
var low_queue_signature:=""
var panel:PanelContainer
var lines:VBoxContainer
var toggle:Button
var board:RichTextLabel
var log_view:RichTextLabel
var folded:=false
var director_camera:=false
var camera_until:=0.0
var camera_target:=""
var manual_camera:=false
var bubbles:Array=[]
var speech_after:Dictionary={}
var last_refresh:=""
var last_day:=0
var progress_at:=0.0
var progress_signature:=""
var watchdog_count:=0
var blocked_at:=0.0
var blocked_retry:=false
var duty_seen:Dictionary={}
var trace_next:=0.0
var trace_gate:=""
var trace_config:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/steward-host.json"))
var announced_day:=0
var summary_card:AcceptDialog
var owned_history_index:=0
var work_seen:Dictionary={}
var highlight:Label
var highlight_until:=0.0
var material_card:ConfirmationDialog
var log_dialog:AcceptDialog
var heading_button:Button
var camera_switch:CheckButton
var level_button:MenuButton
var fold_button:Button
var life=preload("res://scripts/steward_life.gd").new()
var level_choices:Node
func setup(source:Node)->void:
	host=weakref(source);pool=Pool.obtain(get_tree(),game.data_dir);last_day=game.world.days.day()
	local_only=bool(pool.settings.get_value("steward","local_only",true))
	director_camera=bool(pool.settings.get_value("camera","director",false))
	for fact in game.world.memories.records:seen[str(fact.get("id",JSON.stringify(fact)))]=true
	for fact in game.world.work.events:work_seen[str(fact.id)]=true
	Text.events.changed.connect(refresh_locale)
	build_board.call_deferred()
func build_board()->void:
	if game.island_hud==null:return
	panel=PanelContainer.new();panel.name="TodayArrangement";game.island_hud.upper_status.add_child(panel);
	if game.dark_ui!=null and game.dark_ui.entry_button.get_parent()==game.island_hud.upper_status:game.island_hud.upper_status.move_child(game.dark_ui.entry_button,2)
	panel.add_theme_stylebox_override("panel",game.island_hud.pixel_style())
	var board_scroll:=ScrollContainer.new();board_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;board_scroll.custom_minimum_size.y=140;panel.add_child(board_scroll)
	lines=VBoxContainer.new();lines.size_flags_horizontal=Control.SIZE_EXPAND_FILL;board_scroll.add_child(lines)
	var header:=HBoxContainer.new();lines.add_child(header)
	var heading:=Button.new();heading.focus_mode=Control.FOCUS_NONE;heading_button=heading;heading.clip_text=true;heading.set_meta("steward_key","steward.today");heading.text=Text.text("steward.today");heading.custom_minimum_size.x=100;heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(heading)
	level_button=MenuButton.new();level_button.flat=false;level_button.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND;level_button.action_mode=BaseButton.ACTION_MODE_BUTTON_RELEASE;level_button.focus_mode=Control.FOCUS_NONE;header.add_child(level_button)
	for title_text in ["Light","Standard","Deep","Ultra","Lifeblood"]:level_button.get_popup().add_item(title_text)
	level_choices=preload("res://scripts/reasoning_points.gd").new();add_child(level_choices);level_choices.hide()
	level_button.get_popup().id_pressed.connect(func(index):
		if not active:return
		level_choices.setup(game.data_dir,game.world.world_id,manager)
		level_choices.choose(preload("res://scripts/resident_intelligence_preferences.gd").LEVELS[index]);refresh())
	fold_button=Button.new();fold_button.focus_mode=Control.FOCUS_NONE;fold_button.pressed.connect(func():folded=not folded;refresh());header.add_child(fold_button)
	var logs:=Button.new();logs.focus_mode=Control.FOCUS_NONE;logs.set_meta("steward_key","watch.log");logs.text=Text.text("watch.log");logs.pressed.connect(show_log);header.add_child(logs)
	if game.memory_life!=null and is_instance_valid(game.memory_life.notice):game.memory_life.notice.reparent(header,false);game.memory_life.notice.set_meta("compact_mail",true);game.memory_life.notice.add_theme_font_size_override("font_size",12)
	toggle=Button.new();toggle.pressed.connect(choose);lines.add_child(toggle)
	local_switch=CheckButton.new();local_switch.text=preload("res://scripts/localization.gd").text("content.v06.text.5f837f6e371e54");local_switch.set_meta("steward_key","content.v06.text.5f837f6e371e54");local_switch.button_pressed=local_only;lines.add_child(local_switch)
	local_switch.toggled.connect(func(on):local_only=on;pool.settings.set_value("steward","local_only",on);pool.persist())
	board=RichTextLabel.new();board.bbcode_enabled=true;board.custom_minimum_size=Vector2(230,65);board.fit_content=false;board.add_theme_font_size_override("normal_font_size",12);lines.add_child(board)
	log_view=RichTextLabel.new();log_view.custom_minimum_size=Vector2(230,45);log_view.add_theme_font_size_override("normal_font_size",12);log_view.scroll_following=true;lines.add_child(log_view)
	var camera:=CheckButton.new();camera.focus_mode=Control.FOCUS_NONE;camera_switch=camera;camera.text=Text.text("steward.camera");camera.button_pressed=director_camera;camera.toggled.connect(func(on):director_camera=on;manual_camera=false;game.view.follow_player=true;game.view.peek_elapsed=0;pool.settings.set_value("camera","director",on);pool.persist());lines.add_child(camera)
	highlight=Label.new();game.island_hud.add_child(highlight);highlight.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP);highlight.offset_left=-250;highlight.offset_right=250;highlight.offset_top=100;highlight.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;highlight.hide()
	game.ui_scale.changed.connect(func(_index):refresh())
	get_viewport().size_changed.connect(refresh)
	refresh()
func ai_manager(id:String)->bool:
	return game.world.director.model_controlled(id) and pool.management(id)
func authorized(id:String)->bool:
	return id in Pool.IDS and game.world.actors.has(id) and (ai_manager(id) or (active and manager==id))
func candidates()->Array:return Pool.IDS.filter(func(id):return game.world.actors.has(id))
func choose()->void:
	if active:stop();return
	open_setup()
var setup_card:AcceptDialog
var setup_choice:OptionButton
var setup_status:Label
var setup_button:Button
var connecting_manager:=""
func open_setup(preferred:String="")->void:
	if preferred.is_empty():preferred=str(pool.settings.get_value("steward","last_manager","codex"))
	if is_instance_valid(setup_card):setup_card.queue_free()
	setup_card=AcceptDialog.new();setup_card.window_input.connect(func(event):
		if event is InputEventKey and event.pressed and event.keycode==KEY_SPACE:game._return_to_player();setup_card.set_input_as_handled()
	);game.add_child(setup_card);setup_card.title=Text.text("watch.manage")
	var body:=VBoxContainer.new();setup_card.add_child(body)
	setup_choice=OptionButton.new();body.add_child(setup_choice)
	for id in Pool.IDS:
		setup_choice.add_item(Text.resident(game.world,id))
		if id==preferred:setup_choice.select(setup_choice.item_count-1)
	setup_status=Label.new();body.add_child(setup_status)
	setup_button=Button.new();body.add_child(setup_button)
	setup_choice.item_selected.connect(func(_index):refresh_setup())
	setup_button.pressed.connect(func():
		connecting_manager=Pool.IDS[setup_choice.selected]
		finish_setup())
	refresh_setup();setup_card.popup_centered()
func refresh_setup()->void:
	var id:String=Pool.IDS[setup_choice.selected]
	setup_status.text="AI" if ai_manager(id) else (preload("res://scripts/localization.gd").source("content.v06.text.bf4ad761840fcd") if TranslationServer.get_locale().begins_with("zh") else "Local")
	setup_button.text=Text.text("steward.give")%Text.resident(game.world,id)
func finish_setup()->void:
	if connecting_manager.is_empty():return
	var id:String=connecting_manager
	connecting_manager=""
	if start(id) and is_instance_valid(setup_card):setup_card.hide()
func offer_connection()->void:
	if active or not connecting_manager.is_empty():return
	for id in Pool.IDS:
		if not pool.links.has(id) or pool.states.get(id,{}).get("state","")!="ready":continue
		if game._connection_light(id).state!="ready" or pool.settings.get_value("steward_prompt",id,false):continue
		pool.settings.set_value("steward_prompt",id,true);pool.persist()
		speak(id,Text.text("repair.offer"))
		var card:=ConfirmationDialog.new();card.exclusive=false;game.add_child(card);card.title=Text.resident(game.world,id);card.dialog_text=Text.text("repair.offer");card.get_ok_button().text=Text.text("repair.yes");card.get_cancel_button().text=Text.text("repair.later")
		card.confirmed.connect(func():
			if game._connection_light(id).state=="ready" and not active:pool.set_management(id,true);start(id);speak(id,Text.text("repair.accepted")))
		card.popup_centered();return
func permission_prompt(id:String,text:String)->bool:
	if text.begins_with(Text.source("memory.teach_prefix")) or text.begins_with("When I say "):return false
	var parsed:Dictionary=game.local_host_commands.parser.parse_command(game.world,text,[])
	if not parsed.get("ok",false) or not parsed.get("explicit_targets",false):return false
	if authorized(id) or not (text.contains(Text.source("content.steward.all")) or text.contains(Text.source("content.steward.everyone")) or text.to_lower().begins_with("everyone")):return false
	speak(id,Text.text("repair.ask_authority"));open_setup(id);return true
func start(id:String)->bool:
	if id not in candidates():return false
	if active:stop()
	life=preload("res://scripts/steward_life.gd").new();archived_logs.clear()
	body_director.reset()
	progress_at=game.world.forest.clock;progress_signature="";blocked_retry=false
	pool.settings.set_value("steward","last_manager",id);pool.persist()
	original_followers=game.world.activities.following.keys()
	manager=id;active=true;game.world.activities.squad_leader=id;retry_used=false;manual_camera=false;phase_key="";reasons=["enabled"];queue.clear();timeline.clear();body_director.begin(game);refresh();return true
func stop()->void:
	var prior:String=manager
	if is_instance_valid(material_card):material_card.queue_free()
	if game.autonomy!=null and not prior.is_empty():game.autonomy.interrupted(prior)
	body_director.end(game)
	active=false;game.world.activities.squad_leader="";game.world.director.steward_speech_pending=false;queue.clear();reasons.clear();camera_target=""
	if not pending.is_empty() and game._valid_link(game.links,prior):game.links[prior].cancel_turn()
	pending.clear()
	for who in game.intentions.plans.keys():
		if game.intentions.plans[who].get("sponsor","")==prior:game.intentions.cancel(who)
	if not prior.is_empty():speak(prior,Text.text("steward.handover."+(game.world.intelligence.tag(prior) if game.world.intelligence.tag(prior) in ["gentle","lively","laborious","quiet"] else "gentle")))
	for who in original_followers:game.world.activities.following[who]=true
	manager="";game.view.follow_actor="human";game.view.follow_player=true;refresh()
func player(text:String="")->bool:
	if not text.is_empty():last_player_words=text.left(300)
	manual_camera=true
	if not text.is_empty() and is_instance_valid(invitation):invitation.hide()
	if text in [Text.source("content.steward.leave"),Text.source("content.steward.decide"),"Leave it to you","You decide"]:
		var id:String=game.chat_actor
		if authorized(id):start(id);return true
	if is_instance_valid(material_card):material_card.queue_free()
	if not active:return false
	if text in [Text.source("content.steward.stop_short"),Text.source("content.steward.stop_command"),"Stop managing","stop managing"]:stop();return true
	if not text.is_empty():
		var command:Dictionary=game.local_host_commands.parser.parse_command(game.world,text,[])
		if command.get("ok",false):
			# Follow belongs to the original host formation. End the squad lease
			# before executing the exact selected recipients through that route.
			if command.get("action","") in ["follow","unfollow"]:stop();return false
			body_director.player_order(game,command.get("actor_ids",[game.chat_actor]));return false
	if not text.is_empty():body_director.player_order(game,Pool.IDS if game.group_chat else [game.chat_actor])
	# Speaking does not revoke another resident's plan or an in-flight model turn.
	# Explicit commands are resolved against their own actor IDs by the host.
	if not text.is_empty():
		reasons.append("player")
		if not pending.is_empty():pending["superseded"]=true
	return false
func assign(id:String,steps:Array,channel:String,approved_limit:int=0)->Dictionary:
	if active and not body_director.issuing and not body_director.paused.has(id):return game.world._error("director_owned")
	if not authorized(id) or (not ai_manager(id) and not (active and manager==id)):return game.world._error("management_required")
	if steps.is_empty() or steps.size()>5:return game.world._error("invalid_intent_count")
	var expanded:Array=[]
	for step in steps:
		if not valid_step(step):return game.world._error("invalid_intention")
		var assignments:Variant=step.get("assignments",[step])
		if not assignments is Array or assignments.is_empty() or assignments.size()>4:return game.world._error("invalid_assignments")
		for entry in assignments:
			if not valid_step(entry):return game.world._error("invalid_intention")
			var ids:Variant=entry.get("actor_ids",[id])
			if not ids is Array or ids.is_empty():return game.world._error("invalid_participant")
			if ids==["all"]:ids=Pool.IDS.duplicate()
			if ids.size()>4 or ids.any(func(who):return who not in Pool.IDS or not game.world.actors.has(who)) or ids.size()!=ids.reduce(func(unique,who):unique[who]=true;return unique,{}).size():return game.world._error("invalid_participant")
			var own:Dictionary=entry.duplicate(true);own.erase("actor_ids");own.erase("assignments")
			if own.keys().any(func(k):return k not in ["action","text","target_id","item_id","crop_id","x","y","region_id","guest_ids","replace"]):return game.world._error("invalid_intention")
			for who in ids:
				if active and not body_director.issuing and not body_director.paused.has(who):return game.world._error("director_owned")
				expanded.append({"id":who,"step":own.duplicate(true)})
	var grouped:Dictionary={}
	for entry in expanded:
		if not grouped.has(entry.id):grouped[entry.id]=[]
		if entry.step not in grouped[entry.id]:grouped[entry.id].append(entry.step)
		else:events.append({"day":game.world.days.day(),"time":game.world.days.within_day(),"kind":"plan_merged","text":"Merged duplicate: "+entry.id+" "+str(entry.step.action)})
	if grouped.values().any(func(items):return items.size()>5):return game.world._error("invalid_intent_count")
	if grouped.values().any(func(items):return items.slice(1).any(func(step):return step.action=="assemble")):return game.world._error("assemble_must_start_plan")
	var total:=0
	for who in grouped:
		for index in range(grouped[who].size()):total+=material_cost(who,grouped[who][index],grouped[who].slice(index+1))
	var threshold:int=int(JSON.parse_string(FileAccess.get_file_as_string("res://content/companions/host-commands.json")).confirmation_material_threshold)
	if not authorized(id) and total>threshold and total>approved_limit:
		confirm_materials(id,steps,channel,total)
		return game.world._error("confirmation_required")
	var account:Dictionary={"remaining":maxi(threshold,approved_limit),"ids":grouped.keys(),"source":id,"generation":game.world.session_generation}
	var assembly_ids:Array=grouped.keys().filter(func(who):return grouped[who][0].action=="assemble")
	var assembly_accepted:Array=[]
	if not assembly_ids.is_empty():
		var held:Dictionary={}
		for who in assembly_ids:
			if game.world.activities.held.has(who):held[who]=game.world.activities.held[who];game.world.activities.held.erase(who)
		preload("res://scripts/resident_brain.gd").team(game.world,assembly_ids,"assemble",func():
			game.local_host_commands.submit(Text.source("content.steward.command.assemble"),assembly_ids,channel,assembly_ids,assembly_ids,account)
			return game.local_host_commands.last_execution)
		assembly_accepted=game.local_host_commands.last_execution.get("actors",[])
		for who in held:game.world.activities.held[who]=held[who]
	var accepted:Array=[];var rejected:Dictionary={}
	for who in grouped:
		if who!=id and (game._resident_chat_busy(who) or game.world.director.routines[who].held or game.world.activities.held.get(who,false)):rejected[who]="busy";continue
		if who in assembly_ids and who not in assembly_accepted:rejected[who]="very_hungry" if game.world.hunger.rank(who)>=3 else "busy";continue
		var adopted:Dictionary={"job_id":game.world.work.jobs.get(who,{}).get("id","")} if who in assembly_accepted else {}
		var result:Dictionary=game.world.director.brains[who].mandate("steward",str(grouped[who][0].action),func():return game.intentions.submit(who,grouped[who],channel,adopted,id,account))
		if result.get("ok",false):
			accepted.append(who)
			if game.autonomy!=null:game.autonomy.scheduler.note_model_action(who)
		else:rejected[who]=result.get("error","blocked")
	for who in rejected:speak(id,Text.resident(game.world,who)+": "+failure_line(str(rejected[who])))
	camera_target=accepted[0] if not accepted.is_empty() else ""
	return {"ok":not accepted.is_empty(),"accepted":accepted,"rejected":rejected,"error":"no_available_residents" if accepted.is_empty() else ""}
func speak(id:String,text:String,channel:String="",narration:bool=false,kind:String="message")->void:
	if active and game.world.director.brains.has(id):
		game.world.director.brains[id].effect("steward","report",func():
			if game.world.director.say_local(id,text,"steward_report",0,0):game._record_chat(game.Channels.direct(id) if channel.is_empty() else channel,id,text,kind))
		return
	_speak_body(id,text,channel,narration,kind)
func _speak_body(id:String,text:String,channel:String="",narration:bool=false,kind:String="message")->void:
	var compact:String=text.replace("\n"," ")
	for start in range(0,mini(compact.length(),60),30):
		bubbles.append({"id":id,"text":compact.substr(start,30),"source":"local_rules" if kind=="steward_local" else "autonomy" if kind=="autonomy" else "model" if game.world.director.model_controlled(id) else "local_rules"})
		if bubbles.size()>64:bubbles.pop_front()
	deliver_bubbles()
	game._record_chat(game.Channels.direct(id) if channel.is_empty() else channel,id,compact,kind)
	if active and id==manager and narration:events.append({"day":game.world.days.day(),"time":game.world.days.within_day(),"kind":"narration","text":Text.resident(game.world,id)+": "+compact.left(60)})
func request_plan()->void:
	if game.world.forest.clock<next_planning:return
	if active and reasons.is_empty():reasons.append("periodic_preference")
	if active and (local_only or not ai_manager(manager)):
		if queue.is_empty() and not active:preset()
		return
	if game.playground!=null and not game.playground.kind.is_empty():plan_gate("playground");return
	if game.chat.visible and game.chat_input.has_focus():return
	if not manager.is_empty() and meal_locked(manager):plan_gate("meal_locked");return
	if not active or reasons.is_empty() or not pending.is_empty() or (is_instance_valid(material_card) and material_card.visible) or (is_instance_valid(game.local_host_commands.card) and game.local_host_commands.card.visible):return
	if not authorized(manager):stop();return
	var link:Variant=game.links.get(manager)
	if not is_instance_valid(link) or game._connection_light(manager).get("state","")!="ready":
		if queue.is_empty() and not active:preset()
		return
	if game.next_chat.has(manager) or not game.autonomy.pending.is_empty() or link.is_busy() or game.questions.has(manager) or game.group_questions.has(manager):return
	if not link.has_method("uses_intents") or not link.uses_intents():plan_gate("preference_protocol_unsupported");return
	link.helper_filename="intent_companion.py"
	var ledger:Dictionary=game.autonomy.scheduler.usage(manager)
	var maximum:int=pool.daily_limit(manager)
	var reserve:=64000
	if maximum>0 and int(ledger.tokens)+int(ledger.reserved)+reserve>maximum:
		if not local_only:speak(manager,Text.text("steward.limit"))
		local_only=true;reasons.clear();preset();return
	var key:String=Crypto.new().generate_random_bytes(12).hex_encode()
	var sources:Array=game.memory_books.ai_sources(manager,game.world.world_id,game.world.days.day(),game.Channels.direct(manager)).slice(-2)
	var card:Dictionary={"memory_sources":sources,"management":false,"self":{"id":manager,"personality":game.world.intelligence.tag(manager)},"candidates":body_director.candidates(game),"dialogue":{"channel_id":game.Channels.direct(manager),"recipient_ids":[manager]},"steward_request":{"reply_format":"speech, preference (one candidate id), reason; no actions or movement"}}
	trace("planning_request",{"card_bytes":JSON.stringify(card).to_utf8_buffer().size(),"candidates":card.candidates})
	next_planning=game.world.forest.clock+float(trace_config.planning_interval_seconds)
	ledger.reserved+=reserve
	if not game.autonomy.scheduler.preferences.save_accounting(manager,ledger):return
	pending={"id":manager,"key":key,"day":ledger.day,"reserve":reserve,"known":false,"candidates":card.candidates.duplicate(true),"started":game.world.forest.clock};reasons.clear()
	game.immediate_turns[manager]={"command":true,"plan":false,"steward":true,"scope":"direct","memory_sources":sources.duplicate(true),"memory_request":{}}
	link.send_message(preload("res://scripts/localization.gd").source("content.v06.text.efeafd8fe10a0f") if TranslationServer.get_locale().begins_with("zh") else "Choose one candidate and briefly say why, in character. No actions.",{"intent_card":card,"intelligence_level":"low"})
	if pending.is_empty():return
	pending.key=str(link.turn_key);game.immediate_turns[manager].turn_key=pending.key
	reservations[manager+":"+pending.key]=pending.duplicate(true)
	if not link.is_busy():
		var rejected:Dictionary=game.autonomy.scheduler.usage(manager)
		rejected.reserved=maxi(0,int(rejected.reserved)-reserve);game.autonomy.scheduler.preferences.save_accounting(manager,rejected)
		reservations.erase(manager+":"+pending.key);pending.clear();failure("planning_not_sent")
func result(id:String,event:Dictionary)->bool:
	var receipt:String=id+":"+str(event.get("turn_key",""))
	if event.kind=="usage" and event.get("complete",false) and reservations.has(receipt):
		var reserved:Dictionary=reservations[receipt]
		var ledger:Dictionary=game.autonomy.scheduler.usage(id)
		if ledger.day==reserved.day:
			ledger.reserved=maxi(0,int(ledger.reserved)-int(reserved.reserve))
			if not game.autonomy.scheduler.preferences.save_accounting(id,ledger):return false
		reservations.erase(receipt)
	if pending.is_empty() or id!=pending.id or event.get("turn_key")!=pending.key:return false
	if event.kind=="steward_input_profile":trace("planning_input_profile",event);return true
	if event.kind=="intent_result":
		if pending.get("superseded",false) or pending.get("timed_out",false):return true
		var preference:String=str(event.get("preference",""))
		var options:Array=pending.get("candidates",[])
		if not options.any(func(row):return row.id==preference):body_director.ai_ignored+=1;trace("ai_suggestion_ignored",{"preference":preference,"reason":"outside_candidates","planning":event.get("planning",[])})
		else:body_director.suggest(game,preference,str(event.get("reason","")))
		game.memory_books.accept_ai(id,game.world.world_id,"steward",event.get("memory",[]),game.immediate_turns.get(id,{}).get("memory_sources",[]),game.world.days.day(),{})
		speak(id,str(event.get("speech","")).left(120),"",true,"steward");return true
	if event.kind=="error":pending.clear();failure(str(event.get("message","error")))
	if event.kind=="state" and event.get("turnComplete",false):pending.clear()
	return false
func merge_plan(planning:Array)->Array:
	var result:Array=[];var unique:Dictionary={}
	for row in planning:
		var clean:Dictionary=row.duplicate(true);clean.intents=[]
		for step in row.intents:
			var key:String=str(row.phase)+JSON.stringify(step)
			if unique.has(key):
				events.append({"day":game.world.days.day(),"time":game.world.days.within_day(),"kind":"plan_merged","text":"Merged duplicate: "+str(step.action)})
				continue
			unique[key]=true;clean.intents.append(step.duplicate(true))
		if not clean.intents.is_empty():result.append(clean)
	return result
func valid_step(step:Variant)->bool:
	if not step is Dictionary or step.get("action","") not in DELEGATE:return false
	if step.keys().any(func(k):return k not in ["action","text","target_id","item_id","crop_id","x","y","region_id","guest_ids","replace","actor_ids","assignments","color","pattern","quantity","position"]):return false
	for field in ["text","target_id","item_id","crop_id","region_id","color","pattern"]:
		if step.has(field) and (not step[field] is String or step[field].length()>400):return false
	for field in ["x","y"]:
		if step.has(field) and (not game.world.catalog._number(step[field]) or absf(float(step[field]))>100000):return false
	if step.has("quantity") and (not game.world._integer(step.quantity) or step.quantity<1 or step.quantity>800):return false
	if step.has("position") and not game.world.catalog._pair(step.position):return false
	if step.has("replace") and not step.replace is bool:return false
	for field in ["actor_ids","guest_ids"]:
		if not step.has(field):continue
		var ids:Variant=step[field]
		if not ids is Array or ids.is_empty() or ids.size()>4:return false
		if field=="actor_ids" and ids==["all"]:continue
		if ids.any(func(who):return not who is String or who not in Pool.IDS) or ids.size()!=ids.reduce(func(unique,who):unique[who]=true;return unique,{}).size():return false
	if step.has("assignments"):
		if not step.assignments is Array or step.assignments.is_empty() or step.assignments.size()>4:return false
		for entry in step.assignments:
			if not entry is Dictionary or entry.has("assignments") or not valid_step(entry):return false
	return true
func sanitize_plan(value:Variant)->Array:
	var result:Array=[]
	if not value is Array:return result
	var aliases:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/steward-phase-aliases.json"))
	for row in value.slice(0,6):
		if not row is Dictionary:continue
		var phase:String=str(row.get("phase","now")).strip_edges().to_lower()
		phase=str(aliases.get(phase,phase))
		if phase not in ["now","morning","noon","afternoon","evening","dusk","night"]:continue
		var steps:Array=[]
		if not row.get("intents") is Array:continue
		for step in row.intents.slice(0,5):
			if valid_step(step):steps.append(step.duplicate(true))
			else:events.append({"day":game.world.days.day(),"time":game.world.days.within_day(),"kind":"plan_step_discarded","text":"Discarded invalid planning step"})
		if not steps.is_empty():result.append({"phase":phase,"reason":str(row.get("reason","")).left(120),"intents":steps})
	return result
func validate_plan(value:Variant)->bool:
	return not sanitize_plan(value).is_empty()
func failure(reason:String)->void:
	pending.clear();trace("planning_error",{"reason":reason})
	if not active:speak(manager,failure_line(reason))
	if not retry_used:
		retry_used=true
		if queue.is_empty() and not active:preset()
func preset()->void:
	if game.world.standard.active():
		var proposal:Dictionary=tutorial_planner.plan(game)
		if proposal.has("game"):
			current_goal=proposal.goal
			var result:Dictionary=preload("res://scripts/resident_brain.gd").team(game.world,Pool.IDS,"play",func():return game.playground.start(proposal.game))
			trace("game_start",result)
			if not result.get("ok",false):tutorial_planner.retry[proposal.goal.id]=game.world.forest.clock+float(trace_config.retry_seconds)
			return
		if not proposal.is_empty():
			current_goal=proposal.goal
			queue=[{"phase":"now","reason":proposal.reason,"intents":proposal.intents}]
			timeline=[{"phase":"now","reason":proposal.reason,"status":"pending","intents":proposal.intents.duplicate(true)}]
			return
	if game.world.standard.active() and game.world.days.day()==1 and game.world.standard.first_meal.is_empty() and not game.world.standard.ready("home.barbecue"):
		queue=[];timeline=[]
		for entry in [
			{"reason":Text.text("content.overnight.text.9e5e9b480d7a5b"), "intents":[{"action":"chop","actor_ids":["all"]}]},
			{"reason":Text.text("content.overnight.text.6745d2af88080a"), "intents":[{"action":"build","actor_ids":[manager],"target_id":game.world.standard.site_for("home.barbecue")}]},
			{"reason":Text.text("content.overnight.text.50fcba62e25972"), "intents":[{"action":"light","actor_ids":[manager],"target_id":"home.barbecue"},{"action":"roast","actor_ids":[manager],"target_id":"home.barbecue","item_id":"single:mushroom"}]}]:
			var row:Dictionary={"phase":"now","reason":entry.reason,"intents":entry.intents}
			queue.append(row);timeline.append({"phase":"now","reason":entry.reason,"status":"pending","intents":entry.intents.duplicate(true)})
		return
	if Pool.IDS.any(func(who):return game.world.hunger.rank(who)>=2):
		queue=[{"phase":"now","reason":Text.text("watch.hungry"),"intents":[{"action":"roast","actor_ids":[manager],"item_id":"single:mushroom"},{"action":"invite","actor_ids":[manager]}]}]
		timeline=[{"phase":"now","reason":Text.text("watch.hungry"),"status":"pending","intents":queue[0].intents.duplicate(true)}];return
	var checklist:Dictionary=island_checklist()
	var duties:Array=[]
	if int(checklist.stock.get("mushroom",0))<8:duties.append({"action":"gather","actor_ids":[manager]})
	if checklist.wood_low:duties.append({"action":"chop","actor_ids":[manager]})
	for farm in checklist.farms:
		if not farm.built:continue
		if int(farm.states.get("mature",0))>0:duties.append({"action":"harvest","target_id":farm.id,"actor_ids":[manager]})
		elif int(farm.states.get("empty",0))>0:duties.append({"action":"plant","target_id":farm.id,"actor_ids":[manager]})
	if not checklist.next_facility.is_empty() and not checklist.wood_low:duties.append({"action":"build","target_id":checklist.next_facility,"actor_ids":[manager]})
	duties=duties.filter(func(step):return game.world.forest.clock-float(duty_seen.get(JSON.stringify(step),-INF))>=float(trace_config.duty_cooldown_seconds))
	if not duties.is_empty():
		var step:Dictionary=duties[0]
		duty_seen[JSON.stringify(step)]=game.world.forest.clock
		queue=[{"phase":"now","reason":Text.text("content.overnight.text.55e1c8bfddbaab")+str(step.action),"intents":[step]}]
		timeline=[{"phase":"now","reason":queue[0].reason,"status":"pending","intents":[step.duplicate(true)]}];return
	if checklist.pens.any(func(pen):return pen.built and int(pen.fish)<mini(2,int(pen.capacity))) and not duty_seen.has("fish"):
		var shores:Array=game.world.fishing.nearby_shores(manager,1)
		if not shores.is_empty():
			duty_seen["fish"]=true
			var shore:Dictionary=shores[0]
			var steps:Array=[{"action":"go_to","region_id":shore.region_id,"x":shore.position[0],"y":shore.position[1],"actor_ids":[manager]},{"action":"fish","actor_ids":[manager]}]
			queue=[{"phase":"now","reason":Text.text("content.overnight.text.19738806daeb86"),"intents":steps}]
			timeline=[{"phase":"now","reason":queue[0].reason,"status":"pending","intents":steps.duplicate(true)}];return
	var action:String="wander"
	queue=[{"phase":"now","reason":Text.text("steward.local"),"intents":[{"action":action,"actor_ids":["all"]}]}]
	timeline=[{"phase":"now","reason":Text.text("steward.local"),"status":"pending","intents":queue[0].intents.duplicate(true)}]
func tick(delta:float)->void:
	if delta<=0:return
	finish_setup()
	if not pool.steward_requested.is_empty() and authorized(pool.steward_requested):
		start(pool.steward_requested);pool.steward_requested=""
	offer_connection()
	if is_instance_valid(setup_card) and setup_card.visible:refresh_setup()
	deliver_bubbles()
	for fact in game.world.work.events:
		if work_seen.has(str(fact.id)):continue
		work_seen[str(fact.id)]=true
		recent_activity.append({"at":game.world.forest.clock,"text":(str(fact.get("actor_id",""))+":"+str(fact.get("status",""))+":"+str(fact.get("message",""))).left(120)})
		recent_activity=recent_activity.filter(func(row):return game.world.forest.clock-float(row.at)<=1800).slice(-24)
		if fact.status!="completed":continue
		var id:String=str(fact.actor_id)
		# A newly committed team receipt makes the existing director eligible
		# to inspect its live batch now; it grants no new job/route authority.
		if active and not body_director.batch.is_empty() and id in body_director.batch.get("members",[]) and not body_director.paused.has(id):
			body_director.next_check=minf(body_director.next_check,game.world.forest.clock)
		var text:String=str(fact.get("message",""))
		var progress:Dictionary=fact.get("progress",{})
		if not progress.is_empty():text=Text.text("watch.wood_receipt")%[Text.resident(game.world,id),int(progress.trees_completed),int(progress.wood_stored)]
		game.memory_books.add(id,game.world.world_id,"work:"+str(fact.job_id)+":"+str(fact.id),"facts",text,{"canonical_work":fact.duplicate(true)},game.world.days.day(),"game",[id],game.world.forest.clock)
		events.append({"day":game.world.days.day(),"time":game.world.days.within_day(),"kind":"work_completed","text":text})
		# The director reports real goal completions; raw receipts remain in the log.
	if work_seen.size()>256:
		work_seen.clear()
		for fact in game.world.work.events:work_seen[str(fact.id)]=true
	for fact in game.world.memories.records:
		var key:String=str(fact.get("id",JSON.stringify(fact)))
		if seen.has(key):continue
		var described:Dictionary=game.world.memories._describe(fact)
		seen[key]=true;events.append({"day":game.world.days.day(),"time":game.world.days.within_day(),"kind":fact.get("kind",""),"text":str(described.get("summary",fact.get("kind","")))})
		if active and str(fact.kind) in ["signature_taste","first_shared_meal","fishing_catch"]:
			var peers:Array=fact.participants.filter(func(who):return who!="human")
			if not peers.is_empty():camera_target=peers[0]
			if is_instance_valid(highlight):highlight.text=str(described.get("summary",""));highlight.show();highlight_until=game.world.forest.clock+6
		if events.size()>256:events.pop_front()
	if seen.size()>1024:
		seen.clear()
		for fact in game.world.memories.records:seen[str(fact.get("id",JSON.stringify(fact)))]=true
	if is_instance_valid(highlight) and game.world.forest.clock>=highlight_until:highlight.hide()
	if last_day!=game.world.days.day():
		if active:show_summary(last_day)
		last_day=game.world.days.day()
	if not active:game.world.director.steward_speech_pending=false;refresh();return
	if not authorized(manager):stop();return
	if not pending.is_empty() and not pending.get("timed_out",false) and game.world.forest.clock-float(pending.started)>=120:
		pending.timed_out=true;trace("planning_timeout",{"key":pending.key,"elapsed":game.world.forest.clock-float(pending.started)})
	body_director.tick(game,delta)
	trace_residents()
	request_plan()
	game.view.follow_actor=manager if director_camera else "human"
	refresh()

var invitation:PanelContainer
var invitation_label:Label
var invitation_key:=""
var invitation_age:=0.0
var invitation_approved:Dictionary={}
func approve_next(row:Dictionary,delta:float)->bool:
	if active and (local_only or not ai_manager(manager)):return true
	if not row.intents.any(func(step):return step.action in ["fish","roast","stars","go_to","play"]):return true
	var key:String=JSON.stringify(row)
	if invitation_approved.has(key):return true
	if game.chat.visible or game.get_viewport().gui_get_focus_owner() is LineEdit:
		if is_instance_valid(invitation):invitation.hide()
		return false
	for child in game.get_children():
		if child is Window and child.visible and child!=summary_card:return false
	var w:RefCounted=game.world
	if w.actors[manager].region_id!=w.actors.human.region_id:return false
	if w.point(w.actors[manager]).distance_to(w.point(w.actors.human))>4:
		if not w.work.jobs.has(manager) and not w._routes.has(manager):game.intentions.submit(manager,[{"action":"go_to","target_id":"human"}],game.Channels.direct(manager),{},manager)
		return false
	if invitation_key!=key:
		if is_instance_valid(invitation):invitation.queue_free()
		invitation_key=key;invitation_age=0
		invitation=PanelContainer.new();game.island_hud.add_child(invitation)
		var body:=VBoxContainer.new();invitation.add_child(body)
		invitation_label=Label.new();body.add_child(invitation_label)
		var buttons:=HBoxContainer.new();body.add_child(buttons)
		var yes:=Button.new();yes.text=Text.text("content.overnight.text.f867f34178594f") if TranslationServer.get_locale().begins_with("zh") else "Okay";yes.focus_mode=Control.FOCUS_NONE;buttons.add_child(yes)
		var no:=Button.new();no.text=Text.text("content.overnight.text.59275de2fad284") if TranslationServer.get_locale().begins_with("zh") else "Not now";no.focus_mode=Control.FOCUS_NONE;buttons.add_child(no)
		yes.pressed.connect(func():
			if not active or invitation_key!=key:return
			invitation_approved[key]=true;invitation.hide()
			if invitation_walk(manager):
				# Only the exact invitation approach is relinquished by host acceptance.
				game.intentions.cancel(manager)
				if not game.world.work.jobs.has(manager):game.world._routes.erase(manager)
			if not queue.is_empty() and JSON.stringify(queue[0])==key:dispatch_next())
		no.pressed.connect(func():invitation_approved[key]=true;invitation.hide();queue=[{"phase":"now","reason":Text.text("watch.follow"),"intents":[{"action":"follow","actor_ids":["all"]}]}];timeline=[{"phase":"now","reason":Text.text("watch.follow"),"status":"pending","intents":queue[0].intents.duplicate(true)}];reasons.append("host_declined"))
	invitation.show()
	invitation_age+=delta
	var zh:bool=TranslationServer.get_locale().begins_with("zh")
	var action:String=str(row.intents[0].action)
	var activity:String=str(({"fish":Text.text("content.overnight.text.0147dc31ac1357"),"roast":Text.text("content.overnight.text.5691a276aac242"),"stars":Text.text("content.overnight.text.6dcbe3fe605ebc"),"go_to":Text.text("content.overnight.text.25eeed50fdb7dc")} if zh else {"fish":"fish","roast":"barbecue","stars":"watch stars","go_to":"that place"}).get(action,row.reason))
	invitation_label.text=(Text.text("content.overnight.text.806ee16ed5500c") if zh else "Shall I take everyone to %s next?")%activity+"  "+str(maxi(0,ceili(15-invitation_age)))
	invitation.position=game.view.screen(w.point(w.actors[manager]))+Vector2(-100,-130)
	if invitation_age>=15:
		invitation_approved[key]=true;invitation.hide();speak(manager,Text.text("content.overnight.text.a3eded935620db") if zh else "I'll arrange things for now, then~")
	return invitation_approved.has(key)
func archive_logs()->void:
	if manager.is_empty():return
	for event in events:
		var fingerprint:String=JSON.stringify(event).sha256_text()
		if archived_logs.has(fingerprint):continue
		archived_logs[fingerprint]=true
		if archived_logs.size()>512:archived_logs.erase(archived_logs.keys()[0])
		game.memory_books.add(manager,game.world.world_id,"steward-log:"+fingerprint,"facts",str(event.text),{"steward_log":true,"time":event.time,"kind":event.kind},int(event.day),"game",[manager],game.world.forest.clock)

func refresh()->void:
	archive_logs()
	if not is_instance_valid(board):return
	var ids:Array=candidates()
	heading_button.icon=game.island_hud.avatar_buttons[manager].icon if active and game.island_hud.avatar_buttons.has(manager) else null
	heading_button.expand_icon=true;heading_button.add_theme_constant_override("icon_max_width",24)
	heading_button.text=Text.text("repair.running")%Text.resident(game.world,manager) if active else Text.text("watch.manage")
	if active:heading_button.text+=" · "+("AI" if ai_manager(manager) else (preload("res://scripts/localization.gd").source("content.v06.text.bf4ad761840fcd") if TranslationServer.get_locale().begins_with("zh") else "Local"))
	level_button.visible=active and ai_manager(manager)
	if active:
		var names:Array=[Text.text("content.overnight.text.2b81dc69db797a"),Text.text("content.overnight.text.6bea77acefb364"),Text.text("content.overnight.text.e952e0cafb0e8a"),"Ultra",Text.text("content.overnight.text.22c2d7c2ee6997")] if TranslationServer.get_locale().begins_with("zh") else ["Light","Standard","Deep","Ultra","Lifeblood"]
		var index:int=preload("res://scripts/resident_intelligence_preferences.gd").LEVELS.find(game.resident_connections.preferences.preference(manager).level)
		level_button.text=(Text.text("content.overnight.text.fa173dc0680a2a") if TranslationServer.get_locale().begins_with("zh") else "Level: ")+str(names[maxi(0,index)])
		for i in names.size():level_button.get_popup().set_item_text(i,names[i])
	fold_button.text=">" if folded else "v"
	toggle.disabled=false;toggle.tooltip_text=""
	toggle.text=Text.text("repair.running")%Text.resident(game.world,manager) if active else Text.text("steward.give")%Text.resident(game.world,ids[0]) if ids.size()==1 else Text.text("steward.choose")
	if active:toggle.text+=" · "+("AI" if ai_manager(manager) else (preload("res://scripts/localization.gd").source("content.v06.text.bf4ad761840fcd") if TranslationServer.get_locale().begins_with("zh") else "Local"))
	board.visible=active and not folded;log_view.visible=active and not folded and not events.is_empty()
	toggle.visible=not folded
	board.custom_minimum_size.y=65 if active or not timeline.is_empty() else 26
	if is_instance_valid(camera_switch):camera_switch.visible=active
	var text:String=(Text.text("steward.current_manager")%Text.resident(game.world,manager)+"\n") if active else ""
	if timeline.is_empty():text+=Text.text("steward.empty" if active else "repair.no_manager")
	for row in timeline:
		var progress:Array=[]
		for who in row.get("actors",[]):
			for tracked in game.local_host_commands.tracked:
				if who in tracked.actors:progress.append(game.local_host_commands.progress_text(who,tracked))
		var line:String=("✓ " if row.status=="completed" else "▶ " if row.status=="running" else "· ")+Text.text("steward.phase."+str(row.phase))+" "+row.reason+" "+", ".join(row.get("actors",[]).map(func(who):return Text.resident(game.world,who)))+" "+" ".join(progress)+"\n"
		line=line.replace("[","[lb]")
		text+=("[color=#ffe3a3][b]"+line+"[/b][/color]") if row.status=="running" else ("[color=#92cba7]"+line+"[/color]") if row.status=="completed" else line
	if board.text!=text:board.text=text
	var logs:String=""
	for event in events.slice(-5):logs+="◆ [%02d:%02d] %s\n"%[int(event.time)/60,int(event.time)%60,event.text]
	if log_view.text!=logs:log_view.text=logs

func show_summary(day:int)->void:
	if is_instance_valid(summary_card):summary_card.hide();summary_card.queue_free()
	summary_card=AcceptDialog.new();summary_card.exclusive=false;summary_card.title=Text.text("watch.summary")%day;game.add_child(summary_card)
	var body:=VBoxContainer.new();summary_card.add_child(body)
	var text:=RichTextLabel.new();text.custom_minimum_size=Vector2(420,180);body.add_child(text)
	var summary_text:String=""
	for event in events:
		if event.day==day:summary_text+=event.text+"\n"
	# Narration is bounded separately from retained canonical work facts. A noisy
	# afternoon must not hide an earlier real delivery in the day's summary.
	for entry in game.memory_books.entries.values():
		if entry.day!=day or entry.world_id!=game.world.world_id or entry.source!="game" or entry.layer!="facts":continue
		var receipt:Dictionary=entry.params.get("canonical_work",{})
		if receipt.get("status")!="completed" or receipt.get("intent")!="gather_wood":continue
		var progress:Dictionary=receipt.get("progress",{})
		if progress.is_empty() or int(progress.get("wood_stored",0))<=0:continue
		var line:String=Text.text("watch.wood_receipt")%[Text.resident(game.world,str(receipt.actor_id)),int(progress.trees_completed),int(progress.wood_stored)]
		if line not in summary_text:summary_text+=line+"\n"
	var letters:Array=game.memory_books.entries.values().filter(func(entry):return entry.day==day and entry.layer=="letters" and entry.resident_id==manager)
	if not letters.is_empty():summary_text+=game.memory_books.render(letters.back())
	var pictures:=HBoxContainer.new();body.add_child(pictures)
	var photos:Array=[]
	for entry in game.memory_books.entries.values():
		if entry.day!=day or entry.photo_id.is_empty() or entry.photo_id in photos:continue
		photos.append(entry.photo_id)
		var path:String=game.memory_books.directory.path_join(entry.photo_id)
		if FileAccess.file_exists(path):
			var image:=preload("res://scripts/bundled_image.gd").read(path)
			if not image.is_empty():
				var picture:=TextureRect.new();picture.texture=ImageTexture.create_from_image(image);picture.custom_minimum_size=Vector2(130,82);picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;pictures.add_child(picture)
		if photos.size()>=3:break
	text.text=summary_text if not summary_text.is_empty() else Text.text("steward.empty")
	summary_card.popup_centered()

func reason_for(id:String)->String:
	for row in timeline:
		if row.status=="running" and id in row.get("actors",[]):return str(row.reason)
	return Text.content(str(game.world.actors[id].activity))

func failure_line(reason:String)->String:
	if reason in ["very_hungry","hungry"]:return Text.text("local.commands.hungry")
	if reason=="busy":return Text.text("local.commands.busy")
	if reason in ["missing_food","not_enough_wood","missing_materials"]:return Text.text("watch.missing")
	if reason=="confirmation_required":return Text.text("local.commands.awaiting")
	return Text.text("watch.blocked")

func meal_locked(id:String)->bool:
	for life in game.world.barbecues.values():
		var fire:RefCounted=life.fireside
		if fire.active() and not fire.circle_closed and fire.state.get("consent",false) and id in fire.state.get("invited",[]):return true
	return false
func missing_facility()->String:
	for site in game.world.leisure.sites.values():
		if not site.complete:return str(site.id)
	for template in game.world.their_island.config.templates:
		if not game.world.leisure.sites.values().any(func(site):return site.get("template_id","")==template):return str(template)
	return ""

func material_cost(id:String,step:Dictionary,future:Array=[])->int:
	var total:=0
	if step.action in ["plant","water"]:
		var text:String=str(step.get("text","plant" if step.action=="plant" else "water"))
		if step.has("crop_id") and not step.has("text"):text+=" "+str(step.crop_id)
		if step.has("target_id") and game.world.farms.farms.has(step.target_id):text+=" "+str(game.world.farms.farms[step.target_id].name)
		var parsed:Dictionary=game.local_host_commands.parser.parse_command(game.world,text,[id])
		if parsed.get("ok",false):
			var before:Array=game.local_host_commands.fallback_models.duplicate()
			game.local_host_commands.fallback_models=[id]
			var preview:Dictionary=game.local_host_commands.preview(parsed,[id])
			game.local_host_commands.fallback_models=before
			for row in preview.rows:
				for amount in row.get("seed_costs",{}).values():total+=int(amount)
	elif step.action in ["light","roast"]:
		var station:String=str(step.get("target_id",""))
		if station.is_empty():
			var best:float=INF
			for key in game.world.barbecues:
				var camp:Dictionary=game.world.barbecues[key].station
				var distance:float=game.world.point(camp).distance_squared_to(game.world.point(game.world.actors[id]))
				if camp.region_id==game.world.actors[id].region_id and game.world.standard.ready(key) and distance<best:station=key;best=distance
		if not game.world.barbecues.has(station):return 0
		var fire:RefCounted=game.world.barbecues[station].fireside
		if step.action=="light":return 1 if fire.burning() else 2
		if not fire.burning():total+=2
		var food:String=str(step.get("item_id","single:mushroom"))
		if food=="single:mushroom":return total
		var options:Array=fire.menu(id).filter(func(row):return row.id==food)
		if options.is_empty():return total
		var invitations:Array=future.filter(func(next):return next.action=="invite" and next.has("guest_ids"))
		var guests:Array=step.get("guest_ids",invitations[0].guest_ids if not invitations.is_empty() else Pool.IDS).duplicate()
		if id not in guests:guests.append(id)
		guests=guests.filter(func(who):return game.world.hunger.rank(who)<3 and not game.questions.has(who) and not game.group_questions.has(who) and fire.can_invite([who]).get("ok",false))
		var batches:int=mini(int(options[0].maximum),int(ceil(float(guests.size())/maxi(1,int(options[0].portions_per_unit)))))
		for amount in options[0].ingredients.values():total+=int(amount)*batches
	elif step.action=="build":
		var template:String=str(step.get("target_id",missing_facility()))
		if game.world.leisure.sites.has(template):
			var site:Dictionary=game.world.leisure.sites[template]
			total=maxi(0,game.world.leisure.cost(site)-int(site.get("invested",0)))
		elif game.world.library.artworks.has(template):total=preload("res://scripts/leisure_rules.gd").cost(game.world.library.artworks[template].recreation)
	return total
func confirm_materials(id:String,steps:Array,channel:String,total:int)->void:
	if is_instance_valid(material_card):material_card.queue_free()
	material_card=ConfirmationDialog.new();game.add_child(material_card)
	material_card.title=Text.text("steward.authority");material_card.dialog_text=Text.text("watch.material_confirm")%total
	var frozen:Array=steps.duplicate(true);var generation:int=game.world.session_generation
	material_card.confirmed.connect(func():
		if generation==game.world.session_generation and authorized(id):assign(id,frozen,channel,total))
	material_card.popup_centered()
func reserve_materials(account:Dictionary,id:String,cost:int,steps:Array,channel:String)->bool:
	if account.is_empty():return true
	if account.generation!=game.world.session_generation or not authorized(account.source) or id not in account.ids:return false
	if authorized(str(account.source)):return true
	if int(account.remaining)<cost:
		var frozen:Array=steps.duplicate(true)
		for step in frozen:step.actor_ids=[id]
		confirm_materials(account.source,frozen,channel,cost)
		return false
	account.remaining-=cost
	return true

func work_context()->Array:
	var result:Array=[]
	for id in Pool.IDS:
		var actor:Dictionary=game.world.actors[id]
		var trees:Array=game.world.objects.values().filter(func(tree):return tree.kind=="tree" and tree.region_id==actor.region_id and tree.status=="mature")
		trees.sort_custom(func(left,right):return game.world.point(left).distance_squared_to(game.world.point(actor))<game.world.point(right).distance_squared_to(game.world.point(actor)))
		result.append({"id":id,"name":Text.resident(game.world,id),"personality":game.world.intelligence.tag(id),"region_id":actor.region_id,"position":actor.position.duplicate(),"hunger":game.world.hunger.summary(id),"activity":actor.activity,"trees":trees.slice(0,3).map(func(tree):return {"id":tree.id,"position":tree.position.duplicate()}),"leisure_activities":game.world.resort.activities.values().map(func(activity):return {"id":activity.id,"kind":activity.kind,"position":activity.position.duplicate()}),"facilities":game.world.leisure.sites.values().slice(0,16).map(func(site):return {"id":site.id,"complete":site.complete}),"farms":game.world.farms.farms.values().filter(func(farm):return game.world.farms.ready(farm.id)).map(func(farm):return {"id":farm.id,"name":farm.name})})
	return result

func deliver_bubbles()->void:
	var delivered:Dictionary={}
	for speech in bubbles.duplicate():
		if delivered.has(speech.id) or game.world.forest.clock<float(speech_after.get(speech.id,0)):continue
		game.view.say(speech.text,speech.get("source","model"),speech.id);speech_after[speech.id]=game.world.forest.clock+8;delivered[speech.id]=true;bubbles.erase(speech)

func refresh_locale()->void:
	if not is_instance_valid(lines):return
	for control in _controls(lines):
		if control.has_meta("steward_key"):control.text=Text.text(str(control.get_meta("steward_key")))
	refresh()
func _controls(node:Node)->Array:
	var result:Array=[]
	for child in node.get_children():result.append(child);result.append_array(_controls(child))
	return result
func show_log()->void:
	if is_instance_valid(log_dialog):log_dialog.queue_free()
	log_dialog=AcceptDialog.new();game.add_child(log_dialog);log_dialog.title=Text.text("watch.log")
	var text:=RichTextLabel.new();text.custom_minimum_size=Vector2(420,260);text.scroll_following=true;log_dialog.add_child(text)
	var log_text:String=""
	for event in events:
		if event.day==game.world.days.day():log_text+="◆ [%02d:%02d] %s\n"%[int(event.time)/60,int(event.time)%60,event.text]
	text.text=log_text if not log_text.is_empty() else Text.text("steward.empty")
	log_dialog.popup_centered()

func invitation_walk(id:String)->bool:
	var plan:Dictionary=game.intentions.plans.get(id,{})
	var steps:Array=plan.get("steps",[])
	return id==manager and plan.get("sponsor","")==manager and steps.size()==1 and steps[0].get("action")=="go_to" and steps[0].get("target_id")=="human"

func dispatch_next()->void:
	if active:run_arrangements(0.0)

func mark_blocked(index:int,reason:String)->void:
	timeline[index].status="blocked";timeline[index].failure=reason;blocked_at=game.world.forest.clock
	speak(manager,failure_line(reason))

func watch_progress()->void:
	var signature:String=JSON.stringify(game.world.work.jobs.values().map(func(job):return [job.get("id",""),job.get("phase","")]))+JSON.stringify(game.intentions.plans.keys())
	if signature!=progress_signature:progress_signature=signature;progress_at=game.world.forest.clock
	if game.world.forest.clock-progress_at<60:return
	progress_at=game.world.forest.clock;watchdog_count+=1
	# Reviews preserve actor lanes, active jobs and not-yet-started model steps.
	if "no_progress_60s" not in reasons:reasons.append("no_progress_60s")

func island_checklist()->Dictionary:
	var w:RefCounted=game.world
	var farms:Array=[]
	for farm in w.farms.farms.values():
		var counts:Dictionary={}
		for plot in w.farms.farm_plots(farm.id):
			var stage:String=w.farms.stage(plot)
			counts[stage]=int(counts.get(stage,0))+1
		farms.append({"id":farm.id,"built":w.farms.ready(farm.id),"states":counts})
	return {"day":w.days.day(),"phase":w.days.phase().id,"weather":w.weather.current().get("id",""),"stock":w.storage.saved().items,"wood_low":int(w.available_items("human").get("wood",0))<10,"pens":w.fishing.snapshot(manager).pens.map(func(pen):return {"id":pen.id,"fish":pen.fish_count,"capacity":pen.capacity,"built":w.standard.ready(pen.id)}),"farms":farms,"unfinished_facilities":w.leisure.sites.values().filter(func(site):return not site.complete).map(func(site):return site.id),"next_facility":missing_facility(),"wishes":Pool.IDS.filter(func(id):return w.wishes.summary(id).get("active",false)).map(func(id):return {"id":id,"kind":w.wishes.summary(id).get("kind",""),"target":w.wishes.summary(id).get("target_id","")}),"hunger":Pool.IDS.map(func(id):return {"id":id,"rank":w.hunger.rank(id)})}

func run_arrangements(delta:float)->void:
	if game.world.forest.clock<rest_until:return
	var waiting:Dictionary={}
	for row in queue.duplicate():
		var matches:Array=timeline.filter(func(entry):return entry.phase==row.phase and entry.reason==row.reason and entry.intents==row.intents and entry.status!="completed")
		if matches.is_empty():continue
		var tracked:Dictionary=matches[0]
		var due:bool=row.phase in ["now",game.world.days.phase().id] or (row.phase=="noon" and game.world.days.phase().id=="afternoon") or (row.phase=="evening" and game.world.days.phase().id=="dusk")
		if not due:continue
		var grouped:Dictionary={}
		for step in row.intents:
			var ids:Array=step.get("actor_ids",[manager])
			if ids==["all"]:ids=Pool.IDS.duplicate()
			for who in ids:
				if not grouped.has(who):grouped[who]=[]
				var own:Dictionary=step.duplicate(true);own.actor_ids=[who];grouped[who].append(own)
		if not tracked.has("thought_at"):
			game.world.director.steward_speech_pending=true
			var thought:String=rhythm_line(manager,"init",str(row.reason).left(60))
			if not rhythm_say(manager,"init",str(row.reason).left(60)):continue
			game.world.director.steward_speech_pending=false
			tracked.thought_at=game.world.forest.clock
			trace("thought",{"actor":manager,"text":thought,"pause":clampf(float(trace_config.get("thought_pause_seconds",2)),1.5,3)})
			continue
		if game.world.forest.clock-float(tracked.thought_at)<clampf(float(trace_config.get("thought_pause_seconds",2)),1.5,3):continue
		if game.world.forest.clock-float(tracked.thought_at)>120 and tracked.get("launched",{}).is_empty():
			trace("arrangement_expired",{"reason":row.reason})
			if not current_goal.is_empty():tutorial_planner.retry[current_goal.id]=game.world.forest.clock+180
			queue.erase(row);continue
		var launched:Dictionary=tracked.get("launched",{})
		tracked.launched=launched
		var collective:bool=row.intents.any(func(step):return step.action in ["assemble","roast","invite","chess","stars"])
		var blocked:bool=grouped.keys().any(func(who):return waiting.has(who) or (game.intentions.plans.has(who) and not launched.has(who)))
		for who in grouped:
			if launched.has(who) or waiting.has(who):continue
			waiting[who]=true
			if collective and blocked:continue
			if game.intentions.plans.has(who) or not life.eligible(game,who,true):continue
			if collective and not approve_next(row,delta):continue
			var attempts:Dictionary=tracked.get("attempts",{})
			if game.world.forest.clock<float(attempts.get(who,0)):continue
			attempts[who]=game.world.forest.clock+5;tracked.attempts=attempts
			var acknowledgements:Dictionary=tracked.get("acknowledgements",{})
			if who!=manager and not acknowledgements.has(who):
				if not rhythm_say(who,"reply",str(row.reason)):continue
				acknowledgements[who]=true;tracked.acknowledgements=acknowledgements
			var result:Dictionary=assign(manager,grouped[who],game.Channels.direct(manager))
			if not result.ok:trace("assignment_rejected",{"actor":who,"reason":result.get("error",""),"steps":grouped[who]})
			if not result.ok:
				var failures:int=int(tracked.get("failure_count",0))+1;tracked.failure_count=failures
				if failures>=2:
					tracked.status=preload("res://scripts/localization.gd").source("content.v06.text.cc06059ac1bfcd");queue.erase(row)
					if not current_goal.is_empty():tutorial_planner.retry[current_goal.id]=game.world.forest.clock+float(trace_config.retry_seconds)
					trace("skipped",{"goal":current_goal,"reason":result.get("error",""),"attempts":failures});rhythm_say(manager,"missing",str(result.get("error","")));return
			if result.ok:
				trace("depart",{"actor":who,"elapsed":game.world.forest.clock-float(tracked.thought_at)})
				launched[who]=true;tracked.status="running"
				if not tracked.has("actors"):tracked.actors=[]
				tracked.actors.append(who)
		if not launched.is_empty() and launched.size()==grouped.size() and launched.keys().all(func(who):return not game.intentions.plans.has(who)):
			tracked.status="completed";queue.erase(row);progress_at=game.world.forest.clock
			rest_until=progress_at+float(trace_config.rest_seconds)
			trace("rest",{"until":rest_until,"goal":current_goal})
			if launched.keys().all(func(who):return not game.intentions.last_failure.has(who)):rhythm_say(manager,"close")
			elif not current_goal.is_empty():
				var key:String=str(current_goal.id)
				goal_failures[key]=int(goal_failures.get(key,0))+1
				if int(goal_failures[key])>=2:
					tutorial_planner.retry[key]=game.world.forest.clock+float(trace_config.retry_seconds)
					tracked.status=preload("res://scripts/localization.gd").source("content.v06.text.cc06059ac1bfcd");trace("skipped",{"goal":key,"attempts":goal_failures[key],"retry_at":tutorial_planner.retry[key]})


func awaiting_assignment(id:String)->bool:
	for row in queue:
		if row.phase not in ["now",game.world.days.phase().id]:continue
		for step in row.intents:
			if id in step.get("actor_ids",[manager]) or step.get("actor_ids",[])==["all"]:return true
	return false

# Diagnostic records are outside the world save and contain no prompts or credentials.
func trace(kind:String,details:Dictionary)->void:
	var directory:String=game.data_dir.path_join("steward-traces")
	DirAccess.make_dir_recursive_absolute(directory)
	var date:String=Time.get_date_string_from_system()
	var files:Array=[]
	for filename in DirAccess.get_files_at(directory):
		if filename.begins_with("steward-trace-") and filename.ends_with(".jsonl"):files.append(filename)
	files.sort()
	var filename:String="steward-trace-"+date+".jsonl"
	if filename not in files:files.append(filename);files.sort()
	while files.size()>3:DirAccess.remove_absolute(directory.path_join(files.pop_front()))
	var path:String=directory.path_join(filename)
	var file:=FileAccess.open(path,FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file==null:return
	file.seek_end()
	file.store_line(JSON.stringify({"kind":kind,"time":Time.get_datetime_string_from_system(),"clock":game.world.forest.clock,"day":game.world.days.day(),"mode":"AI" if active and ai_manager(manager) else "local","details":details}))
func plan_gate(reason:String)->void:
	if trace_gate==reason:return
	trace_gate=reason;trace("planning_blocked",{"reason":reason})
func trace_residents()->void:
	if game.world.forest.clock<trace_next:return
	trace_next=game.world.forest.clock+10
	var residents:Array=[]
	for who in Pool.IDS:
		var actor:Dictionary=game.world.actors[who]
		var task:Dictionary=body_director.tasks.get(who,{"action":"rest" if game.world.forest.clock<body_director.rest_until else "idle","source":preload("res://scripts/localization.gd").source("content.v06.text.0f98f12cf3aa27"),"start":game.world.forest.clock})
		residents.append({"id":who,"activity":actor.activity,"region":actor.region_id,"position":actor.position,"distance_to_manager":game.world.point(actor).distance_to(game.world.point(game.world.actors[manager])),"traveling":game.world._routes.has(who) or task.get("traveling",false),"goal":current_goal.get("id",""),"task":task,"source":task.source,"task_age":game.world.forest.clock-float(task.start)})
	trace("residents",{"manager":manager,"actors":residents})

func rhythm_line(id:String,kind:String,argument:String="")->String:
	if speech_day!=game.world.days.day():speech_used.clear();speech_day=game.world.days.day()
	var tag:String=game.world.intelligence.tag(id)
	var lang:String="en" if TranslationServer.get_locale().begins_with("en") else "zh"
	var options:Array=steward_speech.get(tag,steward_speech.gentle)[kind][lang]
	for template in options:
		var line:String=str(template)%argument if str(template).contains("%s") else str(template)
		if not speech_used.has(id+":"+line):return line
	return ""
func rhythm_say(id:String,kind:String,argument:String="")->bool:
	return game.world.director.brains[id].effect("steward","speech_"+kind,func():return _rhythm_say_body(id,kind,argument))
func _rhythm_say_body(id:String,kind:String,argument:String="")->bool:
	var line:String=rhythm_line(id,kind,argument)
	if line.is_empty():return true
	if not game.world.director.say_local(id,line,"steward_"+kind,0,0):return false
	speech_used[id+":"+line]=true
	trace("speech",{"actor":id,"category":kind,"text":line})
	return true
