extends RefCounted
## Returns original intention steps only; blockers produce no items or human action.
var retry:Dictionary={}
func plan(g:Node,preferred:String="")->Dictionary:
	var w:RefCounted=g.world
	var owner:String=g.steward.manager
	var stock:Dictionary=w.storage.saved().items
	var guests:Array=g.steward.Pool.IDS.filter(func(id):return id!=owner)
	var goals:Array=w.standard.goals.rows(w)
	if not preferred.is_empty():goals.sort_custom(func(a,b):return a.id==preferred and b.id!=preferred)
	for goal in goals:
		if goal.done or w.forest.clock<float(retry.get(goal.id,0)):continue
		var steps:Array=[]
		match goal.id:
			"wood":steps=[{"action":"chop","actor_ids":["all"]}]
			"camp":steps=[{"action":"build","target_id":w.standard.site_for("home.barbecue")}]
			"light":steps=[{"action":"light","target_id":"home.barbecue"}]
			"meal","dusk","dish":
				if not w.standard.ready("home.barbecue"):continue
				if goal.id=="dusk" and w.days.phase().id!="dusk":continue
				var food:String="single:mushroom"
				if goal.id=="dish":
					var options:Array=w.barbecues["home.barbecue"].fireside.menu(owner).filter(func(row):return not str(row.id).begins_with("single:") and int(row.maximum)>0)
					if not w.standard.goals.proof(w,"harvest") or options.is_empty():continue
					food=str(options[0].id)
				if steps.is_empty():steps=[{"action":"roast","target_id":"home.barbecue","item_id":food,"guest_ids":guests}]
			"mushrooms":steps=[{"action":"gather","text":"gather mushrooms","target_id":w.standard.config.forage_ids[0]}]
			"field":steps=[{"action":"build","target_id":w.standard.site_for("farm.hill")}]
			"plant":
				if not w.farms.ready("farm.home"):continue
				if int(stock.get("seed.turnip",0))+int(stock.get("seed.tomato",0))<=0:
					retry[goal.id]=w.forest.clock+180;g.steward.rhythm_say(owner,"missing","seeds" if TranslationServer.get_locale().begins_with("en") else preload("res://scripts/localization.gd").source("content.v06.text.5e20fc223736c8"));g.steward.trace("missing",{"goal":goal.id,"item":"seed"});continue
				steps=[{"action":"plant","target_id":"farm.home","actor_ids":[owner]}]
			"pen":steps=[{"action":"build","target_id":w.standard.site_for("home.fishery.south")}]
			"stock":
				if not w.standard.ready("home.fishery.south"):continue
				steps=[{"action":"fish"}]
			"game":
				return {"game":{"gentle":"handkerchief","lively":"eagle","quiet":"hide","laborious":"shuttlecock"}.get(w.intelligence.tag(owner),"handkerchief"),"goal":goal}
			"chess":
				var tables:Array=w.leisure.sites.values().filter(func(site):return site.complete and not w.gomoku.table(site.id).is_empty())
				if tables.is_empty():
					if w.leisure.sites.has("play.gomoku"):steps=[{"action":"build","target_id":"play.gomoku"}]
					else:continue
				else:steps=[{"action":"chess","target_id":tables[0].id,"guest_ids":[guests[0]]}]
			"stars":
				if w.days.phase().id!="night":continue
				steps=[{"action":"stars","guest_ids":guests}]
			"harvest":
				var farms:Array=w.farms.farms.keys().filter(func(id):return w.farms.farm_plots(id).any(func(plot):return w.farms.stage(plot)=="mature"))
				if farms.is_empty():continue
				steps=[{"action":"harvest","target_id":farms[0],"actor_ids":[owner]}]
			"moon":
				if not w.standard.ready("moon.lookout"):
					steps=[{"action":"build","target_id":w.standard.site_for("moon.lookout")}]
				elif w.days.phase().id!="night" or w.weather.current().id in ["rain","fog"]:continue
				if steps.is_empty():
					var point:Array=w.map_anchor("moon.lookout")
					steps=[{"action":"go_to","region_id":"home","x":point[0],"y":point[1],"guest_ids":guests}]
		if steps.is_empty():continue
		var cost:int=0
		for step in steps:cost+=g.steward.material_cost(owner,step)
		if int(stock.get("wood",0))<cost+int(g.steward.trace_config.wood_reserve):steps=[{"action":"chop","actor_ids":["all"]}]
		if steps[0].action=="chop":
			var needed:int=maxi(10,cost+int(g.steward.trace_config.wood_reserve))
			if not w.standard.first_meal.is_empty():
				var upcoming:int=0
				var building_cost:=0
				for target in [w.standard.site_for("farm.hill"),w.standard.site_for("home.fishery.south"),w.standard.site_for("moon.lookout"),"play.gomoku"]:
					var site:Dictionary=w.leisure.sites.get(target,{})
					if site.is_empty() or site.complete:continue
					building_cost+=maxi(0,w.leisure.cost(site)-int(site.invested));upcoming+=1
					if upcoming>=int(g.steward.trace_config.wood_lookahead_builds):break
				needed=maxi(needed,building_cost+int(g.steward.trace_config.wood_reserve))
			var count:int=clampi(ceili(float(needed-int(stock.get("wood",0)))/float(w.forest.settings.normal_wood)),1,100)
			var trees:Array=w.objects.values().filter(func(tree):return tree.kind=="tree" and tree.status=="mature" and tree.region_id==w.actors[owner].region_id and not w.resort.retired(tree) and not w.work.claims.has(tree.id))
			trees.sort_custom(func(a,b):return w.point(a).distance_to(w.point(w.actors[owner]))<w.point(b).distance_to(w.point(w.actors[owner])))
			steps=[]
			if not trees.is_empty():
				count=mini(count,int(g.steward.trace_config.wood_batch_trees))
				count=mini(count,trees.filter(func(tree):return tree.zone_id==trees[0].zone_id).size())
				steps=[{"action":"chop","actor_ids":[owner],"target_id":trees[0].id,"text":"chop %d trees"%count}]
			if steps.is_empty():continue
		retry[goal.id]=w.forest.clock+30
		return {"goal":goal,"intents":steps,"reason":goal.text}
	return {}
