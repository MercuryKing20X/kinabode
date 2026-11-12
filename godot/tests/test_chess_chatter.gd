extends SceneTree

class Personality:
	extends RefCounted
	var value := "lively"
	func tag(_id: String) -> String:
		return value

class Intelligence:
	extends RefCounted
	var compatibility := false

class FakeWorld:
	extends RefCounted
	var personality := Personality.new()
	var intelligence := Intelligence.new()

func _initialize() -> void:
	var chatter = preload("res://scripts/chess_chatter.gd").new(FakeWorld.new(), "jieqi")
	var events: Array = []
	chatter.delivered.connect(func(event): events.append(event))
	chatter.begin("match", "resident")
	assert(chatter._profile_key() == "playful")
	chatter.observe_hand(1)
	assert(events.size() == 1)
	chatter.observe_hand(2)
	chatter.advance(3.9)
	assert(events.size() == 1)
	chatter.advance(0.1)
	assert(events.size() == 2 and events[0].key != events[1].key)
	var reactions: Array = chatter.lines.jieqi.playful.goodmove
	reactions.append({"key":"test.reaction.3", "zh":"三", "en":"three"})
	reactions.append({"key":"test.reaction.4", "zh":"四", "en":"four"})
	for i in range(4):
		chatter.last_hand = 3 + i
		chatter.request({"category": "goodmove", "reaction": true})
		chatter.advance(4.0)
	assert(chatter.reaction_counts.get("goodmove") == 4)
	assert(not chatter.request({"category": "goodmove", "reaction": true}))
	chatter.begin("long", "resident")
	for hand in range(1, 31):
		chatter.observe_hand(hand)
		chatter.advance(4.0)
	assert(chatter.events.size() >= 15)
	assert(chatter.events[0].has("trigger_hand"))
	chatter.begin("priority", "resident")
	chatter.request({"category":"idle"})
	chatter.request({"category":"thinking"})
	chatter.request({"category":"result"})
	chatter.advance(4.0)
	assert(chatter.events.back().category == "result")
	var key: String = chatter.current_key
	TranslationServer.set_locale("en")
	assert(chatter.display_line() == preload("res://scripts/localization.gd").text(key))
	chatter.begin("accepted-model", "resident")
	chatter.request({"category":"model","key":"accepted:1","text":"A real accepted move.","actor_id":"model-player"})
	assert(chatter.display_line()=="A real accepted move." and chatter.events.back().actor_id=="model-player")
	TranslationServer.set_locale("zh_CN")
	assert(chatter.display_line()=="A real accepted move.") # External prose stays verbatim.
	var counts := {}
	for personality_tag in ["lively", "gentle", "laborious", "quiet"]:
		var sample_world := FakeWorld.new()
		sample_world.personality.value = personality_tag
		var sample = preload("res://scripts/chess_chatter.gd").new(sample_world, "jieqi")
		sample.begin("test", "resident")
		for hand in range(1, 31):
			sample.observe_hand(hand)
			sample.request({"category":"river", "reaction":true})
			sample.advance(4.0)
		counts[personality_tag] = sample.events.size()
	assert(counts.quiet < counts.lively)
	assert(counts.quiet <= 11)
	print("Chess chatter cadence and reaction cap passed")
	quit(0)
