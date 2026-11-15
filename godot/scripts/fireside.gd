extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
const MealMotion=preload("res://scripts/meal_motion.gd")
## New host-authorized barbecue stages inside SharedLife. World/Work own every route/job.
var _life:WeakRef
var life:RefCounted:
	get:return _life.get_ref()
var world:RefCounted:
	get:return life.world
var state:Dictionary:
	get:return life.station.get("fireside",{})
var config:Dictionary={}
var dialogue:RefCounted
var jobs:Dictionary={}
var seats:Dictionary={}
var suppressed:Dictionary={}
var away:=0.0
var join_after:=0.0
var circle_closed:=false
# Exact host invitation consent, session-only; never restored with an old meal.
var steward_human_authority:Callable
var steward_human_join:=false
var selected_guests:Array=[]
var ignited_at:=-1000.0
var loaded_meal:=false
func _init(owner_life:RefCounted)->void:
	_life=weakref(owner_life);dialogue=preload("res://scripts/fireside_dialogue.gd").new(self);config=JSON.parse_string(FileAccess.get_file_as_string("res://content/barbecue-v2.json"))
func active()->bool:return not state.is_empty()
func burning()->bool:return active() and state.remaining>0 and not state.suspended
func near(id:String,radius:float)->bool:
	return world.actors[id].region_id==life.station.region_id and world.point(world.actors[id]).distance_to(world.point(life.station))<=radius
var host_authority:Callable
func host_ready(actor_id:String="human")->Dictionary:
	if not world.actors.has(actor_id) or (actor_id!="human" and not world.director.model_controlled(actor_id) and not (host_authority.is_valid() and host_authority.call(actor_id))):return world._error("model_required")
	if not world.standard.ready(life.station.id):return world.work.fail("unbuilt_camp",LocalText.text("system.fireside.build_the_campfire_first"))
	if not near(actor_id,float(config.near_radius)):return world.work.fail("too_far",LocalText.text("system.fireside.walking_to_the_fire"))
	if world.work.jobs.has(actor_id) and not jobs.has(actor_id):return world._error("busy")
	if (world._routes.has(actor_id) and not jobs.has(actor_id)) or world.actors[actor_id].has("furniture_id") or world.projects.active(actor_id) or world.farms.active(actor_id) or world.homestead.active(actor_id):return world._error("inventory_reserved")
	return {"ok":true}
# Explicit host-only remote debit. No local routine calls this resource authority.
func available(actor_id:String="human")->Dictionary:return world.available_items(actor_id)
func debit(required:Dictionary,actor_id:String="human")->Dictionary:return world.pay_costs(actor_id,required)
func light_host(storage_only:bool=false,actor_id:String="human")->Dictionary:
	var ready:=host_ready(actor_id)
	if not ready.ok:return ready
	var wood_cost:int=int(config.get("charcoal_wood",1)) if burning() else int(config.wood)
	if int(world.storage.count("wood") if storage_only else available(actor_id).get("wood",0))<wood_cost:return world.work.fail("missing_carried_wood",LocalText.text("storage.wood_shortage")%[0 if storage_only else int(world.actors[actor_id].carry.get("wood",0)),world.storage.count("wood"),wood_cost])
	if active() and state.remaining+float(config.fire_seconds)>86400:return world._error("fire_duration_limit")
	interrupt(actor_id)
	var debit_result:Dictionary=debit_storage({"wood":wood_cost}) if storage_only else debit({"wood":wood_cost},actor_id)
	if not debit_result.ok:return world._error("insufficient_materials")
	if not active():
		life.station["fireside"]={"version":4,"id":Crypto.new().generate_random_bytes(12).hex_encode(),"remaining":0.0,"suspended":false,"consent":false,"invited":[],"attended":[],"ate":{},"current":{},"committed":false,"light_by":actor_id,"roast_by":actor_id}
	state.light_by=actor_id
	if state.committed:
		state.id=Crypto.new().generate_random_bytes(12).hex_encode();state.ate={};state.attended=[];state.current={}
	ignited_at=world.director.time
	state.remaining+=float(config.fire_seconds);state.suspended=false;state.committed=false;away=0;circle_closed=false
	life.station.fuel_used+=wood_cost
	if actor_id=="human":preload("res://scripts/brain_interactions.gd").host_event(world,"host_fire","fire:"+str(world.revision))
	if life.station.artwork.is_empty():life.station.artwork=world.library.artworks[life.station.artwork_id].duplicate(true)
	if life.station.portions==0:life.station.state="embers"
	world.revision+=1;return {"ok":true,"sources":debit_result.sources,"message":LocalText.text("system.fireside.the_fire_is_lit_choose_something_to_eat")}
func people()->Array:
	return world.actors.keys().filter(func(id):return world.residents.supports(world.actors[id],"sit") and near(id,float(config.near_radius)))

