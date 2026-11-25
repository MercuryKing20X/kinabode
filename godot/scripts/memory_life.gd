extends Node
const Text=preload("res://scripts/localization.gd")
var missed_wishes_provider:Callable
var owner_ref:WeakRef
var game:Node:
	get:return owner_ref.get_ref()
var books:RefCounted:
	get:return game.memory_books
var world:RefCounted:
	get:return game.world
var next_speech_check:Dictionary={}
var elapsed:=0.0
var day_seen:=0
var evening_seen:=0
var attempts:Dictionary={}
var photo_busy:=false
var photo_queue:Array=[]
var photo_seen:Dictionary={}
var photo_config:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/memory-books.json"))
var maintenance:Dictionary={}
var letter_retries:Dictionary={}
var state_path:=""
var persistent:Dictionary={}
var goal_card:PanelContainer
var goal_card_id:=""
var notice:Button
func setup(host:Node)->void:
	owner_ref=weakref(host);day_seen=world.days.day()
	# Baseline existing facts on reload: never photograph old history as a new event.
	for e in books.entries.values():photo_seen[e.id]=true
	world.director.local_speech_window.connect(speak)
	world.farms.watered.connect(water_help)
	world.fishing.shared_catch.connect(fishing_together)
	state_path=books.directory.path_join("maintenance.json")
	var previous:Variant=books.read_json(state_path)
	if previous is Dictionary:persistent=previous
	if day_seen>1:
		for id in world.director.routines:attempts[id]={"day":day_seen-1,"pending":true}
	notice=Button.new()
	notice.name="MailboxNotice"
	notice.position=Vector2(16,170)
	notice.icon=mail_icon()
	notice.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	notice.hide()
	notice.pressed.connect(func():game.book_panel.open();game.book_panel.tabs.select(2);game.book_panel.refresh())
	game.add_child(notice)

static func mail_icon()->Texture2D:
	var image:=Image.create(20,16,false,Image.FORMAT_RGBA8)
	var ink:=Color("e8d6aa")
	for box in [Rect2i(1,2,18,2),Rect2i(1,12,18,2),Rect2i(1,2,2,12),Rect2i(17,2,2,12)]:
		image.fill_rect(box,ink)
	for offset in range(7):
		var y:=4+offset/2
		image.set_pixel(3+offset,y,ink)
		image.set_pixel(16-offset,y,ink)
	return ImageTexture.create_from_image(image)

func idle(id:String)->bool:
	return world.director.routines.has(id) and world.director.state(id).effective in ["idle","local_rules","following"] and not world.activities.blocked(id) and not world.work.jobs.has(id) and not world._routes.has(id) and not game.questions.has(id) and not game.group_questions.has(id)
func _process(delta:float)->void:
	elapsed+=delta
	if elapsed<1:return
	elapsed=0
	var letters:int=books.entries.values().filter(func(e):return e.layer=="letters").size()
	notice.text=str(letters)
	notice.tooltip_text=Text.text("memory.new_mail")
	notice.accessibility_name=notice.tooltip_text+" "+notice.text
	notice.visible=letters>0
	for e in books.entries.values():
		if photo_seen.has(e.id):continue
		photo_seen[e.id]=true
		if e.layer=="facts" and e.source=="game":
			var kind:String=e.params.get("legacy",{}).get("kind","")
			if kind in photo_config.photo_kinds and (kind!="gift_flower" or e.params.get("legacy",{}).get("first",false)):
				var previous:Array=books.list_for(e.resident_id,"facts").filter(func(other):return other.id!=e.id and not other.photo_id.is_empty() and other.params.get("legacy",{}).get("kind","")==kind and photo_subject(other)==photo_subject(e))
				if kind=="anniversary" or previous.is_empty():photo_queue.append(e.id)
	if not photo_busy and not photo_queue.is_empty():capture(photo_queue.pop_front())
	# This evening's pages are derived from retained, current-world facts. No
	# backfill for missing days, no new model wakeup, and no gameplay side effect.
	if world.days.phase().id=="night" and evening_seen!=world.days.day():
		evening_seen=world.days.day()
		write_evening_pages()
	if world.days.day()>day_seen:
		var ended:int=world.days.day()-1;day_seen=world.days.day()
		for id in world.director.routines:attempts[id]={"day":ended,"pending":true}
	if is_instance_valid(goal_card):
		if not books.entries.has(goal_card_id) or books.entries[goal_card_id].params.get("goal_status","")!="offered" or int(books.entries[goal_card_id].params.get("expires",0))<world.days.day():goal_card.queue_free();goal_card=null;goal_card_id=""
	if not is_instance_valid(goal_card):
		var offers:Array=books.entries.values().filter(func(e):return e.world_id==world.world_id and e.params.get("goal_status","")=="offered" and e.params.get("expires",0)>=world.days.day())
		if not offers.is_empty():show_goal_card(offers[0].id)
	for id in world.director.routines:
		anniversary(id)
		goals(id)
		if attempts.get(id,{}).get("pending",false) and idle(id):request_daily(id)
