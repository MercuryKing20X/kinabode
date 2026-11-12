class_name FishingLife
extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
## Task-side local presentation: no inference, jobs, routes, inventory or auto orders.
var _owner: WeakRef
var world: RefCounted:
	get:return _owner.get_ref()
var config: Dictionary={}
var time:=0.0
var reactions: Dictionary={}
var replies: Array=[]
var waiting_jobs: Dictionary={}
var show_after: Dictionary={}
var recent: Dictionary={}
var quiet_until: Dictionary={}
var rng:=RandomNumberGenerator.new()
func _init(source: RefCounted) -> void:
	_owner=weakref(source);rng.randomize()
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/companions/fishing-life.json"))
	if valid_config(data):config=data
func valid_config(data: Variant) -> bool:
	if not data is Dictionary or data.get("version")!=1 or not data.get("styles") is Dictionary:return false
	for key in ["personal_gap","group_gap","reply_delay","radius","reaction_seconds","show_interval"]:
		if not world.catalog._number(data.get(key)) or data[key]<1 or data[key]>120:return false
	for style in ["calm","lively","curious"]:
		if not data.styles.get(style) is Dictionary:return false
		for context in ["cast","wait","nibble","bite","catch","giant","reply","reply_giant","show"]:
			var lines: Variant=data.styles[style].get(context)
			if not lines is Array or lines.is_empty() or lines.size()>12 or not lines.all(func(line):return line is String and not line.is_empty() and line.length()<=50):return false
	return true
func allowed(id: String) -> bool:
	if id=="human" or not world.director.routines.has(id):return false
	var routine: RefCounted=world.director.routines[id]
	return routine.enabled and not routine.held and time>=float(quiet_until.get(id,0)) and not world.activities.blocked(id) and not world.shared_activity.holds(id)
func cancel(id: String,intent: String="") -> void:
	reactions.erase(id)
	replies=replies.filter(func(reply):return reply.actor_id!=id and reply.target_id!=id)
	if intent=="stop":quiet_until[id]=time+120
func _line(id: String,context: String) -> bool:
	if not allowed(id) or config.is_empty():return false
	var style: String=str(world.intelligence.preferences_for(id).get("fishing_style","calm"))
	var options: Array=config.styles.get(style,config.styles.calm).get(context,[])
	var mapped:String={"catch":"small","giant":"large","reply":"witness","reply_giant":"witness","show":"witness","nibble":"wait"}.get(context,context)
	var specific:Array=[]
	if not world.intelligence.compatibility:
		specific=world.intelligence.speech_pool(id,"fishing_v2_"+mapped)
		var authored:Array=world.intelligence.speech_pool(id,"fishing_"+context)
		if not authored.is_empty():options=authored
	if not specific.is_empty():options=specific
	elif context in ["giant","reply_giant"]:options=world.personality.pool(id,"giant")
	var candidates: Array=world.personality.selection(id,options,[recent.get(id,"")])
	if candidates.is_empty():return false
	if candidates.is_empty():return false
	var text: String=candidates[rng.randi_range(0,candidates.size()-1)]
	if not world.director.say_local(id,text,"fishing_"+context,float(config.personal_gap),float(config.group_gap)):return false
	recent[id]=text;return true
func _react(id: String,kind: String,target: String="") -> void:
	if not allowed(id):return
	reactions[id]={"kind":kind,"target_id":target,"started":time,"until":time+float(config.reaction_seconds)}
func presentation(id: String) -> Dictionary:
	if not allowed(id) or config.is_empty() or not reactions.has(id) or reactions[id].until<=time:return {}
	return reactions[id].duplicate(true)
