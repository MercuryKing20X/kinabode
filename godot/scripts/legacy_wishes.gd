extends RefCounted
## Validate retired save metadata and retained historical memory facts.
const TEMPLATE_IDS=["soup","pumpkin","salad","bean-cream","ribbon-mint","chair","sit","flowerbed"]

static func valid_saved(world:RefCounted,data: Variant,actors: Dictionary) -> bool:
	if not data is Dictionary or data.get("version")!=1 or not data.get("states") is Dictionary or data.states.size()>actors.size():return false
	for id in data.states:
		var state: Variant=data.states[id]
		if id=="human" or not actors.has(id) or not state is Dictionary or state.size()!=4 or not state.get("active") is Dictionary or not state.get("history") is Array or state.history.size()>2 or not state.history.all(func(key):return key in TEMPLATE_IDS):return false
		if not world.relationships.integer(state.get("last_created_day"),1000000) or state.last_created_day<1 or not world.relationships.integer(state.get("next_day"),1000003) or (state.next_day-state.last_created_day!=2 and state.next_day-state.last_created_day!=3):return false
		var wish: Dictionary=state.active
		if wish.is_empty():continue
		if wish.size()!=9 or not wish.get("id") is String or not wish.id.begins_with("wish-") or wish.id.length()!=29 or not wish.id.substr(5).is_valid_hex_number(false) or wish.get("resident_id")!=id or wish.get("template_id") not in TEMPLATE_IDS or not wish.get("target_id") is String or wish.target_id.length()<1 or wish.target_id.length()>128:return false
		if not world.relationships.integer(wish.get("created_day"),1000000) or wish.created_day!=state.last_created_day or not world.relationships.integer(wish.get("expires_day"),1000014) or wish.expires_day-wish.created_day<1 or wish.expires_day-wish.created_day>14 or not wish.get("announced") is bool or not wish.get("baseline") is Array or wish.baseline.size()>512 or not wish.baseline.all(func(key):return key is String and key.length()<=128) or not wish.get("proof_id") is String or wish.proof_id.length()>128:return false
	return true