func debit_storage(costs:Dictionary)->Dictionary:
	var result:Dictionary=world.storage.take(costs)
	if not result.get("ok",false):return result
	world.revision+=1
	return {"ok":true,"sources":{"backpack":{},"storage":costs.duplicate(true)}}

func direct_grill(fish_id:String,actor_id:String="human")->Dictionary:
	var ready:=host_ready(actor_id)
	if not ready.ok:return ready
	var fish:Dictionary=world.fishing.fish.get(fish_id,{})
	if not direct_fish_available(fish,actor_id):return world._error("fish_not_owned")
	if not valid_fish(fish,true,actor_id):return world._error("invalid_fish")
	if active() and not state.current.is_empty() and int(state.current.eaten)+int(state.current.wasted)<int(state.current.total):return world.work.fail("fire_busy",LocalText.text("system.fireside.there_is_still_food_on_the_fire"))
	var cost:int=int(config.get("charcoal_wood",1)) if burning() else int(config.wood)
	if world.storage.count("wood")<cost:return world.work.fail("missing_wood",LocalText.text("system.fireside.you_need_d_wood")%cost)
	if not burning():
		var lit:=light_host(true,actor_id)
		if not lit.ok:return lit
		return _put_direct_fish(fish,lit.sources)
	if float(state.remaining)+float(config.fire_seconds)>86400:return world._error("fire_duration_limit")
	var payment:=debit_storage({"wood":cost})
	if not payment.ok:return world._error("insufficient_materials")
	state.remaining+=float(config.fire_seconds)
	life.station.fuel_used+=cost
	return _put_direct_fish(fish,payment.sources)

func _put_direct_fish(fish:Dictionary,wood_sources:Dictionary)->Dictionary:
	if state.committed:state.id=Crypto.new().generate_random_bytes(12).hex_encode();state.ate={};state.attended=[]
	loaded_meal=false
	state.roast_by=str(fish.owner_id)
	state.current={"id":Crypto.new().generate_random_bytes(12).hex_encode(),"food_id":"fish","menu_id":"direct:"+fish.id,"name":LocalText.source("system.fireside.grilled_fish"),"category":"fish","receipt":{},"fish":fish.duplicate(true),"total":4,"eaten":0,"wasted":0,"sources":{"backpack":{},"storage":{}},"elapsed":0.0,"seconds":float(config.cook_seconds),"ready":false,"eaters":[],"direct_grill":true,"wait_elapsed":0.0,"wood_sources":wood_sources}
	world.fishing.fish.erase(fish.id)
	_start_meal_timer()
	state.invited=[];state.consent=false;state.committed=false;circle_closed=false;away=0
	life.station.portions=0;life.station.state="cooking";world.revision+=1
	return {"ok":true,"sources":wood_sources,"fish_id":fish.id,"message":LocalText.text("system.fireside.the_fish_is_on_the_fire_invite_companions")}

func waiting_meal()->bool:
	return active() and not state.current.is_empty() and (loaded_meal or state.current.get("direct_grill",false)) and int(state.current.eaten)+int(state.current.wasted)<int(state.current.total)
func invite_direct(ids:Array)->Dictionary:
	if not waiting_meal() or int(state.current.eaten)+int(state.current.wasted)>=int(state.current.total):return world._error("no_waiting_fish")
	var added:Array=ids.filter(func(id):return id not in state.invited)
	var merged:Array=state.invited.duplicate()
	for id in added:
		if id not in merged:merged.append(id)
	var checked:=can_invite(merged)
	if not checked.ok:return checked
	state.invited=merged;state.consent=true;circle_closed=false
	for id in added:
		suppressed.erase(id);world.director.routines[id].interrupt(8)
	if not state.current.is_empty() and not state.current.has("meal_remaining"):_start_meal_timer()
	world.hunger.invite_fireside(life.station.id,added);world.revision+=1
	return {"ok":true}
func direct_fish_available(fish:Dictionary,actor_id:String="human")->bool:
	return fish.get("owner_id")==actor_id and (fish.get("location") in ["pending","storage"] or world.fishing.pens.has(fish.get("location","")))
func cooking_fish(actor_id:String="human")->Dictionary:
	var held:Dictionary=world.fishing.held(actor_id)
	if not held.is_empty():return held
	var stored:Array=world.fishing.fish.values().filter(func(f):return f.get("owner_id")==actor_id and f.get("location")=="storage")
	stored.sort_custom(func(a,b):return float(a.caught_at)<float(b.caught_at))
	return stored[0] if not stored.is_empty() else {}