func sources(id:String,day:int=0)->Array:return books.ai_sources(id,world.world_id,day)
func request_daily(id:String)->bool:
	if not idle(id) or game.world.director.routines[id].held:return false
	if not world.director.model_controlled(id):
		var ended:int=int(attempts[id].day);attempts[id].pending=false
		books.write_local_diary(id,world.world_id,ended,world.forest.clock)
		return false
	if game.resident_connections.preferences.preference(id).level=="low":return false
	if not game._valid_link(game.links,id):return false
	var connection:Node=game.links[id]
	# Existing suite fixtures may configure a native controller without a fake link.
	# Automatic composition must never turn that fixture configuration into a live call.
	if (OS.get_environment("HABITAT_TEST_SUITE")=="1" or game.data_dir.get_file().begins_with("youqi-test-")) and OS.get_environment("HABITAT_LIVE_TEST")!="1" and connection.get_script()==preload("res://scripts/companion_link.gd"):return false
	if not connection.has_method("uses_intents") or not connection.uses_intents() or connection.is_busy():return false
	if game._valid_link(game.group_links,id) and game.group_links[id].is_busy():return false
	var day:int=int(attempts[id].day);attempts[id].pending=false
	var attempt_key:String=world.world_id+":"+id+":"+str(day)
	var rewriting:bool=bool(attempts[id].get("rewrite",false))
	if persistent.has(attempt_key) and not rewriting:return false
	persistent[attempt_key]=true
	if not books.atomic(state_path,persistent):return false
	if game.autonomy==null:return false
	var scheduler:RefCounted=game.autonomy.scheduler
	var policy:Dictionary=scheduler.policy_for(id);var ledger:Dictionary=scheduler.usage(id)
	var reservation:int=int(JSON.parse_string(FileAccess.get_file_as_string("res://bridge/codex_high_budget.json")).chat_turn_tokens) if game.resident_connections.preferences.preference(id).level=="high" else 64000
	if reservation<=0 or (int(policy.daily_tokens)>0 and int(ledger.tokens)+int(ledger.reserved)+reservation>int(policy.daily_tokens)):return false
	var supplied:Array=sources(id,day)
	if supplied.is_empty():return false
	var rebuild:Array=books.dirty_daily.values().filter(func(e):return e.resident_id==id and e.world_id==world.world_id).slice(-2).map(func(e):return int(e.day))
	for old_day in rebuild:
		for source in sources(id,old_day):
			if not supplied.any(func(e):return e.id==source.id):supplied.append(source)
	var life:bool=game.resident_connections.preferences.preference(id).level=="lifeblood"
	var weekly:bool=life and day%7==0
	if weekly:
		for prior in range(maxi(1,day-6),day):
			for source in sources(id,prior):
				if not supplied.any(func(e):return e.id==source.id):supplied.append(source)
	var request:Dictionary={"weekly":weekly,"rebuild_days":rebuild,"day":day,"portrait":not books.list_for(id,"about_you").any(func(e):return e.world_id==world.world_id and e.params.get("kind","")=="portrait" and int((e.day-1)/7)==int((world.days.day()-1)/7))}
	ledger.reserved+=reservation
	if not scheduler.preferences.save_accounting(id,ledger):return false
	maintenance[id]={"reserve":reservation,"reported":0,"day":scheduler.day_key(),"complete":false}
	connection.helper_filename="intent_companion.py"
	game.immediate_turns[id]={"text":"","command":false,"result":{},"maintenance":true,"memory_sources":supplied.map(func(e):return e.id),"memory_request":request}
	var letter_prompt:String="Write today's grounded letter and daily summary; optionally update your portrait. "+Text.source("memory.letter_voice_instruction")+" Do not include citation IDs, quote IDs, notes or system words. No speech or actions."
	if weekly:letter_prompt+=" Also write one daily-layer memory with kind weekly summarizing these seven game days, grounded in supplied sources."
	if life:
		request["life_day"]=true
		letter_prompt+=" Also return life_day={dream:short dream,today:today in your own words,self:who you are (self only when day is a multiple of three)}. The self string must cover all four: your authored personality; recent genuine likes from supplied facts; your feelings toward the human; and who you hope to become. If recent likes are unknown, admit that; never invent shared history. Subjective dream, never historical fact. Ground it in supplied sources."
	if life:letter_prompt+=" Be attentive and specific about your feelings, anniversaries and what you know about the player."
	if rewriting:letter_prompt+=" The previous letter was rejected for system terminology. Rewrite the letter once in your own voice, with no source metadata in its prose."
	connection.send_message(letter_prompt,{"source":"host_memory_maintenance","intent_card":{"self":{"id":id,"personality":world.intelligence.tag(id)},"memory":books.card(id,"", "direct:"+id,game.resident_connections.preferences.preference(id).level),"memory_sources":supplied,"memory_request":request,"forget_revision":JSON.stringify(books.deleted).sha256_text()},"intelligence_level":game.resident_connections.preferences.preference(id).level})
	game.immediate_turns[id].turn_key=connection.turn_key
	if not connection.is_busy():
		ledger=scheduler.usage(id);ledger.reserved=maxi(0,int(ledger.reserved)-reservation);scheduler.preferences.save_accounting(id,ledger);maintenance.erase(id)
	return connection.is_busy()
