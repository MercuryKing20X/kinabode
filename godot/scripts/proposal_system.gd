extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
## Proposing has no actor authority; only respond_host may invoke host activity callbacks.
var _owner: WeakRef
var world: RefCounted:
	get:return _owner.get_ref()
var config: Dictionary={}
var cards: Dictionary={}
var last_created: Dictionary={}
var level_provider: Callable
var policies: Dictionary={}
func _init(source: RefCounted) -> void:
	_owner=weakref(source);config=JSON.parse_string(FileAccess.get_file_as_string("res://content/proposals.json"))
	policies=JSON.parse_string(FileAccess.get_file_as_string("res://content/autonomy.json")).levels
func now() -> float:return maxf(world.forest.clock,Time.get_unix_time_from_system())
func target_valid(activity: String,target: String) -> bool:
	if not config.activities.has(activity):return false
	match str(config.activities[activity].target):
		"sea":return world.fishing.waters.has(target)
		"recipe":return world.recipes.recipes.has(target)
		"homestead":return target==world.homestead.config.site.id and not world.homestead.completed()
		"table":return world.leisure.sites.has(target) and world.leisure.art(world.leisure.sites[target]).get("recreation",{}).get("behavior")=="sit"
		"fishery":return world.fishing.pens.has(target)
	return false
func create(id: String,args: Dictionary,heart_companion: String="") -> Dictionary:
	if args.get("activity")=="opening_fire":return world._error("host_only_opening_hint")
	if id=="human" or not world.director.model_controlled(id):return world._error("model_resident_required")
	if args.keys().any(func(key):return key not in ["intent","text","activity","target_id","ttl_seconds"]):return world._error("invalid_proposal")
	if not args.get("text") is String or args.text.strip_edges().is_empty() or args.text.length()>int(config.max_text) or not args.get("activity") is String or not args.get("target_id") is String or not target_valid(args.activity,args.target_id):return world._error("invalid_proposal")
	var ttl: Variant=args.get("ttl_seconds",config.default_ttl_seconds)
	if not (ttl is int or ttl is float) or not is_finite(ttl) or ttl!=floor(ttl) or ttl<1 or ttl>config.max_ttl_seconds:return world._error("invalid_proposal_expiry")
	if cards.has(id):return world._error("proposal_pending")
	var level: String=level_provider.call(id) if level_provider.is_valid() else "medium"
	if now()-float(last_created.get(id,0))<float(policies.get(level,policies.medium).cooldown):return world._error("proposal_cooldown")
	var card: Dictionary={"id":"proposal-"+Crypto.new().generate_random_bytes(12).hex_encode(),"actor_id":id,"text":args.text.strip_edges(),"activity":args.activity,"target_id":args.target_id,"expires_at":now()+ttl}
	if args.activity=="fish_together" and heart_companion!=id and heart_companion!="human" and world.director.brains.has(heart_companion):
		card["companion_id"]=heart_companion
	cards[id]=card;last_created[id]=now();world.revision+=1
	return {"ok":true,"status":"proposed","proposal_id":card.id,"message":LocalText.text("content.remaining.suggestion_delivered_waiting_for_the_player_s_explicit_choice_no_activ")}
func advance(delta: float) -> void:
	if delta<=0:return
	for id in cards.keys():
		if now()>=float(cards[id].expires_at) or (not cards[id].get("opening_hint",false) and not world.director.model_controlled(id)):cards.erase(id);world.revision+=1
func create_local_opening(id:String,text:String)->Dictionary:
	if not world.standard.active() or cards.has(id) or id not in world.standard.config.companions:return world._error("unavailable")
	var routine:RefCounted=world.director.routines[id]
	if not routine.enabled or not routine.chatter or routine.blocked() or world.shared_activity.holds(id) or routine.time<routine.next_speech or routine.time<routine.visual_quiet_until or world.director.time<world.director.speech_after or world.fishing.life.time<float(world.fishing.life.quiet_until.get(id,0)):return world._error("local_hint_held")
	config.activities["opening_fire"]={"name":LocalText.text("content.remaining.view_the_campfire_foundation"),"target":"opening"}
	cards[id]={"id":"proposal-"+Crypto.new().generate_random_bytes(12).hex_encode(),"actor_id":id,"text":text,"activity":"opening_fire","target_id":"play.standard.camp","expires_at":now()+300,"opening_hint":true,"source":"local_rules"}
	world.revision+=1;return {"ok":true}
func respond_host(key: String,accepted: bool,starter: Callable=Callable()) -> Dictionary:
	var matching: Array=cards.values().filter(func(card):return card.id==key)
	if matching.is_empty():return world._error("proposal_expired")
	var card: Dictionary=matching[0]
	if now()>=float(card.expires_at):cards.erase(card.actor_id);return world._error("proposal_expired")
	if card.get("opening_hint",false):
		if accepted and not starter.is_valid():return world._error("proposal_unavailable")
		var reply:Dictionary=starter.call(card.duplicate(true)) if accepted else {"ok":true,"status":"declined"}
		if reply.ok:cards.erase(card.actor_id)
		return reply
	var result: Dictionary={"ok":true,"status":"declined"}
	if accepted:
		if not target_valid(card.activity,card.target_id) or not starter.is_valid():return world._error("proposal_unavailable")
		result=starter.call(card.duplicate(true))
		if not result.get("ok",false):return result
	var facts: Dictionary={"resident_id":card.actor_id,"text":card.text,"activity":card.activity,"target_id":card.target_id,"decision":"accepted" if accepted else "declined"}
	if not world.memories.record_event("proposal_decision",card.id,["human",card.actor_id],facts):return world._error("proposal_memory_rejected")
	cards.erase(card.actor_id);world.revision+=1;return result
func snapshot() -> Array:return cards.values().duplicate(true)
