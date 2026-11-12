extends Node
## Fifth-tier subjective archive. Observation only: no route, stock or job authority.
const Text=preload("res://scripts/localization.gd")
const AXES=["joy","tired","missing","curious","hurt","safe"]
var host_ref:WeakRef
var game:Node:
	get:return host_ref.get_ref()
var directory:=""
var profiles:Dictionary={}
var seen:Dictionary={}
var fresh_facts:Dictionary={}
var active_levels:Dictionary={}
var day_seen:=1
var elapsed:=0.0
var serial:=0
var pending_reflections:Dictionary={}
func setup(host:Node)->void:
	host_ref=weakref(host);directory=game.data_dir.path_join("life")
	DirAccess.make_dir_recursive_absolute(directory);day_seen=game.world.days.day()
	for filename in DirAccess.get_files_at(directory):
		if not filename.ends_with(".life.json"):continue
		var value:Variant=game.memory_books.read_json(directory.path_join(filename))
		if valid_profile(value):profiles[value.resident_id]=value
	for entry in game.memory_books.entries.values():seen[entry.id]=true
	game.memory_books.entry_deleted.connect(forget)
	game.world.farms.watered.connect(watered)
func enabled(id:String)->bool:
	return game.world.actors.has(id) and id!="human" and game.resident_connections.preferences.preference(id).level=="lifeblood"
func fresh(id:String)->Dictionary:
	return {"version":1,"resident_id":id,"mood":{"joy":50.0,"tired":20.0,"missing":20.0,"curious":50.0,"hurt":10.0,"safe":50.0},"records":[],"curve":[],"dreams":[],"selves":[],"wishes":[],"usage":[],"world_days":{}}
func profile(id:String)->Dictionary:
	if not profiles.has(id):profiles[id]=fresh(id)
	return profiles[id]
func persist(id:String)->bool:
	return game.memory_books.atomic(directory.path_join(id.sha256_text()+".life.json"),profile(id))
func valid_profile(value:Variant)->bool:
	if not value is Dictionary or value.get("version")!=1 or not value.get("resident_id") is String or value.resident_id.is_empty() or value.resident_id=="human" or not value.get("mood") is Dictionary:return false
	for axis in AXES:
		var n:Variant=value.mood.get(axis)
		if not (n is float or n is int) or not is_finite(n) or n<0 or n>100:return false
	for key in ["records","curve","dreams","selves","wishes","usage"]:
		if not value.get(key) is Array or value[key].size()>100000:return false
		for record in value[key]:
			if not record is Dictionary:return false
			if not record.get("id","") is String or not record.get("text","") is String:return false
			if not record.get("world_id") is String or not record.get("day") is int and not record.get("day") is float:return false
			for number_key in ["day","at"]:
				var n:Variant=record.get(number_key)
				if not (n is int or n is float) or not is_finite(n) or n<0:return false
			if float(record.day)!=floor(float(record.day)) or record.text.length()>1200:return false
			if record.has("source_ids") and (not record.source_ids is Array or not record.source_ids.all(func(id):return id is String and id.length()==64 and id.is_valid_hex_number(false))):return false
			if key in ["curve","records"]:
				if not record.get("mood") is Dictionary:return false
				for axis in AXES:
					var n:Variant=record.mood.get(axis)
					if not (n is int or n is float) or not is_finite(n) or n<0 or n>100:return false
			if key=="wishes" and (record.get("kind") not in ["farm","fish"] or record.get("status") not in ["pending","completed"] or (record.kind=="farm" and not record.get("target_id") is String)):return false
			if key=="usage":
				for field in ["total_tokens","input_tokens","output_tokens"]:
					var n:Variant=record.get(field)
					if not (n is int or n is float) or not is_finite(n) or n<0 or n!=floor(n):return false
				if int(record.total_tokens)<int(record.input_tokens)+int(record.output_tokens) or not record.get("complete",false) is bool or not record.get("reported",true) is bool:return false
				var duration:Variant=record.get("elapsed_ms")
				if duration!=null and (not (duration is int or duration is float) or not is_finite(duration) or duration<0):return false
	return value.get("world_days") is Dictionary and JSON.stringify(value).to_utf8_buffer().size()<=16777216
