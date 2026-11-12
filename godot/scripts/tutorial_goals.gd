extends RefCounted
## One ordered catalog for the host journey and steward; proofs never create resources.
var definitions:Array=JSON.parse_string(FileAccess.get_file_as_string("res://content/tutorial-goals.json"))
var baseline_proofs:Dictionary={}
var session_meals:Dictionary={}
var meal_baseline_ready:=false
var observed_meal:=false
func reset_session_meals()->void:
	session_meals.clear();meal_baseline_ready=false;observed_meal=false
func baseline(w:RefCounted)->void:
	baseline_proofs.clear()
	for spec in definitions:
		if proof(w,spec.id) and not w.standard.board_completed.has("goal."+spec.id):baseline_proofs[spec.id]=true
func rows(w:RefCounted)->Array:
	var output:Array=[]
	for spec in definitions:
		var row:Dictionary=spec.duplicate(true)
		row.text=row.en if TranslationServer.get_locale().begins_with("en") else row.zh
		row.done=w.standard.board_completed.has("goal."+row.id) or proof(w,row.id)
		row.completed_at=w.standard.board_completed.get("goal."+row.id,-1)
		output.append(row)
	return output
func proof(w:RefCounted,id:String)->bool:
	match id:
		"wood":return w.storage.count("wood")>=10
		"camp":return w.standard.ready("home.barbecue")
		"light":return w.barbecues.values().any(func(b):return b.fireside.burning() or int(b.station.get("fuel_used",0))>0)
		"meal":return not w.standard.first_meal.is_empty() if w.standard.active() else observed_meal
		"field":return w.standard.ready("farm.hill")
		"plant":return w.farms.plots.values().any(func(p):return not str(p.crop_id).is_empty())
		"pen":return w.standard.ready("home.fishery.south")
		"stock":return w.fishing.fish.values().any(func(f):return w.fishing.pens.has(f.location))
		"harvest":return w.farms.plots.values().any(func(plot):return int(plot.harvests)>0)
		"dusk":return w.days.phase().id=="dusk" and w.barbecues.values().any(func(b):return b.fireside.burning() and b.fireside.state.get("ate",{}).size()>=4 and b.fireside.jobs.size()>=4)
		"dish":return proof(w,"harvest") and w.barbecues.values().any(func(b):return int(b.fireside.state.get("current",{}).get("eaten",0))>0 and str(b.fireside.state.get("current",{}).get("menu_id","")).begins_with("recipe:"))
		"stars":return w.days.phase().id=="night" and w.actors.keys().any(func(actor):return w.resort.using(actor)=="stars")
		"moon":return w.days.phase().id=="night" and w.weather.current().id not in ["rain","fog"] and w.actors.values().filter(func(actor):return actor.id!="human" and w.moon.contains(w.point(actor)) and not w._routes.has(actor.id)).size()>=2
	for fact in w.memories.records:
		if id=="dusk" and fact.kind=="shared_barbecue" and w.days.phase().id=="dusk" and absf(w.forest.clock-float(fact.get("occurred_at",-INF)))<2:return true
		if id=="game" and fact.kind in ["gomoku_match","jieqi_result"]:return true
		if id=="chess" and fact.kind=="gomoku_match":return true
		if id=="moon" and fact.kind=="moon_viewing":return true
		if id=="stars" and fact.kind=="dark_discovery" and str(fact.facts.get("kind","")).contains("star"):return true
	for event in w.work.events:
		if event.get("status")!="completed":continue
		if id=="mushrooms" and event.get("intent")=="forage":return true
	return false
func observe(w:RefCounted)->void:
	if not w.standard.active():
		var meals:Array=w.memories.records.filter(func(e):return e.kind=="shared_barbecue" and e.facts.get("version")==2 and w.standard.config.companions.all(func(id):return id in e.participants))
		if not meal_baseline_ready:
			for meal in meals:session_meals[meal.id]=true
			meal_baseline_ready=true
		else:
			for meal in meals:
				if not session_meals.has(meal.id):observed_meal=true
	for row in rows(w):
		var key:String="goal."+row.id
		if w.standard.active() and row.done and not baseline_proofs.has(row.id) and not w.standard.board_completed.has(key):
			w.standard.board_completed[key]=w.forest.clock;w.revision+=1
func next(w:RefCounted)->Dictionary:
	for row in rows(w):
		if not row.done:return row
	return {}