func menu(actor_id:String="human")->Array:
	var items:Array=[];var stock:Dictionary=available(actor_id)
	for id in config.singles:
		items.append({"id":"single:"+id,"ingredient":id,"ingredients":{} if id=="mushroom" else {id:1},"name":config.singles[id].name,"category":config.singles[id].category,"maximum":160 if id=="mushroom" else mini(160,int(stock.get(id,0))),"portions_per_unit":1,"seconds":3 if id=="mushroom" else config.cook_seconds,"locked":false})
	var fish:Dictionary=cooking_fish(actor_id)
	items.insert(1,{"id":"fish:"+str(fish.get("id","")),"ingredient":"fish","ingredients":{"fish":1},"name":LocalText.source("system.fireside.grilled_fish"),"category":"fish","maximum":0 if fish.is_empty() else 1,"portions_per_unit":1 if fish.is_empty() else int(world.recipes.config.fish_portions[fish.size_id]),"seconds":config.cook_seconds,"locked":false})
	for recipe in world.recipes.recipe_catalog.values():
		var maximum:int=20
		if recipe.fish:maximum=0 if fish.is_empty() or not str(world.recipes.metadata.get(recipe.id,{}).get("fish_species","")).is_empty() and fish.get("species_id")!=world.recipes.metadata[recipe.id].fish_species else 1
		for item in recipe.ingredients:maximum=mini(maximum,int(stock.get(item,0))/int(recipe.ingredients[item]))
		var locked:bool=not world.recipes.recipes.has(recipe.id)
		var ingredients:Dictionary=recipe.ingredients.duplicate(true)
		if recipe.fish:ingredients["fish"]=1
		items.append({"id":"recipe:"+recipe.id,"ingredient":recipe.ingredients.keys()[0],"ingredients":ingredients,"name":recipe.name,"category":"dish","maximum":0 if locked else maximum,"portions_per_unit":int(world.recipes.config.fish_portions[fish.size_id]) if recipe.fish and not fish.is_empty() else int(recipe.portions),"seconds":config.dish_seconds,"locked":locked})
	return items
func roast_host(key:String,actor_id:String="human")->Dictionary:
	var ready:=host_ready(actor_id)
	if not ready.ok:return ready
	if not burning():return world.work.fail("no_fire",LocalText.text("system.fireside.light_the_fire_first"))
	if not state.current.is_empty() and not state.current.ready:return world.work.fail("fire_busy",LocalText.text("system.fireside.food_is_still_cooking_wait_for_this_round"))
	for invited_id in selected_guests:
		var interrupted:Dictionary=can_invite([invited_id])
		if not interrupted.ok:return interrupted
	if state.ate.values().any(func(foods):return foods.size()>=256):return world.work.fail("gathering_full",LocalText.text("system.fireside.this_fireside_record_is_full_end_this_gathering"))

	var options:Array=menu(actor_id).filter(func(o):return o.id==key)
	if options.is_empty() or int(options[0].maximum)<1:return world.work.fail("missing_food",LocalText.text("system.fireside.not_enough_ingredients_gather_some_first"))
	var diners:Array=selected_guests.duplicate()
	steward_human_join=steward_human_authority.is_valid() and steward_human_authority.call(actor_id)
	if (actor_id=="human" or steward_human_join) and near("human",float(config.host_radius)):diners.push_front("human")
	var units:int=mini(int(options[0].maximum),ceili(float(diners.size())/int(options[0].portions_per_unit)))
	if units<1:return world._error("no_diners")
	var choice:Dictionary=options[0];var seconds:float=choice.seconds
	if state.remaining<seconds:return world.work.fail("fire_needs_wood",LocalText.text("system.fireside.the_fire_is_fading_add_2_wood_first"))
	var receipt:Dictionary={};var fish_facts:Dictionary={};var food_id:String=key.get_slice(":",1)
	if key.begins_with("fish:"):
		var fish:Dictionary=cooking_fish(actor_id)
		if fish.is_empty() or fish.id!=food_id:return world._error("fish_not_owned")
		fish_facts=fish.duplicate(true)
	elif choice.category=="dish":
		for item in world.recipes.recipes[food_id].ingredients:receipt[item]=int(world.recipes.recipes[food_id].ingredients[item])*units
		if world.recipes.recipes[food_id].fish:
			fish_facts=cooking_fish(actor_id).duplicate(true)
			if fish_facts.is_empty() or units!=1:return world._error("fish_not_owned")
			var required_species:String=str(world.recipes.metadata.get(food_id,{}).get("fish_species",""))
			if not required_species.is_empty() and fish_facts.get("species_id")!=required_species:return world._error("fish_species_mismatch")
	elif key!="single:mushroom":receipt[food_id]=units
	var debit_result:Dictionary=debit(receipt,actor_id)
	if not debit_result.ok:return world._error("insufficient_carried_food")
	# Start a new explicitly chosen batch; unfinished prior food is honestly waste.
	discard_remaining()
	for old_id in jobs.keys():interrupt(old_id)
	if not fish_facts.is_empty():world.fishing.fish.erase(fish_facts.id)
	if state.committed:
		state.id=Crypto.new().generate_random_bytes(12).hex_encode();state.ate={};state.attended=[]
	loaded_meal=false
	state.current={"id":Crypto.new().generate_random_bytes(12).hex_encode(),"food_id":("fish" if key.begins_with("fish:") else food_id),"menu_id":key,"name":choice.name,"category":choice.category,"receipt":receipt,"fish":fish_facts,"total":units*int(choice.portions_per_unit),"eaten":0,"wasted":maxi(0,units*int(choice.portions_per_unit)-diners.size()),"sources":debit_result.sources,"elapsed":0.0,"seconds":seconds,"ready":false,"eaters":[]}
	_start_meal_timer()
	state.invited=selected_guests.duplicate();state.consent=true;state.suspended=false;state.roast_by=actor_id;state.committed=false;life.station.portions=0;life.station.state="cooking";suppressed.erase("human");circle_closed=false;world.revision+=1
	for invited_id in state.invited:
		suppressed.erase(invited_id)
		world.director.routines[invited_id].interrupt(8)
	world.hunger.invite_fireside(life.station.id,state.invited)
	return {"ok":true,"sources":debit_result.sources,"message":LocalText.text("system.fireside.food_is_on_the_grill_share_it_when")}
