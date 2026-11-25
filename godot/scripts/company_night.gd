extends RefCounted
const Text=preload("res://scripts/localization.gd")
var owner:WeakRef
var c:Node:
	get:return owner.get_ref()
var g:Node:
	get:return c.g
var w:RefCounted:
	get:return c.w
var card:PanelContainer
var pending_card:Dictionary={}
var turn:Dictionary={}
var scene:Dictionary={}
var offered:Dictionary={}
var reminders:Dictionary={}
var appointment_routes:Dictionary={}
var recalled:Dictionary={}
var recall_checked:Dictionary={}
var checked_day:=0
var checked_topics:Dictionary={}
var check_after:=0.0

func _init(host:Node)->void:owner=weakref(host)
func story_events(id:String,station:String)->Array:
	var events:Array=[]
	var fire:RefCounted=w.barbecues[station].fireside
	var meal:Dictionary=fire.state.current
	if id in meal.get("eaters",[]):
		var dish:String=Text.content(str(meal.name))
		events.append({"id":"meal:"+str(meal.id),"text":c.localized(["我在这次围炉吃完了%s。","I finished %s at this fireside meal."]) % dish})
	var visual:Array=w.work.visual_events.filter(func(e):return e.kind=="fall" and e.region_id==w.actors[id].region_id)
	for e in visual.slice(-2):
		if not w.actors.has(e.actor_id):continue
		var name:String=Text.resident(w,e.actor_id)
		events.append({"id":"tree:"+str(e.serial),"text":c.localized(["%s砍倒了一棵树。","%s chopped down a tree."]) % name})
	var weather:Dictionary=w.weather.current()
	if w.actors[id].region_id=="home":
		events.append({"id":"weather:"+str(w.days.day())+":"+str(weather.id),"text":c.localized(["此刻岛上的天气：%s","The weather on the island right now: %s"]) % Text.content(weather.name)})
	var participants:Array=w.director.brains[id].interactions.receipts.filter(func(e):return e.event=="banter_line" and e.listener!="human" and w.actors.has(e.listener))
	if not participants.is_empty():
		var line:Dictionary=participants.back()
		var peer:String=Text.resident(w,line.listener)
		var word:String=line.en if c.localized(["zh","en"])=="en" else line.zh
		events.append({"id":"banter:"+str(line.proof),"text":c.localized(["我和%s拌过一句嘴：%s","I traded a remark with %s: %s"]) % [peer,word]})
	return events
func available_fire()->Dictionary:
	if w.days.phase().id not in ["dusk","night"]:return {}
	for id in w.barbecues:
		var life:RefCounted=w.barbecues[id]
		var fire:RefCounted=life.fireside
		if not fire.burning() or fire.circle_closed or not fire.jobs.has("human") or w.actors.human.activity not in ["fire_sit","fire_squat","fire_eat"]:continue
		var present:Array=c.IDS.filter(func(who):return fire.jobs.has(who) and w.actors[who].activity in ["fire_sit","fire_squat","fire_eat"] and w.director.can_say_local(who,"company_night"))
		if not present.is_empty():return {"station":id,"people":present}
	return {}
