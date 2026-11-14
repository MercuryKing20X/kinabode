extends Node
const Text=preload("res://scripts/localization.gd")
const Parser=preload("res://scripts/farm_commands.gd")
const Card=preload("res://scripts/group_command_card.gd")
signal feedback(text:String,channel_id:String)
signal actor_reply(actor_id:String,text:String,channel_id:String)
signal barbecue_requested(station_id:String,ids:Array)
signal completed(text:String,channel_id:String)
var host:WeakRef
var game:Node:
	get:return host.get_ref()
var world:RefCounted:
	get:return game.world
var parser:RefCounted=Parser.new()
var fallback_models:Array=[]
var last_execution:Dictionary={}
var pending:Dictionary={}
var card:ConfirmationDialog
var tracked:Array=[]
var speech_queue:Array=[]
func _init(source:Node=null)->void:
	if source!=null:
		host=weakref(source)
		if not world.director.local_speech_window.is_connected(_deliver_speech):world.director.local_speech_window.connect(_deliver_speech)
func setup(source:Node)->void:host=weakref(source)
func _local(ids:Array)->Array:return ids.filter(func(id):return world.actors.has(id) and id!="human" and (not world.director.model_controlled(id) or id in fallback_models))
func closest_local()->String:return parser.closest_local(world)
func unknown(actor_ids:Array,text:String="")->Dictionary:
	var ids:Array=_local(actor_ids);var id:String=ids[0] if not ids.is_empty() else closest_local()
	var tag:String=world.intelligence.tag(id) if not id.is_empty() else "gentle"
	if tag not in ["gentle","lively","laborious","quiet"]:tag="gentle"
	var examples:Array=[]
	if not parser.nearest_farm(world).is_empty():examples.append(Text.source("content.one_line.literal_0"))
	if not nearest_fire().is_empty():examples.append(Text.source("content.one_line.literal_1"))
	if examples.size()<2:examples.append(Text.source("content.one_line.literal_2"))
	examples.append(Text.source("content.one_line.literal_3"))
	if not text.is_empty():examples.sort_custom(func(a,b):return str(a).to_lower().similarity(text.to_lower())>str(b).to_lower().similarity(text.to_lower()))
	return {"actor_id":id,"line":Text.text("local.commands.unknown_"+tag),"examples":examples}