func held(id:String)->bool:
	if id=="human":return not state.get("consent",false)
	var r:RefCounted=world.director.routines.get(id)
	if r==null:return true
	return r.held or world.activities.members.has(id) or bool(world.activities.held.get(id,false)) or world.activities.gathering.get("failures",{}).has(id) or world.director.time<r.visual_quiet_until or world.fishing.life.time<float(world.fishing.life.quiet_until.get(id,0)) or (not r.enabled and id not in state.get("invited",[]))
func invite(ids:Array)->Dictionary:
	var checked:=can_invite(ids)
	if not checked.ok:return checked
	# Invitation can precede lighting; no food or human movement is implied.
	if not active():life.station["fireside"]={"version":4,"id":Crypto.new().generate_random_bytes(12).hex_encode(),"remaining":0.0,"suspended":false,"consent":false,"invited":[],"attended":[],"ate":{},"current":{},"committed":false,"light_by":"human","roast_by":"human"}
	for id in ids:
		if id not in selected_guests:selected_guests.append(id)
	return {"ok":true}
func can_invite(ids:Array)->Dictionary:
	if not world.standard.ready(life.station.id):return world._error("unbuilt_camp")
	if ids.size()+1>config.seat_offsets.size() or ids.size()!=Array(ids.reduce(func(a,id):a[id]=true;return a,{}).keys()).size():return world._error("no_seat")
	if ids.any(func(id):return id=="human" or not world.actors.has(id) or not world.residents.supports(world.actors[id],"sit")):return world._error("invalid_participant")
	for id in ids:
		if world.actors[id].region_id!=life.station.region_id and not (life.station.region_id=="home" and world.interior.rooms().has(str(world.actors[id].region_id))):return world.work.fail("different_region",LocalText.text("bbq.reason.region"))
		if not world.fishing.held(id).is_empty() or world.actors[id].has("furniture_id"):return world.work.fail("hands_full",LocalText.text("bbq.reason.hands"))
		var routine:RefCounted=world.director.routines.get(id)
		var local_owned:bool=routine!=null and routine.owns_job()
		if (world.work.jobs.has(id) and world.work.jobs[id].get("id")!=jobs.get(id) and not local_owned) or world.projects.active(id) or world.farms.active(id) or world.activities.members.has(id):return world.work.fail("busy",LocalText.text("bbq.reason.command"))
	return {"ok":true,"participants":["human"]+ids}
func join(id:String)->void:
	if id!="human" and id not in state.get("invited",[]):return
	if world.hunger.rushes.has(id) and not world.hunger.rushes[id].get("arrived",false):return
	# A warehouse handover is idle-owned unless a real command owns its job.
	if id!="human" and world.deliveries.active(id) and not world.work.jobs.has(id):
		world.deliveries.cancel(id)
	if held(id) or jobs.has(id) or world.work.jobs.has(id) or world.projects.active(id) or world.farms.active(id) or world.activities.members.has(id) or world.actors[id].has("furniture_id"):return
	if world._routes.has(id):
		if id=="human":return
		var r:RefCounted=world.director.routines[id]
		var follow:Dictionary=world.hunger.owned_routes.get(id,{})
		var own_follow:bool=follow.has("route") and is_same(follow.route,world._routes[id])
		if not r.owns_route and not own_follow and not (world.hunger.rushes.has(id) and world.hunger.rushes[id].arrived):return
		if own_follow:world.hunger.clear_follow(id)
	if id!="human":
		world.director.routines[id].interrupt(8)
		if world.hunger.rushes.has(id):world.hunger.clear_rush(id)
	var ordered:Array=life.seats()
	# Opposite seats first, then fill each quadrant.
	if ordered.size()==8:ordered=[ordered[0],ordered[4],ordered[2],ordered[6],ordered[1],ordered[5],ordered[3],ordered[7]]
	for seat in ordered:
		if world.work.claims.has(seat.id) or not world.walkable(seat.region_id,world.point(seat)):continue
		world.work.serial+=1
		var job:Dictionary={"id":"job-"+str(world.work.serial),"intent":"eat","phase":"fire_travel","target_id":life.station.id,"seat_id":seat.id,"time":0.0,"region_id":seat.region_id,"position":seat.position.duplicate()}
		world.work.jobs[id]=job
		var result:Dictionary={"ok":true}
		if result.ok:
			jobs[id]=world.work.jobs[id].id;seats[id]=seat.id;world.work.claims[seat.id]=id
			world.interior._arrive(id,job.region_id,Vector2(job.position[0],job.position[1]))
			return
