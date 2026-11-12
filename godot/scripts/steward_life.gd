extends RefCounted
## Session only. The original intention/World validators own every action.
var idle:Dictionary={}
var cooldown:Dictionary={}
var serial:Dictionary={}
var next_circle:=0.0
var visits:=0
var chases:=0
var next_chase:=0.0
var rng:=RandomNumberGenerator.new()
var history:Array=[]
var speech:Dictionary={}
func eligible(g:Node,id:String,planned:bool=false)->bool:
	var w:RefCounted=g.world
	for plan in g.intentions.plans.values():
		if id in plan.get("gather_guests",[]):return false
	var r:RefCounted=w.director.routines[id]
	return not g.steward.meal_locked(id) and w.hunger.rank(id)<3 and not g.intentions.plans.has(id) and (not w.work.jobs.has(id) or r.owns_job()) and not w.farms.active(id) and not w.projects.active(id) and not w.activities.members.has(id) and not w.activities.held.get(id,false) and not r.held and r.enabled and w.director.time>=r.visual_quiet_until and not g.questions.has(id) and not g.group_questions.has(id) and not g._resident_chat_busy(id) and (not w._routes.has(id) or r.owns_route or w.activities.following.has(id))
func tick(g:Node,delta:float)->void:
	var w:RefCounted=g.world
	if next_circle==0:rng.randomize();next_circle=w.forest.clock+rng.randf_range(300,600)
	for who in speech.keys():
		var pending:Dictionary=speech[who]
		if w.forest.clock>pending.until:speech.erase(who);continue
		if w.director.time<w.director.routines[who].visual_quiet_until:continue
		if w.director.say_local(who,pending.text,"steward_life",30,14):speech.erase(who)
	for id in g.steward.Pool.IDS:
		if not eligible(g,id) or g.steward.awaiting_assignment(id):continue
		idle[id]=float(idle.get(id,0))+delta
		if idle[id]<1:continue
		idle[id]=0.0
		var turn:int=int(serial.get(id,0));serial[id]=turn+1
		var leader:Dictionary=w.actors[g.steward.manager]
		if id==g.steward.manager:continue
		var action:String="go_to"
		var at:Vector2=w.point(leader)+Vector2.from_angle(float(turn+g.steward.Pool.IDS.find(id))*2.4)*float(g.steward.trace_config.squad_idle_radius)
		if not w.walkable(leader.region_id,at):continue
		var step:Dictionary={"action":"go_to","x":at.x,"y":at.y,"region_id":leader.region_id}
		var result:Dictionary=g.intentions.submit(id,[step],g.Channels.direct(id),{},g.steward.manager)
		cooldown[id+":"+action]=w.forest.clock+float(g.steward.trace_config.get("idle_repeat_seconds",180))
		if result.get("ok",false):note(g,id,action)
func note(g:Node,id:String,action:String)->void:
	var category:String="circle" if action=="circle" else "chase" if action=="chase" else "rest"
	var tag:String=g.world.intelligence.tag(id)
	if tag not in ["gentle","lively","laborious","quiet"]:tag="gentle"
	var key:String="steward.life.%s.%s.%d"%[tag,category,int(serial.get(id,0))%4]
	speech[id]={"text":preload("res://scripts/localization.gd").text(key),"until":g.world.forest.clock+30}
	history.append({"id":id,"action":action,"at":g.world.forest.clock})
	if history.size()>256:history.pop_front()
