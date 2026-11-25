extends RefCounted
## Composes existing World and gameplay actions. Coordinates always come from the host.
const Text=preload("res://scripts/localization.gd")
const Persona=preload("res://scripts/persona_cards.gd")
const NAMES={
	"visit":["去看看","Explore a place"],"beach_walk":["沿海散步","Walk by the sea"],
	"watch_sea":["看海","Watch the sea"],"visit_flowers":["去鲜花岛","Visit Flower Isle"],
	"talk_player":["来找你聊天","Come find you for a chat"],"ask_player":["问你个问题","Ask your opinion"],
	"invite_meal":["邀你吃饭","Ask you to share a meal"],"arrange_flowers":["摆玫瑰","Arrange roses"],
	"gift_flower":["送你一朵玫瑰","Bring you a rose"],"give_item":["给伙伴送礼","Give a companion a gift"],
	"write_diary":["写日记","Write in her diary"],"write_letter":["写封信给你","Write you a letter"],
	"invite_fishing":["提议一起钓鱼","Suggest fishing together"],"suggest_day":["提议今天的活动","Suggest something for today"]
}
const PLACES={"sea":["海边","the shore"],"flower_isle":["鲜花岛","Flower Isle"],"campfire":["营火边","the campfire"],"doorstep":["你家门前","your doorstep"],"plaza":["广场","the plaza"],"star_view":["观星处","the stargazing spot"],"player":["你身边","beside you"],"roses":["我摆花的地方","the flowers I arranged"]}
const NOTES={
	"invalid_place":["那个地方现在去不了。","I couldn't go to that spot just then."],
	"invalid_companion":["那位伙伴不方便同行。","My companion couldn't come along."],
	"invalid_player_role":["那一段不能替你做决定。","That part was for you to decide."],
	"unavailable_item":["手上或仓库里没有能带的东西。","There wasn't anything available to bring."],
	"invalid_flower_design":["这个花样暂时摆不了。","That flower design wouldn't fit."],
	"outside_offered_list":["这件事现在还做不了，得换个主意。","That idea wasn't available just then."],
	"prerequisite_changed":["出发时条件变了，我得换个主意。","Things changed just as I was about to set out."],
	"social_refused":["伙伴没空，我自己去看看也好。","My companion was busy. I can go on my own."],
	"partner_left":["同行的伙伴没能到。","My companion couldn't make it."],
	"cat_busy":["柚柚不在附近，或正忙着呢。","The cat wasn't nearby or was busy."],
	"unreachable":["没找着能走到那里的路。","I couldn't find a way there."],
	"insufficient_materials":["仓库里的真材料不够。","There wasn't enough in the warehouse."],
	"outcome_missing":["这件事没有做到最后。","I didn't get to finish it."],
	"very_hungry":["太饿了，得先回到你身边。","I got too hungry and needed to come back to you."],
	"interaction_unavailable":["你现在不方便接话。","It wasn't a good moment to ask you."],
	"reply_invalid":["上次没能想出一条岛上能执行的打算。","I didn't manage to make a usable plan last time."],
	"repeat_limit":["这件事刚做过两次了，换个主意吧。","I've already had two goes at that lately. Time for something else."]
}
var brain:WeakRef
var b:RefCounted:
	get:return brain.get_ref()
var w:RefCounted:
	get:return b.world
var host:Callable
var meetings:RefCounted
func _init(owner:RefCounted)->void:brain=weakref(owner)
static func phrase(pair:Array)->String:return pair[1 if TranslationServer.get_locale().begins_with("en") else 0]
static func note(code:String)->String:return phrase(NOTES.get(code,NOTES.outcome_missing))