func stamp()->Dictionary:
	return {"world_id":game.world.world_id,"day":game.world.days.day(),"at":game.world.forest.clock}
func append_record(id:String,kind:String,text:String,sources:Array,origin:String="local",key:String="")->void:
	if not enabled(id) or text.is_empty():return
	var p:Dictionary=profile(id);var record:Dictionary=stamp()
	serial+=1;record.merge({"id":key if not key.is_empty() else (id+kind+str(Time.get_ticks_usec())+str(serial)).sha256_text(),"kind":kind,"text":text.left(1200),"source_ids":sources.duplicate(),"origin":origin,"mood":p.mood.duplicate(true)})
	if origin=="local" and kind=="feeling":record.local_key="gestation.event_feeling"
	if p.records.any(func(e):return e.id==record.id):return
	p.records.append(record)
	# Subjective entries stay grounded in retained canonical game facts.
	if not sources.is_empty():game.memory_books.add(id,game.world.world_id,"life:"+record.id,"feelings",record.text,{"kind":"life_"+kind,"source_ids":sources},game.world.days.day(),origin,[id],game.world.forest.clock)
func forget(entry:Dictionary)->void:
	var id:String=str(entry.resident_id)
	if not profiles.has(id):return
	var p:Dictionary=profiles[id]
	for field in ["records","dreams","selves","wishes"]:p[field]=p[field].filter(func(e):return entry.id not in e.get("source_ids",[]))
	persist(id)
func tick(delta:float)->void:
	if delta<=0:return
	elapsed+=delta
	if elapsed<1:return
	var actual:float=elapsed;elapsed=0
	fresh_facts.clear()
	settle_reflections()
	for id in game.world.director.routines:
		if not enabled(id):active_levels[id]=false;continue
		if not active_levels.get(id,false):
			for entry in game.memory_books.list_for(id):seen[entry.id]=true
			active_levels[id]=true
		var p:Dictionary=profile(id)
		for axis in AXES:p.mood[axis]=move_toward(float(p.mood[axis]),float(fresh(id).mood[axis]),actual*.015)
		if p.selves.is_empty():self_page(id,game.world.days.day(),[],"local","gestation.self_initial")
		for entry in game.memory_books.entries.values():
			if seen.has(entry.id) or entry.resident_id!=id:continue
			seen[entry.id]=true
			if entry.world_id!=game.world.world_id or entry.layer!="facts":continue
			if entry.params.get("human_quote",false):
				var words:String=game.memory_books.render(entry).to_lower()
				if [Text.source("gestation.praise_thanks"),Text.source("gestation.praise_good"),Text.source("gestation.praise_great"),"thank you","well done","great job"].any(func(word):return word in words):p.mood.joy=clampf(float(p.mood.joy)+8,0,100);p.mood.safe=clampf(float(p.mood.safe)+6,0,100)
			if entry.source!="game":continue
			if not fresh_facts.has(id):fresh_facts[id]=[]
			fresh_facts[id].append(entry)
			var kind:String=str(entry.params.get("legacy",{}).get("kind",""))
			var change:Dictionary={"meal":{"joy":12,"safe":10,"tired":-8},"shared_barbecue":{"joy":8,"safe":6},"fishing_catch":{"curious":12,"joy":6},"gomoku_match":{"joy":6,"curious":8},"wish_completed":{"joy":12,"safe":6},"work_completed":{"tired":8,"safe":6}}.get(kind,{"curious":2})
			for axis in change:p.mood[axis]=clampf(float(p.mood[axis])+float(change[axis]),0,100)
			append_record(id,"feeling",Text.text("gestation.event_feeling").replace("{event}",game.memory_books.render(entry)),[entry.id])
		var actor:Dictionary=game.world.actors[id];var human:Dictionary=game.world.actors.human
		var near:bool=actor.region_id==human.region_id and game.world.point(actor).distance_to(game.world.point(human))<=8
		p.mood.missing=clampf(float(p.mood.missing)+actual*(-.05 if near else .025),0,100)
		if near:p.mood.safe=clampf(float(p.mood.safe)+actual*.01,0,100);p.absent_seconds=0.0
		elif not game.world.work.jobs.has(id):
			p.absent_seconds=float(p.get("absent_seconds",0))+actual
			if float(p.absent_seconds)>600:p.mood.hurt=clampf(float(p.mood.hurt)+actual*.005,0,100)
		if game.world.work.jobs.has(id):p.mood.tired=clampf(float(p.mood.tired)+actual*.02,0,100)
		var key:String=game.world.world_id+":"+str(game.world.days.day())
		if not p.world_days.has(key):
			if day_seen!=game.world.days.day():end_day(id,maxi(1,game.world.days.day()-1))
			p.world_days[key]=true
			if game.world.days.day()%3==0 and not p.selves.any(func(e):return e.world_id==game.world.world_id and int(e.day)==game.world.days.day()):self_page(id,game.world.days.day(),sources(id),"local","gestation.self_local")
		observe_weather(id);update_wishes(id)
		if p.curve.is_empty() or p.curve[-1].world_id!=game.world.world_id or game.world.forest.clock-float(p.curve[-1].at)>=30:
			var point:Dictionary=stamp();point["id"]=key+":"+str(game.world.forest.clock);point.text="";point.mood=p.mood.duplicate(true);p.curve.append(point);persist(id)
	day_seen=game.world.days.day()