func anniversary(id:String)->void:
	var first:Array=books.list_for(id,"facts").filter(func(e):return e.world_id==world.world_id and e.day>0)
	if first.is_empty():return
	var kinds:Dictionary={}
	for fact in first:
		var kind:String=str(fact.params.get("legacy",{}).get("kind",""))
		if not kind.is_empty() and (not kinds.has(kind) or fact.day<kinds[kind].day):kinds[kind]=fact
	for kind in kinds:
		var fact:Dictionary=kinds[kind];var elapsed_days:int=world.days.day()-int(fact.day)
		if elapsed_days>0 and elapsed_days%365==0:books.add(id,world.world_id,"anniversary:"+kind+":"+str(elapsed_days),"facts","memory.event_anniversary",{"days":elapsed_days,"memory":books.render(fact),"source_ids":[fact.id],"legacy":{"kind":"anniversary"}},world.days.day(),"game",["human",id],world.forest.clock)
	var since:int=int(first.map(func(e):return e.day).min());var age:int=world.days.day()-since+1
	if age not in [7,30,365] and (age<=0 or age%365!=0):return
	var event:String="anniversary:"+str(age)
	books.add(id,world.world_id,event,"facts","memory.anniversary",{"days":age,"legacy":{"kind":"anniversary"}},world.days.day(),"game",["human",id],world.forest.clock)
func speak(id:String)->void:
	if not world.director.model_controlled(id):return
	if not idle(id) or not world.director.memory_reminders.eligible(id):return
	if world.director.time<float(next_speech_check.get(id,0)):return
	next_speech_check[id]=world.director.time+float(world.director.memory_reminders.config.check_interval)
	if world.weather.current().get("id","")=="rain":
		for note in books.list_for(id,"about_you"):
			if not books.render(note).contains(Text.source("memory.rain_word")) and not books.render(note).to_lower().contains("rain"):continue
			if note.params.get("rain_spoken_day",0)==world.days.day():continue
			if world.director.say_local(id,Text.text("memory.rain_recall").replace("{memory}",books.render(note)),"memory_reminder",float(world.director.memory_reminders.config.personal_gap),float(world.director.memory_reminders.config.village_gap)):
				note.params.rain_spoken_day=world.days.day();books.atomic(books.directory.path_join(note.id+".entry.json"),note);books.entries[note.id]=note
			return
	for e in books.list_for(id,"facts"):
		if e.world_id!=world.world_id or e.day!=world.days.day() or not e.event_id.begins_with("anniversary:") or e.params.get("spoken",false):continue
		if world.director.say_local(id,books.render(e),"memory_reminder",float(world.director.memory_reminders.config.personal_gap),float(world.director.memory_reminders.config.village_gap)):
			e.params.spoken=true;books.atomic(books.directory.path_join(e.id+".entry.json"),e);books.entries[e.id]=e
		return
