extends RefCounted
## Normalized visual timeline fits the existing Fireside eating duration exactly.
static var content:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/eating-styles.json"))
static func style(world:RefCounted,id:String,rank:int)->Dictionary:
	var tag:String=str(world.intelligence.preset(id).get("main_trait",world.intelligence.tag(id))) if id!="human" else ""
	var key:String=str(world.intelligence.catalog.traits.get(tag,{}).get("eating_style",content.default))
	var result:Dictionary=content.styles.get(key,content.styles[content.default]).duplicate(true)
	if id!="human" and rank>=2:result.blow=false;result.chew_at=minf(float(result.chew_at),.20);result.cycles=maxi(4,int(result.cycles))
	if rank>=3:result.blow=false;result.chew_at=minf(float(result.chew_at),.18);result.cycles=maxi(4,int(result.cycles));result.puff=true
	return result
static func first_chew(world:RefCounted,id:String,rank:int)->float:return float(style(world,id,rank).chew_at)
static func timeline(world:RefCounted,id:String,job:Dictionary)->Dictionary:
	var fire_life:RefCounted=world.barbecues.get(job.get("target_id",""))
	if fire_life==null or not fire_life.fireside.jobs.has(id):return {}
	var fire:RefCounted=fire_life.fireside
	if job.get("phase")=="fire_sit":
		var satisfied_seconds:float=float(fire.dialogue.taste_config.favorite_satisfied_seconds) if fire.dialogue.reactions.has(id) and fire.dialogue.reactions[id].get("kind")=="happy" else 1.0
		return {"column":6 if world.director.time-float(job.get("meal_finished_at",-10))<satisfied_seconds else 7+int(world.director.time*1.5)%3,"progress":1.0,"food":{}}
	if job.get("phase")!="fire_eat" or fire.state.current.is_empty():return {}
	var t:float=clampf(float(job.time)/float(fire.config.eat_seconds),0,1)
	var s:=style(world,id,int(job.get("meal_rank",world.hunger.rank(id))))
	var chew:float=s.chew_at;var column:=0
	if t>=chew:
		var cycle:float=fposmod((t-chew)/(1-chew)*float(s.cycles),1)
		column=(5 if s.puff else 4) if cycle<.60 else 2+int(cycle*5)%2
	elif t>=chew*.65:column=2
	elif t>=.10 and s.blow:column=1
	return {"column":column,"progress":t,"food":fire.state.current}
