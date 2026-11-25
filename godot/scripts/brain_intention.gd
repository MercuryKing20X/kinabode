extends RefCounted
## Host validated decisions. No network, route or material authority here.
var brain:WeakRef
var b:RefCounted:
 get:return brain.get_ref()
var pending:Dictionary={}
var offered:Dictionary={}
var recent:Array=[]
var activity_log:Array=[]
var last_request:=-100000.0
var revision:=0
var seen_revision:=-1
var hunger:=-1
var invite_seen:=""
var settled:Callable
var observing:=false
var serial:=0
var outings:RefCounted
var basic:RefCounted
var context:Dictionary={}
var feedback_rows:Array=[]
var near:=false
var mood_reason:=""
var wish_provider:Callable
var wish_accept:Callable
var wish_receipt:Callable
func _init(owner:RefCounted)->void:
 brain=weakref(owner);outings=preload("res://scripts/brain_outing.gd").new(owner);basic=preload("res://scripts/basic_plan.gd").new(owner)
func changed()->void:revision+=1
func window()->Array:
 activity_log=activity_log.filter(func(row):return b.clock-float(row.at)<900.0 or int(row.day)==b.world.days.day())
 return activity_log.filter(func(row):return b.clock-float(row.at)<900.0)
func repeated(action:String)->bool:
 return window().filter(func(row):return row.activity==action).size()>=2
func due()->bool:
 var rank:int=b.world.hunger.rank(b.id)
 var invitation:String=JSON.stringify(b.invitation)
 var nearby:bool=b.distance()<=(8 if not near else 12)
 var feeling:String=b.world.hearts.summary(b.id).reason
 if rank!=hunger or invitation!=invite_seen or nearby!=near or feeling!=mood_reason:changed();hunger=rank;invite_seen=invitation;near=nearby;mood_reason=feeling
 var calm:float=float(b.config.ai_intention.rethink_seconds)+float(posmod(b.id.hash()+serial,31))
 return pending.is_empty() and not b.current.has("basic_plan") and rank<3 and (seen_revision!=revision or b.clock-last_request>=calm)
func card()->Dictionary:
 # Candidate construction consumes no decision entropy when observing.
 var state:int=b.rng.state
 var schedules:Array=b.schedule_options.duplicate(true)
 var due_at:float=b.schedule_due
 observing=true
 var options:Array=b.candidates()
 observing=false
 b.rng.state=state;b.schedule_options=schedules;b.schedule_due=due_at
 offered.clear()
 for option in options:
  if b.config.actions.has(option.action):offered[option.action]=option.duplicate(true)
 var available:Array=[]
 context=outings.describe()
 var combos:Dictionary=outings.options(context)
 for key in combos:
  var entry:Dictionary=combos[key]
  if repeated(key):offered.erase(key);continue
  if entry.ready:offered[key]={"action":key,"outing":true,"partner":""}
  available.append(entry)
 for action in b.config.actions:
  if repeated(action):offered.erase(action);continue
  if not offered.has(action):continue
  var entry:Dictionary={"activity":action,"name":b.action_name(action),"ready":true}
  if not str(offered[action].get("partner","")).is_empty():entry["with"]=[offered[action].partner]
  available.append(entry)
 context["combos"]=combos
 var wishes:Dictionary=wish_provider.call() if wish_provider.is_valid() else {}
 var counts:Dictionary={}
 for row in activity_log:
  if int(row.day)==b.world.days.day():counts[row.activity]=int(counts.get(row.activity,0))+1
 return {"available":available,"mood":b.world.hearts.mood(b.id),"hunger":b.world.hunger.summary(b.id).get("state",""),"time":b.world.days.phase().id,"weather":b.world.weather.current().id,"place":b.world.actors[b.id].region_id,"places":context.places,"roses":context.roses,"own_items":context.carry,"wish":wishes,"recent_15m":window().map(func(row):return [row.activity,row.outcome,int(b.clock-float(row.at))]),"today_counts":counts,"feedback":feedback_rows.slice(-3),"situation":situation()}
func requested()->void:last_request=b.clock;seen_revision=revision
func feedback(activity:String,reason:String,field:String="")->void:
 var row:Dictionary={"activity":activity.left(40),"field":field,"reason":reason,"message":b.action_name(activity)+"："+outings.note(reason)}
 feedback_rows.append(row);feedback_rows=feedback_rows.slice(-5)
 b.trace({"actor":b.id,"at":b.clock,"event":"ai_intention_feedback","detail":row})
