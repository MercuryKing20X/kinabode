extends RefCounted
## Read-only day/weather scoring and destinations. ResidentBrain owns execution.
var owner:WeakRef
var next_speech:=0.0
var b:RefCounted:
	get:return owner.get_ref()
var w:RefCounted:
	get:return b.world
func _init(brain:RefCounted)->void:owner=weakref(brain)
func weights()->Dictionary:
	if not w.activities.following.has(b.id) and b.clock>=b.next_visit:return {}
	var rows:Dictionary=b.config.rhythm.weights.get(b.tag(),b.config.rhythm.weights.gentle)
	var result:Dictionary=rows.get(w.days.phase().id,{}).duplicate()
	if w.weather.current().id=='rain':
		for key in rows.rain:result[key]=float(result.get(key,0))+float(rows.rain[key])
	return result
func shelter(action:String)->Vector2:
	var homes:Array=w.objects.values().filter(func(o):return o.get('kind','')=='construction_site' and int(o.get('stage_index',0))>=5 and o.region_id==w.actors[b.id].region_id)
	homes.sort_custom(func(a,c):return (a.get('owner_id','')==b.id and c.get('owner_id','')!=b.id) or (a.get('owner_id','')==c.get('owner_id','') and w.point(a).distance_to(w.point(w.actors[b.id]))<w.point(c).distance_to(w.point(w.actors[b.id]))))
	for home in homes:
		var half:Vector2=w.site_size(home)/2
		var offsets:Array=[Vector2(0,half.y+1),Vector2(half.x+1,0),Vector2(-half.x-1,0),Vector2(half.x+1,half.y+1),Vector2(-half.x-1,half.y+1)]
		var first:int=Array(w.director.brains.keys()).find(b.id)
		for index in offsets.size():
			var offset:Vector2=offsets[(index+maxi(0,first))%offsets.size()]
			var p:Vector2=w.point(home)+offset
			if w.walkable(home.region_id,p) and w.director.available_position(b.id,home.region_id,p) and p.distance_to(w.point(w.actors.human))>=float(b.config.rhythm.min_radius) and p.distance_to(w.point(w.actors.human))<=minf(float(b.config.follow_max) if w.activities.following.has(b.id) else INF,float(b.config.rhythm.night_home_radius if action=='night_rest' else b.config.rhythm.shelter_search)):return p
	var trees:Array=w.objects.values().filter(func(o):return o.get('kind','')=='tree' and o.get('status','')=='mature' and o.region_id==w.actors[b.id].region_id)
	trees.sort_custom(func(a,c):return w.point(a).distance_to(w.point(w.actors[b.id]))<w.point(c).distance_to(w.point(w.actors[b.id])))
	for tree in trees:
		for offset in [Vector2(1.5,1.5),Vector2(-1.5,1.5)]:
			var p:Vector2=w.point(tree)+offset
			if w.walkable(tree.region_id,p) and w.director.available_position(b.id,tree.region_id,p) and p.distance_to(w.point(w.actors.human))>=float(b.config.rhythm.min_radius) and p.distance_to(w.point(w.actors.human))<=minf(float(b.config.follow_max) if w.activities.following.has(b.id) else INF,float(b.config.rhythm.shelter_search)):return p
	return Vector2.INF
func target(action:String)->Vector2:
	if action in ['night_rest','rain_shelter']:return shelter(action)
	if action=='garden_watch':
		for farm in w.farms.farms.values():
			if not w.farms.ready(farm.id):continue
			for plot in w.farms.farm_plots(farm.id):
				var p:Vector2=w.point(plot)+Vector2(0,1.5)
				if p.distance_to(w.point(w.actors.human))>=float(b.config.rhythm.min_radius) and p.distance_to(w.point(w.actors.human))<=float(b.config.rhythm.near_radius) and w.walkable('home',p):return p
		return Vector2.INF
	if action=='evening_chat':
		for life in w.barbecues.values():
			if not w.standard.ready(life.station.id) or life.station.region_id!=w.actors[b.id].region_id:continue
			var index:int=Array(w.director.brains.keys()).find(b.id)
			var p:Vector2=w.point(life.station)+Vector2.from_angle(float(index)*TAU/4)*4
			if p.distance_to(w.point(w.actors.human))>=float(b.config.rhythm.min_radius) and p.distance_to(w.point(w.actors.human))<=float(b.config.rhythm.near_radius) and w.walkable(life.station.region_id,p):return p
		return b.destination('follow')
	return Vector2.INF
func available(action:String)->bool:
	if w.actors[b.id].region_id!=w.actors.human.region_id:return false
	match action:
		'morning_hello','weather_watch':return w.days.phase().id=='morning'
		'garden_watch':return target(action).is_finite()
		'evening_chat':return w.days.phase().id=='dusk'
		'night_rest':return w.days.phase().id=='night' and target(action).is_finite()
		'fireflies':return w.days.phase().id=='night' and w.weather.current().id not in ['rain','fog']
		'rain_shelter':return w.weather.current().id=='rain' and target(action).is_finite()
	return false

func speak(action:String)->void:
	var voices:Dictionary=b.config.voices.get(b.tag(),{}).get('rhythm_lines',{})
	if not voices.has(action) or b.clock<next_speech:return
	var words:Array=voices[action];var key:String='rhythm:'+action+':'+str(w.days.day())
	var reason:String='rhythm_rain' if action=='rain_shelter' else 'rhythm_'+str(w.days.phase().id)
	if b.interactions.deliver_authored({'zh':words[0],'en':words[1],'key':key},key,key,'human','routine_line',[b.text(reason,'zh'),b.text(reason,'en')]):next_speech=b.clock+float(b.config.rhythm.phase_speech_seconds)
