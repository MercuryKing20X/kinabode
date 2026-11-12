extends RefCounted
## DIRECTION v0.6: inspect real owners, never treat an intention label as work.
var seconds:Dictionary={}
var previous:Dictionary={}
func waiting_for_fishing_team(g:Node,id:String)->bool:
	var w:RefCounted=g.world
	var d:RefCounted=g.steward.body_director
	# A completed fisher waits at her assigned coast for this exact team's
	# remaining real fishing job. A stale task label or another batch is no proof.
	if d.batch.get("phase","")!="running" or d.batch.get("step",{}).get("action","")!="fish":return false
	var members:Array=d.batch.get("members",[])
	if id not in members or not d.tasks.has(id) or d.tasks[id].get("action","")!="fish":return false
	if d.batch.get("primary_tasks",{}).get(id,-1)!=d.tasks[id].get("id",-2):return false
	# team_shores is consumed when the real job starts. The primary task was
	# recorded at that coast; validate its retained position against live terrain.
	if w.point(w.actors[id]).distance_to(d.tasks[id].position)>.5 or w.fishing.shore(id).is_empty():return false
	return members.any(func(who):return who!=id and w.work.jobs.get(who,{}).get("intent","")=="fish")
func waiting_for_regroup(g:Node,id:String)->bool:
	var w:RefCounted=g.world
	var d:RefCounted=g.steward.body_director
	if id not in g.steward.Pool.IDS or d.paused.has(id):return false
	# The director considers a same-region resident already within eight tiles
	# regrouped. Only distant residents receive a formation slot and a route.
	if w.actors[id].region_id!=w.actors[g.steward.manager].region_id or w.point(w.actors[id]).distance_to(w.point(w.actors[g.steward.manager]))>8:return false
	return g.steward.Pool.IDS.any(func(who):return who!=id and d.tasks.get(who,{}).get("action","")=="travel" and d.tasks[who].get("route")!=null and is_same(d.tasks[who].route,w._routes.get(who,[])))
func sample(g:Node,id:String,delta:float)->float:
	var w:RefCounted=g.world
	var at:Vector2=w.point(w.actors[id])
	var moved:bool=not previous.has(id) or at.distance_to(previous[id])>=.01
	previous[id]=at
	var moving:bool=w._routes.has(id)
	var occupied:bool=w.work.jobs.has(id) or w.farms.active(id) or w.deliveries.active(id) or w.projects.active(id) or id in g.playground.members or g.playground.nearby.has(id) or w.gomoku.active(id) or w.activities.members.has(id) or w.activities.held.get(id,false) or g.questions.has(id) or g.group_questions.has(id)
	var d:RefCounted=g.steward.body_director
	if g.steward.active:
		occupied=occupied or waiting_for_fishing_team(g,id)
		# Rest expires at the actual configured deadline: excess time is counted.
		occupied=occupied or w.forest.clock<d.rest_until or d.question_until>w.forest.clock
		# Arrived members genuinely wait for the rest of this exact formation.
		if not d.batch.is_empty() and d.batch.get("phase","")=="approach":
			occupied=occupied or (d.formation_slots.has(id) and at.distance_to(d.formation_slots[id])<=.5 and g.steward.Pool.IDS.any(func(who):return w._routes.has(who)))
		if d.closing:
			occupied=occupied or waiting_for_regroup(g,id)
	var stuck:bool=not moved if moving else not occupied
	seconds[id]=float(seconds.get(id,0))+delta if stuck else 0.0
	return seconds[id]
