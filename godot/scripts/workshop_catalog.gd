class_name WorkshopCatalog
extends RefCounted
const LocalText=preload("res://scripts/localization.gd")

const KINDS := ["character", "building", "facility", "plant"]
const GROUPS := ["content.workshop.appearance", "content.workshop.movement", "content.workshop.work", "content.workshop.daily_life"]
const DIRECTIONS := {"down": "content.workshop.front", "left": "content.workshop.left", "right": "content.workshop.right", "up": "content.workshop.back", "": "content.workshop.general"}
const NAMES := {"ai-gpt":"content.world.characters.ai-gpt.white_dragon_gpt", "ai-claude":"content.world.characters.ai-claude.orange_book_claude", "ai-gemini":"content.world.characters.ai-gemini.purple_cat_gemini", "ai-grok":"content.world.characters.ai-grok.golden_crown_grok", "ai-deepseek":"content.world.characters.ai-deepseek.blue_whale_deepseek", "ai-glm":"content.world.characters.ai-glm.ink_hat_glm", "ai-qwen":"content.world.characters.ai-qwen.jade_fan_qwen", "ai-kimi":"content.world.characters.ai-kimi.moon_white_kimi", "human-starter": "content.workshop.you", "white-haired-girl": "content.workshop.snow", "blue-haired-girl":"content.workshop.skye", "orange-haired-girl":"content.workshop.clem", "black-scarf-girl":"content.workshop.raven", "cottage": "content.workshop.woodland_cottage", "cottage-blue": "content.workshop.sea_blue_cottage", "cottage-large": "content.workshop.porch_house", "camp-grill": "content.workshop.barbecue_grill"}

static func describe(key: String) -> Dictionary:
	var parts := key.split("_")
	var prefix := parts[0]
	if prefix in ["down", "left", "right", "up"]:
		return {"group": LocalText.source("content.workshop.appearance") if key.ends_with("_0") else LocalText.source("content.workshop.movement"), "action": LocalText.source("content.workshop.standing") if key.ends_with("_0") else LocalText.source("content.workshop.walking"), "direction": prefix}
	if prefix == "blink": return {"group": LocalText.source("content.workshop.appearance"), "action": LocalText.source("content.workshop.blinking"), "direction": parts[1]}
	if prefix == "think": return {"group": LocalText.source("content.workshop.daily_life"), "action": LocalText.source("content.workshop.crouching_to_think"), "direction": parts[1]}
	if prefix == "fire":return {"group":LocalText.source("content.workshop.daily_life"),"action":{"squat":LocalText.source("content.workshop.warming_hands_by_the_fire"),"sit":LocalText.source("content.workshop.sitting_by_the_fire"),"eat":LocalText.source("content.workshop.eating_by_the_fire")}.get(parts[1],LocalText.source("content.workshop.by_the_fire")),"direction":parts[2]}
	if prefix in ["chop", "carry", "pickup"]:
		return {"group": LocalText.source("content.workshop.work"), "action": {"chop": LocalText.source("content.workshop.chopping"), "carry": LocalText.source("content.workshop.carrying"), "pickup": LocalText.source("content.workshop.pick_up_put_down")}[prefix], "direction": parts[1]}
	if prefix in ["lighting", "grilling"]: return {"group": LocalText.source("content.workshop.work"), "action": LocalText.source("content.workshop.lighting_a_fire") if prefix == "lighting" else LocalText.source("content.workshop.turning_food"), "direction": ""}
	if prefix in ["sitting", "seated", "standing"]: return {"group": LocalText.source("content.workshop.daily_life"), "action": LocalText.source("content.workshop.dining_together"), "direction": ""}
	if prefix == "eating": return {"group": LocalText.source("content.workshop.daily_life"), "action": LocalText.source("content.workshop.legacy_meal_frames"), "direction": ""}
	if prefix == "rest": return {"group": LocalText.source("content.workshop.daily_life"), "action": LocalText.source("content.workshop.resting_empty_handed"), "direction": ""}
	return {"group": LocalText.source("content.workshop.daily_life"), "action": LocalText.source("content.workshop.custom_action"), "direction": ""}

static func frames(art: Dictionary, group: String, action: String = "", direction: String = "*") -> Array:
	group=LocalText.source(group) if group.begins_with("content.workshop.") else group
	action=LocalText.source(action) if action.begins_with("content.workshop.") else action
	var result: Array = []
	for key in art.frames:
		var info := describe(key)
		if group == LocalText.source("content.workshop.movement") and key in ["down_0", "left_0", "right_0", "up_0"]: info.group = LocalText.source("content.workshop.movement"); info.action = LocalText.source("content.workshop.walking")
		if info.group == group and (action.is_empty() or info.action == action) and (direction == "*" or info.direction == direction): result.append(key)
	return result

