extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
## Opening-specific content projection and first-meal facts; existing Work owns construction.
const PATH="res://content/openings/standard.json"
var _owner:WeakRef
var world:RefCounted:
	get:return _owner.get_ref()
var config:Dictionary={}
var sites:Dictionary={}
var goals=preload("res://scripts/tutorial_goals.gd").new()
var tutorial_step:=0
var first_meal:=""
var spoken:Array=[]
var suggested:=false
var board_completed:Dictionary={}
var board_previous:Dictionary={}
var baseline_meals:Array=[]
func _init(source:RefCounted)->void:
	_owner=weakref(source);config=JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not valid_config(config):world.error=LocalText.text("ui.opening.config_invalid");config={};return
	for spec in config.get("construction",[]):sites[spec.id]=spec
func valid_config(data:Variant)->bool:
	if not data is Dictionary or data.get("version")!=1 or data.get("id")!="standard" or data.get("template_id")!="home-v3" or data.get("implemented")!=true:return false
	var keys:Array=["version","id","template_id","implemented","purpose","companions","spawn_points","hidden_scenery","house","first_farm","storage","forage_ids","forage_anchors","suggestion","first_meal_lines","construction","seat_offsets"]
	if data.size()!=keys.size() or keys.any(func(k):return not data.has(k)) or not data.suggestion is String or data.suggestion.length()>40:return false
	if not data.seat_offsets is Array or data.seat_offsets.size()!=world.life.activity_rules.seat_offsets.size() or data.seat_offsets.any(func(p):return not world.catalog._pair(p)):return false
	if not data.get("companions") is Array or data.companions.size()!=4 or data.companions.any(func(id):return not world.residents.definitions.has(id) or id=="human") or not data.get("spawn_points") is Dictionary:return false
	for id in data.companions:
		if not data.spawn_points.get(id) is Dictionary or data.spawn_points[id].size()!=2 or not data.spawn_points[id].get("anchor") is String or (world.catalog.manifest.get("template_id")=="home-v3" and not world.catalog.regions.home.layout.anchors.has(data.spawn_points[id].anchor)) or not world.catalog._pair(data.spawn_points[id].get("offset")) or not data.get("first_meal_lines",{}).get(id) is String or data.first_meal_lines[id].length()>60:return false
	if not data.get("construction") is Array or data.construction.size()!=8 or not data.get("storage") is Dictionary or not data.get("house") is Dictionary:return false
	if not data.hidden_scenery is Array or data.hidden_scenery.any(func(id):return not id is String or (world.catalog.manifest.get("template_id")=="home-v3" and id not in world.catalog.regions.home.layout.cliffs.map(func(c):return c.id))):return false
	var seen:Array=[]
	var targets:Array=[]
	for spec in data.construction:
		if not spec is Dictionary or spec.size()!=4 or not spec.get("id") is String or not spec.id.begins_with("play.standard.") or spec.id in seen or not spec.get("name") is String or not world._integer(spec.get("wood")) or spec.wood<1 or spec.wood>1000:return false
		if spec.get("target") not in ["home.barbecue","moon.barbecue","moon.lookout","home.fishery.south","home.fishery.west","farm.hill","farm.lake","farm.east"]:return false
		if spec.target in targets:return false
		targets.append(spec.target)
		seen.append(spec.id)
	for item in data.storage:
		if item not in ["wood","mushroom","seed.turnip","seed.tomato"] or not world._integer(data.storage[item]) or data.storage[item]<0 or data.storage[item]>80:return false
	return data.get("first_farm")=="farm.home" and data.house.get("site_id")=="home.house.01" and data.house.get("template_id")=="cottage" and data.house.get("furniture") is Array and data.house.furniture.size()==1 and data.house.furniture[0].get("recipe_id")=="chair" and data.get("forage_ids") is Array and data.get("forage_anchors") is Array and data.forage_ids.size()==2 and data.forage_anchors.size()==2
func active()->bool:return world.opening_id=="standard"
func ready(target:String)->bool:
	if not active():return true
	for id in sites:
		if sites[id].target==target:return world.leisure.sites.get(id,{}).get("complete",false)
	return true
func install_geometry()->void:
	world.life.activity_rules.seat_offsets=config.seat_offsets.duplicate(true)
	for index in range(config.forage_ids.size()):world.life.patches[config.forage_ids[index]].position=world.map_anchor(config.forage_anchors[index])
func site_for(target:String)->String:
	for id in sites:
		if sites[id].target==target:return id
	return ""