func reject(reason:String)->bool:
 feedback("",reason);changed()
 b.trace({"actor":b.id,"at":b.clock,"event":"ai_intention_rejected","reason":reason});return false
func accept(value:Variant,local_daily:bool=false)->bool:
 if not value is Dictionary:return reject("bad_json")
 if value.has("steps"):return basic.accept(value,"local" if local_daily else "model")
 if not local_daily and value.get("activity") is String and repeated(value.activity):
  feedback(value.activity,"repeat_limit");changed()
  b.trace({"actor":b.id,"at":b.clock,"event":"ai_intention_rejected","activity":value.activity,"reason":"repeat_limit"})
  return false
 if not value.get("activity") is String or not offered.has(value.activity):return reject("outside_offered_list")
 var minutes:Variant=value.get("minutes",1.0)
 if not (minutes is float or minutes is int) or not is_finite(minutes) or minutes<1 or minutes>10:return reject("invalid_minutes")
 if not value.get("reason") is String or value.reason.strip_edges().is_empty() or value.reason.length()>240:return reject("missing_reason")
 var choice:Dictionary=offered[value.activity].duplicate(true)
 var dropped:Dictionary={}
 var entry:Dictionary=context.get("combos",{}).get(value.activity,{"places":[b.world.actors[b.id].region_id],"with":[choice.partner] if not str(choice.partner).is_empty() else []})
 var plan:Dictionary=outings.sanitize(value,entry,context,dropped)
 for key in plan.keys():
  if key not in ["activity","minutes","reason","say","place","with","for_player","bring","pattern","flower_text","mood","player_card"]:plan.erase(key)
 if not plan.has("for_player"):plan.erase("player_card")
 if local_daily:plan["local_wish"]=true
 if plan.activity in ["ask_player","invite_meal"] and not plan.has("for_player"):plan["for_player"]="ask" if plan.activity=="ask_player" else "invite"
 if not dropped.is_empty():plan.erase("say")
 plan["minutes"]=minutes
 if plan.has("say") and (not plan.say is String or plan.say.length()>120 or not preload("res://scripts/persona_cards.gd").safe_speech(plan.say)):
  dropped["say"]="reply_invalid";plan.erase("say")
 if value.has("mood"):
  if not value.mood is Dictionary:return reject("invalid_mood")
  for axis in value.mood:
   var n:Variant=value.mood[axis]
   if axis not in b.world.hearts.mood(b.id) or not (n is int or n is float) or not is_finite(n):return reject("invalid_mood")
 if not pending.is_empty():settle(pending.plan,"interrupted","superseded_before_start")
 requested()
 serial+=1
 pending={"choice":choice,"plan":plan,"at":b.clock,"generation":b.generation}
 pending.plan["world_id"]=b.world.world_id;pending.plan["day"]=b.world.days.day()
 pending.plan["host_id"]=b.id+":"+Crypto.new().generate_random_bytes(16).hex_encode()
 if not local_daily:activity_log.append({"id":pending.plan.host_id,"activity":plan.activity,"at":b.clock,"day":pending.plan.day,"outcome":"accepted"})
 offered.clear()
 b.next_decision=b.clock
 for field in dropped:feedback(plan.activity,dropped[field],field)
 b.trace({"actor":b.id,"at":b.clock,"event":"daily_wish_accepted" if local_daily else "ai_intention_accepted","plan":plan.duplicate(true),"discarded":dropped})
 return true
func advance()->void:
 if pending.is_empty():return
 if b.clock-float(pending.at)>float(b.config.ai_intention.timeout_seconds) or (b.world.hunger.rank(b.id)>=3 and pending.plan.activity!="food"):
  settle(pending.plan,"failed","very_hungry" if b.world.hunger.rank(b.id)>=3 else "pending_expired");pending.clear()
func candidate(options:Array)->Dictionary:
 if observing or pending.is_empty():return {}
 if b.generation!=pending.generation or b.clock-float(pending.at)>600:
  settle(pending.plan,"timeout","pending_expired");pending.clear();return {}
 var choices:Array=[pending.choice] if pending.choice.get("outing",false) else options
 for option in choices:
  if option.action==pending.plan.activity:
   var result:Dictionary=option.duplicate(true)
   result.merge({"score":float(b.config.ai_intention.score),"ai_plan":pending.plan.duplicate(true),"reasons":["ai_intention"]},true)
   return result
 settle(pending.plan,"failed","prerequisite_changed");pending.clear();reject("prerequisite_changed");changed();return {}