func start(kind:String,manual:bool=true)->bool:
	if kind not in ["story","question"]:return false
	var fire:Dictionary=available_fire()
	if fire.is_empty():
		if manual:g.status.text=c.tr_key("night_unavailable")
		return false
	var day:int=w.days.day()
	if checked_day!=day:checked_topics.clear()
	if (checked_day==day and (not manual or checked_topics.has(kind))) or w.memories.records.any(func(row):return row.kind=="company_night" and int(row.facts.day)==day and (not manual or row.facts.mode==kind)):
		if manual:g.status.text=c.tr_key("night_used")
		return false
	if not turn.is_empty() or not scene.is_empty():return false
	var speaker:String=fire.people[posmod(day-1,fire.people.size())]
	var facts:Dictionary={"actor_id":speaker,"day":day,"mode":kind}
	if not w.memories.record_event("company_night",w.memories.company_key("company_night",facts),["human",speaker],facts):return false
	checked_day=day;checked_topics[kind]=true
	scene={"id":speaker,"station":fire.station,"people":fire.people,"camera":g.view.zoom,"kind":kind,"day":day}
	w.director.company_night_owner=speaker
	g.view.zoom*=1.10
	var eligible:Array=g.memory_books.list_for(speaker,"facts").filter(func(row):return row.world_id==w.world_id and row.source=="game" and row.params.get("legacy",{}).get("kind")!="company_night")
	var recent:Array=eligible.filter(func(row):return row.params.get("legacy",{}).get("kind") in ["meal","care_first","favorite_taste","signature_taste"]).slice(-3)
	for row in eligible.slice(-3):
		if not recent.has(row):recent.append(row)
	var source_ids:Array=recent.map(func(e):return e.id)
	var context:Dictionary={"language":g.language,"station":fire.station}
	for e in recent:
		if not context.has("memories"):context.memories=[]
		context.memories.append({"id":e.id,"text":g.memory_books.render(e).left(150)})
	if kind=="story":
		var events:Array=story_events(speaker,fire.station)
		context["little_events"]=events
		var lang:int=1 if Text.revision().begins_with("en") else 0
		var options:Array=c.voices.stories[c.tag(speaker)]
		scene.lines=options[posmod(day-1,options.size())][lang].duplicate();scene.index=0;scene.next=w.forest.clock
		if not source_ids.is_empty() or not events.is_empty():c.model_offer(speaker,kind,context,{"day":day,"sources":source_ids,"event_sources":events.map(func(row):return row.id)})
		else:c.model_stage(speaker,kind,"","not_sent","no_grounded_source")
	else:
		var choices:Array=c.voices.questions[c.tag(speaker)]
		var question:Dictionary=choices[posmod(day-1,choices.size())]
		scene["local_question"]={"text":c.localized(question.ask),"options":question.options.map(func(value):return c.localized(value))}
		if not c.model_offer(speaker,"question",context,{"day":day}):
			ask(speaker,scene.local_question.text,scene.local_question.options,"night")
	c.note("night_"+kind,{"actor":speaker,"station":fire.station})
	return true
func ask(id:String,title:String,choices:Array,kind:String)->void:
	if not is_instance_valid(card) and g.person_card_busy():
		if pending_card.is_empty():pending_card={"id":id,"title":title,"choices":choices.duplicate(),"kind":kind,"until":w.forest.clock+35}
		return
	close_card()
	var token:String=Crypto.new().generate_random_bytes(8).hex_encode()
	turn={"id":id,"kind":kind,"question":title,"until":w.forest.clock+float(c.settings.answer_seconds),"token":token,"choices":choices.duplicate()}
	card=c.panel();c.label(card,Text.resident(w,id)+" · "+title)
	var body:VBoxContainer=card.get_node("body")
	for index in choices.size():c.button(body,"answer_"+str(index),choices[index],func():answer(token,index,""))
	if kind=="night":
		var input:=LineEdit.new();input.name="TypedAnswer";input.max_length=120;input.placeholder_text=c.tr_key("type");body.add_child(input)
		input.text_submitted.connect(func(words):answer(token,-1,words))
		c.button(body,"type",c.tr_key("send"),func():answer(token,-1,input.text))
		c.button(body,"pass",c.tr_key("pass"),func():close_card();end_scene())
	preload("res://scripts/person_card.gd").style_card(card);preload("res://scripts/person_card.gd").announce_person_card(g,card,id)
	card.reset_size()
	preload("res://scripts/person_card.gd").position_person_card(g,card,id,turn.until,true)
func close_card()->void:
	pending_card.clear()
	if is_instance_valid(card):card.hide();card.queue_free();card=null
	turn.clear()
