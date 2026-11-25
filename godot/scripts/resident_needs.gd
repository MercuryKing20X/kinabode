extends RefCounted
## Read-only candidates; only a delivered line receives a cooldown.
const DATA="res://content/companions/needs.json"
var content:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(DATA))
var last:Dictionary={}
var waiting:Dictionary={}
var THANKS={"gentle":[preload("res://scripts/localization.gd").source("content.health_20261107.53aaeb5315da"),"Thank you for being with me. I feel warm inside."],"lively":[preload("res://scripts/localization.gd").source("content.health_20261107.536f56209c28"),"Wish granted! Everything is more fun with you!"],"laborious":[preload("res://scripts/localization.gd").source("content.health_20261107.857d0c88b543"),"That feels good. Thank you for remembering."],"quiet":[preload("res://scripts/localization.gd").source("content.health_20261107.a0405aa74efa"),"Mm. I am happy. Thank you."]}
func choose(world:RefCounted,id:String)->Dictionary:
	if world.work.jobs.has(id) or world.farms.active(id):return {}
	var time:float=world.director.time
	if waiting.has(id):
		var wish:Dictionary=waiting[id]
		var satisfied:bool=false
		if wish.kind=="hungry":satisfied=int(world.hunger.states.get(id,{}).get("meals",0))>int(wish.meals)
		elif wish.kind=="fish":satisfied=not world.fishing.held(id).is_empty() and str(world.fishing.held(id).get("id",""))!=str(wish.fish)
		if satisfied:
			var voice:Array=THANKS.get(world.intelligence.tag(id),THANKS.gentle)
			var thanks:String=voice[1 if TranslationServer.get_locale().begins_with("en") else 0]
			if world.personality.allowed_line(id,thanks):return {"kind":"satisfied","text":thanks}
		if time-float(wish.time)>3600:waiting.erase(id)
	var tag:String=world.intelligence.tag(id)
	var phase:String=world.days.phase().id
	var kinds:Array=[]
	if world.hunger.rank(id)>0:kinds.append("hungry")
	if world.weather.current().id=="rain":kinds.append("rain")
	elif phase!="night":kinds.append("sun")
	if phase=="night":kinds.append_array(["stars","sleepy"])
	if time-world.director.moods.last_input>180:kinds.append("bored")
	if world.their_island!=null and world.their_island.get("unlocked")==true:kinds.append("island")
	var favorite:String=""
	if world.hunger.rank(id)>0:
		for food in world.recipes.metadata:
			if world.recipes.metadata[food].get("signature_trait","")==tag:
				favorite=world.recipes.display_name(food);break
		if not favorite.is_empty():kinds.append("favorite")
	if time>180:
		kinds.append("fish")
		if tag=="quiet":kinds.push_front("chess")
		if tag=="gentle" and world.cat.discovered:kinds.push_front("cat")
	# Oldest delivered need first; unserved candidates cannot starve behind chess.
	kinds.sort_custom(func(a,b):
		var at:float=float(last.get(id+":"+a,-INF));var bt:float=float(last.get(id+":"+b,-INF))
		return str(a)<str(b) if at==bt else at<bt)
	for kind in kinds:
		var key:String=id+":"+kind
		if time-float(last.get(key,-180))<180:continue
		var lang:String="en" if TranslationServer.get_locale().begins_with("en") else "zh"
		var lines:Array=content[kind][tag if content[kind].has(tag) else "gentle"][lang]
		var line:String=lines[int(time/180)%lines.size()]
		if kind=="favorite":line=line%favorite
		if not world.personality.allowed_line(id,"☞ "+line):continue
		return {"kind":kind,"text":line}
	return {}
func delivered(id:String,kind:String,time:float,world:RefCounted=null)->void:
	if kind=="satisfied":waiting.erase(id);return
	last[id+":"+kind]=time
	if world!=null and kind in ["hungry","fish"]:
		waiting[id]={"kind":kind,"time":time,"meals":world.hunger.states.get(id,{}).get("meals",0),"fish":world.fishing.held(id).get("id","")}
