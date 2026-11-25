extends Node
const Text=preload("res://scripts/localization.gd")
var game:Node
var world:RefCounted
var shortcuts:VBoxContainer
var map_button:Button
var destination:Dictionary={}
var helpers:Dictionary={}
var elapsed:=0.0
const KEYS=["trees","fire","meal","farm","fish","south"]
func setup(source:Node,root:Control)->void:
	game=source;world=game.world
	shortcuts=VBoxContainer.new();root.add_child(shortcuts);shortcuts.hide();shortcuts.z_index=121
	var atlas_button:=Button.new();atlas_button.focus_mode=Control.FOCUS_NONE;shortcuts.add_child(atlas_button)
	atlas_button.pressed.connect(func():shortcuts.hide();game._toggle_atlas(true,true))
	for key in ["south","farm","fish","chess","home","fire"]:
		var button:=Button.new();button.focus_mode=Control.FOCUS_NONE;shortcuts.add_child(button);button.set_meta("journey",key);button.pressed.connect(func():shortcuts.hide();navigate(key))
func toggle_menu()->void:
	if game.atlas.visible:game._toggle_atlas(false)
	shortcuts.visible=not shortcuts.visible
func _input(event:InputEvent)->void:
	if not shortcuts.visible:return
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
		shortcuts.hide();get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and not shortcuts.get_global_rect().has_point(event.position) and (map_button==null or not map_button.get_global_rect().has_point(event.position)):shortcuts.hide()
func cancel()->void:
	if not destination.is_empty():world.command("human",{"intent":"stop"})
	destination.clear()
func navigate(key:String)->void:
	var at:Vector2=world.point(world.actors.human)
	var id:=""
	match key:
		"trees":
			var trees:Array=world.objects.values().filter(func(t):return t.kind=="tree" and t.status=="mature" and t.region_id==world.actors.human.region_id)
			trees.sort_custom(func(a,b):return world.point(a).distance_squared_to(at)<world.point(b).distance_squared_to(at))
			if trees.is_empty():return
			at=world.point(trees[0])
		"fire","meal":
			var fires:Array=world.barbecues.keys();fires.sort_custom(func(a,b):return world.point(world.barbecues[a].station).distance_squared_to(at)<world.point(world.barbecues[b].station).distance_squared_to(at))
			id=str(fires[0]);at=world.point(world.barbecues[id].station)
		"home":id="home.house.01";at=world.point(world.objects[id])
		"farm":id="farm.home";at=Vector2(world.farms.farms[id].entrance[0],world.farms.farms[id].entrance[1])
		"south":at=Vector2(81,190)
		"fish":
			var anchor:Array=world.map_anchor("dock.south.end");at=Vector2(anchor[0],anchor[1])
		"chess":
			for site in world.leisure.sites.values():
				if not world.gomoku.table(site.id).is_empty():
					game._toggle_atlas(false);game._walk_to_chess(site.id);return
			game._toggle_atlas(false);game._open_chess();return
	go("home",at,key,id)
func go(region:String,at:Vector2,key:String="",id:String="")->void:
	game._toggle_atlas(false)
	if region!=world.actors.human.region_id:
		game.status.text=Text.text("journey.boat")
		var dock:Vector2=world.dark.p(world.dark.config.home_dock)
		go("home",dock,"dock");return
	var candidates:Array=[]
	for y in range(-4,5):
		for x in range(-4,5):
			var p:=at+Vector2(x,y)
			if world.walkable(region,p):candidates.append(p)
	candidates.sort_custom(func(a,b):return a.distance_squared_to(at)<b.distance_squared_to(at))
	for p in candidates:
		var result:Dictionary=world.command("human",{"intent":"move","region_id":region,"x":p.x,"y":p.y})
		if result.ok:
			destination={"point":p,"key":key,"id":id};game.view.follow_player=true;return
