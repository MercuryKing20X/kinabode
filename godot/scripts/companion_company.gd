extends Node

const Text=preload("res://scripts/localization.gd")
const Persona=preload("res://scripts/persona_cards.gd")
const IDS=["codex","companion-2","npc.mira","npc.nora"]
const ACTIONS=["pat","sit","snack","comfort"]
var settings:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/company.json"))
var voices:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/company-voices.json"))
var g:Node
var w:RefCounted:
	get:return g.world
var care:Dictionary={}
var last_care:Dictionary={}
var care_count:Dictionary={}
var return_scene:Dictionary={}
var return_label:Label
var return_card:PanelContainer
var snack_card:PanelContainer
var care_card:PanelContainer
var care_target:=""
var care_buttons:Dictionary={}
var trace:Array=[]
var night:RefCounted
var camera:Node
var model_pending:Dictionary={}
var model_trace:Array=[]
var model_letters:Dictionary={}

func setup(game:Node,loaded:Dictionary)->void:
	g=game
	night=preload("res://scripts/company_night.gd").new(self)
	g.book_panel.letter_opened.connect(model_letter_opened)
	w.director.local_speech_window.connect(_recall_window)
	w.director.return_speech_window.connect(_return_speech_window)
	camera=preload("res://scripts/company_camera.gd").new();add_child(camera);camera.setup(self)
	if loaded.get("loaded",false) and loaded.get("absence_seconds",0)>=float(settings.absence_seconds[0]):
		return_scene=loaded.duplicate(true);return_scene["state"]="starting"

func _recall_window(id:String)->void:night.recall(id)
func _return_speech_window()->void:
	if return_scene.get("state","")=="greeting":tick_return()
func prepare_return_speech()->void:
	if return_scene.get("state","")=="starting":start_return()
	w.director.return_speech_reserved=return_scene.get("state","")=="greeting" and w.forest.clock<float(return_scene.until) and return_scene.targets.keys().any(func(id):
		return w.hunger.rank(id)<2 and w.director.routines[id].enabled and w.director.routines[id].chatter and not w.director.routines[id].held and w.director.time>=w.director.routines[id].visual_quiet_until)

func tr_key(key:String)->String:return Text.text("company."+key)
func localized(pair:Array)->String:return str(pair[1 if Text.revision().begins_with("en") else 0])
func tag(id:String)->String:
	var key:String=w.intelligence.tag(id)
	return key if voices.care.has(key) else "gentle"
func note(kind:String,details:Dictionary={}) ->void:
	trace.append({"kind":kind,"at":w.forest.clock,"day":w.days.day()}.merged(details))
	if trace.size()>200:trace.pop_front()
	if w.director.moment_pacing!=null and kind in ["care","return_summary","promise_accepted","photo"]:
		w.director.moment_pacing.observe(kind)
func button(box:Container,id:String,title:String,click:Callable)->Button:
	var b:=Button.new();b.name=id;b.text=title;b.focus_mode=Control.FOCUS_NONE
	b.size_flags_horizontal=Control.SIZE_EXPAND_FILL;b.custom_minimum_size=Vector2(72,42)
	b.pressed.connect(click);box.add_child(b);return b
func panel()->PanelContainer:
	var p:=PanelContainer.new();p.z_index=150;g.island_hud.ui_root.add_child(p)
	p.add_theme_stylebox_override("panel",g.island_hud.pixel_style())
	var body:=VBoxContainer.new();body.name="body";p.add_child(body);return p
func label(p:PanelContainer,words:String)->Label:
	var l:=Label.new();l.text=words;l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x=minf(410,g.get_viewport_rect().size.x*.62)
	p.get_node("body").add_child(l);return l
func place_panel(p:PanelContainer)->void:
	if is_instance_valid(p):
		p.position=Vector2((g.get_viewport_rect().size.x-p.size.x)*.5,20)
func show_care(id:String)->void:
	if id not in IDS or not w.actors.has(id):return
	close_care_menu()
	g.island_hud.resident_card.hide()
	care_target=id;care_card=panel()
	label(care_card,Text.resident(w,id))
	var body:VBoxContainer=care_card.get_node("body")
	for action in ACTIONS:
		if not allowed(id,action):continue
		care_buttons[action]=button(body,"care_"+action,tr_key(action),func():
			close_care_menu()
			if action=="snack":snack_menu(id)
			else:start_care(id,action))
	button(body,"mind",Text.text("gestation.heart"),func():close_care_menu();g.brain_panel.open(id))
	button(body,"close",Text.text("hud.close"),close_care_menu)
	care_card.reset_size()
	place_panel(care_card)