static func label(key: String) -> String:
	if key.begins_with("stage_"): return [LocalText.text("content.workshop.foundation"), LocalText.text("content.workshop.frame"), LocalText.text("content.workshop.walls"), LocalText.text("content.workshop.roof"), LocalText.text("content.workshop.finished_appearance")][int(key.get_slice("_", 1))]
	var labels := {"idle":LocalText.text("content.workshop.idle"),"active":LocalText.text("content.workshop.in_use"),"seedling":LocalText.text("content.workshop.seedling"), "growing":LocalText.text("content.workshop.growing"), "mature":LocalText.text("content.workshop.mature"),"down": LocalText.text("content.workshop.front"), "up": LocalText.text("content.workshop.back"), "cold": LocalText.text("content.workshop.unused"), "lit": LocalText.text("content.workshop.lighting_a_fire"), "cooking": LocalText.text("content.workshop.grilling"), "embers": LocalText.text("content.workshop.embers"), "sitting_down": LocalText.text("content.workshop.sit_down"), "seated_idle": LocalText.text("content.workshop.sit_quietly"), "seated_bite": LocalText.text("content.workshop.take_a_bite"), "seated_left": LocalText.text("content.workshop.look_left"), "seated_right": LocalText.text("content.workshop.look_right"), "standing_up": LocalText.text("content.workshop.stand_up"), "rest_empty": LocalText.text("content.workshop.resting_empty_handed")}
	if labels.has(key): return labels[key]
	var info := describe(key)
	if key.begins_with("chop_"): return [LocalText.text("content.workshop.raise_axe"), LocalText.text("content.workshop.strike"), LocalText.text("content.workshop.lower_axe")][int(key.get_slice("_", 2))]
	if key.begins_with("carry_") and key.get_slice_count("_") == 2: return LocalText.text("content.workshop.hold_wood")
	if key.begins_with("blink_"): return LocalText.text("content.workshop.eyes_closed")
	if key.begins_with("pickup_"): return LocalText.text("content.workshop.bend_down")
	return LocalText.content(info.action) + " · " + key.get_slice("_", key.get_slice_count("_") - 1) if info.action != LocalText.source("content.workshop.custom_action") else key

static func preview_frames(art: Dictionary, key: String) -> Array:
	if art.get("facility_type")=="recreation":return ["idle","active"]
	if art.get("kind") == "plant": return ["seedling","growing","mature"]
	if art.get("facility_type") == "furniture": return ["down", "up"].filter(func(value): return art.frames.has(value))
	var result: Array = [key]
	var prefix := key.get_slice("_", 0)
	var direction := key.get_slice("_", 1)
	if prefix in ["down", "left", "right", "up"]: result = [prefix + "_0", prefix + "_1", prefix + "_0", prefix + "_2"]
	elif prefix == "chop": result = ["chop_" + direction + "_0", "chop_" + direction + "_0", "chop_" + direction + "_1", "chop_" + direction + "_2"]
	elif prefix == "carry": result = ["carry_" + direction + "_0", "carry_" + direction + "_1"]
	elif prefix == "think": result = ["think_" + direction + "_0", "think_" + direction + "_1", "think_" + direction + "_2"]
	elif prefix == "fire":result=art.frames.keys().filter(func(frame):return frame.begins_with(key.rsplit("_",true,1)[0]+"_"))
	elif prefix in ["sitting", "seated", "standing"]: result = ["sitting_down", "seated_idle", "seated_bite", "seated_idle", "seated_left", "seated_right", "standing_up"]
	elif prefix in ["lighting", "grilling", "eating"]: result = [prefix + "_0", prefix + "_1"]
	elif prefix == "stage": result = ["stage_0", "stage_1", "stage_2", "stage_3", "stage_4"]
	elif art.get("kind") == "facility": result = ["down", "up"] if art.get("facility_type") == "furniture" else ["cold", "lit", "cooking", "embers"]
	return result.filter(func(value): return art.frames.has(value))

static var _bundled_names:Dictionary={}
static func work_name(art:Dictionary,fallback:String="")->String:
	var id:String=str(art.get("id",fallback));var name:String=str(art.get("name",fallback))
	if not _bundled_names.has(id):
		var paths:Array=["res://content/characters/%s.json" % id,"res://content/works/%s.json" % id,"res://content/home-v3/works/%s.json" % id]
		if id.begins_with("v3-roof-"):paths.append("res://content/home-v3/works/houses/%s.json"%id.trim_prefix("v3-roof-"))
		_bundled_names[id]=""
		for path in paths:
			if not FileAccess.file_exists(path):continue
			var source:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
			if source is Dictionary and str(source.get("id",""))==id:_bundled_names[id]=str(source.get("name",""));break
	if NAMES.has(id) and name in [str(_bundled_names[id]),LocalText.source(str(NAMES[id]))]:return LocalText.text(str(NAMES[id]))
	if not str(_bundled_names[id]).is_empty() and name==str(_bundled_names[id]):return LocalText.content(name)
	return name