func started()->void:
 var plan:Dictionary=b.current.get("ai_plan",{})
 if plan.is_empty():return
 pending.clear();b.current.duration=minf(float(plan.minutes)*60,float(b.config.actions.get(plan.activity,{}).get("duration",60))) if not plan.get("local_wish",false) else float(plan.minutes)*60
 if b.current.get("outing",false):b.current.duration=35.0 if plan.activity in ["beach_walk","watch_sea","visit","visit_flowers"] else 2.0
 if plan.has("mood"):
  var delta:Dictionary={}
  for axis in plan.mood:delta[axis]=clampf(float(plan.mood[axis]),-float(b.config.ai_intention.max_mood_delta),float(b.config.ai_intention.max_mood_delta))
  b.world.hearts.change(b.id,delta,"ai_intention")
 if not plan.has("with") and not plan.has("for_player") and not str(plan.get("say","")).is_empty():
  var line:String=str(plan.say).left(60)
  if preload("res://scripts/persona_cards.gd").safe_speech(line):b.world.director.say_local(b.id,line,"ai_intention",20,8)
func executing_plan()->void:
 var plan:Dictionary=b.current.get("ai_plan",{})
 if plan.is_empty():return
 b.trace({"actor":b.id,"at":b.clock,"event":"daily_wish_started" if plan.get("local_wish",false) else "ai_intention_started","plan":plan.duplicate(true)})
 if wish_receipt.is_valid():wish_receipt.call(plan,b.current.get("outing_job",{}),"started")
func finish(outcome:String,reason:String)->void:
 var plan:Dictionary=b.current.get("ai_plan",{})
 if plan.is_empty():return
 if wish_receipt.is_valid():wish_receipt.call(plan,b.current.get("outing_job",{}),outcome)
 settle(plan,outcome,reason)
func settle(plan:Dictionary,outcome:String,reason:String)->void:
 if plan.get("local_wish",false):
  b.trace({"actor":b.id,"at":b.clock,"event":"daily_wish_outcome","plan":plan.duplicate(true),"outcome":outcome,"reason":reason})
  return
 var row:Dictionary={"world_id":plan.get("world_id",b.world.world_id),"day":b.world.days.day() if plan.get("world_id",b.world.world_id)==b.world.world_id else int(plan.get("day",1)),"id":plan.get("host_id",(b.id+str(b.clock)).sha256_text()),"activity":plan.activity,"reason":plan.reason,"outcome":outcome,"detail":reason,"at":b.clock}
 for item in activity_log:
  if item.id==row.id:item.outcome=outcome;break
 recent.append(row);recent=recent.slice(-int(b.config.ai_intention.recent_limit));changed()
 if not reason.is_empty() and outcome!="completed":feedback(plan.activity,reason)
 b.trace({"actor":b.id,"event":"ai_intention_outcome","at":b.clock,"plan":plan.duplicate(true),"outcome":outcome,"reason":reason})
 if settled.is_valid():settled.call(row.duplicate(true))

func situation()->Dictionary:
 # Only present observations and retained canonical facts, never inferred witnesses.
 var w:RefCounted=b.world
 var neighbors:Array=[]
 for who in w.actors:
  if who==b.id or w.actors[who].region_id!=w.actors[b.id].region_id or w.point(w.actors[who]).distance_to(w.point(w.actors[b.id]))>12:continue
  neighbors.append({"id":who,"name":preload("res://scripts/localization.gd").resident(w,who),"doing":str(w.actors[who].activity)})
 var failed:Array=recent.filter(func(row):return row.outcome!="completed").slice(-2).map(func(row):return {"activity":row.activity,"reason":row.reason,"blocker":row.detail})
 var cat:Dictionary={"present":w.cat.discovered and w.cat.region==w.actors[b.id].region_id and w.cat.position.distance_to(w.point(w.actors[b.id]))<=8}
 return {"feeling":{"name":w.hearts.summary(b.id).name,"reason":w.hearts.summary(b.id).reason},"people":neighbors.slice(0,5),"unfinished_wishes":failed,"cat":cat}