func tick(delta:float)->void:
	if not active() or state.suspended:return
	if not circle_closed and state.current.has("meal_remaining"):
		state.current.meal_remaining=maxf(0,float(state.current.meal_remaining)-delta)
		if state.current.meal_remaining<=0:
			end_circle(LocalText.text("meal.timer.finished"));return
	if state.remaining>0:state.remaining=maxf(0,state.remaining-delta)
	if not circle_closed and not near(str(state.get("roast_by","human") if not state.current.is_empty() else state.get("light_by","human")),float(config.near_radius)):away+=delta
	else:away=0
	if away>float(config.away_seconds):end_circle(LocalText.text("system.fireside.you_left_the_fireside"));away=0
	for id in jobs.keys():
		if held(id):
			if id=="human":interrupt(id);continue
			end_circle(LocalText.text("system.fireside.someone_needs_to_leave_the_fireside"));break
		if jobs[id]!=world.work.jobs.get(id,{}).get("id"):interrupt(id)
	if not state.current.is_empty() and not state.current.ready:
		state.current.elapsed=minf(float(state.current.seconds),float(state.current.elapsed)+delta)
		if state.current.elapsed>=state.current.seconds:
			state.current.ready=true;life.station.portions=state.current.total-state.current.wasted;life.station.state="ready"
			if state.current.category=="dish":
				if not world.barbecue_tastes.has("cooked"):world.barbecue_tastes["cooked"]=[]
				if state.current.food_id not in world.barbecue_tastes.cooked:world.barbecue_tastes.cooked.append(state.current.food_id)
	elif not circle_closed and state.current.get("direct_grill",false) and int(state.current.eaten)==0:
		state.current.wait_elapsed=minf(float(config.get("serve_wait_seconds",90)),float(state.current.wait_elapsed)+delta)
		if state.current.wait_elapsed>=float(config.get("serve_wait_seconds",90)):
			end_circle(LocalText.text("system.fireside.the_fish_went_cold_uneaten_food_was_wasted"))
	if state.consent and not circle_closed and world.director.time>=join_after and state.remaining>0:
		join_after=world.director.time+1
		for id in world.actors:
			if world.director.time<float(suppressed.get(id,0)):continue
			var eligible:bool=((state.get("roast_by","human")=="human" or steward_human_join) and not state.current.get("direct_grill",false) and near(id,float(config.near_radius)) and state.current.get("ready",false) and life.station.portions>0) if id=="human" else id in state.invited
			if eligible:join(id)
	if state.consent and not circle_closed:dialogue.tick()
	if state.remaining<=0:
		end_circle(LocalText.text("system.fireside.the_fire_slowly_went_out"))
		if life.station.portions==0:life.station.state="cold";life.station.artwork={}
