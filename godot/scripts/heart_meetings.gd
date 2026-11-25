extends RefCounted
## Session-only invitations. A reply grants the recipient's own leisure route only.
const Outing=preload("res://scripts/brain_outing.gd")
const Persona=preload("res://scripts/persona_cards.gd")
const Text=preload("res://scripts/localization.gd")
var owner:WeakRef
var game:Node:
	get:return owner.get_ref()
var w:RefCounted:
	get:return game.world
var rows:Dictionary={}
var cooldown:Dictionary={}
var speech:Array=[]
var records:Array=[]
func _init(g:Node)->void:owner=weakref(g)
func pair(a:String,b:String)->String:
	var ids:Array=[a,b];ids.sort();return ":".join(ids)
func trace(row:Dictionary,event:String,extra:Dictionary={})->void:
	var entry:Dictionary={"event":event,"at":w.director.time,"actor":row.from,"recipient":row.to,"invitation_id":row.id,"activity":row.activity,"place":row.place}
	entry.merge(extra,true);records.append(entry);records=records.slice(-256)
	w.director.brains[row.from].trace(entry)
func gate(id:String)->String:
	var brain:RefCounted=w.director.brains[id]
	if w.hunger.rank(id)>=3:return "refuse_hunger"
	if not brain.eligible() or brain.busy() or brain.current.get("source","") not in ["","local"] or w.activities.members.has(id) or brain.current.has("heart_guest"):return "refuse_command"
	return ""
func active_source(row:Dictionary)->bool:
	if row.get("celebration",false):
		return row.generation==w.session_generation and game.project_host!=null and game.project_host.celebration.get("tokens",{}).get(row.to)==row.id
	if row.get("project",false):
		return row.generation==w.session_generation and game.project_host!=null and game.project_host.peer_current(row)
	return row.generation==w.session_generation and w.director.brains[row.from].current.get("ai_plan",{}).get("host_id")==row.id
func offer_celebration(id:String,other:String,token:String)->void:
	var row:Dictionary={"id":token,"from":id,"to":other,"activity":"celebrate","place":"home","celebration":true,"generation":w.session_generation,"until":w.director.time+30,"state":"waiting","reason":"","spoken":0}
	rows[token]=row
	trace(row,"heart_peer_delivered")
func offer_project(id:String,other:String,token:String,message:String)->bool:
	if id==other or not w.director.brains.has(other) or w.actors[id].region_id!=w.actors[other].region_id:return false
	var key:String=pair(id,other)
	if w.director.time<float(cooldown.get(key,0)) or rows.values().any(func(row):return key==pair(row.from,row.to)):return false
	var row:Dictionary={"id":token,"from":id,"to":other,"activity":"invite_fishing","place":"sea","project":true,"generation":w.session_generation,"until":w.director.time+38,"state":"waiting","reason":message,"spoken":0}
	rows[token]=row;cooldown[key]=w.director.time+100
	trace(row,"heart_peer_delivered",{"reason":message,"model_recipient":w.director.model_controlled(other)})
	queue(row,id,other,message)
	return true
func send(from:String,job:Dictionary,plan:Dictionary)->bool:
	var to:String=plan.get("with","")
	if from==to or not w.director.brains.has(to) or plan.get("local_wish",false):return false
	if w.actors[to].region_id!=job.region:return false
	var k:String=pair(from,to)
	if w.director.time<float(cooldown.get(k,0)) or rows.values().any(func(other):return k==pair(other.from,other.to)):return false
	var row:Dictionary={"id":plan.host_id,"from":from,"to":to,"activity":plan.activity,"place":job.place,"generation":w.session_generation,"until":w.director.time+38,"state":"waiting","reason":str(plan.reason).left(120),"spoken":0}
	rows[row.id]=row;cooldown[k]=w.director.time+100
	trace(row,"heart_peer_delivered",{"reason":row.reason,"model_recipient":w.director.model_controlled(to)})
	var line:String=str(plan.get("say",""))
	if line.is_empty():line=Text.resident(w,to)+Outing.phrase(["，要一起走走吗？",", want to come along?"])
	queue(row,from,to,line)
	return true
func incoming(id:String)->Dictionary:
	for row in rows.values():
		if row.to==id and row.state=="waiting" and active_source(row) and gate(id).is_empty() and not row.has("turn"):return row
	return {}
func reserved_guest(id:String)->bool:
	return rows.values().any(func(row):return row.to==id and row.state in ["accepted","walking","together"] and active_source(row))
func prompt(id:String,key:String)->Dictionary:
	var row:Dictionary=incoming(id)
	if row.is_empty():return {}
	row["turn"]=key
	return {"id":row.id,"from":row.from,"name":Text.resident(w,row.from),"activity":row.activity,"place":row.place,"reason":row.reason,"current_activity":w.director.brains[id].current.get("action","")}
func answer(id:String,token:String,key:String,data:Variant)->void:
	var row:Dictionary=rows.get(token,{})
	if row.is_empty() or row.to!=id or row.get("turn")!=key or row.state!="waiting" or not active_source(row) or not w.director.time<row.until:return
	if not data is Dictionary or data.get("id")!=token or data.get("decision") not in ["accept","decline"] or not safe_line(data.get("reason")):return
	var blocker:String=gate(id)
	decide(row, data.decision=="accept" and blocker.is_empty(), str(data.reason) if blocker.is_empty() else reason_line(id,blocker), "model" if blocker.is_empty() else "host")
func safe_line(value:Variant)->bool:
	return value is String and value.length()<=100 and not value.strip_edges().is_empty() and not "\n" in value and Persona.safe_speech(value)
