class_name CharacterAssembler
extends RefCounted
const LocalText=preload("res://scripts/localization.gd")

const PARTS := ["head", "hair", "top", "bottom", "shoes", "accessory"]
const RANGES := {"head": [48, 73], "hair": [18, 49], "top": [73, 89], "bottom": [89, 109], "shoes": [109, 128], "accessory": [55, 70]}
static var PRESETS := {
	LocalText.source("content.remaining.girl"): {"head":"blue-haired-girl", "hair":"blue-haired-girl", "top":"orange-haired-girl", "bottom":"orange-haired-girl", "shoes":"blue-haired-girl", "accessory":"blue-haired-girl"},
	LocalText.source("content.remaining.boy"): {"head":"human-starter", "hair":"human-starter", "top":"human-starter", "bottom":"human-starter", "shoes":"black-scarf-girl", "accessory":"human-starter"},
	LocalText.source("content.remaining.villager"): {"head":"orange-haired-girl", "hair":"orange-haired-girl", "top":"orange-haired-girl", "bottom":"blue-haired-girl", "shoes":"orange-haired-girl", "accessory":"orange-haired-girl"},
	LocalText.source("content.remaining.lighthouse_keeper"): {"head":"black-scarf-girl", "hair":"black-scarf-girl", "top":"black-scarf-girl", "bottom":"human-starter", "shoes":"black-scarf-girl", "accessory":"black-scarf-girl"}
}

static func assemble(library: RefCounted, parts: Dictionary, preset_name: String) -> Dictionary:
	for part in PARTS:
		if not parts.has(part) or not library.artworks.has(parts[part]): return {"ok":false,"error":"missing_part"}
		var donor: Dictionary = library.artworks[parts[part]]
		if donor.get("kind", "character") != "character" or donor.width != 96 or donor.height != 128: return {"ok":false,"error":"incompatible_part"}
	var base: Dictionary = library.artworks[parts.head].duplicate(true)
	base.erase("outfit"); base.name = preset_name
	for frame in base.frames.keys():
		for part in PARTS:
			if not library.artworks[parts[part]].frames.has(frame): base.frames.erase(frame); break
	if base.frames.size() < 40: return {"ok":false,"error":"missing_required_frames"}
	var maps := {}
	for part in PARTS:
		var donor: Dictionary = library.artworks[parts[part]]
		var mapping: Array = []
		for color in donor.palette:
			var index: int = base.palette.find(color)
			if index < 0:
				if base.palette.size() >= 4096: return {"ok":false,"error":"palette_full"}
				index = base.palette.size(); base.palette.append(color)
			mapping.append(index)
		maps[part] = mapping
	for frame in base.frames:
		var layers: Array = base.frames[frame]
		if layers.size() != 1: return {"ok":false,"error":"layered_source_not_supported"}
		var pixels: Array = layers[0].pixels
		for part in PARTS:
			var donor: Dictionary = library.artworks[parts[part]]
			if donor.frames[frame].size() != 1: return {"ok":false,"error":"layered_source_not_supported"}
			var source: Array = donor.frames[frame][0].pixels
			for y in range(RANGES[part][0], RANGES[part][1]):
				for x in range(96):
					var at := y * 96 + x
					if int(source[at]) != 0: pixels[at] = maps[part][int(source[at])]
	return library.create_work(base)