func submit(text:String,fallback_ids:Array=[],channel_id:String="",authorized_models:Array=[],exact_ids:Array=[],material_account:Dictionary={},preferred_targets:Dictionary={})->Dictionary:
	last_execution={}
	fallback_models=authorized_models.filter(func(id):return id!="human" and world.actors.has(id))
	if is_instance_valid(card):card.hide();card.queue_free()
	pending.clear()
	var parsed:Dictionary=parser.parse_command(world,text,fallback_ids)
	if not exact_ids.is_empty() and parsed.get("ok",false):
		if exact_ids.any(func(id):return id=="human" or not world.actors.has(id)):return {"handled":false}
		parsed.actor_ids=exact_ids.duplicate()
	if parsed.is_empty():return {"handled":false,"parsed":false,"local_ids":[],"model_ids":[]}
	if not preferred_targets.is_empty():
		if parsed.get("action","") not in ["chop","forage"] or preferred_targets.keys().any(func(id):return id not in parsed.actor_ids):return {"handled":false}
		for target in preferred_targets.values():
			if not target is String or (parsed.action=="chop" and (not world.objects.has(target) or world.objects[target].kind!="tree")):return {"handled":false}
		parsed["preferred_targets"]=preferred_targets.duplicate(true)
	var ids:Array=parsed.actor_ids;var locals:Array=_local(ids);var models:Array=ids.filter(func(id):return world.director.model_controlled(id) and id not in fallback_models)
	if locals.is_empty():return {"handled":false,"parsed":bool(parsed.ok),"local_ids":[],"model_ids":models,"explicit_targets":parsed.explicit_targets}
	if not parsed.ok:
		var response:Dictionary=unknown(locals);var note:String=str(parsed.get("message",response.line))+"\n"+" / ".join(response.examples)
		feedback.emit(note,channel_id)
		return {"handled":true,"parsed":false,"local_ids":locals,"model_ids":models,"feedback":note,"reply":response,"examples":response.examples,"explicit_targets":parsed.explicit_targets}
	if is_instance_valid(card):card.hide();card.queue_free()
	if parsed.action=="query_state":
		last_execution={"ok":true,"actors":locals.duplicate()}
		for actor in locals:
			var activity:String=str(world.actors[actor].activity)
			var line:String=Text.text("local.commands.state")%[Text.content(activity),str(world.hunger.summary(actor).get("state","")),world.storage.count("wood")]
			if channel_id=="command":speech_queue.append({"actor_id":actor,"line":line,"channel_id":channel_id,"expires":world.director.time+180})
			actor_reply.emit(actor,line,channel_id);feedback.emit(Text.resident(world,actor)+": "+line,channel_id)
		return {"handled":true,"parsed":true,"local_ids":locals,"model_ids":models,"explicit_targets":parsed.explicit_targets}
	var plan:Dictionary=preview(parsed,locals)
	for row in plan.rows:
		if not row.get("missing",{}).is_empty():
			var missing:Array=[]
			for seed in row.missing:
				var crop:String=str(seed).trim_prefix("seed.");missing.append(Text.content(world.farms.crops.get(crop,{}).get("name",crop))+" ×"+str(row.missing[seed]))
			feedback.emit(Text.resident(world,row.actor_id)+Text.source("content.one_line.literal_4")+", ".join(missing),channel_id)
	for model in models:plan.rows.append({"actor_id":model,"allowed":false,"reason":Text.text("local.commands.model")})
	plan["fallback_models"]=fallback_models.duplicate()
	plan["steward_order"]=not material_account.is_empty()
	plan.id=Crypto.new().generate_random_bytes(12).hex_encode();plan.channel_id=channel_id
	pending=plan.duplicate(true)
	var settings:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/companions/host-commands.json"))
	var material_count:int=0
	for row in plan.rows:
		for count in row.get("seed_costs",{}).values():material_count+=int(count)
	var automatic:bool=material_count<=int(settings.confirmation_material_threshold)
	if not material_account.is_empty():automatic=material_account.generation==world.session_generation and game.steward.authorized(material_account.source) and locals.all(func(id):return id in material_account.ids) and int(material_account.remaining)>=material_count
	if automatic:
		var selected:Array=plan.rows.filter(func(row):return row.allowed).map(func(row):return row.actor_id)
		for row in plan.rows:
			if not row.allowed and world.resort!=null and str(row.reason)==world.resort.line():speech_queue.append({"actor_id":row.actor_id,"line":world.resort.line(),"channel_id":channel_id,"expires":world.director.time+180})
			if not row.allowed:feedback.emit(Text.resident(world,row.actor_id)+": "+(Text.text("farm.help."+str(row.reason)) if Text.entries.has("farm.help."+str(row.reason)) else str(row.reason)),channel_id)
		decide(plan.id,true,selected)
		if not material_account.is_empty() and last_execution.get("ok",false):material_account.remaining-=material_count
		return {"handled":true,"parsed":true,"local_ids":locals,"model_ids":models,"explicit_targets":parsed.explicit_targets}
	card=Card.new();game.add_child(card);card.setup(plan,world,game.ui_font if game.get("ui_font")!=null else game.view.font)
	if game.get("island_hud")!=null:card.add_theme_stylebox_override("panel",game.island_hud.pixel_style())
	card.decision.connect(decide);card.popup_centered()
	feedback.emit(Text.text("local.commands.awaiting"),channel_id)
	return {"handled":true,"parsed":true,"local_ids":locals,"model_ids":models,"card":card,"feedback":Text.text("local.commands.awaiting"),"explicit_targets":parsed.explicit_targets}