func flush()->void:
	for id in profiles:persist(id)
func _process(delta:float)->void:tick(delta)
func sources(id:String,day:int=0)->Array:
	return game.memory_books.list_for(id,"facts").filter(func(e):return e.world_id==game.world.world_id and e.source=="game" and (day==0 or int(e.day)==day)).slice(-30).map(func(e):return e.id)
func observe_weather(id:String)->void:
	var p:Dictionary=profile(id);var weather:String=str(game.world.weather.current().get("id",""));var key:String=game.world.world_id+":"+str(game.world.days.day())+":"+weather
	if p.get("weather_key","")==key:return
	p.weather_key=key
	if weather=="rain":p.mood.safe=clampf(float(p.mood.safe)+4,0,100);p.mood.curious=clampf(float(p.mood.curious)+3,0,100)
func end_day(id:String,day:int)->void:
	var p:Dictionary=profile(id);var key:String=game.world.world_id+":"+str(day)
	if p.dreams.any(func(e):return e.id==key):return
	var proof:Array=sources(id,day)
	var row:Dictionary=stamp();row.id=key;row.day=day;row.source_ids=proof;row.origin="local";row.text="gestation.dream_local";row.today="gestation.today_local";p.dreams.append(row)
	append_record(id,"dream",row.text,proof,"local","dream:"+key);persist(id)
func self_page(id:String,day:int,proof:Array,origin:String,text:String)->void:
	var row:Dictionary=stamp();row.id=game.world.world_id+":"+str(day);row.day=day;row.source_ids=proof;row.origin=origin;row.text=text
	var rows:Array=profile(id).selves
	var index:int=rows.find_custom(func(e):return e.id==row.id)
	if index>=0:rows[index]=row
	else:rows.append(row)
	persist(id)
func observe_context(id:String,key:String)->void:
	if not enabled(id) or key.is_empty():return
	begin_call(id,key)
	var actor:Dictionary=game.world.actors[id]
	var observed:Dictionary={"day":game.world.days.day(),"phase":str(game.world.days.phase().id),"weather":str(game.world.weather.current().get("id","")),"region_id":str(actor.region_id),"position":actor.position.duplicate(),"activity":str(actor.activity)}
	game.memory_books.add(id,game.world.world_id,"life-observed:"+key,"facts",Text.text("gestation.observed").replace("{weather}",Text.content(str(game.world.weather.current().get("name",observed.weather)))).replace("{phase}",Text.content(str(game.world.days.phase().get("name",observed.phase)))),{"legacy":{"kind":"life_observation","facts":observed}},game.world.days.day(),"game",[id],game.world.forest.clock)