func answer(token:String,index:int,typed:String)->void:
	if turn.is_empty() or turn.token!=token or w.forest.clock>=float(turn.until):return
	var id:String=turn.id
	if turn.kind=="promise":
		var agreement:Dictionary=offered.duplicate(true)
		if index==0 and w.actors[id].region_id==w.actors.human.region_id and w.point(w.actors[id]).distance_to(w.point(w.actors.human))<=float(c.settings.offer_distance) and w.promises.accept_social(id,agreement.action,agreement.target,agreement.day):
			c.note("promise_accepted",{"actor":id,"action":agreement.action})
		else:c.note("promise_declined",{"actor":id})
		offered.clear();close_card();return
	var words:String=str(turn.choices[index]) if index>=0 and index<turn.choices.size() else typed.strip_edges()
	if words.is_empty() or words.length()>120 or not valid_scene():return
	var question:String=turn.question
	var source:Dictionary=g._record_chat("direct:"+id,"human",words,"company_answer")
	var quote_id:String=(id+"|"+w.world_id+"|"+str(source.get("message_id",""))+"|facts").sha256_text()
	var books:RefCounted=g.memory_books
	if not books.entries.has(quote_id):
		books.remember_chat(id,w.world_id,str(source.get("message_id","")),words,w.days.day(),"direct:"+id)
	if books.entries.has(quote_id):
		books.add(id,w.world_id,"night-answer:"+str(w.days.day()),"about_you","memory.localized_fact",{"kind":"night_answer","answer":words,"question":question,"source_ids":[quote_id],"channel":"direct:"+id,"localized":{"zh":question+" 答："+words,"en":"“"+question+"” My answer: "+words}},w.days.day(),"local",["human",id],w.forest.clock)
	c.note("night_answer",{"actor":id,"answer":words,"question":question})
	close_card();end_scene()
func valid_scene()->bool:
	if scene.is_empty() or w.days.day()!=scene.day:return false
	var fire:RefCounted=w.barbecues[scene.station].fireside
	return fire.burning() and not fire.circle_closed and fire.jobs.has(scene.id) and fire.jobs.has("human") and w.actors.human.activity in ["fire_sit","fire_squat","fire_eat"]
func end_scene()->void:
	if not scene.is_empty():g.view.zoom=scene.camera;scene.clear()
	w.director.company_night_owner=""
func offer(id:String)->bool:
	if g.person_card_busy() or g.person_outing_approaching():return false
	if not turn.is_empty() or not scene.is_empty() or c.busy(id) or c.busy("human") or w.hunger.rank(id)>=3 or not w.locations.v3() or w.actors[id].region_id!="home" or w.actors.human.region_id!="home":return false
	if w.point(w.actors[id]).distance_to(w.point(w.actors.human))>float(c.settings.offer_distance):return false
	if not w.promises.offer_social(id,w.days.day()):return false
	var options:Array=[{"action":"social_sunrise","target":"plaza"}]
	if w.standard.ready("home.barbecue") and w.barbecues.has("home.barbecue"):options.append({"action":"social_fireside","target":"home.barbecue"})
	var choice:Dictionary=options.back() if c.tag(id) in ["quiet","lively"] else options.front()
	offered=choice.merged({"day":w.days.day(),"options":options})
	show_offer(id)
	c.model_offer(id,"promise",{"options":options.map(func(row):return {"id":row.action,"description":describe(row.action)})},{"day":w.days.day()})
	return true
func show_offer(id:String)->void:
	var exact:String=c.tr_key("promise_question")%describe(offered.action)
	var opening:String=str(offered.get("opening",""))
	ask(id,exact if opening.is_empty() else opening+"\n"+exact,[c.tr_key("promise_yes"),c.tr_key("promise_no")],"promise")
func describe(action:String)->String:
	return c.tr_key("sunrise" if action=="social_sunrise" else "fireside")