func eligible(id:String,action:String)->String:
	if world.resort!=null and world.resort.vacation(id) and action in ["plant","ready","water","chop","forage","start_project","build_stage","hand_over","fish"]:return world.resort.line()
	if action in ["stop","unfollow"]:return ""
	if world.director.model_controlled(id) and id not in fallback_models:return Text.text("local.commands.model")
	if id not in fallback_models and game.has_method("_resident_chat_busy") and game._resident_chat_busy(id):return Text.text("local.commands.busy")
	if world.actors[id].region_id!=world.actors.human.region_id:return Text.text("local.commands.region")
	if action=="stop":return ""
	if world.hunger.rank(id)>=3 or (action in ["plant","ready","water","chop","forage","start_project","build_stage"] and world.hunger.rank(id)>=2):return Text.text("local.commands.hungry")
	if action in ["unfollow","stop"]:return ""
	# An explicit host follow selection pauses the resident's existing work and
	# route in ResidentActivity. Do not reject it as busy before that handover.
	if action=="follow":return ""
	var routine:RefCounted=world.director.routines.get(id)
	if world.farms.active(id) or world.projects.active(id) or world.activities.members.has(id):return Text.text("local.commands.busy")
	if world.work.jobs.has(id) and (routine==null or not routine.owns_job()):return Text.text("local.commands.busy")
	if world._routes.has(id) and not world.activities.following.has(id) and (routine==null or not routine.owns_route):return Text.text("local.commands.busy")
	return ""
func preview(parsed:Dictionary,locals:Array)->Dictionary:
	var result:Dictionary=parsed.duplicate(true);result.rows=[]
	if parsed.action in ["plant","ready","water"]:
		result.farm_plan=world.farms.preview_host_orders(locals,"plant" if parsed.action=="water" else parsed.action,parsed.farm_id,parsed.crop_id)
		if parsed.action=="water":
			for row in result.farm_plan.rows:
				row.plot_ids=row.plot_ids.filter(func(pid):return world.farms.stage(world.farms.plots[pid])=="dry")
				row.seed_costs={};row.missing={};row.allowed=not row.plot_ids.is_empty() and row.eligible
				if not row.allowed:row.reason="no_work"
			result.farm_plan.seal=preload("res://scripts/farm_host_plan.gd").seal(world.farms,result.farm_plan)
		result.rows=result.farm_plan.rows.duplicate(true)
		for row in result.rows:
			if world.resort!=null and world.resort.vacation(row.actor_id):row.allowed=false;row.reason=world.resort.line()
			if row.actor_id not in fallback_models and game.has_method("_resident_chat_busy") and game._resident_chat_busy(row.actor_id):row.allowed=false;row.reason=Text.text("local.commands.busy")
		return result
	if parsed.action=="vacation":
		var probe:String=str(parsed.source_text).to_lower()
		var kind:String="pool" if [preload("res://scripts/localization.gd").source("content.health_20261107.f9a3556490d4"),preload("res://scripts/localization.gd").source("content.health_20261107.217c29a4e150"),"swim","pool"].any(func(word):return probe.contains(word)) else "hammock" if probe.contains(preload("res://scripts/localization.gd").source("content.health_20261107.e2eeefe44c88")) or probe.contains("hammock") else "swing" if probe.contains(preload("res://scripts/localization.gd").source("content.workshop.swing")) or probe.contains("swings") else "stars" if probe.contains(preload("res://scripts/localization.gd").source("content.health_20261107.83e9c51b3d7a")) or probe.contains("stars") else "sea" if probe.contains(preload("res://scripts/localization.gd").source("content.health_20261107.0ac6d5192ec2")) or probe.contains("sea") else "lounge"
		result.activity_id=world.resort.nearest(kind)
	var target:Dictionary=destination(str(parsed.target))
	if parsed.action=="barbecue":result.station_id=nearest_fire()
	if parsed.action=="gather":result.destination=target
	for id in locals:
		var reason:String=eligible(id,parsed.action)
		if parsed.action=="gather" and target.is_empty():reason=Text.text("local.commands.no_target")
		if parsed.action=="barbecue" and str(result.station_id).is_empty():reason=Text.text("local.commands.no_target")
		result.rows.append({"actor_id":id,"allowed":reason.is_empty(),"reason":reason})
	return result
func nearest_fire()->String:
	var best:="";var distance:=INF
	for id in world.barbecues:
		if world.standard!=null and not world.standard.ready(id):continue
		var station:Dictionary=world.barbecues[id].station
		if station.region_id!=world.actors.human.region_id:continue
		var d:float=world.point(station).distance_squared_to(world.point(world.actors.human))
		if d<distance:best=id;distance=d
	if not best.is_empty() and world.standard!=null and not world.standard.ready(best):return ""
	return best