func install_sites(library:RefCounted)->void:
	for id in sites:
		if world.leisure.sites.has(id):continue
		var spec:Dictionary=sites[id];var art:Dictionary=library.artworks["play-bench"].duplicate(true)
		art.recreation={"width":3,"depth":3,"behavior":"sit","seconds":5,"entry":[0,1.5],"slots":[[-1,1],[1,1]],"obstacles":[]}
		world.leisure.sites[id]={"id":id,"name":spec.name,"kind":"play_site","region_id":"home","position":position(spec.target),"template_id":"play-bench","invested":0,"complete":false,"artwork":art}
func position(target:String)->Array:
	if world.barbecues.has(target):return world.barbecues[target].station.position.duplicate()
	if world.farms.farms.has(target):return world.farms.farms[target].entrance.duplicate()
	if world.fishing.pens.has(target):
		var r:Rect2=world.catalog.rectangle(world.fishing.pens[target].rect)
		return world.map_anchor("dock.south.end" if r.position.x>30 else "dock.west.end")
	return world.map_anchor("moon.lookout")
func board()->Array:
	var rows:Array=[{"id":"fire","target":"home.barbecue","text":LocalText.text("ui.opening.fire"),"done":ready("home.barbecue")},{"id":"farm","target":config.first_farm,"text":LocalText.text("ui.opening.farm"),"done":world.farms.farm_plots(config.first_farm).any(func(p):return not p.crop_id.is_empty())},{"id":"pens","target":"home.fishery.south","text":LocalText.text("ui.opening.pens"),"done":world.fishing.pens.keys().all(func(id):return ready(id))},{"id":"homes","target":"home.house.02","text":LocalText.text("ui.opening.homes"),"done":world.catalog.regions.home.layout.residential.filter(func(p):return p.owner_id in config.companions).all(func(p):return int(world.objects[p.site_id].stage_index)==5)}]
	if world.their_island!=null and world.their_island.introduced:rows.append({"id":"their_island","target":"homelands.barbecue","text":LocalText.text("theirs.goal"),"done":world.home_island.landed})
	for row in rows:row["completed_at"]=float(board_completed.get(row.id,-1))
	rows.sort_custom(func(a,b):return a.completed_at>b.completed_at if a.done and b.done else not a.done and b.done)
	return rows
func board_point(target:String)->Vector2:
	if world.objects.has(target):return world.point(world.objects[target])
	return Vector2(position(target)[0],position(target)[1])
func board_quote()->String:
	var unit:Dictionary=world.intelligence.catalog.speech.get("gentle-happy",{})
	return LocalText.content(str(unit.get("lines",[config.suggestion])[0]))
func react(id:String)->bool:
	if not waiting_reaction(id) or id not in config.companions:return false
	var r:RefCounted=world.director.routines[id]
	if r.time<r.visual_quiet_until or not world.director.moods.can_speak(id):return false
	if world.director.say_local(id,config.first_meal_lines[id],"first_shared_meal",float(world.hunger.config.personal_gap),float(world.hunger.config.village_gap)):spoken.append(id);return true
	return false
func waiting_reaction(id:String)->bool:
	if not active() or first_meal.is_empty() or id in spoken:return false
	var facts:Array=world.memories.records.filter(func(e):return e.kind=="first_shared_meal" and e.facts.activity_id==first_meal)
	return not facts.is_empty() and world.forest.clock-float(facts[0].occurred_at)<=180 and world.actors[id].region_id==world.actors.human.region_id and world.point(world.actors[id]).distance_to(world.point(world.actors.human))<=12