func tick_job(id:String,job:Dictionary,delta:float)->void:
	if not active() or jobs.get(id)!=job.id:world.work._finish(id,LocalText.text("system.fireside.the_fireside_action_has_ended"),false);return
	if held(id):
		if id=="human":interrupt(id)
		else:end_circle(LocalText.text("system.fireside.someone_needs_to_leave_the_fireside"))
		return
	if job.phase=="fire_travel":
		job["travel_age"]=float(job.get("travel_age",0))+delta
		if job.travel_age>float(life.activity_rules.job_timeout):interrupt(id);suppressed[id]=world.director.time+float(config.away_seconds);return
		if world._routes.has(id):return
		if life.station.region_id=="dark" and world.actors[id].region_id!="dark":
			interrupt(id);suppressed[id]=world.director.time+float(config.away_seconds);return
		if not world.interior._arrive(id,job.region_id,Vector2(job.position[0],job.position[1])):
			if not world.work.jobs.has(id):interrupt(id);suppressed[id]=world.director.time+float(config.away_seconds)
			return
		job.phase="fire_sit";job.time=0.0
	if id not in state.attended:state.attended.append(id)
	var toward:Vector2=world.point(life.station)-world.point(world.actors[id]);world.actors[id].facing=world.walking_direction(toward)
	if job.phase=="fire_sit":
		world.actors[id].activity="fire_squat" if int(world.director.time/float(config.idle_pose_seconds)+seats.keys().find(id))%3==0 else "fire_sit";job.time+=delta
		if fmod(job.time,float(config.stretch_every))>float(config.stretch_every)-float(config.stretch_seconds):world.actors[id].activity="local_stretch"
		if dialogue.reactions.has(id):world.actors[id].activity="gesture_wave"
		if state.current.is_empty() or not state.current.ready or state.current.eaters.has(id):return
		var reserved:int=world.work.jobs.values().filter(func(j):return j.get("target_id")==life.station.id and j.get("phase")=="fire_eat").size()
		if life.station.portions<=reserved:return
		job.phase="fire_eat";job.time=0.0;job["meal_rank"]=world.hunger.rank(id);job["taste_queued"]=false;world.actors[id].activity="fire_eat";return
	if job.phase=="fire_eat":
		world.actors[id].activity="fire_eat";job.time+=delta
		if not job.get("taste_queued",false) and job.time>=float(config.eat_seconds)*MealMotion.first_chew(world,id,int(job.get("meal_rank",world.hunger.rank(id)))):
			job.taste_queued=true
			dialogue.ate(id,current_food(id),int(job.get("meal_rank",world.hunger.rank(id))))
		if job.time<float(config.eat_seconds):return
		if life.station.portions<=0:job.phase="fire_sit";job.time=0;return
		life.station.portions-=1;life.station.meals_eaten+=1;state.current.eaten+=1;state.current.eaters.append(id)
		if world.director.brains.has(id):preload("res://scripts/brain_interactions.gd").host_event(world,"meal","meal:"+str(state.current.id),id) if state.roast_by=="human" else world.director.brains[id].interactions.enqueue("meal","meal:"+str(state.current.id))
		var tasted:Array=world.barbecue_tastes.by_actor.get(id,[])
		var first:bool=taste_history_known(state.current.food_id) and state.current.food_id not in tasted
		if state.current.food_id not in tasted:tasted.append(state.current.food_id)
		var species_key:String="fish:"+str(state.current.fish.get("species_id",""))
		if state.current.fish.get("species_id") in ["noodle","eel","kite","cutlass"] and species_key not in tasted:tasted.append(species_key)
		world.barbecue_tastes.by_actor[id]=tasted
		if first and id!="human" and world.recipes.metadata.get(state.current.food_id,{}).get("signature_trait","")==world.intelligence.tag(id):
			var witnesses:Array=[id]
			if "human" in state.attended and world.actors.human.region_id==world.actors[id].region_id and world.point(world.actors.human).distance_to(world.point(world.actors[id]))<=12:witnesses.append("human")
			world.memories.record_event("signature_taste",id+":"+state.current.food_id,witnesses,{"actor_id":id,"recipe_id":state.current.food_id})
		if not state.ate.has(id):state.ate[id]=[]
		state.ate[id].append({"food_id":state.current.food_id,"name":state.current.name,"category":state.current.category,"first_time":first,"first_time_known":taste_history_known(state.current.food_id)})
		var food:Dictionary=state.ate[id][-1].duplicate(true);food["fish"]=state.current.fish.duplicate(true)
		job["meal_finished_at"]=world.director.time
		world.hunger.ate(id,state.current.id+":"+id,"barbecue",life.station.id)
		job.phase="fire_sit";job.time=0;world.actors[id].activity="fire_sit";world.revision+=1
func current_food(id:String)->Dictionary:
	var tasted:Array=world.barbecue_tastes.by_actor.get(id,[])
	var species:String=str(state.current.fish.get("species_id",""))
	return {"food_id":state.current.food_id,"name":state.current.name,"category":state.current.category,"fish":state.current.fish.duplicate(true),"first_species":world.barbecue_tastes.known and species in ["noodle","eel","kite","cutlass"] and "fish:"+species not in tasted,"first_time":taste_history_known(state.current.food_id) and state.current.food_id not in tasted,"first_time_known":taste_history_known(state.current.food_id)}

func interrupt(id:String)->void:
	if jobs.has(id) and world.work.jobs.get(id,{}).get("id")==jobs[id]:
		var job:Dictionary=world.work.jobs[id]
		if not world.work.events.any(func(e):return e.get("job_id")==job.id):
			var finished:bool=id in state.get("current",{}).get("eaters",[])
			world.work.record_event(id,job,"completed" if finished else "blocked",LocalText.text("system.fireside.this_meal_has_finished") if finished else LocalText.text("system.fireside.the_fireside_ended_this_does_not_mean_the"))
		world.work.stop(id,false)
	var replacement:Dictionary=world.work.jobs.get(id,{})
	if seats.has(id) and world.work.claims.get(seats[id])==id and not (replacement.get("seat_id")==seats[id] and replacement.get("id")!=jobs.get(id)):world.work.claims.erase(seats[id])
	jobs.erase(id);seats.erase(id)
func command_received(id:String,intent:String="")->void:
	if not active():return
	if intent=="stop" and jobs.has(id):end_circle(LocalText.text("system.fireside.end_the_fireside"));return
	if id!="human" and jobs.has(id):end_circle(LocalText.text("system.fireside.a_companion_went_to_do_something_else"));return
	if jobs.has(id):interrupt(id)
	suppressed[id]=world.director.time+30
	if id=="human":state.consent=false