func destination(target:String)->Dictionary:
	if target=="human":return {"region_id":world.actors.human.region_id,"position":world.actors.human.position.duplicate()}
	if target=="south":return {"region_id":"home","position":world.home_island.config.arrival.duplicate()} if world.home_island!=null and not world.home_island.legacy else {}
	if target=="campfire":
		var id:String=nearest_fire()
		return {"region_id":world.barbecues[id].station.region_id,"position":world.barbecues[id].station.position.duplicate()} if not id.is_empty() else {}
	if target=="house":
		for plot in world.catalog.regions.home.get("layout",{}).get("residential",[]):
			if plot.owner_id=="human" and world.objects.has(plot.site_id) and world.objects[plot.site_id].stage_index==5:
				var at:Vector2=world.interior.outside("room."+str(plot.site_id));return {"region_id":"home","position":[at.x,at.y]}
	return {}
func decide(id:String,accepted:bool,selected:Array)->void:
	if pending.is_empty() or pending.id!=id:return
	var plan:Dictionary=pending.duplicate(true);pending.clear();fallback_models=plan.get("fallback_models",[]).duplicate()
	if is_instance_valid(card):card.hide();card.queue_free()
	if not accepted:feedback.emit(Text.text("local.commands.canceled"),plan.channel_id);return
	var ids:Array=plan.rows.filter(func(row):return row.allowed and row.actor_id in selected).map(func(row):return row.actor_id)
	ids=_local(ids)
	# Host confirmation revokes only conflicting steward work, before revalidation.
	if not plan.get("steward_order",false) and not ids.is_empty():
		for actor in ids:
			var old:Dictionary=game.intentions.plans.get(actor,{})
			if not str(old.get("sponsor","")).is_empty():
				game.intentions.cancel(actor);world.command(actor,{"intent":"stop"})
	var fresh:Dictionary={}
	if plan.action not in ["plant","ready","water"]:
		fresh=preview(plan,ids);ids=fresh.rows.filter(func(row):return row.allowed).map(func(row):return row.actor_id)
	if ids.is_empty():
		last_execution={"ok":false,"error":"no_eligible_participant"}
		var reasons:Array=plan.rows.filter(func(row):return not row.allowed).map(func(row):return Text.resident(world,row.actor_id)+": "+(Text.text("farm.help."+str(row.reason)) if Text.entries.has("farm.help."+str(row.reason)) else str(row.reason)))
		feedback.emit("；".join(reasons) if not reasons.is_empty() else Text.text("local.commands.nobody"),plan.channel_id);return
	var was_following:Array=world.activities.following.keys()
	var successful:Array=[];var order_tokens:Dictionary={}
	if plan.action in ["plant","ready","water"]:
		ids=ids.filter(func(actor):return eligible(actor,plan.action).is_empty())
		if ids.is_empty():last_execution={"ok":false,"error":"no_eligible_participant"};feedback.emit(Text.text("local.commands.nobody"),plan.channel_id);return
		var result:Dictionary=world.farms.confirm_host_orders(plan.farm_plan,ids)
		for row in result.get("rows",[]):
			if row.get("ok",false):successful.append(row.actor_id);order_tokens[row.actor_id]=str(row.get("order_id",""))
			else:feedback.emit(Text.resident(world,row.actor_id)+": "+str(row.get("message",row.get("error",""))),plan.channel_id)
	elif plan.action=="vacation":
		var result:Dictionary=world.resort.begin(fresh.activity_id,["human"]+ids)
		last_execution=result
		feedback.emit(str(result),plan.channel_id);return
	elif plan.action=="open_chess":
		var actor:String=ids[0]
		var tables:Array=world.leisure.sites.keys().filter(func(site):return not world.gomoku.table(site).is_empty() and world.gomoku.table(site).complete)
		tables.sort_custom(func(a,b):return world.point(world.leisure.sites[a]).distance_squared_to(world.point(world.actors.human))<world.point(world.leisure.sites[b]).distance_squared_to(world.point(world.actors.human)))
		var result:Dictionary=world.gomoku.begin_host(tables[0],actor,true,"local","normal") if not tables.is_empty() else {"ok":false,"error":"no_built_chess_table"}
		if result.get("ok",false):successful.append(actor)
		else:feedback.emit(str(result.get("message",result.get("error",""))),plan.channel_id)
	elif plan.action=="start_project":
		for actor in ids:
			world.activities.release_follow(actor)
			var template:String="play-gazebo"
			var text:String=str(plan.source_text).to_lower()
			for entry in [[Text.source("content.one_line.literal_5"),"chair","outdoor-chair"],[Text.source("content.workshop.swing"),"swing","play-swing"],[Text.source("content.one_line.literal_6"),"path","outdoor-path"],[Text.source("content.one_line.literal_7"),"flowers","outdoor-flowers"],[Text.source("content.one_line.literal_8"),"stage","play-stage"]]:
				if text.contains(entry[0]) or text.contains(entry[1]):template=entry[2]
			var anchor:=Vector2.ZERO
			for territory in world.home_island.config.their_island.territories:
				if territory.owner_id==actor:anchor=Vector2(territory.anchor[0],territory.anchor[1])
			var result:Dictionary={"ok":false,"error":"no_available_project_site"}
			for offset in [Vector2(0,-12),Vector2(0,12),Vector2(0,24),Vector2(0,-24),Vector2(0,36),Vector2(0,-36)]:
				var at:Vector2=anchor+offset
				result=world.their_island.propose(actor,{"template_id":template,"x":at.x,"y":at.y,"name":Text.resident(world,actor)+" · "+template,"reason":Text.source("content.one_line.literal_9")},true)
				if result.get("ok",false):break
			if result.get("ok",false):
				var cost:int=preload("res://scripts/leisure_rules.gd").cost(world.library.artworks[template].recreation)
				if cost<=int(JSON.parse_string(FileAccess.get_file_as_string("res://content/companions/host-commands.json")).confirmation_material_threshold):result=world.their_island.decide(actor,result.proposal_id,"accept")
				else:feedback.emit(Text.source("content.one_line.literal_10"),plan.channel_id);continue
			if result.get("ok",false):successful.append(actor)
			else:feedback.emit(Text.resident(world,actor)+": "+str(result.get("message",result.get("error",""))),plan.channel_id)
	elif plan.action=="build_stage":
		# A work command means one actual stage, never a new island proposal.
		var sites:Array=world.objects.values().filter(func(site):return site.kind=="construction_site" and site.region_id==world.actors.human.region_id and int(site.get("stage_index",0))<5)
		sites.sort_custom(func(a,b):return world.point(a).distance_squared_to(world.point(world.actors.human))<world.point(b).distance_squared_to(world.point(world.actors.human)))
		for actor in ids:
			var result:Dictionary={"ok":false,"error":"no_available_project_site"}
			for site in sites:
				if world.work.claims.has(site.id):continue
				world.activities.release_follow(actor)
				# Host authorization is scoped to this exact original build job.
				world.director.command_received(actor,"build")
				result=world.work.start(actor,"build",site.id)
				if result.get("ok",false):break
			if result.get("ok",false):successful.append(actor)
			else:feedback.emit(Text.resident(world,actor)+": "+str(result.get("message",result.get("error",""))),plan.channel_id)
	elif plan.action=="forage":
		for actor in ids:
			world.activities.release_follow(actor)
			var mushrooms:bool=str(plan.source_text).contains(Text.source("hud.mushroom")) or str(plan.source_text).to_lower().contains("mushroom")
			var targets:Array=world.all_mushrooms().values() if mushrooms else world.ingredients.sources()
			if not mushrooms:
				var named:Array=targets.filter(func(target):return str(plan.source_text).contains(str(target.get("name","#"))) or str(plan.source_text).to_lower().contains(str(target.get("name_en","#")).to_lower()))
				if not named.is_empty():targets=named
			if plan.get("preferred_targets",{}).has(actor):targets=targets.filter(func(target):return target.id==plan.preferred_targets[actor])
			targets.sort_custom(func(a,b):return world.point(world.actors[actor]).distance_squared_to(world.point(a))<world.point(world.actors[actor]).distance_squared_to(world.point(b)))
			var gathered:bool=false
			for target in targets:
				var region:String=str(target.get("region_id",target.get("region","")))
				if region!=world.actors[actor].region_id:continue
				var result:Dictionary=world.host_text_command(actor,{"intent":"forage","target_id":target.id}) if mushrooms else world.ingredients.begin_resident(actor,target.id)
				if result.get("ok",false):successful.append(actor);gathered=true;break
			if not gathered:feedback.emit(Text.resident(world,actor)+Text.source("content.one_line.literal_11"),plan.channel_id)
	elif plan.action=="fish":
		for actor in ids:world.activities.release_follow(actor)
		var result:Dictionary=world.fishing.invite_from_host_text(ids)
		successful=result.get("accepted",[])
		if not result.get("message","").is_empty():feedback.emit(result.message,plan.channel_id)
	elif plan.action in ["chop","hand_over"]:
		for actor in ids:
			world.activities.release_follow(actor)
			var command:Dictionary={"intent":"gather_wood","tree_count":tree_count(str(plan.source_text))}
			if plan.get("preferred_targets",{}).has(actor):command.target_id=plan.preferred_targets[actor]
			var result:Dictionary=world.host_text_command(actor,command) if plan.action=="chop" else {"ok":world.deliveries.request(actor)}
			if result.get("ok",false):successful.append(actor)
			else:feedback.emit(Text.resident(world,actor)+": "+str(result.get("message",result.get("error",Text.source("content.one_line.literal_12")))),plan.channel_id)
	elif plan.action=="stop":
		for actor in ids:
			if world.command(actor,{"intent":"stop"}).get("ok",false):successful.append(actor)
	elif plan.action in ["follow","unfollow"]:
		var followers:Array=world.activities.following.keys()
		for actor in ids:
			if plan.action=="follow" and actor not in followers:followers.append(actor)
			if plan.action=="unfollow":followers.erase(actor)
			if plan.action=="follow" and not (world.director.brains.has(actor) and world.director.brains[actor].continuing_follow()):world.activities.release_follow(actor)
		if world.activities.set_followers(followers).get("ok",false):successful=ids
	elif plan.action=="gather":
		var result:Dictionary=world.activities.gather_selected(ids,fresh.destination.region_id,Vector2(fresh.destination.position[0],fresh.destination.position[1]))
		if result.get("ok",false):successful=ids
	elif plan.action=="barbecue":
		barbecue_requested.emit(fresh.station_id,ids);last_execution={"ok":world.barbecues[fresh.station_id].fireside.selected_guests.any(func(id):return id in ids),"actors":ids};feedback.emit(Text.text("local.commands.bbq_handoff"),plan.channel_id);return
	if successful.is_empty():last_execution={"ok":false,"error":"no_validated_action"};feedback.emit(Text.text("local.commands.nobody"),plan.channel_id);return
	last_execution={"ok":true,"actors":successful.duplicate()}
	var job_ids:Dictionary={}
	for actor in successful:job_ids[actor]=str(world.work.jobs.get(actor,{}).get("id",""))
	tracked.append({"job_ids":job_ids,"actors":successful.duplicate(),"was_following":was_following,"returning":[],"finished":[],"action":plan.action,"channel_id":plan.channel_id,"order_tokens":order_tokens,"canceled":[],"next_text":plan.get("next_text",""),"fallback_models":fallback_models.duplicate(),"steward_order":plan.get("steward_order",false)})
	for actor in successful:
		var tag:String=world.intelligence.tag(actor)
		if tag not in ["gentle","lively","laborious","quiet"]:tag="gentle"
		speech_queue.append({"actor_id":actor,"line":Text.text("local.commands.start_"+tag),"channel_id":plan.channel_id,"expires":world.director.time+180})
	feedback.emit(Text.text("local.commands.started"),plan.channel_id)