func model_result(id:String,entry:Dictionary,result:Dictionary)->bool:
	if int(entry.binding.day)!=w.days.day():return false
	match str(entry.kind):
		"promise":
			if turn.get("kind")!="promise" or turn.get("id")!=id:return false
			for option in offered.options:
				if option.action!=result.get("choice"):continue
				if option.action=="social_fireside" and not w.standard.ready(option.target):return false
				if c.line_valid(result.get("text"),55):offered["opening"]=result.text
				offered.merge(option,true);show_offer(id);return true
		"question":
			var choices:Variant=result.get("options")
			if scene.get("kind")!="question" or scene.get("id")!=id or not valid_scene() or not c.line_valid(result.get("text"),135) or not choices is Array or choices.size()<2 or choices.size()>3 or not choices.all(func(item):return c.line_valid(item,38)):return false
			ask(id,result.text,choices,"night");return true
		"story":
			var lines:Variant=result.get("lines")
			var source:Variant=result.get("source_id")
			if scene.get("kind")!="story" or scene.get("id")!=id or not valid_scene() or not source is String or not ((source in entry.binding.sources and g.memory_books.entries.has(source)) or source in entry.binding.get("event_sources",[])) or not lines is Array or lines.size()<3 or lines.size()>6 or not lines.all(func(item):return c.line_valid(item,68)):return false
			scene.lines=lines.duplicate();scene.index=0;scene.next=w.forest.clock
			scene["model_request"]=entry.id
			c.note("night_story_source",{"actor":id,"source_id":source});return true
	return false
func used_fireside()->bool:
	return not scene.is_empty() or (not turn.is_empty() and turn.kind=="night")
func go_to_appointment(row:Dictionary)->void:
	var id:String=row.resident_id
	if row.action_type!="social_sunrise" or c.busy(id) or w.hunger.rank(id)>=3 or w.actors[id].region_id!="home" or w._routes.has(id):return
	if w.director.time<float(w.director.routines[id].visual_quiet_until):return
	if w.director.brains[id].current.has("outing_job"):return
	var info:Array=w.map_anchor("plaza.center")
	if info.size()!=2:return
	var point:Vector2=w.nearest_walkable("home",Vector2(info[0],info[1])+Vector2(2,1))
	if not point.is_finite() or w.point(w.actors[id]).distance_to(point)<=2:return
	if appointment_routes.has(row.id):return
	w.hunger.clear_follow(id)
	if w.route_to(id,point):
		appointment_routes[row.id]={"id":id,"route":w._routes[id]}
		if id not in w.activities.opening_party:w.activities.opening_party.append(id)
func clean_appointment_routes()->void:
	for key in appointment_routes.keys():
		var record:Dictionary=appointment_routes[key]
		if w.promises.entries.has(key) and not c.busy(record.id) and w.hunger.rank(record.id)<3 and (not w._routes.has(record.id) or is_same(w._routes[record.id],record.route)):continue
		w.activities.opening_party.erase(record.id)
		if w._routes.has(record.id) and is_same(w._routes[record.id],record.route):
			w._routes.erase(record.id);w.actors[record.id].activity="idle"
		appointment_routes.erase(key)
func recall(id:String)->void:
	if id not in c.IDS or w.days.day()<=int(c.settings.recall_days) or not scene.is_empty() or c.busy(id) or w.hunger.rank(id)>=3 or w.director.time<float(w.director.routines[id].visual_quiet_until):return
	if w.forest.clock<float(recall_checked.get(id,0)) or not w.director.can_say_local(id,"company_recall"):return
	recall_checked[id]=w.forest.clock+float(c.settings.answer_seconds)
	var rows:Array=g.memory_books.list_for(id,"about_you").filter(func(e):return e.world_id==w.world_id and e.params.get("kind","")=="night_answer" and not e.params.get("recalled",false) and int(e.day)+int(c.settings.recall_days)<=w.days.day() and e.params.get("source_ids",[]).all(func(key):return g.memory_books.entries.has(key)))
	if rows.is_empty() or recalled.has(rows[-1].id):return
	var e:Dictionary=rows[-1]
	var words:String=c.tr_key("recall")%str(e.params.answer).left(33)
	if c.say(id,words,"company_recall"):
		recalled[e.id]=true;e.params.recalled=true
		if g.memory_books.atomic(g.memory_books.directory.path_join(e.id+".entry.json"),e):g.memory_books.entries[e.id]=e
		g._record_chat("direct:"+id,id,words,"local")
		c.note("night_recalled",{"actor":id,"answer":e.params.answer,"text":words})
