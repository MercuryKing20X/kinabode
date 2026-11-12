class_name ChessChatter
extends RefCounted

signal delivered(event: Dictionary)
signal reaction(actor_id: String, action: String)

const GAP := 4.0
const GLOBAL_GAP := 3.0
const BUBBLE_SECONDS := 3.6
const REACTION_CAP := 4

var world: Variant
var kind: String
var match_id := ""
var opponent := ""
var elapsed := 0.0
var last_delivery := -GAP
var line := ""
var timeleft := 0.0
var action := ""
var used := {}
var reaction_counts := {}
var pending: Array[Dictionary] = []
var lines: Dictionary = {}
var last_hand := -1
var events: Array[Dictionary] = []
var current_key := ""
var external_line := ""
var audience: Array[String] = []
var audience_lines: Dictionary = {}
var actor_last: Dictionary = {}
var actor_used: Dictionary = {}
var audience_cursor := 0
var opponent_streak := 0
var last_delivery_hand := -100
const GENERIC := ["idle", "thinking", "food", "fish", "weather"]
const HAND_EXCEPTIONS := ["start", "result", "tap", "slowplayer", "hunger", "win", "lose", "draw", "model"]

func _init(p_world: Variant, p_kind: String) -> void:
	world = p_world
	kind = p_kind
	var path := "res://content/chess-dialogue.json"
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			lines = parsed
	var audience_data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/chess-audience.json")) if FileAccess.file_exists("res://content/chess-audience.json") else {}
	if audience_data is Dictionary:
		audience_lines = audience_data

func set_audience(ids: Array) -> void:
	audience.clear()
	for id in ids:
		var actor := str(id)
		if actor != "human" and actor != opponent and actor not in audience:
			audience.append(actor)

func begin(p_match_id: String, p_opponent: String) -> void:
	match_id = p_match_id
	opponent = p_opponent
	elapsed = 0.0
	last_delivery = -GAP
	line = ""
	timeleft = 0.0
	action = ""
	used.clear()
	reaction_counts.clear()
	pending.clear()
	last_hand = -1
	events.clear()
	current_key = ""
	external_line = ""
	last_delivery_hand = -100
	actor_last.clear()
	actor_used.clear()
	audience_cursor = 0
	opponent_streak = 0

func _hand_interval() -> int:
	return int({"playful": 1, "gentle": 2, "diligent": 2, "quiet": 3}.get(_profile_key(), 2))

func _eligible(entry: Dictionary) -> bool:
	var actor := str(entry.get("actor_id", opponent))
	if elapsed - float(actor_last.get(actor, -GAP)) < GAP:
		return false
	if bool(entry.get("audience", false)):
		return actor in audience
	return str(entry.get("category", "")) in HAND_EXCEPTIONS or last_hand - last_delivery_hand >= _hand_interval()

func _try_deliver() -> void:
	if elapsed - last_delivery < GLOBAL_GAP:
		return
	if opponent_streak >= 2 and (pending.is_empty() or str(pending[0].get("category", "")) != "result" or bool(pending[0].get("audience", false))):
		for i in range(pending.size()):
			if bool(pending[i].get("audience", false)) and _eligible(pending[i]):
				var audience_entry := pending[i]
				pending.remove_at(i)
				_deliver(audience_entry)
				return
	for i in range(pending.size()):
		if _eligible(pending[i]):
			var entry := pending[i]
			pending.remove_at(i)
			_deliver(entry)
			return

func display_line() -> String:
	if timeleft <= 0.0 or current_key.is_empty():
		return ""
	return external_line if not external_line.is_empty() else preload("res://scripts/localization.gd").text(current_key)

func _profile_key(actor_id: String = "") -> String:
	if world == null:
		return "gentle"
	var tag := str(world.personality.tag(opponent if actor_id.is_empty() else actor_id))
	var mapping := {"lively": "playful", "laborious": "diligent"}
	if world.intelligence.compatibility:
		mapping = {"curious": "playful", "lively": "diligent"}
	var key := str(mapping.get(tag, tag))
	return key if key in ["playful", "gentle", "diligent", "quiet"] else "gentle"

func observe_hand(hand: int, context: String = "") -> void:
	if hand <= last_hand:
		return
	last_hand = hand
	if not context.is_empty():
		request({"category": context, "reaction": true, "priority": 2})
		_queue_audience(context)
		return
	if hand % 3 == 0:
		_queue_audience("comment")
	if hand % _hand_interval() == 0:
		request({"category": "idle"})
	_try_deliver()

func _queue_audience(context: String) -> void:
	if audience.is_empty():
		return
	var actor: String = audience[audience_cursor % audience.size()]
	audience_cursor += 1
	var mapping := {"big_self":"awe", "big_you":"awe", "capture_big":"awe", "capture_hidden":"awe", "check_self":"awe", "check_you":"awe", "chaos_selfcheck":"chaos_selfcheck", "result":"result", "win":"result", "lose":"result", "draw":"result", "nearwin":"cheer", "nearlose":"comment", "chaos_opposite":"awe", "river":"awe", "goodmove":"cheer", "prereveal":"tease"}
	var category := str(mapping.get(context, "comment"))
	if category == "comment" and audience_cursor % 3 == 0 and world != null:
		var hunger: Variant = world.get("hunger")
		if hunger != null and hunger.rank(actor) >= 2:
			category = "hunger"
	request({"actor_id": actor, "category": category, "audience": true})