func _process(_delta:float)->void:
	if host==null or game==null:return
	for item in tracked.duplicate():
		for id in item.actors:
			if id in item.finished or id in item.canceled:continue
			var done:bool=false
			if id in item.returning:
				done=true
			elif item.action=="follow" and not world.activities.following.has(id) or item.action=="gather" and not world.activities.members.has(id):
				item.canceled.append(id);feedback.emit(Text.text("local.commands.interrupted")%Text.resident(world,id),item.channel_id);continue
			if id in item.returning:done=true
			elif item.action in ["open_chess","start_project","build_stage","forage","fish","chop","hand_over"]:done=not world.work.jobs.has(id) and not world.deliveries.active(id) and not world.ingredients.resident_pending.has(id)
			elif item.action=="stop":done=true
			elif item.action=="unfollow":done=not world.activities.following.has(id)
			elif item.action=="follow":done=world.activities.following.has(id) and world.point(world.actors[id]).distance_to(world.point(world.actors.human))<=4 and not world._routes.has(id)
			elif item.action in ["plant","ready","water"]:
				var order:Dictionary=world.farms.orders.get(id,{})
				if str(order.get("host_order_id",""))!=str(item.order_tokens.get(id,"")) or order.get("status","") in ["paused","stopped","canceled"]:
					item.canceled.append(id);feedback.emit(Text.text("local.commands.interrupted")%Text.resident(world,id),item.channel_id);continue
				done=order.get("status","")=="completed" and not world.farms.active(id)
			elif item.action=="gather":done=world.activities.members.get(id,{}).get("arrived",false)
			if done and id not in item.returning and item.action in ["chop","fish","build_stage"]:
				var receipt:Array=world.work.events.filter(func(event):return event.get("actor_id","")==id and event.get("job_id","")==item.job_ids.get(id,"") and event.get("status","") in ["completed","blocked","cancelled","waiting_materials"])
				if receipt.is_empty() or receipt.back().status!="completed":
					item.canceled.append(id);feedback.emit(Text.text("local.commands.interrupted")%Text.resident(world,id),item.channel_id);continue
			if world.hunger.rank(id)>=3 and id not in item.returning:
				item.canceled.append(id);recall(id);feedback.emit(Text.resident(world,id)+": "+Text.text("local.commands.hungry"),item.channel_id);continue
			if done and not item.get("steward_order",false) and item.action not in ["stop","unfollow","follow"]:
				if id not in item.returning:
					item.returning.append(id)
					if world.activities.members.has(id):world.activities.members.erase(id)
					var followers:Array=world.activities.following.keys()
					if id not in followers:followers.append(id)
					world.activities.set_followers(followers)
				_approach_returning(item,id)
				done=world.actors[id].region_id==world.actors.human.region_id and world.point(world.actors[id]).distance_to(world.point(world.actors.human))<=3
			if done:
				if id in item.returning and id not in item.was_following:world.activities.release_follow(id)
				item.finished.append(id);var tag:String=world.intelligence.tag(id)
				if tag not in ["gentle","lively","laborious","quiet"]:tag="gentle"
				speech_queue.append({"actor_id":id,"line":Text.text("local.commands.done_"+tag),"channel_id":item.channel_id,"expires":world.director.time+180})
		if item.finished.size()+item.canceled.size()==item.actors.size():
			if item.canceled.is_empty():completed.emit(Text.text("local.commands.all_done_"+item.action) if Text.entries.has("local.commands.all_done_"+item.action) else Text.text("local.commands.all_done"),item.channel_id)
			tracked.erase(item)
			if item.canceled.is_empty() and not str(item.get("next_text","")).is_empty():call_deferred("submit",item.next_text,item.actors,item.channel_id,item.get("fallback_models",[]))
	_deliver_speech()