func close_care_menu()->void:
	if is_instance_valid(care_card):care_card.hide();care_card.queue_free();care_card=null
	care_buttons.clear();care_target=""
func allowed(id:String,activity:String)->bool:
	if id not in IDS or not w.actors.has(id):return false
	var mood:Dictionary=w.hearts.mood(id)
	return activity!="comfort" or float(mood.hurt)>=float(settings.comfort_hurt) or float(mood.joy)<float(w.hearts.config.baseline.joy)-10
func busy(id:String)->bool:
	return w.work.jobs.has(id) or w.projects.active(id) or w.farms.active(id) or w.homestead.active(id) or w.deliveries.active(id) or w.activities.blocked(id,false) or w.gomoku.active(id) or w.flower_creation.active(id) or id in g.playground.members
func snack_items()->Array:
	return settings.snacks.filter(func(item):return w.storage.count(item)>0)
func snack_menu(id:String)->void:
	if is_instance_valid(snack_card):snack_card.queue_free()
	var items:Array=snack_items()
	if items.is_empty():g.status.text=tr_key("no_snacks");return
	snack_card=panel();label(snack_card,tr_key("snack_pick"))
	for item in items:
		var title:String=Text.text("storage.item."+item)
		if title=="storage.item."+item:title=Text.content(w.farms.crops.get(item,{}).get("name",item))
		button(snack_card.get_node("body"),item,title,func():
			snack_card.queue_free();snack_card=null;start_care(id,"snack",item))
	button(snack_card.get_node("body"),"close",Text.text("hud.close"),func():snack_card.queue_free();snack_card=null)
	place_panel(snack_card)
func start_care(id:String,activity:String,item:String="")->bool:
	if activity not in ACTIONS or not allowed(id,activity) or not care.is_empty() or busy(id) or busy("human") or w.actors.human.region_id!=w.actors[id].region_id:
		g.status.text=tr_key("busy");return false
	if activity=="snack" and item not in snack_items():
		g.status.text=tr_key("no_snacks");return false
	var human:Vector2=w.point(w.actors.human)
	var friend:Vector2=w.point(w.actors[id])
	var region:String=w.actors.human.region_id
	var route:Variant=null
	if human.distance_to(friend)>float(settings.touch_distance):
		var destinations:Array=[Vector2(0,1.6),Vector2(-1.6,0),Vector2(1.6,0),Vector2(0,-1.6)]
		var ordered:Array=destinations.map(func(offset):return friend+offset)
		ordered.sort_custom(func(a,b):return a.distance_squared_to(human)<b.distance_squared_to(human))
		for point:Vector2 in ordered:
			if not w.walkable(region,point):continue
			if w.command("human",{"intent":"move","region_id":region,"x":point.x,"y":point.y}).ok:
				route=w._routes.get("human");break
		if route==null:g.status.text=tr_key("unreachable");return false
	care={"id":id,"action":activity,"item":item,"region":region,"route":route,"phase":"approach","until":w.forest.clock+float(settings.approach_timeout),"poses":{}}
	note("care_approach",{"id":id,"action":activity})
	return true
func end_care()->void:
	for id in care.get("poses",{}):
		if g.view.motion.play_poses.get(id)==care.poses[id]:g.view.motion.play_poses.erase(id)
	care.clear()
func care_string(id:String,action:String,condition:String,variant:int,language:int)->String:
	var profile:Dictionary=voices.care[tag(id)]
	if condition in ["hungry","repeat"]:return str(profile.openings[variant][language])+" "+str(profile.conditions[voices.conditions.find(condition)][language])
	return str(profile.openings[variant][language])+" "+str(profile.acts[ACTIONS.find(action)][language])+" "+str(profile.conditions[voices.conditions.find(condition)][language])