func anchor(place:String)->Vector2:
	var a:Dictionary=w.actors[b.id]
	if place=="player":
		return w.nearest_walkable(a.region_id,w.point(w.actors.human)+Vector2(0,1.5)) if a.region_id==w.actors.human.region_id else Vector2.INF
	if place=="sea":
		var spots:Array=w.fishing.nearby_shores(b.id,1)
		return w.point(spots[0]) if not spots.is_empty() else Vector2.INF
	if a.region_id!="home":return Vector2.INF
	match place:
		"flower_isle":
			if not w.resort.enabled():return Vector2.INF
			return w.nearest_walkable("home",Vector2(43,208))
		"plaza","star_view":
			var p:Array=w.map_anchor("plaza.center")
			return w.nearest_walkable("home",Vector2(p[0],p[1])+Vector2(0,6 if place=="star_view" else 0)) if p.size()==2 else Vector2.INF
		"campfire":
			if w.standard.active() and not w.leisure.sites.has("play.standard.camp"):return Vector2.INF
			return w.nearest_walkable("home",w.point(w.life.station)+Vector2(0,3))
		"doorstep":
			for obj in w.objects.values():
				if obj.kind=="construction_site" and obj.region_id=="home" and obj.get("owner_id","")=="human":
					return w.nearest_walkable("home",w.point(obj)+Vector2(0,w.site_size(obj).y/2+2))
	return Vector2.INF

func describe()->Dictionary:
	var places:Dictionary={}
	for place in PLACES:
		var p:Vector2=anchor(place)
		if p.is_finite() and (place!="star_view" or (w.days.phase().id=="night" and w.weather.current().id not in ["rain","fog"])):
			places[place]=phrase(PLACES[place])
	var peers:Array=[]
	for id in w.director.brains:
		if id!=b.id and w.actors[id].region_id==w.actors[b.id].region_id:peers.append(id)
	var roses:Dictionary={}
	for color in w.flower_creation.config.colors:
		var n:int=w.storage.count(w.flower_creation.item(color))
		if n>0:roses[color]=n
	var can_gift:bool=not roses.is_empty() and int(w.flower_creation.gifts.get(b.id,{}).get("day",0))!=w.days.day()
	var carry:Dictionary={}
	if not peers.is_empty():
		for item in w.actors[b.id].get("carry",{}):
			if w.actors[b.id].carry[item]>0:carry[item]=w.actors[b.id].carry[item]
	return {"places":places,"companions":peers,"roses":roses,"carry":carry,"can_gift":can_gift}

func peer_ready(id:String)->bool:
	return id!=b.id and w.director.brains.has(id) and w.actors[id].region_id==w.actors[b.id].region_id and w.director.brains[id].eligible() and not w.director.brains[id].busy() and w.hunger.rank(id)<3 and w.point(w.actors[id]).distance_to(w.point(w.actors[b.id]))<=12

func options(context:Dictionary)->Dictionary:
	var result:Dictionary={}
	if w.hunger.rank(b.id)>=3:return result
	var places:Dictionary=context.places
	for key in NAMES:
		var choices:Array=[]
		var roles:Array=[]
		var why:=""
		match key:
			"visit":choices=places.keys().filter(func(p):return p!="player")
			"beach_walk","watch_sea":choices=["sea"] if places.has("sea") else []
			"visit_flowers":choices=["flower_isle"] if places.has("flower_isle") else []
			"talk_player","ask_player","invite_meal":
				choices=["player"] if places.has("player") and host.is_valid() else []
				if key=="invite_meal" and not choices.is_empty() and not meal_camp().is_empty():choices.push_front("campfire")
			"arrange_flowers":
				choices=["here"]+places.keys().filter(func(p):return p in ["doorstep","flower_isle","plaza"])
				if context.roses.is_empty():why="insufficient_materials"
			"gift_flower":
				choices=["player"] if places.has("player") else []
				if not context.can_gift:why="insufficient_materials" if context.roses.is_empty() else "daily_limit"
			"give_item":
				choices=["here"] if not context.carry.is_empty() else []
			"write_diary","write_letter":
				choices=["here"] if host.is_valid() and host.call("writing_ready",{"activity":key}) else []
			"invite_fishing":
				choices=["here"] if places.has("sea") and not context.companions.is_empty() and w.director.model_controlled(b.id) else []
			"suggest_day":
				choices=["here"] if w.director.model_controlled(b.id) and not w.proposals.cards.has(b.id) and not w.recipes.recipes.is_empty() else []
		if key in ["visit","watch_sea","beach_walk","visit_flowers","arrange_flowers"]:roles=["show","invite","ask"]
		if key=="gift_flower":roles=["gift"]
		if key=="ask_player":roles=["ask"]
		if key=="invite_meal":roles=["invite"]
		if not choices.is_empty():
			var entry:Dictionary={"activity":key,"name":phrase(NAMES[key]),"ready":why.is_empty(),"places":choices,"for_player":roles}
			if not why.is_empty():entry["prerequisite"]=why
			if key in ["visit","watch_sea","beach_walk","visit_flowers","invite_fishing","give_item"]:entry["with"]=context.companions
			result[key]=entry
	return result

