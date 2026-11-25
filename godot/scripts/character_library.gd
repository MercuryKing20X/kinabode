class_name CharacterLibrary
extends RefCounted
const LocalText=preload("res://scripts/localization.gd")

const Blueprint = preload("res://scripts/blueprint_rules.gd")
const OutfitRules = preload("res://scripts/outfit_rules.gd")
var _resident_owner: WeakRef
var resident_world: RefCounted:
	get:return _resident_owner.get_ref() if _resident_owner!=null else null
	set(value):_resident_owner=weakref(value) if value!=null else null
var artworks: Dictionary = {}
var textures: Dictionary = {}
var history: Dictionary = {}
var directory := ""

func configure(data_directory: String) -> void:
	directory = data_directory.path_join("characters")
	DirAccess.make_dir_recursive_absolute(directory)
	var character_ids: Array = ["human-starter", "white-haired-girl", "blue-haired-girl", "orange-haired-girl", "black-scarf-girl"]
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/characters/spare-catalog.json"))
	if catalog is Dictionary and catalog.get("version") == 1 and catalog.get("character_ids") is Array:
		for id in catalog.character_ids:
			if id is String and safe_id(id) and not character_ids.has(id): character_ids.append(id)
	var ids: Array = character_ids + ["cottage", "cottage-large", "cottage-blue", "camp-grill", "furniture-table", "furniture-chair", "furniture-rug", "furniture-lamp", "crop-turnip", "crop-tomato", "crop-pumpkin", "crop-daisy", "crop-blueberry", "crop-apple", "play-swing", "play-gazebo", "play-stage", "play-gomoku", "outdoor-chair", "outdoor-path", "outdoor-flowers","produce-flowerhouse","produce-herbgarden","produce-fishrack","produce-stargarden"]
	for id in ids:
		var source := ("res://content/characters/%s.json" if id in character_ids else "res://content/works/%s.json") % id
		var saved := directory.path_join(id + ".json")
		var bundled: Variant = JSON.parse_string(FileAccess.get_file_as_string(source))
		if not bundled is Dictionary or bundled.get("id") != id or not valid(bundled):
			push_error("Invalid bundled artwork: " + str(id)); continue
		artworks[id] = bundled
		if FileAccess.file_exists(saved):
			var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(saved))
			if value is Dictionary and valid(value) and value.id == id:
				artworks[id] = value
				if id=="ai-glm":_correct_legacy_glm(artworks[id])
			else: DirAccess.copy_absolute(saved, saved + ".invalid-%s" % Time.get_ticks_usec())
		# Add new action frames without replacing any previously edited frame.
		for key in bundled.frames:
			if not artworks[id].frames.has(key): _import_frame(artworks[id], bundled, key)

	for filename in DirAccess.get_files_at(directory):
		if not filename.ends_with(".json"):continue
		var value: Variant=JSON.parse_string(FileAccess.get_file_as_string(directory.path_join(filename)))
		if value is Dictionary and valid(value) and filename==str(value.id)+".json" and not artworks.has(value.id):artworks[value.id]=value

func _correct_legacy_glm(art:Dictionary)->void:
	# Correct only untouched legacy source-frame pairs in memory.  Never write
	# player artwork, and leave any independently edited pair exactly as-is.
	var manifest:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/characters/glm_legacy_direction_hashes.json"))
	if not manifest is Dictionary:return
	for pair in manifest.get("pairs",[]):
		var a:String=pair.left;var b:String=pair.right
		if not art.frames.has(a) or not art.frames.has(b) or art.frames[a].size()!=1 or art.frames[b].size()!=1:continue
		if art.frames[a][0].get("name")!=LocalText.source("content.remaining.character") or art.frames[b][0].get("name")!=LocalText.source("content.remaining.character") or art.frames[a][0].get("visible",false)!=true or art.frames[b][0].get("visible",false)!=true:continue
		var left:PackedByteArray=PackedByteArray(art.frames[a][0].pixels)
		var right:PackedByteArray=PackedByteArray(art.frames[b][0].pixels)
		if left.hex_encode().sha256_text()!=pair.left_pixels or right.hex_encode().sha256_text()!=pair.right_pixels:continue
		var original:Variant=art.frames[a];art.frames[a]=art.frames[b];art.frames[b]=original
		var status:Variant=art.get("frame_status",{})
		if status is Dictionary:
			var states:Variant=status.get("frames",{})
			if states is Dictionary and states.has(a) and states.has(b):
				var old_status:Variant=states[a];states[a]=states[b];states[b]=old_status