func advance(delta: float) -> void:
	if delta <= 0.0:
		return
	elapsed += delta
	timeleft = maxf(0.0, timeleft - delta)
	if timeleft == 0.0:
		line = ""
		action = ""
		current_key = ""
	else:
		line = display_line()
	_try_deliver()

func request(context: Dictionary) -> bool:
	var category := str(context.get("category", "idle"))
	if category == "idle":
		for queued in pending:
			if queued.get("category") == "idle":
				return false
	if bool(context.get("reaction", false)):
		var count := int(reaction_counts.get(category, 0))
		for queued in pending:
			if queued.get("category") == category and bool(queued.get("reaction", false)):
				count += 1
		if count >= REACTION_CAP:
			return false
	var entry := context.duplicate(true)
	entry["category"] = category
	if bool(entry.get("audience", false)) and not entry.has("priority"):
		entry["priority"] = -1
	entry["hand"] = int(context.get("hand", last_hand))
	if category == "result" and not bool(entry.get("audience", false)):
		entry["priority"] = 100
	if pending.size() >= 4:
		var generic_index := -1
		for i in range(pending.size() - 1, -1, -1):
			if str(pending[i].get("category", "")) in GENERIC:
				generic_index = i
				break
		if generic_index < 0 and category == "result" and not bool(entry.get("audience", false)):
			generic_index = pending.size() - 1
		if generic_index < 0:
			return false
		pending.remove_at(generic_index)
	var priority := int(entry.get("priority", 0))
	var index := 0
	while index < pending.size() and int(pending[index].get("priority", 0)) >= priority:
		index += 1
	pending.insert(index, entry)
	_try_deliver()
	if category == "result" and not bool(entry.get("audience", false)):
		_queue_audience("result")
	return true

func tapped(actor_id: String = "") -> bool:
	var actor := opponent if actor_id.is_empty() else actor_id
	return request({"category": "tap", "priority": 50, "actor_id": actor, "audience": actor != opponent})

func _deliver(context: Dictionary) -> void:
	var category := str(context.category)
	var actor := str(context.get("actor_id", opponent))
	var is_audience := bool(context.get("audience", false))
	var profiles: Dictionary = audience_lines.get(kind, {}) if is_audience else lines.get(kind, {})
	var profile: Dictionary = profiles.get(_profile_key(actor), {})
	var pool_key:String="result_"+str(context.outcome) if category=="result" and context.has("outcome") else category
	var options: Array = [{"key":str(context.get("key","")),"zh":str(context.text),"en":str(context.text)}] if category=="model" and context.has("text") else profile.get(pool_key, [])
	if not is_audience and category == "chaos_selfcheck":
		options = options.duplicate()
		var extra_profiles: Dictionary = audience_lines.get(kind, {})
		var extra_profile: Dictionary = extra_profiles.get(_profile_key(actor), {})
		options=extra_profile.get(category, []).duplicate()+options
	if category in GENERIC:
		options = options.duplicate()
		for fallback in GENERIC:
			if fallback != category:
				options.append_array(profile.get(fallback, []))
	if options.is_empty() and kind == "jieqi" and not is_audience:
		var legacy_key := "jieqi.line.%s.%s" % [_profile_key(), category]
		var local_text = preload("res://scripts/localization.gd")
		var translated: String = local_text.text(legacy_key)
		if translated != legacy_key:
			options = [{"key": legacy_key, "zh": translated, "en": translated}]
	for candidate in options:
		if not candidate is Dictionary:
			continue
		var key := str(candidate.get("key", ""))
		var own_used: Dictionary = actor_used.get(actor, {}) if is_audience else used
		if key.is_empty() or own_used.has(key):
			continue
		own_used[key] = true
		if is_audience:
			actor_used[actor] = own_used
		if bool(context.get("reaction", false)):
			reaction_counts[category] = int(reaction_counts.get(category, 0)) + 1
		var locale := "en" if TranslationServer.get_locale().begins_with("en") else "zh"
		line = str(candidate.get(locale, ""))
		current_key = key
		external_line = line if category=="model" else ""
		timeleft = BUBBLE_SECONDS
		var actions := {"thinking":"thinking", "goodmove":"surprised", "regret":"sad", "hunger":"hunger", "nearwin":"proud", "nearlose":"panic", "result":"happy", "rankchanged":"surprised"}
		action = str(context.get("action", actions.get(category, "calm")))
		last_delivery = elapsed
		actor_last[actor] = elapsed
		if not is_audience:
			last_delivery_hand = last_hand
			opponent_streak += 1
		else:
			opponent_streak = 0
		var event := {"id": match_id, "actor_id": str(context.get("actor_id",opponent)), "key": key, "text": line, "category": category, "action": action, "at": elapsed, "hand": last_hand, "trigger_hand": int(context.get("hand", last_hand))}
		events.append(event.duplicate(true))
		delivered.emit(event)
		return