func sanitize(value:Dictionary,entry:Dictionary,context:Dictionary,dropped:Dictionary)->Dictionary:
	var plan:Dictionary=value.duplicate(true)
	for field in ["place","with","for_player","bring"]:
		if not plan.has(field) or plan[field]=="":plan.erase(field);continue
		var allowed:Array=entry.get({"place":"places"}.get(field,field),[])
		if field=="bring":
			allowed=context.carry.keys() if value.activity=="give_item" else context.roses.keys() if value.activity in ["gift_flower","arrange_flowers"] else []
		if not plan[field] is String or not plan[field] in allowed:
			dropped[field]={"place":"invalid_place","with":"invalid_companion","for_player":"invalid_player_role","bring":"unavailable_item"}[field];plan.erase(field)
	if plan.has("target"):dropped["target"]="invalid_place";plan.erase("target")
	if plan.has("player_card"):
		var card:Variant=plan.player_card
		var valid:bool=card is Dictionary and safe_card_text(card.get("question"),85) and card.get("options") is Array and card.options.size() in [2,3]
		if valid:
			var ids:Array=[]
			for option in card.options:
				if not option is Dictionary or option.get("id") not in ["yes","later","solo"] or option.id in ids or not safe_card_text(option.get("text"),26):
					valid=false;break
				ids.append(option.id)
			valid=valid and "yes" in ids and "later" in ids
		if not valid:plan.erase("player_card")
	for field in ["pattern","flower_text"]:
		if not plan.has(field):continue
		var args:Dictionary={"pattern":plan[field]} if field=="pattern" else {"text":plan[field]}
		if not plan[field] is String or plan[field].length()>16 or plan.activity!="arrange_flowers" or w.flower_creation.pixels(args).is_empty():
			dropped[field]="invalid_flower_design";plan.erase(field)
	return plan
func safe_card_text(value:Variant,n:int)->bool:
	return value is String and value.length()<=n and not value.strip_edges().is_empty() and not "\n" in value and Persona.safe_speech(value)

func start(plan:Dictionary)->Dictionary:
	var key:String=plan.activity
	var region:String=w.actors[b.id].region_id
	var entry:Dictionary=options(describe()).get(key,{})
	if entry.is_empty() or not entry.ready:return {"ok":false,"error":entry.get("prerequisite","prerequisite_changed")}
	var place:String=plan.get("place",entry.places[0])
	if place not in entry.places:place=entry.places[0];b.intention.feedback(key,"invalid_place","place")
	var p:Vector2=anchor(place) if place!="here" else w.point(w.actors[b.id])
	var job:Dictionary={"ok":true,"region":region,"place":place,"position":p,"since":b.clock,"key":key,"phase":"walk","route":null}
	if key=="invite_meal":
		var camp:Dictionary=meal_camp()
		if not camp.is_empty():job.place="campfire";job.position=w.point(camp.station);job["meal_station"]=camp.station.id
	if key in ["arrange_flowers","gift_flower"]:
		var ctx:Dictionary=describe()
		var color:String=plan.get("bring","white" if ctx.roses.has("white") else ctx.roses.keys()[0])
		var args:Dictionary={"intent":key,"color":color}
		if key=="arrange_flowers":
			if plan.has("flower_text"):args["text"]=plan.flower_text
			else:args["pattern"]=plan.get("pattern","single")
			if int(ctx.roses.get(color,0))<w.flower_creation.pixels(args).size():
				b.intention.feedback(key,"insufficient_materials","pattern");args.erase("text");args.pattern="single"
			if place!="here":
				var offsets:Array=w.flower_creation.pixels(args)
				var found:=false
				for radius in [2,4,6,8]:
					for offset in [Vector2(radius,0),Vector2(-radius,0),Vector2(0,radius),Vector2(0,-radius)]:
						var here:Vector2=(p+offset).round()
						if offsets.all(func(cell):return w.flower_creation.space(region,here+cell)):
							args["position"]=[here.x,here.y];found=true;break
					if found:break
				if not found:b.intention.feedback(key,"invalid_place","place")
		var result:Dictionary=w.flower_creation.execute(b.id,args)
		if not result.ok:return result
		job.phase="flowers";job["flowers"]=w.flower_creation.jobs[b.id]
		if plan.has("with"):b.intention.feedback(key,"social_refused","with")
		return job
	if key in ["write_diary","write_letter","invite_fishing","suggest_day","give_item"]:
		job.phase="action"
		return job
	if not p.is_finite():return {"ok":false,"error":"unreachable"}
	job["id"]=plan.host_id
	if plan.has("for_player") and host.is_valid():
		if b.distance()<=20:
			job.phase="player_approach"
			if b.distance()>3 and not move(job,anchor("player")):return {"ok":false,"error":"unreachable"}
			return job
		w.director.say_local(b.id,phrase(["我先过去啦！","I'll go on ahead!"]),"heart_call",12,8)
		b.trace({"actor":b.id,"event":"heart_player_too_far","at":b.clock,"invitation_id":job.id})
		if key in ["ask_player","invite_meal"]:return {"ok":false,"error":"interaction_unavailable"}
	if not begin_destination(job,plan):return {"ok":false,"error":"unreachable"}
	return job