func _process(delta:float)->void:
	if world==null:return
	if shortcuts.visible:shortcuts.move_to_front()
	if map_button!=null:
		shortcuts.position=Vector2(minf(map_button.global_position.x,game.get_viewport_rect().size.x-shortcuts.size.x-12),maxf(12,map_button.global_position.y-shortcuts.size.y-6))
		shortcuts.custom_minimum_size.x=map_button.size.x
	shortcuts.get_child(0).text="Open world map" if TranslationServer.get_locale().begins_with("en") else preload("res://scripts/localization.gd").source("content.health_20261107.7def5458aedf")
	for b in shortcuts.get_children():
		if not b.has_meta("journey"):continue
		b.text=Text.text("journey."+str(b.get_meta("journey")))
		if b.get_meta("journey")=="chess":
			b.disabled=not world.leisure.sites.values().any(func(site):return not world.gomoku.table(site.id).is_empty())
			b.tooltip_text=("Build a chess table first" if TranslationServer.get_locale().begins_with("en") else preload("res://scripts/localization.gd").source("content.health_20261107.6b97bb4da661")) if b.disabled else ""
	if not destination.is_empty() and not world._routes.has("human") and not world.work.jobs.has("human"):
		var arrived:bool=world.point(world.actors.human).distance_to(destination.point)<2
		var done:Dictionary=destination;destination={}
		if arrived:
			match done.key:
				"fire","meal":game._clicked(done.id,world.point(world.barbecues[done.id].station))
				"farm":game.farm_panel.open_farm(done.id)
				"home":game.house_panel.open_site(done.id)
				"fish":game.action_dock.open_invite(true)
	elapsed+=delta
	if elapsed>=.5:elapsed=0;assist()
func proof(step:int)->bool:
	match step:
		0:return world.storage.count("wood")>=6
		1:return world.barbecues.values().any(func(b):return b.fireside.burning())
		2:return world.hunger.states.values().any(func(s):return int(s.get("meals",0))>0)
		3:return world.farms.plots.values().any(func(p):return not str(p.crop_id).is_empty())
		4:return not world.journal.saved().get("discoveries",{}).is_empty() or not world.fishing.fish.is_empty()
		5:return world.home_island.landed
	return false
func assist()->void:
	var human:Dictionary=world.actors.human
	var job:Dictionary=world.work.jobs.get("human",{})
	var cutting:bool=job.get("phase","")=="chop"
	for actor in helpers.keys():
		var owned:Dictionary=helpers[actor]
		if (not job.is_empty() and not cutting) or world._routes.has("human") or human.region_id!=owned.region or world.point(human).distance_to(owned.point)>6 or not world.activities.following.has(actor) or world.hunger.rank(actor)>=2:
			if world.work.jobs.get(actor,{}).get("id")==owned.job:world.work.stop(actor)
			helpers.erase(actor)
	if not cutting:return
	for actor in world.activities.following:
		if helpers.has(actor) or world.hunger.rank(actor)>=2 or world.work.jobs.has(actor) or world.activities.blocked(actor,false) or not world.actors[actor].carry.is_empty():continue
		var trees:Array=world.objects.values().filter(func(t):return t.kind=="tree" and t.status=="mature" and t.region_id==human.region_id and world.point(t).distance_to(world.point(human))<=6 and not world.work.claims.has(t.id))
		if trees.is_empty():continue
		world.hunger.clear_follow(actor)
		world.activities.follow_issuing=true
		var result:Dictionary=world.host_text_command(actor,{"intent":"gather_wood","tree_count":1,"target_id":trees[0].id})
		world.activities.follow_issuing=false
		if result.ok:helpers[actor]={"job":result.job_id,"point":world.point(human),"region":human.region_id}

func suggestion_key()->String:
	if world.storage.count("wood")<10:return "trees"
	if world.director.routines.keys().any(func(id):return world.hunger.rank(id)>=2):return "meal"
	if world.farms.preview_host_orders(["human"],"ready","","").rows.any(func(row):return row.allowed):return "farm"
	return "fish"
