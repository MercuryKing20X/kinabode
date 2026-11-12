extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
var _owner: WeakRef
var game: Node:
	get:return _owner.get_ref()
func _init(owner_node: Node) -> void:_owner=weakref(owner_node)
func start(card: Dictionary) -> Dictionary:
	if card.get("opening_hint",false):
		if not game.world.standard.active():return game.world._error("proposal_unavailable")
		game.view.center=game.world.point(game.world.leisure.sites[card.target_id]);game.view.follow_player=false
		game.status.text=LocalText.text("content.remaining.the_campfire_foundation_is_here_bring_6_wood_then_explicitly_choose_bu")
		return {"ok":true,"status":"focused"}
	var world: RefCounted=game.world;var id: String=card.actor_id
	for who in ["human",id]:
		if world.work.jobs.has(who) or world._routes.has(who) or world.projects.active(who) or world.farms.active(who) or world.homestead.active(who) or world.activities.members.has(who) or world.shared_activity.holds(who) or world.gomoku.active(who):return world.work.fail("busy",LocalText.text("content.remaining.current_actions_continue_accept_the_suggestion_when_you_re_free"))
	if game.questions.has(id) or game.group_questions.has(id):return world._error("waiting_for_answer")
	game._cancel_resident_turn(id);game.autonomy.scheduler.note_model_action(id)
	match str(card.activity):
		"fish_together":
			var shore: Dictionary=world.fishing.shore("human")
			if shore.is_empty() or shore.water_id!=card.target_id or world.loaded("human") or not world.fishing.held("human").is_empty():return world._error("not_ready_for_sea")
			var invited: Dictionary=world.fishing.invite_host([id])
			if not invited.ok:return invited
			var human: Dictionary=world.command("human",{"intent":"fish"})
			if not human.ok:world.command(id,{"intent":"stop"});return human
			return invited
		"cook_together":
			var camp:RefCounted=world.nearest_barbecue("human",3)
			if camp==null:return world.work.fail("too_far",LocalText.text("content.remaining.come_to_the_campfire_before_inviting_everyone_to_barbecue"))
			game._invite_barbecue(camp.station.id)
			return {"ok":true,"status":"menu_opened"}
		"homestead_together":
			var result: Dictionary=world.command(id,{"intent":"homestead_start","site_id":card.target_id})
			if result.ok:
				world.command("human",{"intent":"homestead_start","site_id":card.target_id});game.homestead_panel.open("human")
			return result
		"sit_together":
			var site: Dictionary=world.leisure.sites[card.target_id]
			var free: int=world.leisure.art(site).recreation.slots.size()-world.work.jobs.values().filter(func(job):return job.get("target_id")==site.id).size()
			if not site.complete or free<2:return world._error("no_two_seats")
			var result: Dictionary=world.host_command(id,{"intent":"use_facility","target_id":site.id})
			if result.ok:result=world.command("human",{"intent":"use_facility","target_id":site.id})
			return result
		"watch_fishery":
			game._open_fishing(card.target_id);return {"ok":true,"status":"opened","message":LocalText.text("content.remaining.the_real_fishery_is_open_for_a_look_together_nobody_was_moved")}
	return world._error("unknown_proposal_activity")