func _approach_returning(item:Dictionary,id:String)->void:
	# The ordinary following formation may be wider than the actual <=3 hand-in.
	# Cross-region travel stays with the existing follower/door route until local.
	var actor:Dictionary=world.actors[id];var human:Dictionary=world.actors.human
	if actor.region_id!=human.region_id or world.point(actor).distance_to(world.point(human))<=3:return
	if world.work.jobs.has(id) or world.farms.active(id) or world.projects.active(id) or world.homestead.active(id) or world.deliveries.active(id) or not world.hunger.can_follow(id):return
	var routine:RefCounted=world.director.routines[id];var now:float=world.director.time
	if now<routine.visual_quiet_until or now<float(world.hunger.quiet_until.get(id,0)) or world.fishing.life.time<float(world.fishing.life.quiet_until.get(id,0)):return
	var retry:Dictionary=item.get("return_after",{})
	if now<float(retry.get(id,0)):return
	# A new manual/task/play route or this existing return route is never replaced.
	if world._routes.has(id):
		var lease:Dictionary=world.hunger.owned_routes.get(id,{})
		if not lease.has("route") or not is_same(lease.route,world._routes[id]):return
	retry[id]=now+float(world.hunger.config.follow_interval);item["return_after"]=retry
	# clear_follow cancels only this resident's matching hunger-owned route.
	world.hunger.clear_follow(id)
	world.approach(id,human)