func start_social(plan:Dictionary)->Dictionary:
	var who:String=plan.get("with","")
	var region:String=w.actors[b.id].region_id
	if meetings==null or not w.director.brains.has(who) or w.actors[who].region_id!=region:return {"ok":false,"error":"invalid_companion"}
	var place:String="sea" if plan.activity=="pair_sea" else "here"
	var p:Vector2=anchor("sea") if place=="sea" else w.nearest_walkable(region,w.point(w.actors[b.id])+Vector2(-1.8,0))
	if not p.is_finite():return {"ok":false,"error":"unreachable"}
	var job:Dictionary={"ok":true,"region":region,"place":place,"position":p,"since":b.clock,"key":plan.activity,"phase":"walk","route":null,"id":plan.host_id}
	return job if begin_destination(job,plan) else {"ok":false,"error":"unreachable"}
func move(job:Dictionary,p:Vector2)->bool:
	if not b.intention.basic.travel(p):return false
	job.route=b.route;return true
func begin_destination(job:Dictionary,plan:Dictionary)->bool:
	if plan.has("with") and not job.get("human_joining",false) and meetings!=null and meetings.send(b.id,job,plan):
		job.phase="peer_wait";job["peer_id"]=plan.host_id;return true
	if plan.has("with"):b.intention.feedback(job.key,"social_refused","with")
	job.phase="walk"
	return move(job,job.position)