func end_circle(_reason:String)->void:
	if not active():return
	if state.current.has("meal_remaining"):state.current.meal_remaining=0.0
	discard_remaining()
	for id in jobs.keys():interrupt(id)
	state.consent=false;state.invited=[];selected_guests=[]
	circle_closed=true;dialogue.clear()
	if not state.committed and not state.ate.is_empty():
		var facts:Dictionary={"version":2,"activity_id":state.id,"station_id":life.station.id,"place_id":life.station.get("place_id","home"),"attended":state.attended.duplicate(),"consumed_by":state.ate.keys(),"foods":state.ate.duplicate(true),"roles":{"light":state.light_by,"roast":state.roast_by}}
		if world.memories.record_event("shared_barbecue",state.id,state.ate.keys(),facts):state.committed=true
func discard_remaining()->void:
	if not active() or state.get("current",{}).is_empty():return
	var current:Dictionary=state.current
	current.wasted=int(current.total)-int(current.eaten)
	current.ready=true;current.elapsed=current.seconds
	life.station.portions=0

func after_load()->void:
	jobs.clear();seats.clear();suppressed.clear();dialogue.clear();circle_closed=true;selected_guests=[]
	if state.get("current",{}).has("meal_duration"):
		var old_duration:float=float(state.current.meal_duration)
		var ratio:float=float(state.current.meal_remaining)/old_duration
		_start_meal_timer()
		state.current.meal_remaining*=ratio
	if active() and state.current.has("meal_remaining") and float(state.current.meal_remaining)>0:
		state.current["paused_guests"]=state.invited.duplicate() if not state.invited.is_empty() else state.current.get("paused_guests",[])
		state.suspended=true;state.consent=false;state.invited=[]
		return
	loaded_meal=active() and state.current.get("storage_migrated",false) and int(state.current.get("eaten",0))+int(state.current.get("wasted",0))<int(state.current.get("total",0))
	if active():
		if not loaded_meal and not state.current.get("direct_grill",false):discard_remaining()
		else:circle_closed=false
		state.suspended=false;state.consent=false;state.invited=[]
func valid(data:Variant,actors:Dictionary,station:Dictionary)->bool:
	if not data is Dictionary or data.get("version")!=4:return false
	if not data.get("id") is String or data.id.length()!=24 or not world.catalog._number(data.get("remaining")) or data.remaining<0 or data.remaining>86400:return false
	for key in ["suspended","consent","committed"]:
		if not data.get(key) is bool:return false
	if not actors.has(data.get("light_by","")) or not actors.has(data.get("roast_by","")):return false
	for key in ["invited","attended"]:
		if not data.get(key) is Array or data[key].size()>actors.size() or data[key].size()!=Array(data[key].reduce(func(a,id):a[id]=true;return a,{}).keys()).size() or data[key].any(func(id):return not actors.has(id)):return false
	if not data.get("ate") is Dictionary or data.ate.size()>actors.size() or data.ate.keys().any(func(id):return id not in data.attended or not data.ate[id] is Array or data.ate[id].size()>256):return false
	if not data.get("current") is Dictionary:return false
	var c:Dictionary=data.current
	if c.has("meal_remaining"):
		if not world.catalog._number(c.get("meal_duration")) or float(c.meal_duration) not in [30.0,60.0,90.0,120.0] or not world.catalog._number(c.meal_remaining) or c.meal_remaining<0 or c.meal_remaining>c.meal_duration:return false
		if c.has("paused_guests") and (not c.paused_guests is Array or c.paused_guests.size()>actors.size() or c.paused_guests.any(func(id):return id=="human" or not actors.has(id))):return false
	if c.has("storage_migrated") and not c.storage_migrated is bool:return false
	if c.is_empty():return station.portions==0
	for key in ["id","food_id","menu_id","name","category"]:
		if not c.get(key) is String or c[key].is_empty() or c[key].length()>128:return false
	if c.id.length()!=24 or c.category not in ["fish","dish","mushroom","vegetable","fruit"]:return false
	if not c.get("sources") is Dictionary or not c.sources.get("backpack") is Dictionary or not c.sources.get("storage") is Dictionary:return false
	if not c.get("receipt") is Dictionary or not c.get("fish") is Dictionary or not c.get("eaters") is Array or not c.get("ready") is bool:return false
	for key in ["total","eaten","wasted"]:
		if not world._integer(c.get(key)) or c[key]<0 or c[key]>160:return false
	if c.total<1 or c.eaters.size()!=c.eaten or c.eaters.size()!=Array(c.eaters.reduce(func(a,id):a[id]=true;return a,{}).keys()).size() or c.eaters.any(func(id):return not actors.has(id)):return false
	if c.eaten+c.wasted>c.total:return false
	if c.eaten+c.wasted+(int(station.portions) if c.ready else c.total-c.eaten-c.wasted)!=c.total:return false
	if not world.catalog._number(c.get("seconds")) or c.seconds<=0 or not world.catalog._number(c.get("elapsed")) or c.elapsed<0 or c.elapsed>c.seconds:return false
	for item in c.receipt:
		if item not in (world.recipes.INGREDIENT_IDS if c.category=="dish" else config.singles.keys()) or not world._integer(c.receipt[item]) or c.receipt[item]<1 or c.receipt[item]>160:return false
	if not valid_sources(c.sources,c.receipt):return false
	if c.eaters.any(func(id):return id not in data.attended):return false
	if not c.ready and (c.eaten>0 or int(station.portions)!=0):return false
	if c.category=="fish" and c.food_id=="fish":
		if c.get("direct_grill",false):
			var wood_sources:Variant=c.get("wood_sources")
			return valid_fish(c.fish,true,str(data.get("roast_by","human"))) and c.receipt.is_empty() and c.total==4 and world.catalog._number(c.get("wait_elapsed")) and c.wait_elapsed>=0 and c.wait_elapsed<=float(config.get("serve_wait_seconds",90)) and wood_sources is Dictionary and (valid_sources(wood_sources,{"wood":int(config.wood)}) or valid_sources(wood_sources,{"wood":int(config.get("charcoal_wood",1))}))
		return valid_fish(c.fish,true,str(data.get("roast_by","human"))) and c.receipt.is_empty() and c.total==world.recipes.config.fish_portions[c.fish.size_id]
	if c.category=="dish":
		if not world.recipes.recipe_catalog.has(c.food_id):return false
		var recipe:Dictionary=world.recipes.recipe_catalog[c.food_id]
		if c.receipt.size()!=recipe.ingredients.size():return false
		var batches:int=1 if recipe.fish else int(c.total)/int(recipe.portions)
		if recipe.fish and (not valid_fish(c.fish,true,str(data.get("roast_by","human"))) or c.total!=world.recipes.config.fish_portions[c.fish.size_id]):return false
		var required_species:String=str(world.recipes.metadata.get(c.food_id,{}).get("fish_species",""))
		if recipe.fish and not required_species.is_empty() and c.fish.get("species_id")!=required_species:return false
		if not recipe.fish and (not c.fish.is_empty() or int(c.total)%int(recipe.portions)!=0):return false
		return recipe.ingredients.keys().all(func(item):return c.receipt.get(item)==int(recipe.ingredients[item])*batches)
	if c.food_id=="mushroom" and c.receipt.is_empty():return c.fish.is_empty()
	return c.food_id in config.singles and c.receipt.size()==1 and c.receipt.get(c.food_id)==c.total and c.fish.is_empty()