func _deliver_speech(actor_id:String="")->void:
	for speech in speech_queue.duplicate():
		if not actor_id.is_empty() and speech.actor_id!=actor_id:continue
		var routine:RefCounted=world.director.routines.get(speech.actor_id)
		if routine==null or world.director.time<routine.visual_quiet_until or world.fishing.life.time<float(world.fishing.life.quiet_until.get(speech.actor_id,0)):continue
		if speech.expires<world.director.time:speech_queue.erase(speech);continue
		if world.director.say_local(speech.actor_id,speech.line,"host_command_complete",float(world.hunger.config.personal_gap),float(world.hunger.config.village_gap)):
			actor_reply.emit(speech.actor_id,speech.line,speech.channel_id);speech_queue.erase(speech)

func tree_count(text:String)->int:
	var expression:=RegEx.new();expression.compile("[0-9]+")
	var found:RegExMatch=expression.search(text)
	if found!=null:return clampi(int(found.get_string()),1,100)
	for pair in [[preload("res://scripts/localization.gd").source("content.health_20261107.51a75f4634df"),1],[preload("res://scripts/localization.gd").source("content.health_20261107.83385d2edafe"),2],[preload("res://scripts/localization.gd").source("content.health_20261107.084b42f6e95e"),2],[preload("res://scripts/localization.gd").source("content.health_20261107.a4c3313deb18"),3],[preload("res://scripts/localization.gd").source("content.health_20261107.754a9d5828d5"),4],[preload("res://scripts/localization.gd").source("content.health_20261107.c9b87f516a38"),5],[preload("res://scripts/localization.gd").source("content.health_20261107.de07b5383874"),6],[preload("res://scripts/localization.gd").source("content.health_20261107.1b0542878c67"),7],[preload("res://scripts/localization.gd").source("content.health_20261107.2c467d367392"),8],[preload("res://scripts/localization.gd").source("content.health_20261107.df897da6e02e"),9],[preload("res://scripts/localization.gd").source("content.health_20261107.fc7edd399a5c"),10]]:
		if text.contains(str(pair[0])+preload("res://scripts/localization.gd").source("content.health_20261107.f1c9fb52fcfb")):return int(pair[1])
	return 3
func replace_order(id:String)->void:
	for item in tracked:
		if id in item.actors and id not in item.finished and id not in item.canceled:
			world.command(id,{"intent":"stop"});item.canceled.append(id)
	for speech in speech_queue.duplicate():
		if speech.actor_id==id:speech_queue.erase(speech)
func recall(id:String)->void:
	replace_order(id)
	var followers:Array=world.activities.following.keys()
	if id not in followers:followers.append(id)
	world.activities.set_followers(followers)

func progress_text(id:String,item:Dictionary)->String:
	if id in item.returning:return " · "+("Returning" if TranslationServer.get_locale().begins_with("en") else preload("res://scripts/localization.gd").source("content.health_20261107.2687a1b739dd"))
	if item.action=="chop":
		var job:Dictionary=world.work.jobs.get(id,{})
		return " %s/%s"%[job.get("trees_cut",0),job.get("tree_count",3)]
	if item.action in ["plant","ready","water"]:
		var order:Dictionary=world.farms.orders.get(id,{})
		return " %s/%s"%[order.get("completed",[]).size(),world.farms.farm_plots(str(order.get("farm_id",""))).size()]
	return ""