func request(id:String)->Dictionary:
	if not enabled(id):return {}
	return {"version":1,"mood":profile(id).mood.duplicate(true),"source_ids":sources(id),"wishes":wish_options(id),"active_wishes":active_wishes(id),"instruction":"Return observe, feel, want, act, reflect. feel={text,source_ids}; cite supplied true facts. act must equal intents. reflect describes your current thought, never an uncompleted outcome. Optional life_day={dream,today,self}; self only every three game days. The self string must cover all four: your authored personality; recent genuine likes from supplied facts; your feelings toward the human; and who you hope to become. If recent likes are unknown, admit that; never invent shared history. Wishes are proposals only, never permissions. active_wishes contains only your pending wishes in this world and host-verified progress. During an already authorized idle autonomy turn, consider an available intent_hints action as your ordinary own intent; during authorized stewardship, include it in the ordinary planning array. Otherwise use existing dialogue or host-confirmation proposals. Hints never authorize a new call, movement, work, another resident, or completion; the original host must validate every action again. Never repeat local_execution work or mark progress from AI text."}
func accept(id:String,value:Dictionary,allowed:Array,key:String)->bool:
	if not enabled(id):return false
	for field in ["observe","want","reflect"]:
		if not value.get(field) is String or value[field].strip_edges().is_empty() or value[field].length()>1200:return false
	var feel:Variant=value.get("feel")
	if not feel is Dictionary or not feel.get("text") is String or feel.text.strip_edges().is_empty() or feel.text.length()>1200 or not feel.get("source_ids") is Array or feel.source_ids.is_empty():return false
	for proof in feel.source_ids:
		if proof not in allowed or not game.memory_books.entries.has(proof):return false
		var fact:Dictionary=game.memory_books.entries[proof]
		if fact.resident_id!=id or fact.source!="game" or fact.layer!="facts":return false
	if not value.get("act") is Array or value.act!=value.get("intents",[]):return false
	for field in ["observe","feel","want","act","reflect"]:
		var line:String=str(feel.text) if field=="feel" else JSON.stringify(value.act) if field=="act" else str(value[field])
		if field=="reflect" and not value.act.is_empty():
			pending_reflections[id]={"key":key,"text":line,"source_ids":feel.source_ids.duplicate(),"steps":value.act.duplicate(true),"bound":false}
		else:append_record(id,field,line,feel.source_ids,"ai",key+":"+field)
	var wishes:Variant=value.get("life_wishes",[])
	if wishes is Array and wishes.size()<=3:
		for wish in wishes:
			if not wish is Dictionary:continue
			var option:Array=wish_options(id).filter(func(o):return o.id==wish.get("id"))
			if option.is_empty() or profile(id).wishes.filter(func(w):return w.get("status")=="pending").size()>=3 or profile(id).wishes.any(func(w):return w.id==wish.id and w.status=="pending"):continue
			var row:Dictionary=stamp();row.merge(option[0]);row.source_ids=feel.source_ids.duplicate();row.status="pending";profile(id).wishes.append(row)
	persist(id);return true
func bind_plan(id:String,key:String)->void:
	if not pending_reflections.has(id) or pending_reflections[id].key!=key:return
	var plan:Dictionary=game.intentions.plans.get(id,{})
	if plan.is_empty() or plan.steps!=pending_reflections[id].steps:pending_reflections.erase(id);return
	pending_reflections[id].plan=plan;pending_reflections[id].bound=true
	pending_reflections[id].plan.life_turn_key=key
func settle_reflections()->void:
	for id in pending_reflections.keys():
		var wait:Dictionary=pending_reflections[id]
		if not wait.bound:continue
		if game.intentions.plans.has(id) and is_same(game.intentions.plans[id],wait.plan):continue
		# The original plan dictionary must reach the end, and its final real completion
		# receipt must match the last action. Stop/reload/replacement never reflects success.
		var receipts:Array=game.intentions.history.filter(func(e):return e.actor_id==id and e.get("life_turn_key","")==wait.key)
		if receipts.filter(func(e):return e.result=="completed").size()>=wait.steps.size() and not receipts.is_empty() and receipts[-1].result=="completed" and receipts[-1].action==str(wait.steps[-1].action) and int(wait.plan.index)>=wait.steps.size():
			append_record(id,"reflect",str(wait.text),wait.source_ids,"ai",wait.key+":reflect");persist(id)
		pending_reflections.erase(id)