func deliver_care()->void:
	var id:String=care.id
	var action:String=care.action
	var key:=id+":"+action
	var before:Dictionary=w.hearts.mood(id)
	var repeat:bool=w.forest.clock-float(last_care.get(key,-100000))<float(settings.repeat_seconds)
	var hungry:bool=w.hunger.rank(id)>=3
	var condition:String="hungry" if hungry else "repeat" if repeat else "neglect" if w.hearts.profile(id).reason=="neglect" else "hurt" if float(before.hurt)>=float(settings.comfort_hurt) or float(before.joy)<float(w.hearts.config.baseline.joy)-10 else "joy"
	if action=="snack":
		if not w.storage.take({care.item:1}).ok:g.status.text=tr_key("no_snacks");end_care();return
		w.revision+=1
	var delta:Dictionary=settings.effects[action].duplicate()
	if repeat:
		for axis in delta:delta[axis]=float(delta[axis])*float(settings.repeat_factor)
	if not hungry or action=="snack":
		w.hearts.profile(id).last_contact=w.forest.clock
		w.hearts.change(id,delta,"company_"+action)
	var after:Dictionary=w.hearts.mood(id)
	if action=="pat":
		w.hearts.react(id,"pat")
		w.memories.record_event("care_first",id+":pat",["human",id],{"actor_id":id,"action":"pat"})
	if action=="comfort" and float(after.hurt)<float(before.hurt):
		w.memories.record_event("care_first",id+":comfort",["human",id],{"actor_id":id,"action":"comfort"})
		if float(before.hurt)>=float(settings.comfort_hurt):w.memories.record_event("emotion_reconciled",id+":"+str(w.days.day()),["human",id],{"actor_id":id,"day":w.days.day(),"previous_hurt":before.hurt})
	var variant:int=int(care_count.get(key,0))%4
	var words:String=care_string(id,action,condition,variant,1 if Text.revision().begins_with("en") else 0)
	last_care[key]=w.forest.clock;care_count[key]=int(care_count.get(key,0))+1
	care.phase="perform";care.until=w.forest.clock+float(settings.sit_seconds if action=="sit" and not hungry else settings.gesture_seconds)
	care.poses={"human":"fire_sit" if action=="sit" and not hungry else "gesture_wave"}
	if not hungry and not w._routes.has(id):
		if action=="sit":care.poses[id]="fire_sit"
		elif tag(id)=="lively":care.poses[id]="play_cute"
		elif tag(id)=="quiet":care.poses[id]="local_look"
		else:care.poses[id]="gesture_wave"
	for actor in care.poses:g.view.motion.play_poses[actor]=care.poses[actor]
	note("care",{"actor":id,"action":action,"condition":condition,"reply":words,"before":before,"after":after,"snack":care.item})
	if not model_offer(id,"care",{"action":tr_key(action),"condition":condition,"language":g.language},{"action":action,"care_sequence":care_count[key],"fallback":words}):
		say(id,words,"company_care")
func say(id:String,words:String,context:String)->bool:
	if not w.director.say_local(id,words,context,4,4):return false
	g.view.say(words,"local_rules",id,context)
	return true
func tick_care()->void:
	if care.is_empty():return
	var id:String=care.id
	var route:Variant=w._routes.get("human")
	if w.actors.human.region_id!=care.region or w.actors[id].region_id!=care.region or busy(id) or busy("human") or (route!=null and not is_same(care.route,route)) or w.forest.clock>=float(care.until):
		end_care();return
	if care.phase=="approach" and route==null:
		if w.point(w.actors.human).distance_to(w.point(w.actors[id]))<=float(settings.touch_distance):deliver_care()
		else:g.status.text=tr_key("unreachable");end_care()
	elif care.phase=="perform" and w.point(w.actors.human).distance_to(w.point(w.actors[id]))>float(settings.touch_distance):end_care()

func start_return()->void:
	var seconds:float=return_scene.absence_seconds
	var band:int=0
	for i in settings.absence_seconds.size():
		if seconds>=float(settings.absence_seconds[i]):band=i
	return_scene.merge({"state":"greeting","band":band,"targets":{},"routes":{},"arrived":[],"until":w.forest.clock+float(settings.approach_timeout),"next":w.forest.clock},true)
	return_card=panel();label(return_card,tr_key("return"))
	return_label=label(return_card,"")
	button(return_card.get_node("body"),"close",Text.text("hud.close"),func():return_card.queue_free();return_card=null)
	update_return_label()
	for id in IDS:
		if not w.actors.has(id):continue
		if busy(id) or w.hunger.rank(id)>=3 or w.actors[id].region_id!=w.actors.human.region_id or w.point(w.actors[id]).distance_to(w.point(w.actors.human))>float(settings.absence_route_tiles):continue
		w.hunger.clear_follow(id)
		if w._routes.has(id):continue
		var target:Vector2=w.deliveries.visit_slot(id)
		if not target.is_finite():continue
		if w.route_to(id,target):
			return_scene.targets[id]=target;return_scene.routes[id]=w._routes[id]
			if id not in w.activities.opening_party:w.activities.opening_party.append(id)
	if band>=int(settings.letter_min_band):
		for id in IDS:
			if w.actors.has(id):welcome_letter(id)
	note("return_summary",{"seconds":seconds,"band":band,"crops":return_scene.matured})