func advance(job:Dictionary,plan:Dictionary)->void:
	if b.clock-float(job.since)>180:
		w.director.say_local(b.id,phrase(["今天就先走到这里吧。","I think this is far enough for today."]),"heart_social",12,8)
		b.finish("timeout","route_stalled");return
	match job.phase:
		"peer_wait":
			var state:String=meetings.outcome(job.peer_id)
			if state=="waiting":return
			if state=="accepted":
				var seat:Vector2=w.nearest_walkable(job.region,job.position+Vector2(1.8,0))
				var depart:String=meetings.depart(job.peer_id,seat)
				if depart=="waiting":return
				job["joining"]=depart=="walking"
			job.phase="walk"
			if not move(job,job.position):b.finish("failed","unreachable")
		"player_approach":
			if not owned(job):b.finish("interrupted","route_replaced");return
			if w._routes.has(b.id):return
			if b.distance()>4:
				if b.distance()<=20 and not job.get("retried_player",false):
					job["retried_player"]=true
					if move(job,anchor("player")):return
				b.finish("failed","interaction_unavailable");return
			if not host.call("interaction",plan.merged({"arrival":job.place})):
				if b.clock-float(job.since)<35:return
				b.finish("failed","interaction_unavailable");return
			job.phase="player_wait"
		"player_wait":
			var reply:String=host.call("response",plan)
			if reply.is_empty():return
			if reply=="revoked":b.finish("interrupted","player_invitation_revoked");return
			if reply=="later":b.finish("completed","player_declined");return
			if job.key=="invite_meal" and reply=="yes" and job.has("meal_seats"):
				job["human_joining"]=true;job.phase="walk"
				if not move(job,job.position):b.finish("failed","unreachable")
				return
			if job.key in ["ask_player","invite_meal"]:
				b.finish("completed","player_"+reply);return
			job["human_joining"]=reply=="yes" and job.place not in ["player","here"] and plan.get("for_player") in ["invite","show"]
			if not begin_destination(job,plan):b.finish("failed","unreachable")
		"flowers":
			if is_same(w.flower_creation.jobs.get(b.id),job.flowers):return
			var committed:bool=job.flowers.get("committed",false)
			if committed and plan.get("for_player","") in ["show","invite","ask"] and host.is_valid():
				var pattern:String=job.flowers.get("pattern_id","")
				var actual:Array=w.flower_creation.flowers.values().filter(func(f):return f.actor_id==b.id and f.pattern_id==pattern and f.region_id==job.region)
				if not actual.is_empty() and b.distance()<=20:
					job.position=w.point(actual[0]);job.place="roses";job["id"]=plan.host_id
					job.phase="player_approach";job.since=b.clock
					if b.distance()<=3 or move(job,anchor("player")):return
				b.intention.feedback(job.key,"interaction_unavailable","for_player")
			b.finish("completed" if committed else "failed","" if committed else "outcome_missing")
		"action":
			var result:Dictionary=perform(plan)
			b.finish("completed" if result.ok else "failed",str(result.get("error","")))
		"walk":
			if not owned(job):
				b.finish("interrupted","route_replaced");return
			if w._routes.has(b.id):return
			if w.point(w.actors[b.id]).distance_to(job.position)>1:
				b.finish("failed","unreachable");return
			if job.key=="beach_walk" and not job.get("walked_shore",false) and not job.get("joining",false) and not job.get("human_joining",false):
				job["walked_shore"]=true
				for spot in w.fishing.nearby_shores(b.id,24):
					var next:Vector2=w.point(spot)
					var distance:float=next.distance_to(job.position)
					if distance<3 or distance>16 or not w.segment_clear(job.region,job.position,next):continue
					if not w.route_to(b.id,next):continue
					job.position=next;job.route=w._routes.get(b.id);b.route=job.route
					return
			job.phase="arrived";job.arrived=b.clock;b.current.arrived=b.clock;b.pose()
		"arrived":
			if job.get("joining",false) and not meetings.arrived(job.peer_id,job.position):
				if b.clock-float(job.arrived)<30:return
				b.intention.feedback(job.key,"partner_left","with");job.joining=false
			elif job.get("joining",false) and not job.get("together",false):
				job["together"]=true;job.arrived=b.clock
			if job.get("human_joining",false):
				if job.has("meal_seats") and not job.get("player_arrived",false) and w._routes.has("human"):
					if b.clock-float(job.arrived)<30:return
					b.finish("interrupted","player_did_not_arrive");return
				if w.actors.human.region_id!=job.region or w.point(w.actors.human).distance_to(job.position)>4:
					if b.clock-float(job.arrived)<30:return
					b.finish("interrupted","player_did_not_arrive");return
				if not job.get("player_arrived",false):
					if job.has("meal_seats") and not seat_meal(job):b.finish("interrupted","seat_unavailable");return
					job["player_arrived"]=true
					b.trace({"actor":b.id,"event":"heart_player_together","at":b.clock,"invitation_id":job.id,"place":job.place})
			if b.clock-float(job.arrived)<float(b.current.duration):return
			if job.key=="talk_player":
				var interaction:Dictionary=plan.merged({"arrival":job.place})
				if not host.is_valid() or not host.call("interaction",interaction):
					b.intention.feedback(job.key,"interaction_unavailable","for_player")
					if job.key in ["talk_player","ask_player","invite_meal"]:b.finish("failed","interaction_unavailable");return
			if not job.get("together",false) and not job.get("player_arrived",false) and job.key in ["beach_walk","watch_sea","visit","visit_flowers"]:
				w.director.say_local(b.id,phrase(["今天就看到这儿吧。","I'll leave a little more to see next time."]),"heart_social",12,8)
			b.finish("completed")
func owned(job:Dictionary)->bool:
	return w.actors[b.id].region_id==job.region and (not w._routes.has(b.id) or is_same(w._routes[b.id],job.route))

