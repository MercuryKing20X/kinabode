extends RefCounted
## Integration — disposable QA Worlds — BLOCKING physical resources / explicit human input.
## Helpers only issue original World jobs and explicit host barbecue operations.
static var previous_managers:Dictionary={}
static func step(world:RefCounted,delta:float,advance_frame:Callable=Callable())->bool:
	if advance_frame.is_valid():
		var result:Variant=advance_frame.call()
		return result!=false
	world.advance(delta);return true
static func wait_actor(world:RefCounted,id:String,advance_frame:Callable=Callable())->bool:
	for tick in range(18000):
		if not world.work.jobs.has(id) and not world._routes.has(id):return true
		if not step(world,.1,advance_frame):return false
	return false
static func job(world:RefCounted,id:String,args:Dictionary,advance_frame:Callable=Callable())->bool:
	return world.command(id,args).ok and wait_actor(world,id,advance_frame)
static func approach(world:RefCounted,station_id:String="home.barbecue",advance_frame:Callable=Callable())->bool:
	var life:RefCounted=world.barbecues[station_id]
	if life.fireside.near("human",3) and not world._routes.has("human"):return true
	var center:Vector2=world.point(life.station)
	for angle in range(32):
		var p:Vector2=center+Vector2.from_angle(angle*TAU/32)*2.5
		if world.walkable(life.station.region_id,p) and not world.find_route("human",p).is_empty():
			return job(world,"human",{"intent":"move","x":p.x,"y":p.y},advance_frame)
	return false
static func light(world:RefCounted,station_id:String="home.barbecue",advance_frame:Callable=Callable())->bool:
	if world.library==null:
		world.library=preload("res://scripts/character_library.gd").new();world.library.configure(OS.get_environment("HABITAT_DATA_DIR").path_join("fixture-art"))
	var fire:RefCounted=world.barbecues[station_id].fireside
	if not approach(world,station_id,advance_frame):return false
	if fire.burning():return true
	if int(fire.available().get("wood",0))<2:
		if not world.actors.human.carry.is_empty() and not world.deposit_all("human").ok:return false
		if not job(world,"human",{"intent":"gather_wood","tree_count":1,"zone_id":"home.forest"},advance_frame):return false
		if not approach(world,station_id,advance_frame):return false
	return fire.light_host().ok
static func start(world:RefCounted,key:String,guests:Array=["human","codex"],station_id:String="home.barbecue",advance_frame:Callable=Callable())->Dictionary:
	var fire:RefCounted=world.barbecues[station_id].fireside
	if fire.active() and not fire.state.current.is_empty() and fire.state.current.get("ready",false):fire.end_circle("host explicitly ends previous QA gathering")
	if not light(world,station_id,advance_frame):return {"ok":false,"error":"qa_cannot_light"}
	var ids:Array=guests.filter(func(id):return id!="human")
	var invitation:Dictionary=fire.invite(ids)
	if not invitation.ok:return invitation
	# These helpers promise a finished meal, so reserve time for the real diner to
	# reach a seat and eat as well as the recipe itself. A fire that can only
	# finish cooking may otherwise go out during seating and correctly waste it.
	# Never gather wood while holding a fish; light_host debits only actual authorized stock.
	var selected:Array=fire.menu().filter(func(choice):return choice.id==key)
	if not selected.is_empty() and int(selected[0].maximum)>0 and float(fire.state.remaining)<float(selected[0].seconds)+float(fire.config.eat_seconds)+20.0:
		var renewed:Dictionary=fire.light_host()
		if not renewed.ok:return renewed
	# Recipe prerequisites explicitly grant and then restore host farm management.
	# Core permission suites call fire directly and never use this fixture convenience.
	var managers:Dictionary={}
	if key.begins_with("recipe:") and world.fishing.held("human").is_empty():
		for farm in world.farms.farms.values():
			if farm.manager_id!="human":
				if not farm.manager_id.is_empty() and (world.work.jobs.has(farm.manager_id) or world.farms.active(farm.manager_id)):continue
				managers[farm.id]=farm.manager_id
				if not world.command("human",{"intent":"assign_farm","farm_id":farm.id,"manager_id":"human"}).ok:return {"ok":false,"error":"qa_cannot_authorize_farm"}
	previous_managers[world.get_instance_id()]=managers
	return fire.roast_host(key)
static func ready(world:RefCounted,station_id:String="home.barbecue",advance_frame:Callable=Callable())->bool:
	var fire:RefCounted=world.barbecues[station_id].fireside
	for tick in range(18000):
		if not fire.state.current.is_empty() and fire.state.current.get("ready",false):return true
		if not step(world,.1,advance_frame):return false
	return false
static func ate(world:RefCounted,id:String,station_id:String="home.barbecue",advance_frame:Callable=Callable())->bool:
	var fire:RefCounted=world.barbecues[station_id].fireside
	for tick in range(18000):
		if not fire.state.current.is_empty() and id in fire.state.current.get("eaters",[]):return true
		if fire.circle_closed or not fire.active() or (fire.state.get("current",{}).get("ready",false) and world.barbecues[station_id].station.portions==0):return false
		if not step(world,.1,advance_frame):return false
	return false
static func finish(world:RefCounted,guests:Array=["human","codex"],station_id:String="home.barbecue",advance_frame:Callable=Callable())->bool:
	for id in guests:
		if not ate(world,id,station_id,advance_frame):return false
	end(world,station_id)
	return true
static func meal(world:RefCounted,key:String,guests:Array=["human","codex"],station_id:String="home.barbecue",advance_frame:Callable=Callable())->bool:
	return start(world,key,guests,station_id,advance_frame).ok and finish(world,guests,station_id,advance_frame)
static func end(world:RefCounted,station_id:String="home.barbecue")->void:
	world.barbecues[station_id].fireside.end_circle("host explicitly ends QA gathering")
	var managers:Dictionary=previous_managers.get(world.get_instance_id(),{})
	for farm_id in managers:world.command("human",{"intent":"assign_farm","farm_id":farm_id,"manager_id":managers[farm_id]})
	previous_managers.erase(world.get_instance_id())