func update_return_label()->void:
	if not is_instance_valid(return_label):return
	var seconds:float=return_scene.absence_seconds
	var time:String=tr_key("absence_days")%int(seconds/86400) if seconds>=86400 else tr_key("absence_hours")%int(seconds/3600) if seconds>=3600 else tr_key("absence_minutes")%int(seconds/60)
	var writers:Array=IDS.filter(func(id):return g.memory_books.list_for(id,"daily").any(func(e):return e.world_id==w.world_id and float(e.at)<=float(return_scene.saved_wall) and int(e.day)==int(return_scene.saved_day)))
	var names:=func(ids:Array)->String:return ", ".join(ids.map(func(id):return Text.resident(w,id)))
	return_label.text="\n".join([time,tr_key("absence_hunger"),tr_key("absence_crops")%return_scene.matured if return_scene.matured>0 else tr_key("absence_no_crop"),tr_key("absence_diaries")%names.call(writers) if not writers.is_empty() else tr_key("absence_no_diaries"),tr_key("absence_arrivals")%names.call(return_scene.arrived) if not return_scene.arrived.is_empty() else tr_key("absence_arranging")])
	if return_scene.get("wrote",false):return_label.text+="\n"+tr_key("absence_letters")
func tick_return()->void:
	if return_scene.is_empty() or return_scene.state=="done":return
	if return_scene.state=="starting":start_return();return
	place_panel(return_card)
	for id in return_scene.targets.keys():
		if w._routes.has(id) and is_same(return_scene.routes[id],w._routes[id]) and w.forest.clock<float(return_scene.until) and w.hunger.rank(id)<3:continue
		if w.forest.clock<float(return_scene.next) and w.forest.clock<float(return_scene.until):continue
		if not w._routes.has(id) and w.hunger.rank(id)<3 and not busy(id) and w.director.time>=w.director.routines[id].visual_quiet_until and w.actors[id].region_id==w.actors.human.region_id and w.point(w.actors[id]).distance_to(return_scene.targets[id])<=.5 and w.point(w.actors[id]).distance_to(w.point(w.actors.human))<=7:
			if model_waiting(id,"letter") and w.forest.clock<float(return_scene.until):continue
			var local_greeting:String=localized(voices.care[tag(id)].returns[int(return_scene.band)])
			var fact:Dictionary=return_scene.get("model_greetings",{}).get(id,{})
			var greeting:String=local_greeting if fact.is_empty() else str(fact.text)
			var greeted:bool=w.forest.clock<float(return_scene.until) and w.director.say_local(id,greeting,"company_return",4,4,"human","local_rules" if fact.is_empty() else "model")
			if not greeted and w.forest.clock<float(return_scene.until):continue
			if greeted and not fact.is_empty():
				model_stage(id,"greeting",fact.id,"shown","bubble",{"text":greeting,"local":local_greeting})
			return_scene.arrived.append(id);return_scene.next=w.forest.clock+4
			note("return_arrived",{"actor":id,"spoken":greeted,"text":greeting if greeted else "","local":local_greeting})
		elif w._routes.has(id) and is_same(return_scene.routes[id],w._routes[id]):
			w._routes.erase(id);w.actors[id].activity="idle"
		w.deliveries.visits.erase(id);w.activities.opening_party.erase(id);return_scene.targets.erase(id)
		update_return_label()
	if return_scene.targets.is_empty():return_scene.state="done"