func tick()->void:
	clean_appointment_routes()
	if not pending_card.is_empty():
		if w.forest.clock>=pending_card.until or (pending_card.kind=="night" and not valid_scene()) or (pending_card.kind=="promise" and offered.is_empty()):pending_card.clear()
		elif not g.person_card_busy():
			var waiting:Dictionary=pending_card.duplicate()
			ask(waiting.id,waiting.title,waiting.choices,waiting.kind)
	if not turn.is_empty():
		if w.forest.clock>=float(turn.until) or (turn.kind=="night" and not valid_scene()) or (turn.kind=="promise" and (c.busy(turn.id) or w.hunger.rank(turn.id)>=3)):
			close_card();end_scene();offered.clear()
		else:preload("res://scripts/person_card.gd").position_person_card(g,card,turn.id,turn.until,true)
	if not scene.is_empty():
		if not valid_scene():close_card();end_scene()
		elif scene.kind=="question" and turn.is_empty() and not c.model_waiting(scene.id,"question") and scene.has("local_question"):
			ask(scene.id,scene.local_question.text,scene.local_question.options,"night")
		elif scene.kind=="story" and not c.model_waiting(scene.id,"story") and w.forest.clock>=float(scene.next):
			if scene.index<scene.lines.size():
				var words:String=scene.lines[scene.index]
				if c.say(scene.id,words,"company_night"):
					if scene.has("model_request"):
						g.view.say(words,"model",scene.id,"company_night")
						c.model_stage(scene.id,"story",scene.model_request,"shown","bubble",{"text":words,"line":scene.index})
					c.note("night_line",{"actor":scene.id,"text":words})
					scene.index+=1;scene.next=w.forest.clock+float(c.settings.night_line_seconds)
			else:
				for other in scene.people:
					if other!=scene.id and c.say(other,c.tr_key("listen"),"company_night"):break
				end_scene()
	if w.forest.clock<check_after:return
	check_after=w.forest.clock+1
	for event in w.promises.queued_social.duplicate():
		var id:String=event.actor
		var kept:bool=event.outcome=="completed"
		if not kept and w.days.day()<=int(event.day):continue
		w.promises.queued_social.erase(event)
		var mood_key:String="promise_kept" if kept else "promise_missed"
		w.hearts.change(id,c.settings.effects[mood_key],"company_"+mood_key)
		c.say(id,c.tr_key(mood_key),"company_promise")
		c.note(mood_key,{"actor":id,"target":event.target})
	for id in c.IDS:
		if not w.actors.has(id):continue
		for row in w.promises.social(id):
			if w.forest.clock>=float(row.due_at) and w.forest.clock<float(row.expires_at):
				go_to_appointment(row)
				if not reminders.has(row.id) and c.say(id,c.tr_key("promise_remind"),"company_promise"):reminders[row.id]=true
	if not turn.is_empty() or not scene.is_empty() or not c.care.is_empty() or (is_instance_valid(c.return_card)):return
	if w.director.moment_pacing!=null and w.director.moment_pacing.score()<0:return
	var pace:Dictionary=w.standard.COMPANY_PACING.data
	var first:bool=w.standard.first_company_day()
	var dusk_start:float=float(w.days.config.phases[2].start)*w.days.day_seconds
	if w.days.phase().id in ["dusk","night"] and checked_day!=w.days.day() and (not first or w.days.within_day()>=dusk_start+float(pace.first_night_after_dusk)) and not available_fire().is_empty():
		if start("question" if w.days.day()%2==0 else "story",false):return
	if w.days.phase().id=="morning" and w.days.within_day()>=float(pace.first_promise_after if first else c.settings.offer_after) and not g.chat.visible:
		for id in c.IDS:
			if w.director.brains.has(id) and w.director.brains[id].moment_candidate("company_promise",func():return offer(id)):return