func valid(art: Dictionary) -> bool:
	if art.get("schema_version") != 1 or not art.get("id") is String or not art.get("frames") is Dictionary or not art.get("palette") is Array: return false
	if not safe_id(str(art.id)):return false
	if art.has("name") and (not art.name is String or art.name.length()>64):return false
	if not _integer(art.get("width"), 1, 256) or not _integer(art.get("height"), 1, 256) or not _integer(art.get("revision"), 1, 100000000): return false
	if art.palette.is_empty() or art.palette.size() > 4096: return false
	for color in art.palette:
		if not color is String or not Color.html_is_valid(color): return false
	if not art.get("anchor") is Array or art.anchor.size() != 2: return false
	if not _integer(art.anchor[0], 0, int(art.width)) or not _integer(art.anchor[1], 0, int(art.height)): return false
	var kind := str(art.get("kind", "character"))
	if kind not in ["character", "building", "facility", "plant"]: return false
	if art.has("outfit") and not OutfitRules.valid(art.outfit, art): return false
	if kind == "character":
		for direction in ["down", "left", "right", "up"]:
			for frame in range(3):
				if not art.frames.has("%s_%s" % [direction, frame]): return false
	elif kind == "building":
		if not Blueprint.valid_structure(art.get("structure")): return false
		for stage in range(5):
			if not art.frames.has("stage_%s" % stage): return false
	elif kind == "plant":
		for stage in ["seedling","growing","mature"]:
			if not art.frames.has(stage): return false
	elif kind == "facility":
		if art.get("facility_type")=="recreation" and not preload("res://scripts/leisure_rules.gd").valid(art.get("recreation")):return false
		if art.get("recreation",{}).has("board_rect"):
			var box: Array=art.recreation.board_rect
			if box[0]+box[2]>art.width or box[1]+box[3]>art.height:return false
		for state in (["idle","active"] if art.get("facility_type")=="recreation" else ["down", "up"] if art.get("facility_type") == "furniture" else ["cold", "lit", "cooking", "embers"]):
			if not art.frames.has(state): return false
	if art.has("recreation") and (kind!="facility" or art.get("facility_type")!="recreation"):return false
	for rig in art.get("recreation",{}).get("rigs",[]):
		if rig.rect[0]+rig.rect[2]>art.width or rig.rect[1]+rig.rect[3]>art.height:return false
		for p in [rig.pivot,rig.seat]:
			if p[0]<0 or p[1]<0 or p[0]>art.width or p[1]>art.height:return false
	if art.frames.size() > 80: return false
	for key in art.frames:
		var layers: Variant = art.frames[key]
		if not layers is Array or layers.is_empty() or layers.size() > 16: return false
		for layer in layers:
			if not layer is Dictionary or not layer.get("name") is String or not layer.get("visible") is bool or not layer.get("pixels") is Array or layer.pixels.size() != int(art.width) * int(art.height): return false
			for pixel in layer.pixels:
				if not (pixel is int or pixel is float) or int(pixel) != pixel or pixel < 0 or pixel >= art.palette.size(): return false
	return true

func visual_appearance(actor: Dictionary) -> String:
	var id := str(actor.get("appearance_id", "human-starter"))
	if artworks.has(id): return id
	if resident_world != null:
		var fallback: String = resident_world.residents.appearance_for(str(actor.get("id", "")), "human-starter")
		if artworks.has(fallback): return fallback
	return "human-starter"