func perform(plan:Dictionary)->Dictionary:
	match plan.activity:
		"write_diary","write_letter":
			return {"ok":true} if host.is_valid() and host.call("write",plan) else {"ok":false,"error":"outcome_missing"}
		"invite_fishing","suggest_day":
			var fish:bool=plan.activity=="invite_fishing"
			var targets:Array=w.fishing.nearby_shores(b.id,1).map(func(spot):return spot.water_id) if fish else w.recipes.recipes.keys()
			if targets.is_empty():return {"ok":false,"error":"prerequisite_changed"}
			var peer:String=plan.get("with","")
			if not peer.is_empty() and not peer_ready(peer):
				b.intention.feedback(plan.activity,"invalid_companion","with");peer=""
			var text:String=phrase(["要不要一起去钓鱼？","Would you come fishing with us?"] if fish else ["今天要不要一起吃顿饭？","Could we share a meal today?"])
			if not peer.is_empty():text=(Text.resident(w,peer)+phrase(["也可以一起来钓鱼。"," could come fishing with us, too."])).left(40)
			var line:String=plan.get("say",text).left(40)
			return w.proposals.create(b.id,{"text":line if not line.is_empty() and Persona.safe_speech(line) else text,"activity":"fish_together" if fish else "cook_together","target_id":targets[0]},peer)
		"give_item":
			var who:String=plan.get("with","")
			if not peer_ready(who):return {"ok":false,"error":"invalid_companion"}
			var items:Dictionary=describe().carry
			if items.is_empty():return {"ok":false,"error":"unavailable_item"}
			return w.work.give(b.id,{"receiver_id":who,"item_id":plan.get("bring",items.keys()[0]),"quantity":1})
	return {"ok":false,"error":"prerequisite_changed"}

func cancel(job:Dictionary,outcome:String="",reason:String="")->void:
	for id in job.get("meal_seats",{}):
		var seat:Dictionary=job.meal_seats[id]
		if w.work.claims.get(seat.id)==id:w.work.claims.erase(seat.id)
		if w.actors[id].activity=="fire_sit" and not w.work.jobs.has(id) and w.point(w.actors[id]).distance_to(w.point(seat))<.5:w.actors[id].activity="idle"
	if job.get("phase")=="flowers" and is_same(w.flower_creation.jobs.get(b.id),job.flowers):w.flower_creation.cancel(b.id)
	if meetings!=null and job.has("peer_id"):meetings.close(job.peer_id,outcome if reason.is_empty() else reason)
	if host.is_valid() and job.has("id"):host.call("cancel",{"host_id":job.id})

func meal_camp()->Dictionary:
	var camp:RefCounted=w.nearest_barbecue(b.id)
	if camp==null or not w.standard.ready(camp.station.id) or not camp.fireside.jobs.is_empty():return {}
	return {"station":camp.station}

func meal_choice(job:Dictionary)->Vector2:
	var camp:RefCounted=w.barbecues.get(job.get("meal_station"))
	if camp==null or not w.standard.ready(camp.station.id) or not camp.fireside.jobs.is_empty():return Vector2.INF
	var chosen:Dictionary={}
	for id in [b.id,"human"]:
		for seat in camp.seats():
			if w.work.claims.has(seat.id) or chosen.values().any(func(row):return row.id==seat.id) or w.actors[id].region_id!=seat.region_id:continue
			if w.find_route(id,w.point(seat)).is_empty():continue
			if id=="human" and w.point(seat).distance_to(w.point(chosen[b.id]))>4:continue
			chosen[id]=seat;break
		if not chosen.has(id):return Vector2.INF
	for id in chosen:w.work.claims[chosen[id].id]=id
	job["meal_seats"]=chosen;job.position=w.point(chosen[b.id])
	return w.point(chosen.human)

func seat_meal(job:Dictionary)->bool:
	var camp:RefCounted=w.barbecues.get(job.meal_station)
	if camp==null or not camp.fireside.jobs.is_empty():return false
	for id in job.meal_seats:
		var seat:Dictionary=job.meal_seats[id]
		if w._routes.has(id) or w.work.jobs.has(id) or w.activities.held.get(id,false) or w.work.claims.get(seat.id)!=id or w.actors[id].region_id!=seat.region_id or w.point(w.actors[id]).distance_to(w.point(seat))>.5:return false
	for id in job.meal_seats:
		w.actors[id].activity="fire_sit"
		w.actors[id].facing=w.walking_direction(w.point(camp.station)-w.point(w.actors[id]))
	job.arrived=b.clock
	return true