func accept_day(id:String,value:Variant,allowed:Array,ended:int)->bool:
	if not enabled(id) or not value is Dictionary:return false
	for field in ["dream","today"]:
		if not value.get(field) is String or value[field].strip_edges().is_empty() or value[field].length()>1200:return false
	var grounded:Array=allowed.filter(func(source):return game.memory_books.entries.has(source) and game.memory_books.entries[source].resident_id==id and game.memory_books.entries[source].world_id==game.world.world_id and game.memory_books.entries[source].layer=="facts" and game.memory_books.entries[source].source=="game" and int(game.memory_books.entries[source].day)==ended)
	if grounded.is_empty():return false
	var key:String=game.world.world_id+":"+str(ended);var rows:Array=profile(id).dreams
	var index:int=rows.find_custom(func(e):return e.id==key)
	if index<0:end_day(id,ended);index=rows.size()-1
	rows[index].text=value.dream;rows[index].today=value.today;rows[index].origin="ai";rows[index].source_ids=grounded.duplicate()
	if value.get("self") is String and not value.self.strip_edges().is_empty() and value.self.length()<=1200 and (ended%3==0):self_page(id,ended,grounded,"ai",value.self)
	persist(id);return true
func wish_options(id:String)->Array:
	var result:Array=[]
	if not enabled(id):return result
	for option in game.memory_life.goal_options() if game.memory_life!=null else []:
		if not game.world.residents.supports(game.world.actors[id],"plant") or not game.world.residents.supports(game.world.actors[id],"water") or not game.world.farms.allowed(id,str(option.id)):continue
		result.append({"id":"farm:"+str(option.id),"kind":"farm","target_id":option.id,"text":Text.text("gestation.wish_farm").replace("{farm}",str(option.name))})
	if game.world.residents.supports(game.world.actors[id],"fish") and not game.world.fishing.nearby_shores(id,1).is_empty():result.append({"id":"fish:"+game.world.world_id,"kind":"fish","text":Text.text("gestation.wish_fish")})
	return result
func watered(id:String,farm_id:String,plot_id:String,job_id:String)->void:
	if not enabled(id) or not game.world.farms.plots.has(plot_id):return
	var plot:Dictionary=game.world.farms.plots[plot_id]
	if not plot.watered or plot.crop_id.is_empty():return
	for wish in profile(id).wishes:
		if wish.kind!="farm" or wish.status!="pending" or wish.world_id!=game.world.world_id or wish.target_id!=farm_id:continue
		var event_id:String="life-water:"+job_id
		game.memory_books.add(id,game.world.world_id,event_id,"facts","gestation.water_proof",{"legacy":{"kind":"life_wish_water","farm_id":farm_id,"plot_id":plot_id,"job_id":job_id,"crop_id":plot.crop_id,"planted_at":plot.planted_at}},game.world.days.day(),"game",[id],game.world.forest.clock)
		if not wish.get("progress") is Dictionary:wish.progress={}
		wish.progress[plot_id]=(id+"|"+game.world.world_id+"|"+event_id+"|facts").sha256_text();persist(id)
func wish_plot_proof(id:String,row:Dictionary,plot:Dictionary)->String:
	if not row.get("progress") is Dictionary or plot.crop_id.is_empty() or not plot.watered:return ""
	var proof:String=str(row.progress.get(plot.id,""))
	if not game.memory_books.entries.has(proof):return ""
	var fact:Dictionary=game.memory_books.entries[proof];var actual:Dictionary=fact.params.get("legacy",{})
	if fact.resident_id!=id or fact.world_id!=row.world_id or fact.source!="game" or float(fact.at)<float(row.at) or actual.get("kind")!="life_wish_water" or actual.get("farm_id")!=row.target_id or actual.get("plot_id")!=plot.id or actual.get("crop_id")!=plot.crop_id or actual.get("planted_at")!=plot.planted_at:return ""
	return proof
func farm_wish_done(id:String,row:Dictionary)->bool:
	var plots:Array=game.world.farms.farm_plots(str(row.target_id))
	return not plots.is_empty() and plots.all(func(plot):return not wish_plot_proof(id,row,plot).is_empty())
func wish_idle(id:String)->bool:
	var w:RefCounted=game.world
	return w.director.model_controlled(id) and not w.work.jobs.has(id) and not w._routes.has(id) and not w.farms.active(id) and not w.projects.active(id) and not w.homestead.active(id) and not w.shared_activity.holds(id) and not w.gomoku.active(id) and not w.deliveries.active(id) and not w.activities.commanded(id) and not w.activities.blocked(id,false) and not w.director.routines[id].held and not game.questions.has(id) and not game.group_questions.has(id)