func render(art: Dictionary, frame: String) -> Image:
	var image := Image.create(int(art.width), int(art.height), false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var colors: Array[Color] = []
	for value in art.palette: colors.append(Color(value))
	var replacements := OutfitRules.colors_for_frame(art, frame)
	for layer in art.frames.get(frame, []):
		if not layer.get("visible", true): continue
		if replacements.is_empty():
			for index in range(layer.pixels.size()):
				var color: Color = colors[int(layer.pixels[index])]
				if color.a <= 0: continue
				var x := index % int(art.width)
				var y := index / int(art.width)
				image.set_pixel(x, y, image.get_pixel(x, y).blend(color))
			continue
		for index in range(layer.pixels.size()):
			var source: int = int(layer.pixels[index])
			if replacements.has(index): source = int(replacements[index].get(str(source), source))
			var color: Color = colors[source]
			if color.a <= 0: continue
			var x := index % int(art.width)
			var y := index / int(art.width)
			image.set_pixel(x, y, image.get_pixel(x, y).blend(color))
	return image

func texture(id: String, frame: String) -> Texture2D:
	var art: Dictionary = artworks[id]
	var key := "%s:%s:%s" % [id, art.revision, frame]
	if not textures.has(key): textures[key] = ImageTexture.create_from_image(render(art, frame))
	return textures[key]

func publish(art: Dictionary, expected_revision: int) -> Dictionary:
	if not valid(art) or not artworks.has(art.id): return {"ok": false, "error": "invalid_artwork"}
	var current: Dictionary = artworks[art.id]
	if art.get("kind", "character") != current.get("kind", "character"): return {"ok": false, "error": "artwork_kind_changed"}
	if int(current.revision) != expected_revision: return {"ok": false, "error": "stale_artwork", "message": LocalText.text("content.remaining.another_edit_updated_this_character_reload_before_editing_again")}
	var next: Dictionary = art.duplicate(true)
	next.revision = expected_revision + 1
	var path := directory.path_join(art.id + ".json")
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: return {"ok": false, "error": "save_failed"}
	file.store_string(JSON.stringify(next)); file.close()
	if DirAccess.rename_absolute(path + ".tmp", path) != OK: return {"ok": false, "error": "save_failed"}
	if not history.has(art.id): history[art.id] = []
	history[art.id].append(current.duplicate(true))
	if history[art.id].size() > 10: history[art.id].pop_front()
	artworks[art.id] = next
	textures.clear()
	return {"ok": true, "revision": next.revision}

func undo_publish(id: String) -> Dictionary:
	if history.get(id, []).is_empty(): return {"ok": false, "error": "no_history"}
	var previous: Dictionary = history[id].pop_back()
	var saved_history: Array = history[id].duplicate(true)
	var result := publish(previous, int(artworks[id].revision))
	history[id] = saved_history
	return result

func read_frame(id: String, frame: String) -> Dictionary:
	if not artworks.has(id) or not artworks[id].frames.has(frame): return {"ok": false, "error": "unknown_artwork_frame"}
	var art: Dictionary = artworks[id]
	return {"ok": true, "artwork_id": id, "revision": art.revision, "width": art.width, "height": art.height, "palette": art.palette.duplicate(), "frame": frame, "layers": art.frames[frame].duplicate(true), "kind": art.get("kind", "character"), "structure": art.get("structure", {}).duplicate(true)}

func patch(id: String, request: Dictionary) -> Dictionary:
	if not artworks.has(id): return {"ok": false, "error": "unknown_artwork"}
	var art: Dictionary = artworks[id].duplicate(true)
	if request.get("base_revision") != art.revision: return {"ok": false, "error": "stale_artwork"}
	if request.has("outfit"):
		if request.has("pixels") or request.has("structure") or request.has("recreation") or not OutfitRules.valid(request.outfit, art):
			return {"ok": false, "error": "invalid_outfit"}
		art.outfit = request.outfit.duplicate(true)
		return publish(art, int(request.base_revision))
	if request.has("recreation"):
		if art.get("facility_type")!="recreation" or not preload("res://scripts/leisure_rules.gd").valid(request.recreation):return {"ok":false,"error":"invalid_recreation"}
		art.recreation=request.recreation.duplicate(true)
		if not request.has("pixels"):return publish(art,int(request.base_revision))
	if request.has("structure"):
		if art.get("kind") != "building" or not Blueprint.valid_structure(request.structure): return {"ok": false, "error": "invalid_structure"}
		art.structure = request.structure.duplicate(true)
		if not request.has("pixels"): return publish(art, int(request.base_revision))
	var frame := str(request.get("frame", ""))
	if not _integer(request.get("layer"), 0, 15): return {"ok": false, "error": "invalid_layer"}
	var layer_index: int = int(request.layer)
	var edits: Variant = request.get("pixels", [])
	if not art.frames.has(frame) or layer_index < 0 or layer_index >= art.frames[frame].size() or not edits is Array or edits.is_empty() or edits.size() > 1024: return {"ok": false, "error": "invalid_patch"}
	for edit in edits:
		if not edit is Dictionary or not _integer(edit.get("x"), 0, int(art.width) - 1) or not _integer(edit.get("y"), 0, int(art.height) - 1) or not edit.get("color") is String or not Color.html_is_valid(edit.color): return {"ok": false, "error": "invalid_pixel"}
		var color := Color(edit.color).to_html(true)
		color = "#" + color
		var index: int = art.palette.find(color)
		if index < 0:
			index = art.palette.size()
			art.palette.append(color)
		art.frames[frame][layer_index].pixels[int(edit.y) * int(art.width) + int(edit.x)] = index
	return publish(art, int(request.base_revision))

func ensure_resident(id: String) -> String:
	var artwork_id := "resident-" + id
	if artworks.has(artwork_id): return artwork_id
	var source_id := "white-haired-girl" if id in ["npc.mira","npc.nora"] else "human-starter"
	var art: Dictionary = artworks[source_id].duplicate(true)
	art["name"] = LocalText.source("content.remaining.skye") if id == "companion-2" else id
	for index in range(1, art.palette.size()):
		var color := Color(art.palette[index])
		if id in ["npc.mira","npc.nora"] and color.r>.65 and color.g>.65 and color.b>.65:
			var tint := Color("e9b9ca") if id=="npc.mira" else Color("c4bce5")
			color=Color(color.r*tint.r,color.g*tint.g,color.b*tint.b,color.a)
		elif id=="npc.luca" and color.r>color.b*1.3 and color.g>color.b*1.1: color=Color(color.g*.67,color.r*.85,color.b*.8,color.a)
		elif not id.begins_with("npc.") and color.r > color.b * 1.3 and color.g > color.b * 1.1: color = Color(color.b * .9, color.g * .92, color.r * .85, color.a)
		art.palette[index] = "#" + color.to_html(true)
	art.id = artwork_id
	art.revision = 1
	var path := directory.path_join(artwork_id + ".json")
	if FileAccess.file_exists(path):
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if saved is Dictionary and saved.get("id") == artwork_id and valid(saved): art = saved
	var bundled: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/characters/%s.json" % source_id))
	for key in bundled.frames:
		if not art.frames.has(key): _import_frame(art, bundled, key)
	artworks[artwork_id] = art
	return artwork_id

func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == floor(float(value)) and value >= low and value <= high

func _import_frame(target: Dictionary, source: Dictionary, key: String) -> void:
	# Different-size player canvases keep their own animation set and fall back
	# to their existing idle frame. Never insert malformed pixel arrays.
	if int(target.width) != int(source.width) or int(target.height) != int(source.height): return
	var used: Dictionary = {}
	for layer in source.frames[key]:
		for pixel in layer.pixels: used[int(pixel)] = true
	var next_palette: Array = target.palette.duplicate()
	var mapping: Dictionary = {}
	for pixel in used:
		var color: String = source.palette[pixel]
		var index := next_palette.find(color)
		if index < 0:
			index = next_palette.size()
			next_palette.append(color)
		mapping[pixel] = index
	if next_palette.size() > 4096: return
	var layers: Array = source.frames[key].duplicate(true)
	for layer in layers:
		for index in range(layer.pixels.size()): layer.pixels[index] = mapping[int(layer.pixels[index])]
	target.palette = next_palette
	target.frames[key] = layers
	if source.get("frame_status",{}).get("frames",{}).has(key):
		if not target.has("frame_status"):target["frame_status"]={}
		if not target.frame_status.has("frames"):target.frame_status["frames"]={}
		target.frame_status.frames[key]=source.frame_status.frames[key]

func compile_blueprint(id: String) -> Dictionary:
	if not artworks.has(id): return {"ok": false, "error": "unknown_artwork"}
	var art: Dictionary = artworks[id]
	if art.get("kind") != "building" or not valid(art): return {"ok": false, "error": "invalid_building"}
	var quote := Blueprint.quote(art.structure)
	return {"ok": true, "id": id, "revision": art.revision, "structure": art.structure.duplicate(true), "stages": quote.stages, "wood": quote.wood, "artwork": art.duplicate(true)}

func frozen_texture(art: Dictionary, frame: String) -> Texture2D:
	var key := "frozen:%s:%s:%s" % [art.id, art.revision, frame]
	if not textures.has(key): textures[key] = ImageTexture.create_from_image(render(art, frame))
	return textures[key]

func read_work(query: Dictionary) -> Dictionary:
	var id := str(query.get("artwork_id", ""))
	if not artworks.has(id): return {"ok": false, "error": "unknown_artwork"}
	var art: Dictionary = artworks[id]
	var frame := str(query.get("frame", art.frames.keys()[0]))
	if not art.frames.has(frame): return {"ok": false, "error": "unknown_frame"}
	var x: Variant = query.get("x", 0)
	var y: Variant = query.get("y", 0)
	if not _integer(x, 0, int(art.width) - 1) or not _integer(y, 0, int(art.height) - 1): return {"ok": false, "error": "invalid_region"}
	if query.has("revision") and query.revision != art.revision: return {"ok": false, "error": "stale_artwork"}
	var width := mini(24, int(art.width) - int(x))
	var height := mini(24, int(art.height) - int(y))
	var layers: Array = []
	for layer in art.frames[frame]:
		var pixels: Array = []
		for row in range(height):
			for col in range(width): pixels.append(layer.pixels[(int(y) + row) * int(art.width) + int(x) + col])
		layers.append({"id": layer.get("id","layer"), "name": layer.name, "visible": layer.visible, "pixels": pixels})
	return {"ok": true, "artwork_id": id, "kind": art.get("kind", "character"), "revision": art.revision, "width": art.width, "height": art.height, "frames": art.frames.keys(), "frame": frame, "palette": art.palette.duplicate(), "region": {"x": x, "y": y, "width": width, "height": height}, "layers": layers, "structure": art.get("structure", {}).duplicate(true), "recreation":art.get("recreation",{}).duplicate(true), "complete": width == art.width and height == art.height, "note": "24x24 pixel window; request other x/y with same revision for more. Patch uses absolute artwork coordinates."}

func safe_id(value: String) -> bool:
	if value.is_empty() or value.length()>64:return false
	for c in value:
		if not c in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.":return false
	return value!="." and value!=".." and not value.begins_with(".")
func display_name(id: String) -> String:
	var art: Dictionary=artworks.get(id,{})
	if "spare" in art.get("tags", []): return preload("res://scripts/workshop_catalog.gd").work_name(art,id) + LocalText.text("content.remaining.spare_suffix")
	if resident_world!=null:
		for actor in resident_world.actors.values():
			if actor.appearance_id==id:return LocalText.resident(resident_world,str(actor.id))
	if art.get("kind","character")=="character" and preload("res://scripts/workshop_catalog.gd").NAMES.has(id):return preload("res://scripts/workshop_catalog.gd").work_name(art,id)
	return str(art.get("name",id))
func create_work(source: Dictionary,blank: bool = false) -> Dictionary:
	var next: Dictionary=source.duplicate(true);next.id="custom-"+str(Time.get_ticks_usec());next.revision=1;next.name=str(next.get("name",LocalText.source("content.remaining.work")))+LocalText.source("content.remaining.copy")
	if next.get("tags", []) is Array: next["tags"] = next.get("tags", []).filter(func(tag): return tag not in ["spare", LocalText.source("content.remaining.spare")])
	if blank:
		next.name=LocalText.source("content.remaining.new_work")
		for layers in next.frames.values():
			for layer in layers:layer.pixels.fill(0)
	if not valid(next):return {"ok":false,"error":"invalid_artwork"}
	var file:=FileAccess.open(directory.path_join(next.id+".json"),FileAccess.WRITE)
	if file==null:return {"ok":false,"error":"save_failed"}
	file.store_string(JSON.stringify(next));file.close();artworks[next.id]=next
	return {"ok":true,"id":next.id}
func import_work(path: String) -> Dictionary:
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>8*1024*1024:return {"ok":false,"error":"invalid_file"}
	var value: Variant=JSON.parse_string(file.get_as_text());file.close()
	if not value is Dictionary or not valid(value):return {"ok":false,"error":"invalid_artwork"}
	return create_work(value)
func export_work(art: Dictionary,path: String) -> bool:
	if not valid(art):return false
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return false
	file.store_string(JSON.stringify(art));file.close();return true