func welcome_letter(id:String)->void:
	var source:String="return:"+str(int(return_scene.saved_wall))
	var participants:Array=["human",id]
	var words:Array=voices.care[tag(id)].returns[int(return_scene.band)]
	var facts:Dictionary={"localized":{"zh":"你回来了。","en":"You returned to the island."}}
	var books:RefCounted=g.memory_books
	books.add(id,w.world_id,source,"facts","memory.localized_fact",facts,w.days.day(),"game",participants,w.forest.clock)
	var key:String=(id+"|"+w.world_id+"|"+source+"|facts").sha256_text()
	if not books.entries.has(key):return
	var letter_id:String=(id+"|"+w.world_id+"|"+source+"|letters").sha256_text()
	if books.entries.has(letter_id) or books.deleted.has(letter_id):return
	var binding:Dictionary={"source_id":key,"event_id":source,"day":w.days.day(),
		"local":{"zh":words[0]+" 我给你留了个位置。回来就好，其他事慢慢说。","en":words[1]+" I left you a place beside me. The rest can wait."}}
	if not model_offer(id,"letter",{"away_hours":int(float(return_scene.absence_seconds)/3600),"language":g.language,
			"greeting_eligible":return_scene.get("targets",{}).has(id)},binding):
		save_return_letter(id,binding)

func save_return_letter(id:String,binding:Dictionary,reply:String="")->bool:
	var books:RefCounted=g.memory_books
	if not books.entries.has(binding.source_id):return false
	var params:Dictionary={"source_ids":[binding.source_id]}
	if reply.is_empty():params["localized"]=binding.local
	if not books.add(id,w.world_id,binding.event_id,"letters","memory.localized_fact" if reply.is_empty() else reply,params,int(binding.day),"local" if reply.is_empty() else "ai",["human",id],w.forest.clock):return false
	if str(binding.event_id)=="return:"+str(int(return_scene.get("saved_wall",-1))):
		return_scene.wrote=true
		update_return_label()
	return true

func tick(delta:float)->void:
	if delta<=0:return
	tick_care();tick_return();place_panel(snack_card);place_panel(care_card)
	night.tick()
	for id in model_pending.keys():
		if w.forest.clock>=float(model_pending[id].until):model_failed(id,"timeout")
		elif not w.director.model_controlled(id) or not g.autonomy.native_heart(id):model_failed(id,"source_changed")
func model_stage(id:String,kind:String,token:String,state:String,reason:String="",more:Dictionary={})->void:
	var row:Dictionary={"actor":id,"type":kind,"request":token,"state":state,"reason":reason,"at":w.forest.clock}.merged(more)
	if state=="waiting" and model_trace.any(func(item):return item.request==token and item.state==state and item.reason==reason):return
	model_trace.append(row)
	if model_trace.size()>96:model_trace.pop_front()
func model_letter_opened(entry_id:String)->void:
	var receipt:Dictionary=model_letters.get(entry_id,{})
	if receipt.is_empty():return
	model_letters.erase(entry_id)
	model_stage(receipt.actor,"letter",receipt.id,"shown","mail_view",{"text":receipt.text})
func model_failed(id:String,reason:String)->void:
	var entry:Dictionary=model_pending.get(id,{})
	if entry.is_empty():return
	model_pending.erase(id)
	model_stage(id,entry.kind,entry.id,"fallback",reason)
	if entry.kind=="care" and entry.binding.has("fallback") and not busy(id) and w.actors[id].region_id==w.actors.human.region_id and w.point(w.actors[id]).distance_to(w.point(w.actors.human))<=12:
		say(id,entry.binding.fallback,"company_care")
	elif entry.kind=="letter":save_return_letter(id,entry.binding)
func model_offer(id:String,kind:String,context:Dictionary,binding:Dictionary)->bool:
	var reason:=""
	if g.autonomy==null or not w.director.model_controlled(id) or not g.autonomy.native_heart(id):reason="no_native_connection"
	elif not g.resident_connections.preferences.preference(id).get("autonomy_enabled",false):reason="autonomy_disabled"
	elif model_pending.has(id):reason="prior_company_request"
	if not reason.is_empty():
		model_stage(id,kind,"","not_sent",reason)
		return false
	var token:String=Crypto.new().generate_random_bytes(8).hex_encode()
	var facts:Dictionary=context.duplicate(true)
	if kind in ["care","letter","promise"]:
		var rows:Array=g.memory_books.list_for(id,"facts").filter(func(row):return row.world_id==w.world_id and row.source=="game" and row.params.get("legacy",{}).get("kind","") in ["first_meeting","first_shared_meal","favorite_taste","care_first","company_promise_first","fishing_catch","shared_barbecue","home_island_arrival"])
		facts["recent"]=rows.slice(-3).map(func(row):return g.memory_books.render(row).left(130))
	facts["language"]=g.language
	model_pending[id]={"id":token,"kind":kind,"context":facts,"binding":binding.duplicate(true),"until":w.forest.clock+float(settings.model_wait_seconds),"turn":""}
	model_stage(id,kind,token,"queued")
	return true