func fish_wish_hint(id:String)->bool:
	var w:RefCounted=game.world;var f:RefCounted=w.fishing
	if not wish_idle(id) or not w.residents.supports(w.actors[id],"fish") or w.hunger.rank(id)>=3 or w.loaded(id) or not f.pending(id).is_empty() or f.fish.size()>=int(f.rules.max_fish):return false
	var coast:Dictionary=f.shore(id)
	if coast.is_empty():return false
	var reserved:int=w.work.jobs.values().filter(func(job):return job.get("intent")=="fish" and job.get("water_id")==coast.water_id).size()
	if int(f.waters[coast.water_id].available)<=reserved:return false
	return not w.work.jobs.values().any(func(job):return job.get("intent")=="fish" and job.get("region_id")==w.actors[id].region_id and w.point(w.actors[id]).distance_to(Vector2(job.position[0],job.position[1]))<maxf(2.0,float(f.rules.shore_spacing)))
func active_wishes(id:String)->Array:
	var result:Array=[]
	if not enabled(id):return result
	var w:RefCounted=game.world
	for wish in profile(id).wishes:
		if wish.get("status")!="pending" or wish.get("world_id")!=w.world_id:continue
		var item:Dictionary={"id":str(wish.id),"kind":str(wish.kind),"text":str(wish.text).left(1200),"status":"pending","progress":{"current":0,"total":1},"source_ids":[],"intent_hints":[]}
		if wish.kind=="fish":
			if fish_wish_hint(id):item.intent_hints.append({"action":"fish"})
		elif wish.kind=="farm":
			var farm_id:String=str(wish.target_id);item.target_id=farm_id
			var plots:Array=w.farms.farm_plots(farm_id);item.progress.total=plots.size()
			for plot in plots:
				var proof:String=wish_plot_proof(id,wish,plot)
				if not proof.is_empty():
					item.progress.current+=1
					if item.source_ids.size()<3:item.source_ids.append(proof)
			if wish_idle(id) and w.hunger.rank(id)<2 and w.farms.allowed(id,farm_id) and w.residents.supports(w.actors[id],"plant") and w.residents.supports(w.actors[id],"water"):
				# Existing read-only host preview enforces real seeds, dry plots and claims.
				var preview:Dictionary=w.farms.preview_host_orders([id],"plant",farm_id,"mixed")
				for row in preview.get("rows",[]):
					if not row.get("allowed",false):continue
					if row.plot_ids.any(func(pid):return w.farms.stage(w.farms.plots[pid])=="dry"):item.intent_hints.append({"action":"water","target_id":farm_id})
					elif row.plot_ids.any(func(pid):return w.farms.stage(w.farms.plots[pid])=="empty"):item.intent_hints.append({"action":"plant","target_id":farm_id})
		result.append(item)
		if result.size()>=3:break
	return result.duplicate(true)
func update_wishes(id:String)->void:
	var p:Dictionary=profile(id)
	if p.wishes.is_empty():
		var options:Array=wish_options(id)
		if not options.is_empty():
			var row:Dictionary=stamp();row.merge(options[0]);row.status="pending";row.source_ids=sources(id);p.wishes.append(row);persist(id);return
	for row in p.wishes:
		if row.status!="pending" or row.world_id!=game.world.world_id:continue
		if row.kind=="farm" and farm_wish_done(id,row):
			var event_id:String="life-goal-completed:"+str(row.id)
			game.memory_books.add(id,game.world.world_id,event_id,"facts","gestation.farm_proof",{"farm_id":row.target_id,"source_ids":row.progress.values(),"legacy":{"kind":"goal_completed","farm_id":row.target_id}},game.world.days.day(),"game",[id],game.world.forest.clock)
			row.status="completed";row.source_ids=[(id+"|"+game.world.world_id+"|"+event_id+"|facts").sha256_text()];append_record(id,"wish",row.text,row.source_ids,"local","wish:"+row.id);persist(id);continue
		var proof:Array=fresh_facts.get(id,[]).filter(func(e):return e.world_id==row.world_id and e.source=="game" and str(e.params.get("legacy",{}).get("kind","")) in (["fishing_catch"] if row.kind=="fish" else ["goal_completed"]) and (row.kind=="fish" or e.params.get("farm_id",e.params.get("legacy",{}).get("farm_id",""))==row.target_id))
		if not proof.is_empty():
			row.status="completed";row.source_ids=proof.map(func(e):return e.id);append_record(id,"wish",row.text,row.source_ids,"local","wish:"+row.id);persist(id)