func capture(id:String,play_photo:bool=false)->void:
	if not books.entries.has(id) or DisplayServer.get_name()=="headless":return
	var entry:Dictionary=books.entries[id]
	var photos:Array=[]
	for e in books.entries.values():
		if e.world_id==world.world_id and e.day==entry.day and not e.photo_id.is_empty() and e.photo_id not in photos:photos.append(e.photo_id)
	var first_rose:bool=entry.params.get("legacy",{}).get("kind","")=="gift_flower" and entry.params.get("legacy",{}).get("first",false)
	if (photos.size()>=int(photo_config.photo_daily_limit) and not first_rose and entry.params.get("legacy",{}).get("kind","") not in ["story_chapter","heart_project"] and not (play_photo and entry.text.begins_with("playground.memory."))) or not entry.photo_id.is_empty():return
	var actor:Dictionary=world.actors.get(entry.resident_id,{})
	if actor.is_empty():return
	photo_busy=true
	var viewport:=SubViewport.new();viewport.size=Vector2i(320,200);viewport.render_target_update_mode=SubViewport.UPDATE_ONCE;add_child(viewport)
	var camera_view:Node2D=game.view.get_script().new();camera_view.world=world;camera_view.library=game.library;camera_view.font=game.view.font;camera_view.sound_enabled=false;camera_view.memory_photo=true;viewport.add_child(camera_view);camera_view.set_process(false);camera_view.set_process_unhandled_input(false)
	camera_view.region_id=actor.region_id;camera_view.center=world.point(actor);camera_view.zoom=.62;camera_view.clock=game.view.clock;camera_view.queue_redraw()
	await RenderingServer.frame_post_draw
	if not is_instance_valid(game) or not books.entries.has(id):viewport.queue_free();photo_busy=false;return
	var image:Image=viewport.get_texture().get_image()
	var folder:String=books.directory.path_join("photos").path_join(str(int((entry.day-1)/30)));DirAccess.make_dir_recursive_absolute(folder)
	var relative:String="photos/"+str(int((entry.day-1)/30))+"/"+id+".png"
	if image!=null and not image.is_empty() and image.save_png(books.directory.path_join(relative))==OK:
		entry.photo_id=relative
		if books.atomic(books.directory.path_join(id+".entry.json"),entry):
			books.entries[id]=entry
			for other in books.entries.values():
				if other.world_id==entry.world_id and other.event_id==entry.event_id:
					other.photo_id=relative;books.atomic(books.directory.path_join(other.id+".entry.json"),other);books.entries[other.id]=other
	viewport.queue_free();photo_busy=false

func event(id:String,value:Dictionary)->void:
	if not maintenance.has(id):return
	var turn:Dictionary=maintenance[id]
	if str(game.immediate_turns.get(id,{}).get("turn_key",""))!=str(value.get("turn_key","")):return
	var scheduler:RefCounted=game.autonomy.scheduler
	if value.get("kind")=="usage":
		var total:int=int(value.get("total_tokens",-1))
		if total<int(turn.reported):return
		var ledger:Dictionary=scheduler.usage(id)
		var freed:int=mini(int(turn.reserve),total-int(turn.reported))
		if turn.day==scheduler.day_key():ledger.reserved=maxi(0,int(ledger.reserved)-freed)
		if scheduler.preferences.save_accounting(id,ledger):turn.reserve-=freed;turn.reported=total;turn.complete=value.get("complete",false)
	if value.get("kind")=="state" and value.get("state") in ["ready","cancelled","disconnected","error"]:
		if turn.complete and turn.day==scheduler.day_key():
			var ledger:Dictionary=scheduler.usage(id);ledger.reserved=maxi(0,int(ledger.reserved)-int(turn.reserve));scheduler.preferences.save_accounting(id,ledger)
		maintenance.erase(id)
		if letter_retries.has(id):
			var retry_day:int=int(letter_retries[id])
			letter_retries.erase(id)
			# Cancellation/disconnection/error must never create another turn.
			if value.get("state")=="ready":attempts[id]={"day":retry_day,"pending":true,"rewrite":true}
