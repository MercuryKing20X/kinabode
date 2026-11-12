class_name OutfitRules
extends RefCounted

# Masks refer to existing pixels; they never replace or edit the source frame.
const PARTS := ["top", "bottom", "shoes", "head"]

static func valid(value: Variant, art: Dictionary) -> bool:
	if not value is Dictionary or art.get("kind", "character") != "character": return false
	if value.keys().any(func(key): return key not in PARTS): return false
	var count: int = int(art.width) * int(art.height)
	for name in value:
		var part: Variant = value[name]
		if not part is Dictionary or part.keys().any(func(key): return key not in ["enabled", "colors", "masks", "inherit"]): return false
		if not part.get("enabled") is bool or not part.get("colors") is Dictionary or not part.get("masks") is Dictionary: return false
		if not part.get("inherit", {}) is Dictionary: return false
		if part.colors.size() > art.palette.size() or part.masks.size() > art.frames.size(): return false
		if part.get("inherit", {}).size() > art.frames.size(): return false
		for source in part.colors:
			if not source is String or not source.is_valid_int(): return false
			var index := int(source)
			var target: Variant = part.colors[source]
			if str(index) != source or index < 0 or index >= art.palette.size(): return false
			if not (target is int or target is float) or int(target) != target or target < 0 or target >= art.palette.size(): return false
			# A palette remap must not make transparent pixels visible or vice versa.
			if (Color(art.palette[index]).a == 0.0) != (Color(art.palette[int(target)]).a == 0.0): return false
		for frame in part.masks:
			if not art.frames.has(frame) or not part.masks[frame] is Array or part.masks[frame].size() > count: return false
			var previous := -1
			for pixel in part.masks[frame]:
				if not (pixel is int or pixel is float) or int(pixel) != pixel or pixel <= previous or pixel >= count: return false
				previous = int(pixel)
		for frame in part.get("inherit", {}):
			var source: Variant = part.inherit[frame]
			if not art.frames.has(frame) or not source is String or not part.masks.has(source) or part.masks.has(frame): return false
	return true

static func colors_for_frame(art: Dictionary, frame: String) -> Dictionary:
	var result := {}
	for name in PARTS:
		var part: Dictionary = art.get("outfit", {}).get(name, {})
		if not part.get("enabled", false): continue
		var source_frame: String = part.get("inherit", {}).get(frame, frame)
		var shift := 0
		if frame.begins_with("fire_") and not part.get("masks",{}).has(source_frame) and art.frames.has(frame):
			var colors:Dictionary={}
			for sample in ["down_0","pickup_down"]:
				for pixel in part.get("masks",{}).get(sample,[]):
					for layer in art.frames.get(sample,[]):colors[int(layer.pixels[int(pixel)])]=true
			colors.erase(0)
			# New poses inherit color ownership only in the body/foot area; an explicit
			# authored mask always wins, and no palette or base pixel is mutated.
			for layer in art.frames[frame]:
				for pixel in range(layer.pixels.size()):
					var y:int=pixel/int(art.width);var x:int=pixel%int(art.width)
					if colors.has(int(layer.pixels[pixel])) and (name=="head" and y<70 or name!="head" and y>=74 and abs(x-int(art.width)/2)<27):result[pixel]=part.colors
			continue
		if frame.begins_with("think_down_") and art.get("frame_status", {}).get("frames", {}).get(frame, "") != "placeholder" and not part.get("masks", {}).has(source_frame) and part.get("masks", {}).has("pickup_down"):
			source_frame = "pickup_down"
			if frame == "think_down_1": shift = -int(art.width)
		for pixel in part.get("masks", {}).get(source_frame, []):
			var target:int=int(pixel)+shift
			if target>=0 and target<int(art.width)*int(art.height):result[target] = part.get("colors", {})
	return result