func apply(library:RefCounted)->Dictionary:
	install_geometry();install_sites(library)
	var site:Dictionary=world.objects[config.house.site_id];var art:Dictionary=library.artworks[config.house.template_id].duplicate(true);var quote:Dictionary=world.Blueprint.quote(art.structure)
	site["blueprint"]={"id":art.id,"structure":art.structure.duplicate(true),"artwork":art,"wood":quote.wood,"stages":quote.stages.duplicate()}
	site.stage_index=5;site.status="complete";site.stage="complete";site.invested=0;site.delivered={};site["preset_origin"]="standard";site.erase("contributions")
	for definition in config.house.furniture:
		world.interior.serial+=1;var recipe:Dictionary=world.interior.RECIPES[definition.recipe_id];var fid:="furniture."+str(world.interior.serial)
		world.interior.furniture[fid]={"id":fid,"kind":"furniture","recipe_id":definition.recipe_id,"name":recipe.name,"region_id":"room."+site.id,"position":definition.position.duplicate(),"facing":definition.facing,"holder_id":"","invested":0,"items":{},"capacity":0,"artwork":library.artworks["furniture-"+definition.recipe_id].duplicate(true),"preset_origin":"standard"}
	world.storage.restore({"items":config.storage})
	for farm in world.farms.farms.values():farm.manager_id="human"
	for id in config.companions:
		world.actors[id].controller="local";var spec:Dictionary=config.spawn_points[id];var anchor:Array=world.map_anchor(spec.anchor);var at:Vector2=Vector2(anchor[0],anchor[1])+Vector2(spec.offset[0],spec.offset[1]);world.actors[id].position=[at.x,at.y]
	for index in range(config.forage_ids.size()):world.life.patches[config.forage_ids[index]].position=world.map_anchor(config.forage_anchors[index])
	world.opening_id="standard";world._grids.clear();world._terrain_solids.clear();world.revision+=1
	return {"ok":true,"applied":true}
func offer_hint()->void:
	if not active():return
	if not suggested and not ready("home.barbecue"):
		for id in config.companions:
			var r:RefCounted=world.director.routines[id]
			if r.enabled and r.chatter and not r.blocked() and not world.shared_activity.holds(id) and r.time>=r.next_speech and world.fishing.life.time>=float(world.fishing.life.quiet_until.get(id,0)) and world.director.time>=r.visual_quiet_until and world.director.time>=world.director.speech_after:
				if world.proposals.create_local_opening(id,config.suggestion).ok:suggested=true;break
	if ready("home.barbecue"):
		for id in world.proposals.cards.keys():
			if world.proposals.cards[id].get("opening_hint",false):world.proposals.cards.erase(id);world.revision+=1
func advance(delta:float)->void:
	if delta<=0:return
	goals.observe(world)
	if not active():return
	for row in board():
		if row.done and board_previous.has(row.id) and not board_previous[row.id]:board_completed[row.id]=world.forest.clock
		board_previous[row.id]=row.done

	if first_meal.is_empty():
		for event in world.memories.records.duplicate():
			if event.kind!="shared_barbecue" or event.facts.get("version")!=2 or event.facts.station_id!="home.barbecue":continue
			if config.companions.all(func(id):return id in event.participants):
				if event.source.id in baseline_meals:
					first_meal=event.source.id
					continue
				var facts:Dictionary={"activity_id":event.source.id,"station_id":"home.barbecue","day":world.days.day(),"phase":world.days.phase().id,"ate":event.participants.duplicate()}
				if world.memories.record_event("first_shared_meal",event.source.id,event.participants,facts):first_meal=event.source.id
	if not first_meal.is_empty():
		for id in config.companions:
			if react(id):break
func saved()->Dictionary:return {"tutorial_step":tutorial_step,"version":1,"first_meal":first_meal,"spoken":spoken.duplicate(),"suggested":suggested,"board_completed":board_completed.duplicate()}
func restore(data:Dictionary)->void:
	goals.reset_session_meals()
	tutorial_step=int(data.get("tutorial_step",0))
	first_meal=str(data.get("first_meal",""));spoken=data.get("spoken",[]).duplicate();suggested=bool(data.get("suggested",false));board_completed=data.get("board_completed",{}).duplicate();board_previous.clear()
	if not active():return
	for row in board():board_previous[row.id]=row.done
	goals.baseline(world)
func valid(data:Variant)->bool:
	if not data is Dictionary:return false
	if data.is_empty():return true
	if data.has("tutorial_step") and (not world._integer(data.tutorial_step) or data.tutorial_step<0 or data.tutorial_step>6):return false
	if data.keys().any(func(k):return k not in ["version","first_meal","spoken","suggested","board_completed","tutorial_step"]):return false
	if data.get("version")!=1 or not data.get("first_meal") is String or data.first_meal.length()>64 or not data.get("suggested") is bool or not data.get("spoken") is Array or data.spoken.size()>config.companions.size() or not data.spoken.all(func(id):return id in config.companions):return false
	var times:Variant=data.get("board_completed",{})
	return times is Dictionary and times.size()<=20 and times.keys().all(func(k):return (k in ["fire","farm","pens","homes"] or k in goals.definitions.map(func(row):return "goal."+row.id)) and (times[k] is int or times[k] is float) and is_finite(float(times[k])) and float(times[k])>=0)