func reason_line(id:String,reason:String)->String:
	var brain:RefCounted=w.director.brains[id]
	if reason in ["refuse_hunger","refuse_command","refuse_tired"]:return brain.text(reason)
	if brain.tag()=="lively":return Outing.phrase(["这次先不了！下一趟叫我呀。","I'll sit this one out. Get me next time!"])
	return Outing.phrase(["今天这趟我就不去了，想在这儿待一会儿。","I think I'll stay here a little longer today."])
func decide(row:Dictionary,yes:bool,reason:String,source:String)->void:
	row.state="accepted" if yes else "declined";row["answer"]=reason
	if yes:row["join_until"]=w.director.time+45
	trace(row,"heart_peer_decided",{"decision":row.state,"reason":reason,"source":source})
	queue(row,row.to,row.from,reason)
	if not yes and not row.get("celebration",false):queue(row,row.from,row.to,Outing.phrase(["那我自己走一小段啦。","I'll take a little walk on my own, then."]))
func queue(row:Dictionary,who:String,to:String,line:String)->void:
	if not safe_line(line) or int(row.spoken)>=4:return
	row.spoken+=1
	speech.append({"row":row,"actor":who,"to":to,"text":line,"until":w.director.time+45})
	if speech.size()>24:speech.pop_front()
func tick()->void:
	for row in rows.values():
		if not active_source(row):close(row.id,"source_ended");continue
		if row.state!="waiting":continue
		var why:String=gate(row.to)
		if row.get("celebration",false):
			if w.actors[row.from].region_id!=w.actors[row.to].region_id:why="other_island"
			elif why.is_empty() and w.point(w.actors[row.to]).distance_to(game.project_host.celebration.point)>36:why="too_far"
			decide(row,why.is_empty(),Text.text("heart.project.celebration."+("join" if why.is_empty() else why)),"local");continue
		if not why.is_empty() and not row.has("turn"):
			decide(row,false,reason_line(row.to,why),"host")
		elif not game.autonomy.native_heart(row.to) or not game.autonomy.scheduler.enabled(row.to) or game.connection_pool.quota_reached(row.to):
			var other:RefCounted=w.director.brains[row.to]
			var tired:bool=float(w.hearts.mood(row.to).tired)>=70
			if row.get("project",false) and game.project_host.peer_engaged(row.to):
				decide(row,false,Text.text("heart.project.peer_own_work"),"local");continue
			var result:Dictionary=other.interactions.social("walk",row.from) if not tired else {"ok":false,"error":"refuse_tired"}
			# Keep all lines for this exchange in the same four-line queue.
			if not result.ok:other.refusal.clear()
			var line:String=Outing.phrase(["走呀！那里一定好玩。","Let's go! I want to see it too."] if other.tag()=="lively" else ["嗯，我也想出去透透气。","I'd like a little air too."])
			decide(row,result.ok,line if result.ok else reason_line(row.to,str(result.error)),"local")
		elif w.director.time>=row.until:
			decide(row,false,reason_line(row.to,"timeout"),"timeout")
func deliver()->void:
	for line in speech.duplicate():
		if w.director.time>=line.until or line.row.generation!=w.session_generation:speech.erase(line);continue
		if w.director.say_local(line.actor,line.text,"heart_social",12,8,line.to):
			trace(line.row,"heart_peer_spoken",{"speaker":line.actor,"listener":line.to,"text":line.text})
			speech.erase(line);break
func outcome(token:String)->String:return str(rows.get(token,{}).get("state","declined"))
func depart(token:String,p:Vector2)->String:
	var row:Dictionary=rows.get(token,{})
	if row.is_empty() or row.state!="accepted":return "declined"
	var guest:RefCounted=w.director.brains[row.to]
	if guest.current.has("ai_plan") and not guest.current.get("ai_plan",{}).get("local_wish",false) and w.director.time<float(row.join_until):return "waiting"
	if guest.current.has("ai_plan") or not gate(row.to).is_empty() or not guest.join_heart_outing(token,p,row.place):
		row.state="declined"
		trace(row,"heart_peer_unavailable",{"reason":"busy_or_unreachable"})
		queue(row,row.from,row.to,Outing.phrase(["没关系，我先去看看。","That's all right. I'll go have a look."]))
		return "declined"
	row.state="walking";trace(row,"heart_peer_departed")
	return "walking"
func arrived(token:String,p:Vector2)->bool:
	var row:Dictionary=rows.get(token,{})
	if row.is_empty() or row.state not in ["walking","together"]:return false
	var guest:RefCounted=w.director.brains[row.to]
	if guest.current.get("heart_guest")!=token or w._routes.has(row.to) or w.point(w.actors[row.to]).distance_to(p)>3.5:return false
	if row.state=="walking":
		row.state="together";trace(row,"heart_peer_together")
		if row.get("celebration",false):queue(row,row.to,row.from,Text.text("heart.project.celebration.arrived"))
		else:
			queue(row,row.from,row.to,Outing.phrase(["一起到啦，在这里待一会儿吧。","We made it. Let's stay a little while."]))
			queue(row,row.to,row.from,Outing.phrase(["好呀，这里正好。","Right here is lovely."]))
	return true
func close(token:String,result:String)->void:
	var row:Dictionary=rows.get(token,{})
	if row.is_empty():return
	rows.erase(token)
	var k:String=pair(row.from,row.to)
	cooldown[k]=maxf(float(cooldown.get(k,0)),w.director.time+45)
	trace(row,"heart_peer_ended",{"result":result,"stage":row.state})
	var guest:RefCounted=w.director.brains[row.to]
	if guest.current.get("heart_guest")==token:guest.finish("completed" if row.state=="together" and result=="completed" else "interrupted","outing_ended")