func begin_call(id:String,key:String)->void:
	if not enabled(id) or key.is_empty():return
	var rows:Array=profile(id).usage
	if rows.any(func(row):return row.id==key):return
	var row:Dictionary=stamp();row.merge({"id":key,"text":"","total_tokens":0,"input_tokens":0,"output_tokens":0,"calendar_day":Time.get_date_string_from_system(),"elapsed_ms":null,"complete":false,"reported":false})
	rows.append(row);persist(id)
func reject_before_inference(id:String,key:String)->void:
	if not profiles.has(id):return
	var rows:Array=profiles[id].usage
	var index:int=rows.find_custom(func(row):return row.id==key)
	if index<0 or rows[index].get("reported",false):return
	rows[index].status="rejected_before_inference";rows[index].complete=true;rows[index].reported=true;rows[index].elapsed_ms=0
	persist(id)
func record_event(id:String,event:Dictionary)->void:
	if event.get("kind")=="state" and event.get("state") in ["thinking","acting"]:begin_call(id,str(event.get("turn_key","")))
	if event.get("kind")=="usage":record_usage(id,event)
func record_usage(id:String,event:Dictionary)->void:
	if not enabled(id) or event.get("kind")!="usage":return
	for field in ["total_tokens","input_tokens","output_tokens"]:
		var amount:Variant=event.get(field)
		if not (amount is int or amount is float) or not is_finite(amount) or amount<0 or amount!=floor(amount):return
	if int(event.total_tokens)<int(event.input_tokens)+int(event.output_tokens) or not event.get("complete",false) is bool:return
	var rows:Array=profile(id).usage;var key:String=str(event.get("turn_key",""))
	if key.is_empty():return
	var index:int=rows.find_custom(func(e):return e.id==key)
	if index>=0:
		for field in ["total_tokens","input_tokens","output_tokens"]:
			if int(rows[index][field])>int(event[field]):return
		if rows[index].get("complete",false) and not event.get("complete",false):return
	var duration:Variant=event.get("ai_reply_ms")
	if not (duration is int or duration is float) or not is_finite(duration) or duration<0:duration=null
	var row:Dictionary=stamp();row.merge({"id":key,"text":"","total_tokens":int(event.total_tokens),"input_tokens":int(event.input_tokens),"output_tokens":int(event.output_tokens),"calendar_day":Time.get_date_string_from_system(),"elapsed_ms":duration,"complete":event.get("complete",false),"reported":true})
	if index>=0:rows[index]=row
	else:rows.append(row)
	persist(id)
func today_usage(id:String)->Dictionary:
	var result:Dictionary={"tokens":0,"elapsed_ms":0,"unknown_time":false,"unknown_tokens":false}
	for row in snapshot(id).get("usage",[]):
		if row.get("calendar_day","")!=Time.get_date_string_from_system():continue
		result.tokens+=int(row.total_tokens)
		if not row.get("reported",true) or not row.get("complete",false):result.unknown_tokens=true
		if row.get("elapsed_ms") is int or row.get("elapsed_ms") is float:result.elapsed_ms+=int(row.elapsed_ms)
		else:result.unknown_time=true
	return result
func snapshot(id:String)->Dictionary:
	return profile(id).duplicate(true) if profiles.has(id) or enabled(id) else {}
func export_bundle()->Dictionary:return profiles.duplicate(true)
func valid_bundle(data:Variant)->bool:
	return data is Dictionary and data.size()<=128 and data.keys().all(func(id):return id is String and valid_profile(data[id]) and data[id].resident_id==id)