func cancel_pending(id:String)->void:
	letter_retries.erase(id)
	if attempts.get(id,{}).get("rewrite",false):attempts[id].pending=false
func check_letter_reply(id:String,writes:Variant,immediate:Dictionary)->void:
	if not writes is Array:return
	if not immediate.get("maintenance",false):return
	if not writes.any(func(e):return e is Dictionary and e.get("layer")=="letters" and books.letter_has_system_words(str(e.get("text","")))):return
	if attempts.get(id,{}).get("rewrite",false):return
	letter_retries[id]=int(immediate.get("memory_request",{}).get("day",0))
func water_help(actor:String,farm_id:String,plot_id:String,proof:String)->void:
	var manager:String=world.farms.farms[farm_id].manager_id
	if actor==manager or actor=="human" or manager in ["","human"]:return
	for id in [actor,manager]:
		books.add(id,world.world_id,"water-help:"+proof,"facts","memory.water_help",{"helper":Text.resident(world,actor),"receiver":Text.resident(world,manager),"plot":plot_id,"legacy":{"kind":"water_help","helper_id":actor,"receiver_id":manager,"plot_id":plot_id,"job_id":proof}},world.days.day(),"game",[actor,manager],world.forest.clock)
func goals(id:String)->void:
	var all:Array=books.list_for(id,"facts").filter(func(e):return e.world_id==world.world_id and e.params.has("goal_status"))
	for e in all:
		if e.params.goal_status!="accepted" or e.params.get("expires",0)<world.days.day():continue
		var target:String=e.params.farm_id
		var plots:Array=world.farms.plots.values().filter(func(p):return p.farm_id==target)
		if plots.is_empty() or not plots.all(func(p):return not p.crop_id.is_empty() and p.watered):continue
		e.params.goal_status="completed";books.atomic(books.directory.path_join(e.id+".entry.json"),e);books.entries[e.id]=e
		books.add(id,world.world_id,"goal-completed:"+e.id,"facts","memory.goal_completed",{"farm":e.params.farm,"source_ids":[e.id],"legacy":{"kind":"goal_completed","farm_id":target}},world.days.day(),"game",["human",id],world.forest.clock)
	if world.director.model_controlled(id) or world.director.routines[id].time<120 or not idle(id) or all.any(func(e):return e.day>world.days.day()-3 or (e.params.goal_status in ["offered","accepted"] and e.params.expires>=world.days.day())):return
	for farm in world.farms.farms.values():
		if not world.farms.ready(farm.id):continue
		var plots:Array=world.farms.plots.values().filter(func(p):return p.farm_id==farm.id)
		if plots.is_empty() or not plots.all(func(p):return p.crop_id.is_empty()):continue
		if not farm.crop_ids.any(func(c):return world.storage.count("seed."+c)>=plots.size()):continue
		if not world.director.say_local(id,Text.text("memory.goal_offer").replace("{farm}",Text.content(str(farm.name))),"memory_reminder",float(world.director.memory_reminders.config.personal_gap),float(world.director.memory_reminders.config.village_gap)):return
		books.add(id,world.world_id,"goal-offer:"+str(world.days.day()),"facts","memory.goal_offer",{"goal_status":"offered","farm_id":farm.id,"farm":Text.content(str(farm.name)),"expires":world.days.day()+5},world.days.day(),"local",["human",id],world.forest.clock)
		show_goal_card(books.list_for(id,"facts")[-1].id);return

func goal_options()->Array:
	var result:Array=[]
	for farm in world.farms.farms.values():
		if not world.farms.ready(farm.id):continue
		var plots:Array=world.farms.plots.values().filter(func(p):return p.farm_id==farm.id)
		if plots.is_empty() or not plots.all(func(p):return p.crop_id.is_empty()):continue
		if not farm.crop_ids.any(func(c):return world.storage.count("seed."+c)>=plots.size()):continue
		result.append({"id":farm.id,"name":Text.content(str(farm.name)),"expires":world.days.day()+5})
	return result.slice(0,4)