func model_ready(id:String)->bool:
	return model_pending.has(id) and str(model_pending[id].turn).is_empty() and w.forest.clock<float(model_pending[id].until)
func model_waiting(id:String,kind:String)->bool:
	return model_pending.get(id,{}).get("kind","")==kind and w.forest.clock<float(model_pending[id].until)
func scheduler_state(id:String,state:String,reason:String="")->void:
	var entry:Dictionary=model_pending.get(id,{})
	if not entry.is_empty():model_stage(id,entry.kind,entry.id,state,reason)
func fireside_model_ready(id:String)->bool:
	return model_ready(id) and fireside_model_bound(id,"")
func fireside_model_bound(id:String,turn:String)->bool:
	var entry:Dictionary=model_pending.get(id,{})
	return entry.get("turn","invalid")==turn and w.forest.clock<float(entry.get("until",0)) and entry.get("kind","") in ["story","question"] and night.scene.get("id")==id and night.valid_scene() and not w.activities.held.get(id,false) and not w.activities.members.has(id) and w.hunger.rank(id)<3
func model_card(id:String,turn:String)->Dictionary:
	if not model_pending.has(id) or w.forest.clock>float(model_pending[id].until):return {}
	var entry:Dictionary=model_pending[id]
	entry.turn=turn
	return {"id":entry.id,"kind":entry.kind,"facts":entry.context.duplicate(true)}
func model_result(id:String,turn:String,result:Variant)->bool:
	var entry:Dictionary=model_pending.get(id,{})
	if entry.is_empty() or entry.turn!=turn or w.forest.clock>=float(entry.until):return false
	model_stage(id,entry.kind,entry.id,"received")
	if not result is Dictionary or result.get("id")!=entry.id:
		model_failed(id,"invalid_reply");return false
	var delivered:Dictionary={}
	match str(entry.kind):
		"care":
			var key:String=id+":"+str(entry.binding.action)
			if int(care_count.get(key,0))!=int(entry.binding.care_sequence) or not line_valid(result.get("text"),68) or busy(id) or w.point(w.actors[id]).distance_to(w.point(w.actors.human))>12 or w.actors[id].region_id!=w.actors.human.region_id:
				model_failed(id,"invalid_care");return false
			g.view.say(result.text,"model",id,"company_care")
			delivered["text"]=result.text
		"letter":
			if not line_valid(result.get("text"),360) or not save_return_letter(id,entry.binding,result.text):
				model_failed(id,"invalid_letter");return false
			var key:String=(id+"|"+w.world_id+"|"+entry.binding.event_id+"|letters").sha256_text()
			model_letters[key]={"actor":id,"id":entry.id,"text":result.text}
			if model_letters.size()>32:model_letters.erase(model_letters.keys()[0])
			delivered["text"]=result.text
			if line_valid(result.get("greeting"),68) and return_scene.get("targets",{}).has(id):
				if not return_scene.has("model_greetings"):return_scene["model_greetings"]={}
				return_scene.model_greetings[id]={"id":entry.id,"text":result.greeting}
				model_stage(id,"greeting",entry.id,"received")
		"story","question","promise":
			if not night.model_result(id,entry,result):
				model_failed(id,"invalid_scene_reply");return false
			if entry.kind=="story":delivered["lines"]=result.lines.duplicate()
			elif entry.kind=="question":delivered["text"]=result.text;delivered["options"]=result.options.duplicate()
			else:delivered["text"]=night.turn.get("question","")
		_:return false
	model_pending.erase(id)
	var stage:String="saved" if entry.kind=="letter" else "accepted" if entry.kind=="story" or (entry.kind=="promise" and not line_valid(result.get("text"),55)) else "shown"
	model_stage(id,entry.kind,entry.id,stage,"letter_saved" if entry.kind=="letter" else "ui",delivered)
	note("model_written",{"actor":id,"type":entry.kind}.merged(delivered));return true
func line_valid(value:Variant,limit:int)->bool:
	return value is String and not value.strip_edges().is_empty() and value.length()<=limit and not "\n" in value and Persona.safe_speech(value)