func import_bundle(data:Dictionary)->bool:
	if not valid_bundle(data):return false
	for id in data:
		var incoming:Dictionary=data[id]
		incoming=incoming.duplicate(true)
		for field in ["records","dreams","selves","wishes"]:
			incoming[field]=incoming[field].filter(func(row):return row.get("source_ids",[]).all(func(source):return game.memory_books.entries.has(source) and game.memory_books.entries[source].resident_id==id and game.memory_books.entries[source].layer=="facts" and game.memory_books.entries[source].source=="game"))
		incoming.wishes=incoming.wishes.filter(func(row):return row.status!="completed" or row.source_ids.any(func(source):return str(game.memory_books.entries[source].params.get("legacy",{}).get("kind",""))==("fishing_catch" if row.kind=="fish" else "goal_completed") and (row.kind=="fish" or game.memory_books.entries[source].params.get("farm_id",game.memory_books.entries[source].params.get("legacy",{}).get("farm_id",""))==row.target_id)))
		if not profiles.has(id):profiles[id]=incoming.duplicate(true)
		else:
			for field in ["records","curve","dreams","selves","wishes","usage"]:
				for row in incoming[field]:
					if not profiles[id][field].any(func(old):return old.id==row.id):profiles[id][field].append(row.duplicate(true))
		if not persist(id):return false
	return true
func render_row(row:Dictionary)->String:
	if row.get("kind","")=="act":
		var steps:Variant=JSON.parse_string(str(row.get("text","")))
		if steps is Array:
			if steps.is_empty():return Text.text("gestation.act_rest")
			var labels:Array[String]=[]
			for step in steps:
				if not step is Dictionary:continue
				var key:String="intent.action."+str(step.get("action",""))
				labels.append(Text.text(key) if Text.entries.has(key) else Text.text("gestation.act_other"))
			return Text.text("gestation.act_plan").replace("{actions}"," → ".join(labels))
	if row.get("origin","")=="ai":return str(row.text)
	if row.get("local_key","")=="gestation.event_feeling":
		var proof:Array=row.get("source_ids",[])
		if not proof.is_empty() and game.memory_books.entries.has(proof[0]):return Text.text("gestation.event_feeling").replace("{event}",game.memory_books.render(game.memory_books.entries[proof[0]]))
	return Text.text(str(row.text)) if Text.entries.has(str(row.text)) else str(row.text)
func render_today(row:Dictionary)->String:
	return Text.text(str(row.get("today",""))) if Text.entries.has(str(row.get("today",""))) else str(row.get("today",""))
func export_html(id:String,path:String)->bool:
	var p:Dictionary=snapshot(id)
	if p.is_empty():return false
	var html:String="<!doctype html><html><meta charset=utf-8><title>"+Text.text("gestation.diary").xml_escape()+"</title><style>body{max-width:850px;margin:3em auto;background:#fff9eb;color:#42382e;font:18px sans-serif;padding:1em}article{padding:1em;border-bottom:1px solid #dbc}svg{width:100%;background:#fff}small{color:#776}</style><h1>"+game.memory_books.display_name(id).xml_escape()+" · "+Text.text("gestation.diary").xml_escape()+"</h1><svg viewBox='0 0 800 140' role='img' aria-label='Mood history'>"
	var colors:Array=["#ed9d46","#9b877a","#bc80ad","#55aabe","#b58383","#85a56a"]
	var points:Array=p.curve.slice(-200)
	for axis_index in AXES.size():
		var path_points:Array[String]=[]
		for i in points.size():path_points.append("%f,%f"%[float(i)*800/maxi(1,points.size()-1),130-float(points[i].mood[AXES[axis_index]])*1.2])
		html+="<polyline fill='none' stroke='"+colors[axis_index]+"' points='"+" ".join(path_points)+"'/>"
	html+="</svg><p>"+" · ".join(AXES.map(func(axis):return Text.text("gestation."+axis).xml_escape()))+"</p>"
	for field in ["records","dreams","selves","wishes"]:
		html+="<h2>"+Text.text("gestation."+field).xml_escape()+"</h2>"
		for row in p[field]:html+="<article><small>Day "+str(row.get("day",0))+" · "+str(row.get("origin","local")).xml_escape()+"</small><p>"+render_row(row).xml_escape()+"</p>"+("<p>"+render_today(row).xml_escape()+"</p>" if row.has("today") else "")+"</article>"
	return game.memory_books.atomic_text(path,html+"</html>")
