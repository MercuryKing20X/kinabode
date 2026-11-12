class_name SharedActivity
extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
## Selected host invitation only. Each Fireside owns its real jobs, seats and food.
var _owner:WeakRef
var world:RefCounted:
	get:return _owner.get_ref()
var selected_station:="home.barbecue"
var life:RefCounted:
	get:return world.barbecues[selected_station]
var session:Dictionary={}
var memories:Array=[]
var owned_jobs:Dictionary={}
var issuing:=""
func _init(source:RefCounted)->void:_owner=weakref(source)
func active()->bool:return world.barbecues.values().any(func(c):return c.fireside.active() and c.fireside.state.consent and not c.fireside.circle_closed)
func contains(id:String)->bool:return world.barbecues.values().any(func(c):return c.fireside.active() and not c.fireside.circle_closed and (c.fireside.jobs.has(id) or id in c.fireside.state.invited))
func holds(id:String)->bool:return world.barbecues.values().any(func(c):return c.fireside.jobs.has(id))
func locked()->bool:return active()
func validate_invitation(ids:Array,station_id:String="home.barbecue")->Dictionary:
	if not world.barbecues.has(station_id):return world._error("unknown_station")
	return world.barbecues[station_id].fireside.can_invite(ids)
func begin_fireside(ids:Array,station_id:String="home.barbecue")->Dictionary:
	var checked:Dictionary=validate_invitation(ids,station_id)
	if not checked.ok:return checked
	selected_station=station_id
	var result:Dictionary=life.fireside.invite(ids)
	if result.ok:session={"id":life.fireside.state.id,"kind":"barbecue","station_id":station_id,"participants":["human"]+ids,"status":"selected","phase":"menu"}
	return result
func begin(ids:Array,station_id:String="home.barbecue")->Dictionary:return begin_fireside(ids,station_id)
func pause_actor(id:String,reason:String)->void:
	for fire_life in world.barbecues.values():
		if fire_life.fireside.jobs.has(id):fire_life.fireside.end_circle(reason)
func pause(reason:String)->void:
	for camp in world.barbecues.values():
		if camp.fireside.active() and camp.fireside.state.consent:camp.fireside.end_circle(reason)
	if not session.is_empty():session.status="closed"
func cancel()->Dictionary:
	pause(LocalText.text("content.remaining.end_the_fireside_gathering"));return {"ok":true}
func decide(_id:String,_action:String,_actor:String="")->Dictionary:return world.work.fail("retired_action",LocalText.text("content.remaining.choose_barbecue_by_the_fire_invite_companions_then_start_grilling"))
func advance(_delta:float)->void:pass
func snapshot()->Dictionary:
	return session.duplicate(true)
func restore(_data:Dictionary)->void:session={};memories=[];owned_jobs={}
