extends SceneTree
const World=preload("res://scripts/world_state.gd")
var checks:=0
var failed:=false
func check(ok:bool,msg:String)->void:
	checks+=1
	if not ok:failed=true;push_error(msg)
func _initialize()->void:call_deferred("run")
func run()->void:
	var w:=World.new("res://content/home-v3/world.json");w.residents.provision(w)
	w.library=preload("res://scripts/character_library.gd").new();w.library.configure(OS.get_environment("HABITAT_DATA_DIR"))
	check(preload("res://scripts/world_opening.gd").apply(w,w.library).ok,"real showcase opening")
	w.director.set_all_enabled(true);w.hunger.start()
	var at:Array=w.map_anchor("plaza.center");w.actors.human.position=[float(at[0])+10,float(at[1])+8];w.actors.human.facing="down"
	var human:Dictionary=w.actors.human.duplicate(true);var stocks:Dictionary={}
	for chest in [{"id":"storage","items":w.storage.saved().items,"capacity":9007199254740991,"kind":"storage"}]:stocks[chest.id]=chest.items.duplicate(true)
	for chest in w.farms.containers.values():stocks[chest.id]=chest.items.duplicate(true)
	for id in w.hunger.states:w.hunger.states[id].elapsed=float(w.hunger.config.thresholds[3])+60
	for frame in range(1800):w.advance(.1)
	var ids:Array=w.hunger.states.keys()
	for i in range(ids.size()):
		check(w.point(w.actors[ids[i]]).distance_to(w.point(w.actors.human))<=13,"hungry resident really reaches player neighbourhood")
		for j in range(i+1,ids.size()):check(w.point(w.actors[ids[i]]).distance_to(w.point(w.actors[ids[j]]))>=1.3,"follow destinations remain separate")
	check(w.actors.human==human,"following never moves human")
	for chest in [{"id":"storage","items":w.storage.saved().items,"capacity":9007199254740991,"kind":"storage"}]:check(chest.items==stocks[chest.id],"hungry locals never take from storage")
	for chest in w.farms.containers.values():check(chest.items==stocks[chest.id],"hungry locals never take from harvest/seed storage")
	var first:String=ids[0];var beside:Vector2=w.point(w.actors[first])+Vector2(1,0)
	check(w.command("human",{"intent":"move","x":beside.x,"y":beside.y}).ok,"human explicitly approaches hungry partner")
	for i in range(100):
		if not w._routes.has("human"):break
		w.advance(.1)
	check(w.point(w.actors[first]).distance_to(w.point(w.actors.human))<=13,"side-stepping follower stays in original player neighbourhood instead of backing away")
	var id:String=ids[0];w.command(id,{"intent":"stop"});var point:Vector2=w.point(w.actors[id])
	for i in range(1000):w.advance(.1)
	check(w.point(w.actors[id]).distance_to(point)<.01,"explicit stop prevents following during quiet period")
	check(w.director.events.filter(func(e):return e.actor_id==id and str(e.context).begins_with("hunger_") and e.time>=180).is_empty(),"explicit stop quiet period also blocks hunger speech")
	w.director.set_held(id,true);w.advance(.1);var n:int=w.director.serial
	for i in range(300):w.advance(.1)
	check(w.director.events.all(func(e):return e.serial<=n or e.actor_id!=id),"held prevents speech")
	var other:String=ids[1];var destination:Vector2=w.point(w.actors.human)+(w.point(w.actors.human)-w.point(w.actors[other])).normalized()*9
	check(w.command("human",{"intent":"move","x":destination.x,"y":destination.y}).ok,"explicit player movement starts another follow opportunity")
	for frame in range(40):
		w.advance(.1)
		if w._routes.has(other):break
	check(w._routes.has(other),"actual hunger follow route is moving before held")
	w.director.set_held(other,true);var held_point:Vector2=w.point(w.actors[other])
	for frame in range(20):w.advance(.1)
	check(not w._routes.has(other) and w.point(w.actors[other]).distance_to(held_point)<.01,"held cancels only owned hunger-follow movement")
	var doorway:=World.new("res://content/home-v3/world.json");doorway.residents.provision(doorway)
	doorway.library=preload("res://scripts/character_library.gd").new();doorway.library.configure(OS.get_environment("HABITAT_DATA_DIR").path_join("doorway"))
	check(preload("res://scripts/world_opening.gd").apply(doorway,doorway.library).ok,"real completed-house doorway fixture")
	doorway.director.set_all_enabled(false)
	var house:String=doorway.catalog.regions.home.layout.residential.filter(func(p):return p.owner_id=="human")[0].site_id
	check(doorway.command("human",{"intent":"enter","target_id":house}).ok,"human explicitly enters completed home")
	for frame in range(1200):
		doorway.advance(.1)
		if not doorway.work.jobs.has("human"):break
	check(doorway.actors.human.region_id.begins_with("room."),"human actually arrives inside")
	var moved_inside:=false
	for offset in [Vector2(-8,-2),Vector2(8,-2),Vector2(-4,0),Vector2(4,0)]:
		var inside:Vector2=doorway.interior.FLOOR.get_center()+offset
		if doorway.walkable(doorway.actors.human.region_id,inside) and doorway.command("human",{"intent":"move","x":inside.x,"y":inside.y}).ok:moved_inside=true;break
	check(moved_inside,"human explicitly walks clear of doorway")
	for frame in range(300):
		doorway.advance(.1)
		if not doorway._routes.has("human"):break
	doorway.hunger.start();var third:String=ids[2];doorway.hunger.states[third].elapsed=float(doorway.hunger.config.thresholds[3])+60;doorway.director.routines[third].set_enabled(true)
	var crossing:=false
	for frame in range(300):
		doorway.advance(.1)
		if doorway._routes.has(third) and doorway.hunger.follow_targets.get(third,{}).get("region")==doorway.actors.human.region_id and doorway.actors[third].region_id!=doorway.actors.human.region_id:crossing=true;break
	var human_region:String=doorway.actors.human.region_id
	var entrance:Vector2=doorway.interior.outside(human_region)
	print("HUNGER_DOOR_DIAGNOSTIC ",JSON.stringify({"id":third,"rank":doorway.hunger.rank(third),"enabled":doorway.director.routines[third].enabled,"held":doorway.director.routines[third].held,"can_follow":doorway.hunger.can_follow(third),"actor":doorway.actors[third],"human":doorway.actors.human,"following":doorway.activities.following,"entrance":[entrance.x,entrance.y],"entrance_walkable":doorway.walkable("home",entrance),"route_to_entrance":doorway.find_route(third,entrance),"routes":doorway._routes,"owned":doorway.hunger.owned_routes,"follow_targets":doorway.hunger.follow_targets,"follow_after":doorway.hunger.follow_after,"quiet":doorway.hunger.quiet_until,"forest_clock":doorway.forest.clock,"director_time":doorway.director.time}))
	check(crossing,"actual follow crosses original house doorway route")
	doorway.director.set_held(third,true);var before_crossing:Vector2=doorway.point(doorway.actors[third]);var old_region:String=doorway.actors[third].region_id
	for frame in range(20):doorway.advance(.1)
	check(not doorway._routes.has(third) and doorway.actors[third].region_id==old_region and doorway.point(doorway.actors[third]).distance_to(before_crossing)<.01,"held cancels owned intermediate doorway route")
	doorway.director.set_held(third,false)
	for frame in range(40):
		doorway.advance(.1)
		if doorway._routes.has(third):break
	check(doorway._routes.has(third),"follow creates another real intermediate route")
	var foreign:Array=doorway._routes[third].duplicate();doorway._apply_route(third,foreign)
	doorway.director.set_held(third,true);var before_foreign:Vector2=doorway.point(doorway.actors[third]);doorway.advance(.1)
	check(doorway._routes.has(third) and doorway.point(doorway.actors[third]).distance_to(before_foreign)>.01,"same-destination replacement route is not owned by hunger and is retained")
	print("Hunger follow: ",checks," checks, failed=",failed);quit(1 if failed else 0)