func _neighbours(id: String) -> Array:
	var actor: Dictionary=world.actors[id];var found: Array=[]
	for other in world.actors.values():
		if other.id==id or not allowed(other.id) or other.region_id!=actor.region_id or world.point(other).distance_to(world.point(actor))>float(config.radius):continue
		var job: Dictionary=world.work.jobs.get(other.id,{})
		if (not job.is_empty() and (job.get("intent")!="fish" or job.get("phase")!="fish_wait")) or world._routes.has(other.id) or world.projects.active(other.id) or world.farms.active(other.id):continue
		found.append(other.id)
	found.sort_custom(func(a,b):return world.point(world.actors[a]).distance_squared_to(world.point(actor))<world.point(world.actors[b]).distance_squared_to(world.point(actor)))
	return found
func catch_context(fish:Dictionary,discovery:bool)->String:
	return "first" if discovery else "rare" if fish.get("color_id")=="aurora" else "large" if float(fish.get("scale",1))>=2.0 else "small"
func trigger(id: String,context: String,discovery: bool=false) -> void:
	if config.is_empty():return
	_react(id,context)
	var announced:=false
	var fish:Dictionary=world.fishing.held(id) if context in ["catch","giant"] else {}
	if discovery and not fish.is_empty() and allowed(id) and world.journal.discoveries.get(id,{}).values().filter(func(first):return first.species_id==fish.species_id).size()==1:
		var custom:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/fish-catch-lines-v3.json"))
		var key:String=str(custom.get(fish.species_id,{}).get(world.intelligence.tag(id),""))
		if not key.is_empty():announced=world.director.say_local(id,LocalText.text(key),"fishing_discovery",float(config.personal_gap),float(config.group_gap))
	if not fish.is_empty() and not announced:
		var actual:String=catch_context(fish,discovery)
		if not world.intelligence.compatibility and not world.intelligence.speech_pool(id,"fishing_v2_"+actual).is_empty():announced=_line(id,actual)
	if discovery and not announced and allowed(id) and (world.intelligence.compatibility or world.intelligence.speech_pool(id,"fishing_v2_first").is_empty()):
		var lines: Array=world.journal.config.discovery_lines
		announced=world.director.say_local(id,lines[rng.randi_range(0,lines.size()-1)],"fishing_discovery",float(config.personal_gap),float(config.group_gap))
	if not announced and fish.is_empty():_line(id,context)
	if context not in ["catch","giant"]:return
	if fish.get("species_id")=="cutlass":_react(id,"giant")
	show_after[id]=time+float(config.show_interval)
	var neighbours:=_neighbours(id)
	if neighbours.is_empty() or replies.size()>=world.residents.capacity:return
	# One event permits one response; responses never call trigger recursively.
	if fish.is_empty():return
	replies.append({"actor_id":neighbours[0],"target_id":id,"fish_id":fish.id,"context":"reply_giant" if context=="giant" or fish.species_id=="cutlass" else "reply","at":time+float(config.reply_delay),"controller":world.actors[neighbours[0]].controller})
func advance(delta: float) -> void:
	time+=delta
	if config.is_empty():return
	for id in reactions.keys():
		if reactions[id].until<=time or not allowed(id):reactions.erase(id)
	for reply in replies.duplicate():
		if time<reply.at:continue
		replies.erase(reply)
		var id: String=reply.actor_id;var target: String=reply.target_id
		if not allowed(id) or world.actors[id].controller!=reply.controller or world.fishing.held(target).get("id")!=reply.fish_id or id not in _neighbours(target):continue
		_react(id,"admire",target);_line(id,reply.context)
	for actor in world.actors.values():
		var id: String=actor.id
		var job: Dictionary=world.work.jobs.get(id,{})
		if job.get("phase")=="fish_wait" and job.get("time",0)>18 and waiting_jobs.get(id)!=job.id:
			waiting_jobs[id]=job.id;_react(id,"look");_line(id,"wait")
		if not allowed(id) or world.fishing.held(id).is_empty() or time<float(show_after.get(id,0)):continue
		show_after[id]=time+float(config.show_interval)
		var neighbours:=_neighbours(id)
		if neighbours.is_empty():continue
		var neighbour: String=neighbours[0]
		_react(neighbour,"admire",id);_line(neighbour,"show")
