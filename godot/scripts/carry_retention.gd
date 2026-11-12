extends RefCounted
## Optional subset of actual carry. No extra inventory, rewards, history or capacity.
static func valid(value:Variant,carry:Dictionary)->bool:
	if not value is Dictionary or value.size()>20:return false
	for item in value:
		var n:Variant=value[item]
		if not item is String or not carry.has(item) or not (n is int or n is float) or not is_finite(float(n)) or n!=floor(float(n)) or n<=0 or n>int(carry[item]):return false
	return true
static func clamp_actor(actor:Dictionary)->void:
	if not actor.has("retained_carry"):return
	var next:Dictionary={}
	for item in actor.retained_carry:
		var n:int=mini(int(actor.retained_carry[item]),int(actor.carry.get(item,0)))
		if n>0:next[item]=n
	actor.retained_carry=next
static func mark(actor:Dictionary,item:String,quantity:int)->void:
	if actor.id=="human":return
	var kept:Dictionary=actor.get("retained_carry",{}).duplicate(true)
	kept[item]=mini(int(actor.carry.get(item,0)),int(kept.get(item,0))+quantity)
	actor.retained_carry=kept;clamp_actor(actor)
static func consume(actor:Dictionary,item:String,quantity:int)->void:
	var kept:Dictionary=actor.get("retained_carry",{}).duplicate(true)
	if kept.has(item):
		kept[item]=maxi(0,int(kept[item])-quantity)
		if kept[item]==0:kept.erase(item)
	actor.retained_carry=kept
static func unprotected(actor:Dictionary)->Dictionary:
	var result:Dictionary={};var kept:Dictionary=actor.get("retained_carry",{})
	for item in actor.carry:
		var n:int=maxi(0,int(actor.carry[item])-int(kept.get(item,0)))
		if n>0:result[item]=n
	return result
static func preserve_legacy(actor:Dictionary)->void:
	# Unknown old provenance is kept as physical goods; never called a past gift.
	if actor.id!="human" and not actor.has("retained_carry"):actor.retained_carry=actor.carry.duplicate(true)