func show_goal_card(entry_id:String)->void:
	if not books.entries.has(entry_id) or is_instance_valid(goal_card):return
	if game.chat.visible or game.editor.visible or game.resident_connections.visible or world.work.jobs.has("human"):return
	var entry:Dictionary=books.entries[entry_id]
	goal_card=PanelContainer.new();goal_card_id=entry_id;goal_card.z_index=150;goal_card.position=Vector2(16,220);goal_card.custom_minimum_size=Vector2(290,110)
	var style:=StyleBoxFlat.new();style.bg_color=Color("213e37");style.set_content_margin_all(12);goal_card.add_theme_stylebox_override("panel",style)
	game.book_panel.get_parent().add_child(goal_card)
	var column:=VBoxContainer.new();goal_card.add_child(column)
	var line:=Label.new();line.custom_minimum_size.x=270;line.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;line.text=books.display_name(entry.resident_id)+": "+books.render(entry);column.add_child(line)
	var actions:=HBoxContainer.new();column.add_child(actions)
	for choice in [true,false]:
		var button:=Button.new();button.focus_mode=Control.FOCUS_NONE;button.text=Text.text("memory.agree" if choice else "memory.decline");actions.add_child(button)
		button.pressed.connect(func():books.decide_goal(entry_id,choice);goal_card.queue_free();goal_card=null;goal_card_id="")
func photo_subject(entry:Dictionary)->String:
	var raw:Dictionary=entry.params.get("legacy",{});var facts:Dictionary=raw.get("facts",{})
	var kind:String=str(raw.get("kind",""))
	if kind=="story_chapter":return str(facts.get("chapter_id",""))
	if kind=="fishing_catch":return str(facts.get("species_id",""))+":"+str(float(facts.get("scale",1))>=float(world.director.memory_reminders.config.large_fish_scale))
	return kind

func fishing_together(catcher:String,fish_id:String,others:Array)->void:
	if not world.fishing.fish.has(fish_id) or world.fishing.fish[fish_id].owner_id!=catcher:return
	for other in others:
		for id in [catcher,other]:
			books.add(id,world.world_id,"fishing-together:"+fish_id+":"+other,"facts","memory.fishing_together",{"first":Text.resident(world,catcher),"second":Text.resident(world,other),"legacy":{"kind":"fishing_together","fish_id":fish_id,"catcher_id":catcher,"peer_id":other}},world.days.day(),"game",[catcher,other],world.forest.clock)

# An uneventful evening still has one real observation to ground its page.
# This observes the current night only; it cannot invent prior days or activities.
func write_evening_pages()->void:
	if world.days.phase().id!="night":return
	var day:int=world.days.day()
	var weather:Dictionary=world.weather.current()
	var names:Dictionary={"sunny":["晴","clear"],"cloudy":["多云","cloudy"],"rain":["小雨","light rain"],"fog":["雾","foggy"]}
	for id in world.director.routines:
		var missed:Array=missed_wishes_provider.call(id) if missed_wishes_provider.is_valid() else []
		var diary_id:String=(str(id)+"|"+world.world_id+"|diary-evening:"+str(day)+"|daily").sha256_text()
		if books.deleted.has(diary_id):continue
		var actual:Array=books.list_for(id,"facts").filter(func(e):return e.world_id==world.world_id and int(e.day)==day and (e.source=="game" or e.params.get("human_quote",false)))
		if actual.is_empty():
			var words:Array=names.get(weather.id,[str(weather.name),str(weather.id)])
			books.add(id,world.world_id,"evening-observation:"+str(day),"facts","memory.localized_fact",{"localized":{"zh":"第 %s 天，已经是夜晚，天气是%s。"%[day,words[0]],"en":"Day %s: it is night, and the weather is %s."%[day,words[1]]},"legacy":{"kind":"evening_observation","day":day,"phase":"night","weather_id":weather.id},"channel":"direct:"+str(id)},day,"game",[id],world.forest.clock)
		books.write_local_diary(id,world.world_id,day,world.forest.clock,missed)
