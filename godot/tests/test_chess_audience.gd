extends SceneTree

class Personality:
	extends RefCounted
	func tag(_actor: String) -> String:
		return "lively"

class Intelligence:
	extends RefCounted
	var compatibility := false

class FakeWorld:
	extends RefCounted
	var personality := Personality.new()
	var intelligence := Intelligence.new()

func _initialize() -> void:
	var chatter = preload("res://scripts/chess_chatter.gd").new(FakeWorld.new(), "jieqi")
	for game in ["jieqi", "gomoku"]:
		for personality_tag in ["playful", "gentle", "diligent", "quiet"]:
			var entries: Dictionary = chatter.audience_lines[game][personality_tag]
			var zh := {}
			var en := {}
			for group in entries.values():
				for candidate in group:
					zh[candidate.zh] = true
					en[candidate.en] = true
			assert(zh.size() >= 30 and en.size() >= 30)
	chatter.audience_lines = {"jieqi":{"playful":{"comment":[{"key":"test.one","zh":"一","en":"one"},{"key":"test.two","zh":"二","en":"two"}]}}}
	chatter.begin("match", "opponent")
	chatter.set_audience(["human", "opponent", "a", "b", "c"])
	assert(chatter.audience == ["a", "b", "c"])
	for hand in range(1, 31):
		chatter.observe_hand(hand)
		chatter.advance(4.0)
	var last_at := -100.0
	var actor_at := {}
	var seen := {}
	for event in chatter.events:
		assert(event.at - last_at >= 3.0)
		assert(event.at - float(actor_at.get(event.actor_id, -100.0)) >= 4.0)
		last_at = event.at
		actor_at[event.actor_id] = event.at
		var pair: String = str(event.actor_id) + ":" + str(event.key)
		assert(not seen.has(pair))
		seen[pair] = true
	for actor in ["a", "b", "c"]:
		assert(actor_at.has(actor))
	var mapped = preload("res://scripts/chess_chatter.gd").new(FakeWorld.new(), "jieqi")
	mapped.begin("mapped", "opponent")
	mapped.set_audience(["a", "b", "c"])
	mapped.observe_hand(1, "chaos_selfcheck")
	assert(mapped.pending.any(func(entry): return entry.get("audience", false) and entry.category == "chaos_selfcheck") or mapped.events.any(func(event): return event.actor_id == "a" and event.category == "chaos_selfcheck"))
	mapped.request({"category":"result"})
	mapped.advance(4.0)
	assert(mapped.events.back().actor_id == "opponent" and mapped.events.back().category == "result")
	print("Chess audience spacing and fairness passed")
	quit(0)
