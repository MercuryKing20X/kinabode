extends RefCounted
## Bounded presentation of actual scheduler receipts; never a source of wakeups.
var prefs: RefCounted
var limit:=20
func _init(preferences: RefCounted,capacity: int=20) -> void:prefs=preferences;limit=capacity
func read(id: String) -> Dictionary:
	var value: Variant=prefs.settings.get_value(prefs.section(id),"autonomy_records",{})
	if not value is Dictionary:return {"turns":[],"gates":[],"notice_day":-1}
	var decoded:Dictionary=value.duplicate(true)
	for entry in decoded.get("turns",[])+decoded.get("gates",[]):
		if entry.get("at") is String and entry.at.is_valid_float():entry.at=float(entry.at)
	value=decoded
	return {"turns":value.get("turns",[]).duplicate(true),"gates":value.get("gates",[]).duplicate(true),"notice_day":value.get("notice_day",-1)}
func save(id: String,value: Dictionary) -> bool:
	var encoded:Dictionary=value.duplicate(true)
	for entry in encoded.get("turns",[])+encoded.get("gates",[]):
		if entry.get("at") is float:entry.at="%.17f"%entry.at
	prefs.settings.set_value(prefs.section(id),"autonomy_records",encoded);return prefs.persist()==OK
func gate(id: String,reason: String,at: float) -> void:
	var data:=read(id)
	if not data.gates.is_empty() and data.gates[-1].reason==reason:return
	data.gates.append({"at":at,"reason":reason})
	if data.gates.size()>limit:data.gates.pop_front()
	save(id,data)
func start(id: String,key: String,events: Array,at: float,estimate: int) -> void:
	var data:=read(id)
	data.turns.append({"id":key,"at":at,"events":events.map(func(event):return event.kind),"actions":[],"estimated_tokens":estimate,"actual_tokens":0,"usage_status":"pending","status":"pending"})
	if data.turns.size()>limit:data.turns.pop_front()
	save(id,data)
func update(id: String,key: String,total: int,status: String) -> void:
	var data:=read(id)
	for turn in data.turns:
		if turn.id==key:turn.actual_tokens=total;turn.usage_status=status;turn.status=status;break
	save(id,data)
func action(id: String,key: String,command: Dictionary,result: Dictionary) -> void:
	var data:=read(id)
	for turn in data.turns:
		if turn.id!=key:continue
		if turn.actions.size()<8:turn.actions.append({"intent":str(command.get("intent","")),"status":str(result.get("status","accepted" if result.get("ok",false) else "rejected")),"job_id":str(result.get("job_id",""))})
		break
	save(id,data)
func job_finished(event: Dictionary) -> void:
	if str(event.get("job_id","")).is_empty():return
	var data:=read(str(event.actor_id));var changed:=false
	for turn in data.turns:
		for action in turn.actions:
			if action.job_id==event.job_id and action.status!=event.status:action.status=event.status;changed=true
	if changed:save(str(event.actor_id),data)
func notice_once(id: String,day: int) -> bool:
	var data:=read(id)
	if data.notice_day==day:return false
	data.notice_day=day;return save(id,data)
func recover(id: String) -> void:
	var data:=read(id);var changed:=false
	for turn in data.turns:
		if turn.status in ["pending","reported_partial"]:turn.status="interrupted_unknown";turn.usage_status="unknown";changed=true
	if changed:save(id,data)