func valid_fish(fish:Dictionary,allow_stored:bool=false,actor_id:String="human")->bool:
	return fish.get("owner_id")==actor_id and (fish.get("location")=="pending" or (allow_stored and (fish.get("location")=="storage" or world.fishing.pens.has(fish.get("location",""))))) and fish.get("id") is String and world.fishing.known_water(fish.get("source_id","")) and fish.get("size_id") in world.recipes.config.fish_portions and world.fishing.rules.species.any(func(s):return s.id==fish.get("species_id")) and world.fishing.rules.colors.any(func(s):return s.id==fish.get("color_id")) and world.catalog._number(fish.get("scale")) and fish.scale>=1 and fish.scale<=8

func valid_sources(value:Dictionary,receipt:Dictionary)->bool:
	if value.keys().any(func(k):return k not in ["backpack","storage"]):return false
	if not value.get("backpack") is Dictionary or not value.get("storage") is Dictionary:return false
	var totals:Dictionary={}
	for amounts in [value.backpack,value.storage]:
		for item in amounts:
			if item not in receipt or not world._integer(amounts[item]) or amounts[item]<1 or amounts[item]>160:return false
			totals[item]=int(totals.get(item,0))+int(amounts[item])
	return totals.size()==receipt.size() and receipt.keys().all(func(item):return totals.get(item)==receipt[item])

func taste_history_known(food_id:String)->bool:
	# Only new authored foods have provably empty history on pre-expansion saves.
	return world.barbecue_tastes.known or world.recipes.metadata.has(food_id)

func _start_meal_timer()->void:
	var duration:float=30.0 if state.current.get("menu_id","")=="single:mushroom" else 90.0 if not state.current.get("fish",{}).is_empty() else 60.0
	state.current["meal_duration"]=duration;state.current["meal_remaining"]=duration
func resume_meal()->Dictionary:
	var ready:=host_ready()
	if not ready.ok:return ready
	if not state.suspended or float(state.current.get("meal_remaining",0))<=0:return world._error("no_waiting_food")
	var guests:Array=state.current.get("paused_guests",[]).filter(func(id):return world.hunger.rank(id)<3)
	var checked:=can_invite(guests)
	if not checked.ok:return checked
	state.invited=guests;selected_guests=guests.duplicate();state.suspended=false;state.consent=true;circle_closed=false;away=0
	state.current.erase("paused_guests");world.revision+=1
	return {"ok":true}
