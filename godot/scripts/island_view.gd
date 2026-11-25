class_name IslandView
extends Node2D
signal need_clicked(actor_id:String,kind:String)
signal mind_clicked(actor_id:String)
signal care_clicked(actor_id:String)
var play_stage:Node
var play_rendered:Dictionary={}
var inspect_actor_frames:=false
var submitted_actor_frames:Dictionary={}
var photo_poses:Dictionary={}
var cat_contact_art=preload("res://scripts/cat_contact_art.gd").new()
const LocalText=preload("res://scripts/localization.gd")
const Places = preload("res://scripts/map_locations.gd")

var dark_renderer:=preload("res://scripts/dark_island_renderer.gd").new()
var fishing_renderer := preload("res://scripts/fishing_renderer.gd").new()
var leisure_renderer := preload("res://scripts/leisure_renderer.gd").new()
var homestead_renderer := preload("res://scripts/homestead_renderer.gd").new()
var farm_renderer := preload("res://scripts/farm_renderer.gd").new()
const Room = preload("res://scripts/room_renderer.gd")
var room_renderer := Room.new()
var region_id := "home"
var last_human_region := "home"
var placement_recipe := ""
const Layout = preload("res://scripts/home_layout.gd")
var scenery: Array = []
const Ambience = preload("res://scripts/environment_motion.gd")
var camp_textures: Dictionary = {}
const Motion = preload("res://scripts/actor_motion.gd")
const MealMotion=preload("res://scripts/meal_motion.gd")
const ActionAtlases=preload("res://scripts/motion_atlas.gd")
var action_atlases:=ActionAtlases.new()
var motion := Motion.new()
var hungry_onlooker:=preload("res://scripts/hungry_onlooker.gd").new()
var effects: Array = []
var last_visual_serial := 0
var memory_photo:=false
var sound_enabled := true
var sounds: Dictionary = {}
var foliage_alpha: Dictionary = {}

signal clicked(object_id: String, local_position: Vector2)
var world: RefCounted
var library: RefCounted
var font: Font
var center := Places.point("p_49_48")
var zoom := 0.62
var camera_defaults:=preload("res://scripts/camera_defaults.gd").new()
var clock := 0.0
var textures: Dictionary = {}
var alpha_images: Dictionary = {}
var hover_id := ""
var selected_id := ""
var dragging := false
var follow_player := true
var follow_actor := "human"
var peek_elapsed:=0.0
var chess_overlay := false
var resident_head_heights:Dictionary={}
var thought_rendered:Array=[]
var speech_actor := "codex"
var speech := ""
var speech_source := "model"
var speech_by_actor: Dictionary={}
var consultation_sidebar:Control
var speech_until := 0.0
var hunger_symbols:Dictionary={}
var heart_symbols:Array=[]
var atmosphere=preload("res://scripts/island_ambience.gd").new()
const Emotes=preload("res://scripts/pixel_emotes.gd")
var face_overlays=preload("res://scripts/face_overlays.gd").new()
const REACTION_MARK={"pat":"heart","happy":"spark","hurt":"rain","surprise":"alert","shy":"heart","sleep":"sleep","wince":"anger"}

func visible_reaction(id:String)->Dictionary:
	var event:Dictionary=world.hearts.reactions.get(id,{})
	var age:float=world.director.time-float(event.get("at",-100))
	if age>=0 and age<2.5:return {"cue":event.cue,"age":age}
	var period:float=float(world.hearts.config.symbol_period)
	age=fposmod(clock+float(abs(id.hash())%11),period)
	if age>=2.5:return {}
	var activity:String=world.actors[id].activity
	var brain:RefCounted=world.director.brains.get(id)
	if activity in ["local_rest","play_lie"] and brain!=null and brain.current.get("action")=="night_rest":return {"cue":"sleep","age":age}
	if world.hunger.rank(id)>=2:return {"cue":"hungry","age":age}
	if world.hearts.symbol(id,clock).is_empty():return {}
	var axis:String=world.hearts.dominant(id)
	return {"cue":{"joy":"happy","hurt":"hurt","tired":"sleep","curious":"surprise"}.get(axis,""),"mark":Emotes.MOODS[axis],"age":age}
var gesture_symbols:Array=[]
var gesture_symbol_bounds:Dictionary={}

func _ready() -> void:
	for kind in (["hit", "fall", "pickup", "deposit", "breeze", "fire", "moon_tide", "fish_splash", "fish_bite", "gomoku_stone"] if sound_enabled else []):
		var player := AudioStreamPlayer.new()
		player.stream = load("res://assets/audio/%s.wav" % kind)
		if kind in ["breeze", "fire", "moon_tide"]:
			player.stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			player.stream.loop_end = int(player.stream.get_length() * player.stream.mix_rate)
		player.volume_db = -22
		add_child(player)
		sounds[kind] = player
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for name in ["grass", "sand", "soil", "water", "oak", "oak_small", "birch", "fir", "chest", "stump", "bush", "rock", "fence_h", "fence_v", "gate", "grass_clump", "flowers", "barrel", "logs", "axe", "stool", "mushrooms", "meal", "picnic", "smoke"]:
		textures[name] = load("res://assets/island/%s.png" % name)
	for i in range(6): textures["house_%s" % i] = load("res://assets/island/house_%s.png" % i)
	textures["cooking-pot"]=load("res://assets/island/cooking-pot.png")
	if not memory_photo:
		for name in ["oak","oak_small","birch","fir","stump"]:
			alpha_images[name]=textures[name].get_image()
	_prepare_scenery()

func screen(point: Vector2) -> Vector2:
	return (point - center) * 32.0 * zoom + get_viewport_rect().size / 2

func local_point(point: Vector2) -> Vector2:
	return (point - get_viewport_rect().size / 2) / (32.0 * zoom) + center

func _process(delta: float) -> void:
	clock += delta
	if world != null and world.actors.human.region_id != last_human_region:
		last_human_region = world.actors.human.region_id
		show_region(last_human_region)
	if world != null:
		var running := {}
		var movements:Dictionary={};var gaits:Dictionary={}
		for id in world.actors:running[id]=world.display_running(id);movements[id]=world.motion_state(id);gaits[id]=world.intelligence.gait(id)
		motion.advance(delta, world.actors, running,movements,gaits)
		var nearby_actors:Array[Vector2]=[]
		for actor in world.actors.values():
			if actor.region_id==region_id:nearby_actors.append(world.point(actor))
		var tree_clip:=get_viewport_rect().grow(400)
		for object in world.objects.values():
			if object.kind != "tree" or object.status != "mature" or object.region_id!=region_id:continue
			var at:Vector2=world.point(object)
			if not tree_clip.has_point(screen(at)):
				foliage_alpha.erase(object.id)
				continue
			var target_alpha := 1.0
			for actor_at in nearby_actors:
				var offset:=at-actor_at
				if offset.y > 0 and offset.y < 9 and absf(offset.x) < 3.7:
					target_alpha=.18
					break
			foliage_alpha[object.id] = move_toward(float(foliage_alpha.get(object.id, 1.0)), target_alpha, delta * 4)

		for event in world.work.visual_events:
			if int(event.serial) <= last_visual_serial: continue
			last_visual_serial = int(event.serial)
			var effect: Dictionary = event.duplicate(true)
			effect["started"] = clock
			effects.append(effect)
			if event.kind=="fish_caught" and event.region_id=="home":
				var fire:RefCounted=world.nearest_barbecue(event.actor_id)
				if fire!=null and world.standard.ready(fire.station.id):atmosphere.leave_trace(self,"fish",world.point(fire.station)+Vector2(2,1))
			if event.kind=="mushroom_gathered" and event.region_id=="home":
				var site_id:=""
				for home in world.objects.values():
					if home.kind!="construction_site" or int(home.stage_index)!=5:continue
					if home.get("owner_id","")=="human" and site_id.is_empty():site_id=home.id
					if home.get("owner_id","")==event.actor_id:site_id=home.id;break
				if not site_id.is_empty():atmosphere.leave_trace(self,"basket",world.interior.outside(world.interior.room_for(site_id))+Vector2(.8,0))
			if sound_enabled and sounds.has(event.kind) and visible and event.get("region_id", "home") == region_id:
				var distance: float = center.distance_to(Vector2(event.position[0], event.position[1]))
				if distance < 20:
					sounds[event.kind].volume_db = -20 - distance * .6
					sounds[event.kind].play()
		for i in range(effects.size() - 1, -1, -1):
			if clock - float(effects[i].started) > .8: effects.remove_at(i)
	if not follow_player and world!=null:
		peek_elapsed+=delta
		if peek_elapsed>=5 and not dragging:
			show_region(world.actors.get(follow_actor,world.actors.human).region_id);follow_player=true
	else:peek_elapsed=0
	if follow_player and world != null and world.actors.has(follow_actor):
		if region_id!=world.actors[follow_actor].region_id:show_region(world.actors[follow_actor].region_id)
		follow_player=true;center = world.point(world.actors[follow_actor])
	_update_ambience()
	if world!=null and world.dark!=null:dark_renderer.update(self)
	queue_redraw()

func say(text: String, source: String = "model", actor_id: String = "codex", context:String="") -> void:
	if not world.actors.has(actor_id):return
	var previous: Dictionary=speech_by_actor.get(actor_id,{})
	if source=="local_rules" and previous.get("source") in ["model","autonomy"] and float(previous.get("until",0))>clock:return
	speech_actor = actor_id
	speech_source = source
	motion.attend()
	speech = text.left(72)
	speech_until = clock + (6 if source == "local_rules" else 9)
	speech_by_actor[actor_id]={"text":speech,"source":source,"until":speech_until,"context":context}

var run_click := false
var world_placement:Control

func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(world_placement) and world_placement.map_input(event):
		get_viewport().set_input_as_handled();return
	if event is InputEventMouseButton:
		if event.pressed and event.button_index==MOUSE_BUTTON_RIGHT:
			var resident:=care_hit(event.position)
			if not resident.is_empty():
				care_clicked.emit(resident);get_viewport().set_input_as_handled();return
		if event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			dragging = event.pressed
			if dragging: peek_elapsed=0; follow_player = false; placement_recipe = ""
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			follow_player = false
			var before := local_point(event.position)
			zoom = clampf(zoom * (1.12 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1 / 1.12), 0.42, 1.5)
			center += before - local_point(event.position)
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var target:String=hit(event.position)
			if target.begins_with("island-note:") or target.begins_with("island-gift:") or (world.barbecues.has(target) and world.standard.ready(target)):
				selected_id=target
				clicked.emit(target,local_point(event.position))
				return
			for actor in world.actors.values():
				if actor.id!="human" and actor.region_id==region_id and Rect2(screen(world.point(actor))+Vector2(-22,-85)*zoom,Vector2(44,90)*zoom).has_point(event.position):
					care_clicked.emit(actor.id);get_viewport().set_input_as_handled();return
			for entry in speech_layout():
				var context:String=str(speech_by_actor.get(entry.actor_id,{}).get("context",""))
				if context.begins_with("need_") and entry.box.has_point(event.position):
					need_clicked.emit(entry.actor_id,context.trim_prefix("need_"));get_viewport().set_input_as_handled();return
			selected_id = target
			run_click = event.shift_pressed or event.double_click
			clicked.emit(selected_id, local_point(event.position))
			run_click = false
	elif event is InputEventMouseMotion:
		if dragging: center -= event.relative / (32.0 * zoom)
		hover_id = hit(event.position)

func note_rect(row:Dictionary,gift:bool)->Rect2:
	var center:Vector2=screen(world.point(row))
	var entries:Dictionary=world.island_notes.gifts if gift else world.island_notes.rows
	var order:int=int(str(row.id).get_slice(":",1))
	var slot:=0
	for other in entries.values():
		if other.position==row.position and int(str(other.id).get_slice(":",1))<order:slot+=1
	var offset:=Vector2(float(slot%4)*14.0-25.0,float(slot/4)*14.0+(4.0 if gift else -47.0))
	return Rect2(center+offset,Vector2(12,12))

func care_hit(mouse:Vector2)->String:
	var nearest:=""
	var distance:=INF
	for actor in world.actors.values():
		if actor.id=="human" or actor.region_id!=region_id:continue
		var bounds:=Rect2(screen(world.point(actor))+Vector2(-22,-85)*zoom,Vector2(44,90)*zoom)
		if not bounds.has_point(mouse):continue
		var next:=bounds.get_center().distance_squared_to(mouse)
		if next<distance:
			distance=next
			nearest=actor.id
	return nearest

func note_hit(mouse:Vector2)->String:
	if region_id!="home":return ""
	for row in world.island_notes.rows.values():
		if note_rect(row,false).has_point(mouse):return row.id
	for row in world.island_notes.gifts.values():
		if note_rect(row,true).has_point(mouse):return row.id
	return ""

func hit(mouse: Vector2) -> String:
	if world.resort!=null and world.resort.enabled():
		var resort_hit:String=preload("res://scripts/resort_renderer.gd").hit(self,mouse)
		if not resort_hit.is_empty():return resort_hit
	if world.cat!=null and preload("res://scripts/cat_companion_ui.gd").hits(self,mouse):return "pet.yuzu"
	var dark_hit:String=dark_renderer.hit(self,mouse)
	if not dark_hit.is_empty():return dark_hit
	if region_id=="dark":return ""
	if region_id != "home": return room_renderer.hit(self, mouse)
	var paper:String=note_hit(mouse)
	if not paper.is_empty():return paper
	var fishing_hit: String=fishing_renderer.hit(self,mouse)
	if not fishing_hit.is_empty():return fishing_hit
	var farm_hit: String = farm_renderer.hit(self, mouse)
	if not farm_hit.is_empty(): return farm_hit
	var homestead_area: Rect2=world.homestead.area()
	if Rect2(screen(homestead_area.position),homestead_area.size*32*zoom).has_point(mouse) and (world.homestead.site.state!="unstarted" or world.homestead.occupancy().is_empty()):return world.homestead.config.site.id
	for life in world.barbecues.values():
		if _barbecue_hit_box(life.station).has_point(mouse): return life.station.id
	for patch in world.all_mushrooms().values():
		if int(patch.amount) > 0 and screen(world.point(patch)).distance_to(mouse) < 45 * zoom: return patch.id
	var hits: Array = []
	for object in world.objects.values():
		if object.region_id != "home": continue
		if object.kind=="construction_site" and int(object.get("stage_index",0))<5 and world.resort!=null and world.resort.retired(object):continue
		var p := screen(world.point(object))
		if object.kind == "tree":
			var size := (Vector2(128, 112) * .65 if object.status == "stump" else Vector2(256, 320) * (.36 if object.status == "sapling" else 1.0)) * zoom
			var name: String = "stump" if object.status == "stump" else ["oak", "oak_small", "birch", "fir"][int(object.id.get_slice(".", 2)) % 4]
			var rect := Rect2(p - Vector2(size.x / 2, size.y - 8 * zoom), size)
			if _opaque(name, rect, mouse): hits.append(object)
		elif object.kind == "construction_site":
			var size := _house_size(object)
			var foot: Vector2 = p + Vector2(0, world.site_size(object).y / 2 * 32) * zoom
			var footprint := Rect2(p - world.site_size(object) * 16 * zoom, world.site_size(object) * 32 * zoom)
			if int(object.get("stage_index", 0)) == 0:
				if footprint.has_point(mouse): hits.append(object)
			elif Rect2(foot - Vector2(size.x / 2, size.y - 12) * zoom, size * zoom).has_point(mouse): hits.append(object)
	for drop in world.drops.values():
		if drop.region_id == "home" and screen(world.point(drop)).distance_to(mouse) < 28 * zoom: return drop.id
	for site in world.leisure.sites.values():
		var art: Dictionary=world.leisure.art(site)
		if art.is_empty():continue
		var footprint:=Rect2(screen(world.point(site))-Vector2(art.recreation.width,art.recreation.depth)*16*zoom,Vector2(art.recreation.width,art.recreation.depth)*32*zoom)
		if (site.complete and leisure_renderer.rect(self,site).has_point(mouse)) or (not site.complete and footprint.has_point(mouse)):hits.append(site)
	if hits.is_empty(): return ""
	hits.sort_custom(func(a, b): return a.position[1] > b.position[1])
	return str(hits[0].id)

func _surface(points: PackedVector2Array, texture: Texture2D, color: Color = Color.WHITE, drift: Vector2 = Vector2.ZERO) -> void:
	var visible_points := PackedVector2Array()
	var uv := PackedVector2Array()
	for point in points:
		visible_points.append(screen(point))
		uv.append(point * 32.0 / Vector2(texture.get_size()) + drift)
	draw_polygon(visible_points, PackedColorArray([color]), uv, texture)

func _path_polygons(points:PackedVector2Array,width:float)->Array[PackedVector2Array]:
	# Offset in pixels so small tile-unit radii retain round edges.
	var pixels := PackedVector2Array()
	pixels.append(points[0] * 32)
	for i in range(1, points.size() - 1):
		var before := points[i - 1]; var corner := points[i]; var after := points[i + 1]
		var radius := minf(2.0, minf(before.distance_to(corner), after.distance_to(corner)) * .3)
		var start := corner.move_toward(before, radius); var end := corner.move_toward(after, radius)
		for step in range(9):
			var t := step / 8.0
			pixels.append((start * (1 - t) * (1 - t) + corner * 2 * (1 - t) * t + end * t * t) * 32)
	pixels.append(points[-1] * 32)
	var result:Array[PackedVector2Array]=[]
	for polygon in Geometry2D.offset_polyline(pixels, width * 32, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND):
		var tiles := PackedVector2Array()
		for point in polygon: tiles.append(point / 32)
		result.append(tiles)
	return result

func _path(points: PackedVector2Array, width: float) -> void:
	for tiles in _path_polygons(points,width):
		_surface(tiles, textures.sand, Color("d9cbaa"))

func _sprite(name: String, point: Vector2, scale_value: float = 1.0, tint: Color = Color.WHITE, tilt: float = 0.0) -> void:
	var texture: Texture2D = textures[name]
	var size := Vector2(texture.get_size()) * zoom * scale_value
	var p := screen(point)
	draw_set_transform(p, tilt)
	draw_texture_rect(texture, Rect2(Vector2(-size.x / 2, -size.y + 8 * zoom * scale_value), size), false, tint)
	draw_set_transform(Vector2.ZERO)

func _shadow(p: Vector2, width: float) -> void:
	draw_set_transform(p, 0, Vector2(1, 0.34))
	draw_circle(Vector2.ZERO, width * zoom, Color(0.08, 0.18, 0.14, 0.22))
	draw_set_transform(Vector2.ZERO)

func _draw() -> void:
	if world == null or textures.is_empty(): return
	gesture_symbols.clear();heart_symbols.clear()
	if region_id=="dark":dark_renderer.draw(self);_draw_creation_flowers();_draw_social_gestures();return
	if region_id != "home": room_renderer.draw(self); return
	var viewport := get_viewport_rect()
	var decor_clip:Rect2=viewport.grow(160)
	var flower_clip:Rect2=viewport.grow(80)
	var entry_clip:Rect2=viewport.grow(400)
	_draw_ground(viewport)
	_draw_world_creations()
	atmosphere.draw_puddles(self)
	if world.resort!=null and world.resort.enabled():preload("res://scripts/resort_renderer.gd").ground(self)
	dark_renderer.boat(self)
	for decor in scenery:
		if not decor_clip.has_point(screen(decor.point)): continue
		var sway: float = Ambience.wind(clock, decor.point) * .035 if decor.name != "rock" else 0.0
		_sprite(decor.name, decor.point, decor.scale, Color.WHITE, sway)
	fishing_renderer.water(self)
	for patch in world.flower_gifts.patches:
		if flower_clip.has_point(screen(patch.point)):
			_sprite("flowers", patch.point, .38, Color.WHITE, Ambience.wind(clock, patch.point) * .025)
	_draw_creation_flowers()
	atmosphere.observe_homes(self)
	atmosphere.draw_traces(self)
	# All farm surfaces and fences use one compact layout contract.
	for site in world.objects.values():
		if site.kind == "construction_site": _draw_courtyard(site)
	farm_renderer.ground(self)
	homestead_renderer.draw(self)
	_sprite("picnic", world.locations.point("p_21_47"), .85)
	for patch in world.all_mushrooms().values():
		if int(patch.amount) > 0: _sprite("mushrooms", world.point(patch), .8)
	var entries: Array = []
	farm_renderer.entries(self, entries)
	for site in world.leisure.sites.values():
		if not site.complete and world.resort!=null and world.resort.retired(site):continue
		entries.append({"type":"leisure","value":site,"y":site.position[1]-2.0})
	for farm in world.farms.farms.values():
		if not world.farms.ready(farm.id):continue
		for fence in world.farms.fences(farm): _add_fence_entries(entries, fence[0], fence[1])
	_add_house_fences(entries)
	_extra_entries(entries)
	for object in world.objects.values():
		if object.kind=="construction_site" and int(object.get("stage_index",0))<5 and world.resort!=null and world.resort.retired(object):continue
		if object.region_id == "home" and object.kind != "farm_plot":
			# Resort structures use their own draw callback before the general clip.
			if not str(object.id).begins_with("resort.villa.") and not entry_clip.has_point(screen(world.point(object))):continue
			var depth: float = object.position[1] + (world.site_size(object).y / 2 if object.kind == "construction_site" else 0.0)
			entries.append({"type": "object", "value": object, "y": depth})
	for actor in world.actors.values():
		if actor.region_id == "home": entries.append({"type": "actor", "value": actor, "y": actor.position[1]})
	for drop in world.drops.values():
		if drop.region_id == "home": entries.append({"type": "drop", "value": drop, "y": drop.position[1]})
	for life in world.barbecues.values():
		if not world.standard.ready(life.station.id):continue
		var ring:bool=world.locations.v3() and (life.fireside.active() or life.station.state=="cold")
		for seat in (life.fire_seats() if ring else life.seats()):entries.append({"type":"seat","value":seat,"y":seat.position[1]-.01,"ring":ring})
		entries.append({"type":"barbecue","value":life.station,"y":life.station.position[1]})
	for actor in world.actors.values():
		if actor.region_id==region_id:fishing_renderer.held_back(self,actor)
	entries.sort_custom(func(a, b): return a.y < b.y)
	var rope_back_drawn:=false
	for entry in entries:
		if entry.type=="actor" and play_stage!=null and not rope_back_drawn and entry.value.id in play_stage.members:
			play_stage.draw_props(self,true);rope_back_drawn=true
		if _draw_extra_entry(entry):continue
		if str(entry.value.get("id","")).begins_with("resort.villa."):
			preload("res://scripts/resort_renderer.gd").draw_entry(self,{"type":"resort_villa","value":world.resort.villa(entry.value.id)});continue
		var value: Dictionary = entry.value
		var point: Vector2 = world.point(value)
		var p := screen(point)
		if not entry_clip.has_point(p): continue
		if entry.type=="leisure":leisure_renderer.draw(self,value);continue
		if entry.type in ["crop"]: farm_renderer.draw_entry(self, entry); continue
		if entry.type == "fence": _fence_line(value.start, value.end); continue
		if entry.type == "seat":
			var circular:bool=entry.get("ring",false)
			var stone:bool=circular and int(str(value.id).get_slice(".",3))%2==1
			_sprite("rock" if stone else "stool",point,.4 if stone else .62 if circular else .47);continue
		if entry.type == "barbecue":
			var state: String = value.state
			var fire:RefCounted=world.barbecues[value.id].fireside
			if fire.active():state="cooking" if fire.burning() else "cold"
			var frame: String = "cold" if state == "cold" else "cooking" if state in ["cooking", "needs_turn"] else "embers"
			var art: Dictionary = value.artwork if not value.artwork.is_empty() else library.artworks["camp-grill"]
			_camp_glow(point, state)
			if not _round_camp(value,point,state):_camp_sprite(art, frame, point, state)
			_camp_smoke(point, state)
			if fire.active() and not fire.state.current.is_empty() and not fire.state.current.get("fish",{}).is_empty() and int(fire.state.current.eaten)+int(fire.state.current.wasted)<int(fire.state.current.total):
				var fish:Dictionary=fire.state.current.fish
				var fish_texture:Texture2D=fishing_renderer.texture(fish.species_id,fish.color_id,world.fishing.rules,-1,"grill")
				var fish_size:=Vector2(64,64*float(fish_texture.get_height())/float(fish_texture.get_width()))*zoom
				draw_texture_rect(fish_texture,Rect2(screen(point)+Vector2(-32,-39)*zoom,fish_size),false)
			if fire.active() and not fire.state.current.is_empty() and not fire.state.current.ready:
				var label:String=LocalText.content(fire.state.current.name)+LocalText.text("ui.island_view.grilling")
				var label_at:=screen(point)+Vector2(-60,-100)*zoom
				draw_string_outline(font,label_at,label,HORIZONTAL_ALIGNMENT_LEFT,-1,15,4,Color("203e37"));draw_string(font,label_at,label,HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("fff4db"))
			continue
		if entry.type == "actor": _actor(value); continue
		if entry.type == "drop":
			_sprite("logs", point, .8)
			draw_string(font, p + Vector2(10, -10), str(value.wood), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("fff1cf"))
			continue
		if value.id == hover_id or value.id == selected_id:
			draw_set_transform(p, 0, Vector2(1, .4))
			draw_arc(Vector2.ZERO, 40 * zoom, 0, TAU, 40, Color("fff0b1"), 2, true)
			draw_set_transform(Vector2.ZERO)
		match value.kind:
			"tree":
				_shadow(p, 18 if value.status == "sapling" else 48)
				var tilt := Ambience.wind(clock, point) * .008
				for effect in effects:
					if effect.target_id == value.id and effect.kind == "hit":
						var age: float = clock - float(effect.started)
						tilt += sin(age * 48) * .035 * maxf(0, 1.0 - age / .28)
				var name: String = ["oak", "oak_small", "birch", "fir"][int(value.id.get_slice(".", 2)) % 4]
				_sprite("stump" if value.status == "stump" else name, point, .36 if value.status == "sapling" else 1.0 if value.status == "mature" else .65, Color(1, 1, 1, float(foliage_alpha.get(value.id, 1.0)) if value.status == "mature" else 1.0), tilt)
				for effect in effects:
					if effect.target_id == value.id and effect.kind == "fall":
						var progress := clampf((clock - float(effect.started)) / .65, 0, 1)
						_sprite(name, point, 1.0, Color(1, 1, 1, 1.0 - progress), progress * progress * 1.35)
			"construction_site": _draw_house(value)
	if play_stage!=null:play_stage.draw_props(self)
	_draw_work_effects()
	preload("res://scripts/weather_renderer.gd").draw(self)
	if not memory_photo:
		_draw_notes()
		_draw_social_gestures()
		_draw_resident_labels()
		if is_instance_valid(world_placement):world_placement.draw_preview(self)

func _draw_notes()->void:
	for row in world.island_notes.rows.values():
		var rect:Rect2=note_rect(row,false)
		draw_rect(rect,Color("#f7e7ac"))
		draw_rect(rect,Color("#684a32"),false,1)
		draw_line(rect.position+Vector2(3,4),rect.position+Vector2(rect.size.x-3,4),Color("#92765a"))
	for row in world.island_notes.gifts.values():
		var rect:Rect2=note_rect(row,true)
		draw_rect(rect,Color("#cd6b78"))
		draw_rect(rect,Color("#603942"),false,1)
		draw_line(rect.get_center()-Vector2(0,5),rect.get_center()+Vector2(0,5),Color("#ffe6ae"),2)

func _draw_resident_labels() -> void:
	var viewport := get_viewport_rect()
	fishing_renderer.overlay(self)
	for companion in world.actors.values():
		if companion.id == "human" or companion.region_id != region_id: continue
		var label: String = LocalText.resident(world,str(companion.id))
		var p := screen(world.point(companion)) - Vector2(0, (_resident_head_height(companion)+4) * zoom + 10)
		p.x -= font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,preload("res://scripts/ui_scale.gd").pixels(16)).x/2
		draw_string_outline(font,p,label,HORIZONTAL_ALIGNMENT_LEFT,-1,preload("res://scripts/ui_scale.gd").pixels(16),4,Color("24392f"))
		draw_string(font,p,label,HORIZONTAL_ALIGNMENT_LEFT,-1,preload("res://scripts/ui_scale.gd").pixels(16),Color("fff4db"))
	for entry in speech_layout():
		draw_line(entry.anchor,entry.box.get_center(),Color(.95,.93,.8,.6),1,true)
		draw_style_box(_bubble(),entry.box)
		draw_multiline_string(font,entry.box.position+Vector2(10,25)*preload("res://scripts/ui_scale.gd").factor(),entry.text,HORIZONTAL_ALIGNMENT_LEFT,entry.box.size.x-20*preload("res://scripts/ui_scale.gd").factor(),preload("res://scripts/ui_scale.gd").pixels(14),-1,Color("3b483d"))

	_draw_thought_clouds()

func _resident_head_height(actor:Dictionary)->float:
	var id:String=library.visual_appearance(actor)
	var work:Dictionary=library.artworks.get(id,{})
	var key:String=id+":"+str(work.get("revision",0))
	if not resident_head_heights.has(key):
		var image:Image=library.texture(id,"down_0").get_image()
		resident_head_heights[key]=float(work.get("anchor",[48,120])[1])-float(image.get_used_rect().position.y) if image!=null else 120.0
	return float(resident_head_heights[key])*(1.18 if id=="suit-hulk" else 1.0)

func _wrap_thought(value:String,width:float)->String:
	var lines:PackedStringArray=[];var current:=""
	for character in value:
		if not current.is_empty() and font.get_string_size(current+character,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x>width:
			lines.append(current);current=character
		else:current+=character
	if not current.is_empty():lines.append(current)
	return "\n".join(lines)

func _draw_thought_clouds() -> void:
	thought_rendered.clear()
	if world.director.local_dialogue==null or chess_overlay:return
	var boxes:Array=[]
	for entry in speech_layout():boxes.append(entry.box)
	var host:Node=get_parent()
	if host!=null and host.get_script()!=null and host.get_script().resource_path=="res://scripts/main.gd":
		var hud:Node=host.island_hud
		if hud!=null:
			for panel in [hud.residents_panel,hud.resident_card,hud.task]:
				if is_instance_valid(panel) and panel.is_visible_in_tree():boxes.append(panel.get_global_rect())
	for id in world.director.local_dialogue.thoughts:
		var actor:Dictionary=world.actors.get(id,{})
		if actor.is_empty() or actor.region_id!=region_id:continue
		if float(speech_by_actor.get(id,{}).get("until",0))>clock:continue
		var thought:Dictionary=world.director.local_dialogue.thoughts[id]
		var value:String=LocalText.resident(world,str(id))+" · "+(str(thought.en) if LocalText.revision().begins_with("en") else str(thought.zh))
		value=_wrap_thought(value,minf(230,get_viewport_rect().size.x-40))
		var width:=0.0
		for line in value.split("\n"):width=maxf(width,font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x)
		var size:=Vector2(width+24,30+20*(value.count("\n")))
		var anchor:Vector2=screen(world.point(actor))-Vector2(0,(_resident_head_height(actor)+12)*zoom)
		if not get_viewport_rect().grow(30).has_point(anchor):continue
		for attempt in range(24):
			var point:Vector2=anchor-Vector2(size.x/2,42+(attempt/3)*38)+Vector2((attempt%3-1)*180,0)
			point.x=clampf(point.x,12,maxf(12,get_viewport_rect().size.x-size.x-12))
			var box:=Rect2(point,size)
			if box.position.y<80 or boxes.any(func(other):return other.grow(8).intersects(box)):continue
			boxes.append(box);thought_rendered.append({"actor_id":id,"box":box,"text":value})
			var style:=_bubble();style.bg_color=Color("ecf2ee");style.set_corner_radius_all(15)
			draw_circle(anchor-Vector2(0,6),2,Color("ecf2ee"))
			draw_circle(anchor-Vector2(2,15),4,Color("ecf2ee"))
			draw_style_box(style,box)
			draw_circle(Vector2(box.get_center().x+8,box.end.y+5),3,Color("ecf2ee"))
			draw_circle(Vector2(box.get_center().x+18,box.end.y+11),2,Color("ecf2ee"))
			for n in range(3):draw_circle(box.position+Vector2(15+n*maxf(8,(size.x-30)/2),2),7,Color("ecf2ee"))
			draw_multiline_string(font,box.position+Vector2(12,21),value,HORIZONTAL_ALIGNMENT_LEFT,size.x-24,14,-1,Color("43594f"))
			break

func clear_local_speech(actor_id: String) -> void:
	if speech_by_actor.get(actor_id,{}).get("source")=="local_rules":speech_by_actor.erase(actor_id)
	if speech_actor==actor_id and speech_source=="local_rules":speech_until=0
func _barbecue_hit_box(station:Dictionary)->Rect2:
	return Rect2(screen(world.point(station))-Vector2(34,65)*zoom,Vector2(68,74)*zoom)

func speech_layout() -> Array:
	if chess_overlay:return [] # Board bubbles own the visible scene; world gates and facts keep running.
	var entries: Array=[];var boxes: Array[Rect2]=[]
	var viewport:=get_viewport_rect()
	# Keep the actual fire target available under clickable need bubbles. The
	# same rectangle owns hit testing; moving a bubble must not accept a need.
	for life in world.barbecues.values():
		if life.station.region_id==region_id and world.standard.ready(life.station.id):boxes.append(_barbecue_hit_box(life.station))
	for actor in world.actors.values():
		if actor.id=="human" or actor.region_id!=region_id:continue
		var label_point:Vector2=screen(world.point(actor))+Vector2(-12,15) if world.locations.v3() else screen(world.point(actor))-Vector2(font.get_string_size(LocalText.resident(world,str(actor.id)),HORIZONTAL_ALIGNMENT_LEFT,-1,preload("res://scripts/ui_scale.gd").pixels(16)).x/2,(_resident_head_height(actor)+4)*zoom+10)
		boxes.append(Rect2(label_point-Vector2(3,17),Vector2(font.get_string_size(LocalText.resident(world,str(actor.id)),HORIZONTAL_ALIGNMENT_LEFT,-1,preload("res://scripts/ui_scale.gd").pixels(16)).x+6,23)))
		if world.locations.v3() and actor.has("world_door_client"):
			var size:=maxi(14,preload("res://scripts/ui_scale.gd").pixels(12))
			var bounds:=font.get_string_size(str(actor.world_door_client),HORIZONTAL_ALIGNMENT_LEFT,-1,size)
			var badge:=screen(world.point(actor))+Vector2(-bounds.x*.5-5,-(_resident_head_height(actor)+12)*zoom-11-font.get_ascent(size))
			boxes.append(Rect2(badge,bounds+Vector2(10,6)))
	var visible_speech:Dictionary=speech_by_actor.duplicate(true)
	if world.hunger!=null and world.hunger.has_method("visible_cue"):
		for id in world.director.routines:
			if str(visible_speech.get(id,{}).get("context","")).begins_with("fireside_") or str(visible_speech.get(id,{}).get("context","")).begins_with("need_"):continue
			var cue:Dictionary=world.hunger.visible_cue(id)
			if not cue.is_empty():visible_speech[id]={"text":cue.text,"source":"local_rules","until":clock+1,"cue":true}
	var ids: Array=visible_speech.keys()
	var fireside_count:=0
	ids.sort_custom(func(a,b):return float(visible_speech[a].until)>float(visible_speech[b].until))
	for id in ids:
		if entries.size()>=8:break
		var speech_state: Dictionary=visible_speech[id]
		var fireside_cue:bool=str(speech_state.get("context","")).begins_with("fireside_")
		if fireside_cue:
			if fireside_count>=2 or not world.barbecues.values().any(func(l):return l.fireside.burning() and not l.fireside.circle_closed and l.fireside.jobs.has(id) and not l.fireside.held(id) and world.director.routines[id].chatter):continue
			fireside_count+=1
		if float(speech_state.until)<=clock or (not speech_state.get("cue",false) and id==speech_actor and speech_until<=clock) or not world.actors.has(id) or world.actors[id].region_id!=region_id:continue
		var anchor:=screen(world.point(world.actors[id]))-Vector2(0,_resident_head_height(world.actors[id])*zoom)
		if not viewport.grow(70).has_point(anchor):continue
		var appetite_cue:bool=speech_state.source=="local_rules" and (speech_state.get("cue",false) or world.director.events.any(func(e):return e.actor_id==id and e.text==speech_state.text and str(e.context).begins_with("hunger_")))
		var spoken:String=LocalText.speech(world,str(id),str(speech_state.text)) if speech_state.source=="local_rules" else str(speech_state.text)
		var prefix:String="" if appetite_cue or fireside_cue or speech_state.source=="local_rules" else LocalText.text("ui.speech.autonomous") if speech_state.source=="autonomy" else LocalText.text("ui.speech.model") if speech_state.source=="model" else ""
		var english:bool=LocalText.revision().begins_with("en")
		var text:String=prefix+spoken.left(18)
		if english or str(speech_state.get("context","")) in ["opening"]:text=_wrap_speech(prefix+spoken,minf(290*preload("res://scripts/ui_scale.gd").factor(),viewport.size.x-40),not english)
		elif spoken.length()>18:text+="…"
		var lines:=text.split("\n");var width:=0.0
		for line in lines:width=maxf(width,font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,preload("res://scripts/ui_scale.gd").pixels(14)).x)
		var size:=Vector2(width+20*preload("res://scripts/ui_scale.gd").factor(),(36+20*(lines.size()-1))*preload("res://scripts/ui_scale.gd").factor())
		for attempt in range(60):
			var point:=anchor-Vector2(size.x/2,48+42*(attempt/3))+Vector2((attempt%3-1)*90,0)
			if attempt>=12:
				var cell:int=attempt-12
				point=Vector2(12+(cell%6)*maxf(0,viewport.size.x-size.x-24)/5.0,85+(cell/6)*maxf(0,viewport.size.y-size.y-285)/7.0)
			point.x=clampf(point.x,12,maxf(12,viewport.size.x-size.x-12));point.y=clampf(point.y,85,maxf(85,viewport.size.y-200))
			var box:=Rect2(point,size)
			if boxes.any(func(existing):return existing.grow(4).intersects(box)):continue
			boxes.append(box);entries.append({"actor_id":id,"anchor":anchor,"box":box,"text":text,"source":speech_state.source});break

	return entries

func _bubble() -> StyleBoxFlat:
	var style := StyleBoxFlat.new(); style.bg_color = Color("fff4db")
	style.corner_radius_top_left = 9; style.corner_radius_top_right = 9; style.corner_radius_bottom_left = 9; style.corner_radius_bottom_right = 9
	return style

func _actor(actor: Dictionary) -> void:
	if photo_poses.has(actor.id):
		actor=actor.merged(photo_poses[actor.id],true)
		motion.play_poses.erase(actor.id)
	var p := screen(world.point(actor))
	_shadow(p, 22)
	p+=leisure_renderer.actor_offset(self,actor)*zoom
	if region_id=="dark" and actor.id!="human" and world.intelligence.tag(actor.id)=="lively" and not world.dark.events.is_empty():
		var event:Dictionary=world.dark.events.back();var age:float=world.director.time-float(event.get("time",-100))
		if event.kind in ["torch_light","beacon"] and age>=0 and age<.6:p.y-=sin(age/.6*PI)*7*zoom
	var gesture: Dictionary = world.flower_gifts.presentation(actor.id)
	if world.flower_creation!=null and world.flower_creation.jobs.get(actor.id,{}).get("action")=="gift_flower":
		var job:Dictionary=world.flower_creation.jobs[actor.id]
		gesture={"phase":"offering" if not world._routes.has(actor.id) else "bringing","carrying":job.get("offered",false),"progress":clampf(float(job.elapsed)/1.5,0,1),"delivered":not job.get("offered",false),"color":job.color}
	var running: bool = world.display_running(actor.id)
	var rushing:bool=world.hunger!=null and world.hunger.has_method("rushing") and world.hunger.rushing(actor.id)
	var motion_gesture := gesture.duplicate()
	motion_gesture["running"] = running
	motion_gesture["rushing"] = rushing
	motion_gesture["motion"] = world.motion_state(actor.id)
	motion_gesture["gait"] = world.intelligence.gait(actor.id)
	motion_gesture["hunger"] = world.hunger.rank(actor.id)
	if actor.id != "human" and world.director.routines.has(actor.id):
		var routine:RefCounted = world.director.routines[actor.id]
		motion_gesture["routine_kind"]=routine.kind
		motion_gesture["thinking_allowed"] = routine.enabled and not routine.held and not routine.blocked() and routine.time >= routine.visual_quiet_until and routine.kind.is_empty() and not world.work.jobs.has(actor.id) and not world._routes.has(actor.id)
	var pose: Dictionary = motion.pose(actor, world.work.jobs.get(actor.id, {}), world.actors, motion_gesture)
	var visible_cue:Dictionary=visible_reaction(actor.id) if actor.id!="human" else {}
	var face:=""
	if world.hunger!=null and world.hunger.rank(actor.id)>=2 and actor.activity in ["idle","local_look"] and not world.work.jobs.has(actor.id):
		pose.frame="think_down_0" if world.hunger.rank(actor.id)>=3 or library.visual_appearance(actor)=="orange-sunflower-girl" else "pickup_down"
		pose.fallback="down_0"
	
	if actor.id!="human" and world.get("hearts")!=null:
		var feeling:Dictionary=world.hearts.mood(actor.id)
		var emotion_pose:Dictionary=world.hearts.config.pose
		if motion_gesture.motion.moving:
			if float(feeling.joy)>float(emotion_pose.joy_threshold):pose.bob-=absf(sin(clock*7))*float(emotion_pose.joy_bounce_pixels)
			if float(feeling.hurt)>float(emotion_pose.hurt_threshold):pose.scale.y*=float(emotion_pose.hurt_scale_y);pose.lean+=float(emotion_pose.hurt_lean)
		elif not world.work.jobs.has(actor.id) and float(feeling.tired)>float(emotion_pose.tired_threshold):
			pose.frame="rest_empty";pose.fallback=pose.facing+"_0"
	var reaction:Dictionary=world.hunger.reaction(actor.id) if world.hunger!=null and world.hunger.has_method("reaction") else {}
	if not reaction.is_empty():
		var wave:float=sin((world.director.time-float(reaction.started))*9)
		pose.bob=-absf(wave)*float(reaction.tier)*3;pose.lean=wave*.045*float(reaction.tier)
		if reaction.tier==3:
			for n in range(3):draw_circle(p+Vector2(-25+n*25,-80-absf(wave)*10)*zoom,3*zoom,Color("fff1a2"))
	var onlooker:Dictionary=hungry_onlooker.presentation(world,actor.id,clock)
	hungry_onlooker.apply(pose,onlooker)
	fishing_renderer.rod_pose(self,actor,pose)
	# Last presentation gate: no fishing, hunger or seat pose can turn a body
	# against its actual World movement, including its final arrival frame.
	motion.enforce_direction(pose,actor,motion_gesture.motion)
	if motion_gesture.motion.moving and float(pose.get("dust",0))>0:
		var direction:Vector2=Vector2(motion_gesture.motion.velocity).normalized();var normal:=Vector2(-direction.y,direction.x)
		# At most three ephemeral marks per actor. No emitter/texture allocations.
		for n in range(5 if rushing else 3 if running else 2):
			var age:float=fposmod(clock*(18 if running else 11)+float(hash(actor.id)%7)+n*3,10)
			var offset:Vector2=-direction*(age*1.4+3)+normal*(n-1)*3
			draw_circle(p+offset*zoom,(1.2+age*.1)*float(pose.dust)*zoom,Color(.78,.70,.55,(.34 if running else .22)*(1-age/10)))
	if float(pose.get("brake_dust",0))>0:
		for n in range(4):
			draw_circle(p+Vector2((n-1.5)*5,-n%2*2)*zoom,(2.5+n*.4)*float(pose.brake_dust)*zoom,Color(.78,.70,.55,.3*motion.run_transition(actor.id).stop))
	if world.resort!=null:
		var pool:bool=world.resort.using(actor.id)=="pool"
		if pool or float(world.resort.wet.get(actor.id,0))>world.forest.clock:
			for drop in range(5):
				var age:float=fposmod(clock*2+drop*.21,1)
				draw_circle(p+Vector2(sin(drop*2.4+clock)*(30 if pool else 9),-25-age*25)*zoom,(2 if pool else 1.2)*zoom,Color(.6,.95,1,1-age))
	if not motion.working(actor,world.work.jobs.get(actor.id,{})):world.lively.apply(actor.id,pose)
	if actor.id!="human" and not motion_gesture.motion.moving and float(motion_gesture.motion.get("still_seconds",1))>=.3 and not world.work.jobs.has(actor.id) and actor.activity in ["idle","local_look","play_lie"]:
		var here:Vector2=world.point(actor)
		var host:Dictionary=world.actors.human
		var aim:Vector2=world.point(host)-here if host.region_id==actor.region_id else Vector2.ZERO
		var talking:Dictionary=speech_by_actor.get(actor.id,{})
		var brain:RefCounted=world.director.brains.get(actor.id)
		var peer:Dictionary=world.actors.get(brain.current.get("partner",""),{}) if brain!=null else {}
		if not peer.is_empty() and peer.region_id==actor.region_id:aim=world.point(peer)-here
		if aim.length_squared()>.04 and (aim.length_squared()<=9 or not peer.is_empty()):
			pose.facing=motion.direction(aim)
			pose.frame=pose.facing+"_0";pose.fallback=pose.frame
		if float(talking.get("until",0))>clock:pose.lean+=sin(clock*5)*.04
		if brain!=null and brain.current.get("action")=="social_banter" and not peer.is_empty():
			if float(talking.get("until",0))>clock:pose.lean+=.075 if pose.facing=="left" else -.075
			elif float(speech_by_actor.get(peer.id,{}).get("until",0))>clock and aim.length_squared()>.04:
				pose.facing=motion.direction(aim.orthogonal());pose.frame=pose.facing+"_0";pose.fallback=pose.frame
		var age:float=float(visible_cue.get("age",0))
		var envelope:float=sin(clampf(age/2.5,0,1)*PI)
		match visible_cue.get("cue",""):
			"pat":
				face="pat";pose.lean+=sin(age*5)*.085*envelope
				pose.sway+=signf(aim.x)*absf(sin(age*PI/.7))*4*envelope
			"happy":pose.bob-=absf(sin(clampf(age/1.25,0,1)*TAU))*11
			"hurt":
				face="tear";pose.bob+=envelope*5
				if age>.45 and aim.length_squared()>.04:pose.facing=motion.direction(-aim)
			"surprise":pose.bob-=sin(clampf(age/.65,0,1)*PI)*10
			"shy":face="blush";pose.bob+=envelope*4
			"sleep":face="mouth" if age<.9 else "blink"
			"wake":
				face="mouth" if age<.8 else ""
				pose.scale.y*=1+envelope*.07
				pose.bob-=envelope*5
			"wince":face="anger";pose.lean-=envelope*.06
		if not face.is_empty():
			pose.frame=pose.facing+"_0";pose.fallback=pose.frame
	var visual_id: String = library.visual_appearance(actor)
	var art: Dictionary = library.artworks[visual_id]
	var frame: String = pose.frame if art.frames.has(pose.frame) else pose.fallback
	if world.resort!=null and world.resort.using(actor.id) in ["lounge","hammock","swing"] and art.frames.has("seated_down"):frame="seated_down"

	if actor.activity in ["fire_sit","fire_squat","fire_eat"] and actor.facing!="down" and not art.frames.has(pose.frame):
		frame="up_0" if actor.facing=="up" else "seated_"+actor.facing
		pose.scale.y*=.78
	if not art.frames.has(frame): frame = actor.get("facing", "down") + "_0"
	if actor.activity in ["seated","swinging"] and not art.frames.has(pose.frame) and world.work.jobs.get(actor.id,{}).get("intent")!="play_gomoku":pose.scale.y*=.78
	var texture: Texture2D = library.texture(visual_id, frame)

	var fishing_texture:Texture2D=fishing_renderer.animation_texture(self,actor)
	if fishing_texture!=null:texture=fishing_texture
	if running and motion_gesture.motion.moving:
		var run_texture:Texture2D=action_atlases.texture("run",library,actor,motion.run_column(actor.id,motion_gesture.gait,rushing))
		if run_texture!=null:
			texture=run_texture
			var contact:Dictionary=action_atlases.run_contact(library,actor,motion.run_column(actor.id,motion_gesture.gait,rushing))
			motion.authored_run_pose(pose,actor.id,motion_gesture.gait,contact,Vector2(motion_gesture.motion.velocity),rushing)
	if not running and motion_gesture.motion.moving:
		var walk_col:int=motion.walk_column(actor.id)
		var walk_texture:Texture2D=action_atlases.texture("walk",library,actor,walk_col)
		if walk_texture!=null:
			texture=walk_texture
			motion.authored_walk_pose(pose,actor.id,action_atlases.contact("walk",library,actor,walk_col),Vector2(motion_gesture.motion.velocity),motion_gesture.gait)
	if not motion_gesture.motion.moving:
		var action:String="chop" if actor.activity=="chopping" else "gather" if actor.activity=="gathering" else ""
		if not action.is_empty():
			var work_job:Dictionary=world.work.jobs.get(actor.id,{})
			var age:float=float(work_job.get("time",0))
			var column:int=mini(3,int(age/2.0*4))
			if action=="chop":
				var phase:float=fposmod(age,float(world.forest.settings.swing_seconds))/float(world.forest.settings.swing_seconds)
				column=3 if phase<.12 else 4 if phase<.3 else 0 if phase<.65 else 1 if phase<.85 else 2
				for effect in effects:
					if effect.kind=="hit" and effect.get("actor_id","")==actor.id and clock-float(effect.started)<.12:column=2
			var work_texture:Texture2D=action_atlases.texture(action,library,actor,column)
			if work_texture!=null:texture=work_texture;pose.bob=0;pose.scale=Vector2.ONE;pose.lean=0;pose.sway=0
	var meal_pose:Dictionary=MealMotion.timeline(world,actor.id,world.work.jobs.get(actor.id,{}))
	var eat_texture:Texture2D=null
	if not meal_pose.is_empty() and not motion_gesture.motion.moving:
		eat_texture=action_atlases.texture("eat",library,actor,int(meal_pose.column))
		if eat_texture!=null:texture=eat_texture
	# Optional authored farm/social textures obey the same editable-art protection.
	if not motion_gesture.motion.moving:
		var extra_action:String="";var extra_col:int=0
		var visual_job:Dictionary=world.work.jobs.get(actor.id,{})
		if actor.activity=="watering":extra_action="farm";extra_col=2+int(clock*4)%2
		elif actor.activity in ["picking_up","putting_down"] and visual_job.get("step") in ["plant","harvest"]:extra_action="farm";extra_col=(4 if visual_job.step=="harvest" else 0)+int(clock*4)%2
		elif actor.activity=="gesture_wave":extra_action="gesture";extra_col=mini(2,int(float(motion.states.get(actor.id,{}).get("activity_age",0))/.7*3))
		elif actor.activity in ["idle","local_look"] and float(speech_by_actor.get(actor.id,{}).get("until",0))>clock:extra_action="gesture";extra_col=3+int(clock*6)%3
		if not extra_action.is_empty():
			var extra_texture:Texture2D=action_atlases.texture(extra_action,library,actor,extra_col)
			if extra_texture!=null:texture=extra_texture;pose.scale=Vector2.ONE;pose.lean=0;pose.bob=0;pose.sway=0
	var cat_contact:Dictionary=world.cat.actor_poses.get(actor.id,{})
	if world.cat.carrier==actor.id or (float(cat_contact.get("until",0))>world.cat.clock and not world.work.jobs.has(actor.id) and not world._routes.has(actor.id)):
		var action:String="hold" if world.cat.carrier==actor.id else str(cat_contact.get("action","pet"))
		var contact_texture:Texture2D=cat_contact_art.texture(library,actor,action,(1+int(clock*6)%2) if action=="hold" and world._routes.has(actor.id) else 0 if action=="hold" else int(clock*4)%2)
		if contact_texture!=null:texture=contact_texture
		if action=="pet" and not cat_contact_art.redrawn(library,actor):pose.scale.y*=.72;pose.bob+=14
	var holiday:String=world.resort.using(actor.id) if world.resort!=null else ""
	if holiday in ["lounge","hammock"]:
		pose.lean=-1.35+(sin(clock*1.6)*.1 if holiday=="hammock" else sin(clock*.12)*.035);pose.scale=Vector2(1,.78+sin(clock*1.6)*.015);pose.bob=16+sin(clock*1.6)*(5 if holiday=="hammock" else 1.2)
		p+=Vector2(32,0)*zoom
	elif holiday=="swing":pose.bob=sin(clock*1.6)*10;pose.lean=sin(clock*1.6)*.1
	elif holiday=="pool":pose.bob=18+sin(clock*2.2)*4
	# The jump clock belongs to the activity, even when editable art rejects an atlas.
	# Apply this after idle cosmetic poses so they cannot erase the accepted jump.
	if pose.has("play_style") and not motion.working(actor,world.work.jobs.get(actor.id,{})):
		if float(pose.get("play_land",0))>0:
			for i in range(3):draw_circle(p+Vector2((i-1)*12,0)*zoom,(1.5+float(pose.play_land)*2)*zoom,Color(.8,.72,.51,.35*float(pose.play_land)))
		play_rendered[actor.id]={"lift":float(pose.bob),"frame":frame,"phase":float(motion.play_phases.get(actor.id,0))}
	else:play_rendered.erase(actor.id)
	if visual_id=="suit-hulk":pose.scale*=1.18
	draw_set_transform(p + Vector2(float(pose.get("sway",0)), float(pose.bob)) * zoom, float(pose.lean), pose.scale)
	var food_hand:Dictionary=action_atlases.food_hand(library,actor,int(meal_pose.get("column",0))) if eat_texture!=null else {}
	if not food_hand.is_empty() and not food_hand.front:_meal_food(actor,meal_pose,food_hand,art)
	dark_renderer.held(self,actor,pose,art,false)
	if inspect_actor_frames:
		var atlas:=texture as AtlasTexture
		submitted_actor_frames[actor.id]={"frame":frame if atlas==null else "", "asset":atlas.atlas.resource_path.get_file() if atlas!=null else visual_id, "sheet":atlas.atlas.resource_path.get_base_dir().get_file() if atlas!=null else "", "region":str(atlas.region) if atlas!=null else "", "play":pose.has("play_style"),"tilt":float(pose.lean),"height_scale":float(pose.scale.y)}
	if holiday=="pool":
		var part:=Rect2(0,0,texture.get_width(),texture.get_height()*.57)
		draw_texture_rect_region(texture,Rect2(-Vector2(art.anchor[0],art.anchor[1])*zoom,Vector2(art.width,art.height*.57)*zoom),part)
	else:draw_texture_rect(texture, Rect2(-Vector2(art.anchor[0], art.anchor[1]) * zoom, Vector2(art.width, art.height) * zoom), false)
	if texture is not AtlasTexture and frame==pose.facing+"_0":face_overlays.draw(self,library,art,pose.facing,face)
	if not food_hand.is_empty() and food_hand.front:_meal_food(actor,meal_pose,food_hand,art)
	dark_renderer.held(self,actor,pose,art)
	hungry_onlooker.draw_front(self,onlooker,art)
	if not str(actor.get("furniture_id", "")).is_empty():
		var item: Dictionary = world.interior.furniture[actor.furniture_id]
		var work_art: Dictionary = item.artwork if not item.artwork.is_empty() else library.artworks["furniture-" + item.recipe_id]
		var carried: Texture2D = library.frozen_texture(work_art, "down")
		var carried_size := Vector2(work_art.width, work_art.height) * .5 * zoom
		draw_texture_rect(carried, Rect2(Vector2(-carried_size.x / 2, -58 * zoom), carried_size), false)
	# Seeds and produce have no authored hand sprite: never substitute a picnic basket.
	if actor.carry.has("mushroom"):
		draw_texture_rect(textures.mushrooms, Rect2(Vector2(-24, -50) * zoom, Vector2(48, 42) * zoom), false)
	if not gesture.is_empty(): _flower_gesture(actor, gesture)
	draw_set_transform(Vector2.ZERO)
	if actor.id!="human" and world.get("hearts")!=null:
		if not visible_cue.is_empty():heart_symbols.append({"actor":actor.id,"at":p+Vector2(0,-float(art.anchor[1])-5)*zoom,"cue":visible_cue})
	world.lively.draw(self,actor,p)
	if actor.activity in ["gesture_wave","gesture_stretch"] and not motion_gesture.motion.moving:gesture_symbols.append({"actor":actor,"point":p,"art":art,"frame":frame,"pose":pose})
	fishing_renderer.held_front(self,actor)
	fishing_renderer.gesture_front(self,actor)
	fishing_renderer.rod_front(self,actor,fishing_texture!=null,pose)
	leisure_renderer.chess_gesture(self,actor)
	draw_set_transform(Vector2.ZERO)

	if actor.id=="human" and world.dark!=null:
		for lamp in world.dark.discoveries.lamps:
			if lamp.region==region_id:
				var light_at:Vector2=screen(world.dark.p(lamp.position));draw_circle(light_at,7*zoom,Color("b5db74"));
				if world.days.phase().id=="night":draw_circle(light_at,30*zoom,Color(.8,1,.5,.10))

func draw_hunger_symbols(canvas:Node2D)->void:
	for id in hunger_symbols.keys():
		var left:float=float(hunger_symbols[id])-clock
		if left<=0:hunger_symbols.erase(id);continue
		if not world.actors.has(id) or world.actors[id].region_id!=region_id:continue
		var at:Vector2=screen(world.point(world.actors[id]))+Vector2(-15,-100)*zoom+Vector2(0,-(1.2-left)*8)
		var color:=Color(1,.92,.69,minf(1,left/.35))
		canvas.draw_string_outline(font,at,LocalText.text("ui.island_view.rumble"),HORIZONTAL_ALIGNMENT_LEFT,-1,18,3,Color(0,0,0,color.a))
		canvas.draw_string(font,at,LocalText.text("ui.island_view.rumble"),HORIZONTAL_ALIGNMENT_LEFT,-1,18,color)
func _draw_social_gestures()->void:
	draw_set_transform(Vector2.ZERO)
	for item in heart_symbols:
		var cue:Dictionary=item.cue
		var mark:String=cue.get("mark",REACTION_MARK.get(cue.cue,"sweat"))
		var at:Vector2=item.at+Vector2(29 if float(speech_by_actor.get(item.actor,{}).get("until",0))>clock else 0,0)*zoom
		if not get_viewport_rect().has_point(at):continue
		Emotes.paint(self,at,mark,20*zoom,float(cue.age),2.5)
		world.hearts.note_symbol(item.actor,clock)
	if region_id!="dark":draw_hunger_symbols(self)
	for item in gesture_symbols:_social_gesture_symbol(item.actor,item.point,item.art,item.frame,item.pose)
func _social_gesture_symbol(actor:Dictionary,p:Vector2,art:Dictionary,frame:String,pose:Dictionary)->void:
	var key:String=str(art.id)+":"+str(art.revision)+":"+frame
	if not gesture_symbol_bounds.has(key):
		if gesture_symbol_bounds.size()>=128:gesture_symbol_bounds.clear()
		gesture_symbol_bounds[key]=library.render(art,frame).get_used_rect()
	var bounds:Rect2i=gesture_symbol_bounds[key]
	var head:=p+Vector2((bounds.position.x+bounds.size.x*.5-float(art.anchor[0]))*zoom,(bounds.position.y-float(art.anchor[1])-8+float(pose.bob))*zoom)
	draw_circle(head,8*zoom,Color("594353"));draw_circle(head,7*zoom,Color("fff2cf"))
	var ink:=Color("654453");var width:float=maxf(1.0,1.5*zoom)
	if actor.activity=="gesture_wave":
		draw_circle(head,3.0*zoom,ink)
		for x in [-3,-1,1,3]:draw_line(head+Vector2(x,-2)*zoom,head+Vector2(x,-6)*zoom,ink,width)
		draw_line(head+Vector2(3,1)*zoom,head+Vector2(6,-2)*zoom,ink,width)
		draw_arc(head+Vector2(1,0)*zoom,8*zoom,-1.1,-.35,5,ink,width)
	else:
		draw_circle(head+Vector2(0,-3)*zoom,2*zoom,ink)
		draw_line(head+Vector2(0,0)*zoom,head+Vector2(0,5)*zoom,ink,width)
		draw_line(head+Vector2(0,1)*zoom,head+Vector2(-5,-4)*zoom,ink,width)
		draw_line(head+Vector2(0,1)*zoom,head+Vector2(5,-4)*zoom,ink,width)

func _meal_food(actor:Dictionary,meal:Dictionary,hand:Dictionary,art:Dictionary)->void:
	var food:Dictionary=meal.get("food",{})
	if food.is_empty():return
	var at:Vector2=(Vector2(hand.pixel[0],hand.pixel[1])-Vector2(art.anchor[0],art.anchor[1]))*zoom
	var details:Dictionary=world.recipes.metadata.get(str(food.get("food_id","")),{})
	if actor.id!="human" and details.get("signature_trait","")==world.intelligence.tag(actor.id) and not details.is_empty():
		var heart:=PackedVector2Array()
		var lift:float=sin(clock*3.0)*2.0
		for point in [Vector2(0,3),Vector2(-6,-2),Vector2(-6,-6),Vector2(-3,-8),Vector2(0,-5),Vector2(3,-8),Vector2(6,-6),Vector2(6,-2)]:heart.append(at+(point+Vector2(12,-26+lift))*zoom)
		draw_colored_polygon(heart,Color("ed98ac"))
	var stage:int=mini(3,int(float(meal.progress)*3.4))
	var remaining:float=[1.0,.68,.35,0.0][stage]
	if food.category=="dish":
		var dish_path:String="res://assets/island-food/"+str(food.food_id)+".png"
		if ResourceLoader.exists(dish_path) and remaining>0:
			draw_texture_rect(load(dish_path),Rect2(at-Vector2(12,18)*zoom,Vector2(24,24)*zoom),false)
			return
		draw_arc(at,9*zoom,0,PI,10,Color("eee1ce"),5*zoom)
		if remaining>0:draw_line(at+Vector2(-6,0)*zoom,at+Vector2(6,0)*zoom,Color("d89455"),3*zoom*remaining)
	elif food.get("fish",{}).get("size_id")=="giant":
		if remaining>0:
			var fish:Dictionary=food.fish
			var tex:Texture2D=fishing_renderer.texture(fish.species_id,fish.color_id,world.fishing.rules,-1,"grill")
			draw_texture_rect(tex,Rect2(at-Vector2(25,12)*zoom*remaining,Vector2(50,24)*zoom*remaining),false)
	else:
		draw_line(at+Vector2(-1,8)*zoom,at+Vector2(1,-12)*zoom,Color("ba8954"),2*zoom)
		if remaining<=0:return
		var icon:Texture2D
		if food.food_id=="fish" and not food.get("fish",{}).is_empty():icon=fishing_renderer.texture(food.fish.species_id,food.fish.color_id,world.fishing.rules,-1,"grill")
		elif ResourceLoader.exists("res://assets/island-food/"+str(food.food_id)+".png"):icon=load("res://assets/island-food/"+str(food.food_id)+".png")
		elif library.artworks.has("crop-"+str(food.food_id)):icon=library.texture("crop-"+str(food.food_id),"mature")
		else:icon=textures.mushrooms
		draw_texture_rect(icon,Rect2(at-Vector2(7,11)*zoom*remaining,Vector2(14,14)*zoom*remaining),false)

func _flower_gesture(actor: Dictionary, gesture: Dictionary) -> void:
	var phase: String = gesture.phase
	var progress: float = gesture.progress
	if not gesture.carrying and not (phase == "picking" and progress > .65): return
	var facing: String = actor.facing
	var side := -1.0 if facing == "left" else 1.0
	var hand := Vector2(side * 19, -40)
	if facing in ["up", "down"]: hand = Vector2(11, -36 if facing == "down" else -49)
	if phase == "picking": hand.y += (1.0-progress) * 25
	if phase == "bringing": hand.y += sin(clock * 9) * .7
	if phase == "offering":
		var reach := sin(clampf(progress * 1.8, 0, 1) * PI * .5)
		hand += (Vector2(side * 14,-3) if facing in ["left","right"] else Vector2(0,8 if facing=="down" else -6)) * reach
	var opacity := 1.0 - smoothstep(.78,1.0,progress) if phase == "offering" else 1.0
	if gesture.has("color"):
		var rose:Texture2D=preload("res://scripts/resort_renderer.gd").asset("rose-"+str(gesture.color))
		if rose!=null:draw_texture_rect(rose,Rect2((hand-Vector2(11,24))*zoom,Vector2(22,28)*zoom),false,Color(1,1,1,opacity))
	else:draw_texture_rect(textures.flowers, Rect2((hand-Vector2(15,22))*zoom,Vector2(30,24)*zoom),false,Color(1,1,1,opacity))
	if phase == "offering" and gesture.get("delivered",false):
		for i in range(3):
			var drift := Vector2((i-1)*8,-8-progress*15)
			draw_rect(Rect2((hand+drift)*zoom,Vector2(2,2)*zoom),Color(1,.91,.66,sin(progress*PI)*.65))

func _draw_work_effects() -> void:
	for effect in effects:
		var age: float = clock - float(effect.started)
		var p := screen(Vector2(effect.position[0], effect.position[1]))
		if effect.kind == "storage_text":
			if effect.get("region_id",region_id)!=region_id:continue
			var caption:String=str(effect.get("storage_text",effect.get("text","")));var width:float=font.get_string_size(caption,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x
			var at:Vector2=p+Vector2(-width/2,-90-age*22)*zoom
			draw_string_outline(font,at,caption,HORIZONTAL_ALIGNMENT_LEFT,-1,16,4,Color("294b42"))
			draw_string(font,at,caption,HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("fff4db"))
		elif effect.kind == "hit":
			for chip in range(5):
				var velocity := Vector2((chip - 2) * 38, -65 - (chip % 3) * 14)
				var offset := velocity * age + Vector2(0, 140 * age * age - 16)
				var alpha := maxf(0, 1.0 - age / .55)
				draw_rect(Rect2(p + offset * zoom, Vector2(4, 3) * zoom), Color(.82, .62, .32, alpha))
		elif effect.kind in ["pickup", "deposit"]:
			var alpha := maxf(0, 1.0 - age / .4)
			draw_set_transform(p, 0, Vector2(1, .35))
			draw_arc(Vector2.ZERO, (14 + age * 35) * zoom, 0, TAU, 24, Color(.91, .81, .51, alpha * .6), 1.5)
			draw_set_transform(Vector2.ZERO)

func _opaque(name: String, rect: Rect2, mouse: Vector2) -> bool:
	if not rect.has_point(mouse): return false
	var image: Image = alpha_images[name]
	var uv := (mouse - rect.position) / rect.size
	return image.get_pixel(clampi(int(uv.x * image.get_width()), 0, image.get_width() - 1), clampi(int(uv.y * image.get_height()), 0, image.get_height() - 1)).a > .15

func _near_path(point: Vector2) -> bool:
	return Layout.near_road(world.catalog.regions.home.layout, point, 1.0)

func _work_sprite(art: Dictionary, frame: String, point: Vector2, size: Vector2, tint: Color = Color.WHITE) -> void:
	var texture: Texture2D = library.frozen_texture(art, frame)
	var anchor := Vector2(art.anchor[0] / float(art.width), art.anchor[1] / float(art.height))
	draw_texture_rect(texture, Rect2(screen(point) - size * anchor * zoom, size * zoom), false, tint)

func _fence_line(start: Vector2, end: Vector2) -> void:
	var horizontal := absf(end.x - start.x) > absf(end.y - start.y)
	var distance := start.distance_to(end)
	var count := maxi(1, int(ceil(distance / (3.8 if horizontal else 2.2))))
	for i in range(count):
		var point := start.lerp(end, (float(i) + .5) / count)
		if horizontal:
			var size := Vector2(distance / count * 32 + 12, 76) * zoom
			draw_texture_rect(textures.fence_h, Rect2(screen(point) - Vector2(size.x / 2, size.y - 5 * zoom), size), false, Color("dfd6bf"))
		else:
			var size := Vector2(43, distance / count * 32 + 55) * zoom
			draw_texture_rect(textures.fence_v, Rect2(screen(point) - Vector2(size.x / 2, size.y - 12 * zoom), size), false, Color("dfd6bf"))

func _update_ambience() -> void:
	if world == null or sounds.is_empty(): return
	var stations:Array=world.barbecues.values();stations.sort_custom(func(a,b):return center.distance_squared_to(world.point(a.station))<center.distance_squared_to(world.point(b.station)))
	var heat: float = 0.0 if stations[0].fireside.active() and not stations[0].fireside.burning() else Ambience.heat(stations[0].station.state)
	var distance: float = center.distance_to(world.point(stations[0].station))
	for kind in ["breeze", "fire", "moon_tide"]:
		var active: bool = sound_enabled and is_visible_in_tree() and region_id == "home" and (kind == "breeze" or (heat > 0 and distance < 18))
		if kind=="moon_tide":active=sound_enabled and is_visible_in_tree() and region_id=="home" and world.moon!=null and world.moon.contains(center)
		var player: AudioStreamPlayer = sounds[kind]
		if active:
			player.volume_db = -29 if kind == "breeze" else -24 if kind=="moon_tide" else -23 - distance * .8 + linear_to_db(heat)
			if not player.playing: player.play()
		elif player.playing: player.stop()

func _round_camp(_station:Dictionary,_point:Vector2,_state:String)->bool:return false
func _camp_glow(point: Vector2, state: String) -> void:
	var heat: float = Ambience.heat(state)
	if heat <= 0: return
	var flicker := .92 + sin(clock * 9) * .05 + sin(clock * 17) * .03
	draw_set_transform(screen(point) - Vector2(0, 28) * zoom, 0, Vector2(1, .45))
	for i in range(3): draw_circle(Vector2.ZERO, (78 - i * 17) * zoom, Color(1, .62, .2, .035 * heat * flicker))
	draw_set_transform(Vector2.ZERO)

func _camp_sprite(art: Dictionary, frame: String, point: Vector2, state: String) -> void:
	if state not in ["cooking", "needs_turn"]:
		_work_sprite(art, frame, point, Vector2(192, 176)); return
	# Animate highlights in the existing source artwork; no fixed replacement art.
	var index := int(clock * 8) % 3
	var key := "%s:%s:%s:%s" % [art.id, art.revision, frame, index]
	if not camp_textures.has(key):
		if camp_textures.size() >= 12: camp_textures.clear()
		var image: Image = library.render(art, frame)
		for y in range(int(art.height * .43), int(art.height * .82)):
			for x in range(int(art.width * .28), int(art.width * .72)):
				var color := image.get_pixel(x, y)
				if color.a > .1 and color.r > .55 and color.r > color.b * 1.7 and color.g > color.b * 1.2:
					var gain: float = [.88, 1.0, 1.1][index]
					image.set_pixel(x, y, Color(minf(color.r * gain, 1), minf(color.g * gain, 1), color.b, color.a))
		camp_textures[key] = ImageTexture.create_from_image(image)
	var size := Vector2(192, 176)
	var anchor := Vector2(art.anchor[0] / float(art.width), art.anchor[1] / float(art.height))
	draw_texture_rect(camp_textures[key], Rect2(screen(point) - size * anchor * zoom, size * zoom), false)

func _camp_smoke(point: Vector2, state: String) -> void:
	var heat: float = Ambience.heat(state)
	if heat <= 0: return
	var p := screen(point)
	for i in range(7):
		var puff: Dictionary = Ambience.smoke(clock, i, point, heat)
		var size := Vector2.ONE * float(puff.size) * zoom
		draw_texture_rect(textures.smoke, Rect2(p + puff.offset * zoom - size / 2, size), false, Color(1, 1, 1, puff.alpha*(.45 if world.weather.current().id=="rain" else 1.0)))
	if heat < .5: return
	for i in range(4):
		var life := fposmod(clock * .55 + i * .27, 1)
		var offset := Vector2(sin(i * 2 + clock) * 11 + life * 12, -52 - life * 42) * zoom
		draw_rect(Rect2(p + offset, Vector2(2, 3) * zoom), Color(1, .73, .32, sin(life * PI) * .65))

func _exit_tree() -> void:
	for player in sounds.values(): player.stop()

func _prepare_scenery() -> void:
	scenery.clear()
	var rng := RandomNumberGenerator.new(); rng.seed = 404
	var region: Dictionary = world.catalog.regions.home
	for i in range(650):
		var point := Vector2(rng.randf_range(12, region.size[0] - 8), rng.randf_range(10, region.size[1] - 8))
		if not world.walkable("home", point) or _near_path(point): continue
		var zone: String = world.catalog.zone_at("home", point)
		if world.farms.farms.values().any(func(farm): return world.catalog.rectangle(farm.rect).grow(2).has_point(point)): continue
		if zone in ["home.court", "home.garden", "home.second_court", "home.storage", "home.orchard", "home.east_orchard"]: continue
		var name: String = ["grass_clump", "flowers", "bush", "rock"][i % 4]
		scenery.append({"point": point, "name": name, "scale": rng.randf_range(.35, .68)})

func _draw_garden(garden: Dictionary) -> void:
	# One shared layout drives soil, rows, gate and fence collision. No overlapping bands.
	var apron: Rect2 = world.catalog.rectangle(garden.apron_rect)
	_surface(Layout.rectangle(apron, .4), textures.sand, Color("c6bb91"))
	var soil: Rect2 = world.catalog.rectangle(garden.soil_rect)
	_surface(Layout.rectangle(soil, .22), textures.soil, Color("9d9673"))
	var bed_size := Vector2(garden.bed_size[0], garden.bed_size[1])
	for plot in world.objects.values():
		if plot.kind != "farm_plot" or plot.zone_id != "home.garden": continue
		var rect := Rect2(world.point(plot) - bed_size / 2, bed_size)
		_surface(Layout.rectangle(rect, .13), textures.soil, Color("b9a883"))
		for row in range(3):
			var y := rect.position.y + .35 + row * .52
			draw_line(screen(Vector2(rect.position.x + .16, y)), screen(Vector2(rect.end.x - .16, y)), Color(.27, .18, .11, .45), 2 * zoom)
	# Straight, level crosspaths lead directly to the open east gate.
	var paths:Dictionary=Places.section("old_garden")
	for path in paths.vertical:_path(Layout.points(path),.22)
	for path in paths.horizontal:_path(Layout.points(path),.28)
	_path(Layout.points(paths.entry),.65)
	_sprite("barrel",Vector2(paths.barrel[0],paths.barrel[1]),.55)
	for at in paths.flowers:_sprite("flowers",Vector2(at[0],at[1]),.42)

func _draw_orchards() -> void:
	for zone in world.catalog.regions.home.zones:
		if zone.purpose != "orchard": continue
		var r: Rect2 = world.catalog.rectangle(zone.rect)
		_path(PackedVector2Array([Vector2(r.get_center().x, r.position.y), Vector2(r.get_center().x, r.end.y)]), .55)
		for i in range(3):
			for side in [-1, 1]:
				var at := Vector2(r.get_center().x + side * 4, r.position.y + 2 + i * 3)
				_surface(Layout.ellipse(at, Vector2(.8, .5)), textures.soil, Color("b3a886"))
				_sprite("flowers", at + Vector2(1.2, .4), .3)

func _draw_courtyard(site: Dictionary) -> void:
	var point: Vector2 = world.point(site)
	var half: Vector2 = world.site_size(site) / 2
	var stage := int(site.get("stage_index", 0))
	var yard := Rect2(point - half - Vector2(1.5, .7), half * 2 + Vector2(3, 4.5))
	_surface(Layout.rectangle(yard, .65), textures.sand, Color("c5c0a3"))
	var entry := point + Vector2(0, half.y)
	for i in range(4):
		var at := entry + Vector2(sin(i * 1.7) * .1, .5 + i * .7)
		var stone := Layout.rectangle(Rect2(at - Vector2(.65, .25), Vector2(1.3, .5)), .15)
		var pixels := PackedVector2Array()
		for p in stone: pixels.append(screen(p))
		draw_colored_polygon(pixels, Color("b9b29a"))
	if stage >= 3:
		for side in [-1, 1]:
			_sprite("bush", point + Vector2(side * (half.x + 1), half.y + 1), .45)
			_sprite("flowers", point + Vector2(side * (half.x + .6), half.y + 2.6), .48)
	if stage == 5:
		_sprite("barrel", point + Vector2(-half.x - .7, half.y - .5), .45)
	elif int(site.delivered.get("wood", 0)) > 0:
		_sprite("logs", point + Vector2(half.x + 1.3, half.y + 1), .65)

func _house_size(site: Dictionary) -> Vector2:
	if site.has("blueprint"):
		var s: Dictionary = site.blueprint.structure
		return Vector2(float(s.width) * 44, 280 + float(s.floors) * 90)
	return Vector2(352, 370)

func _draw_house(site: Dictionary) -> void:
	var stage := int(site.get("stage_index", 0))
	var point: Vector2 = world.point(site)
	var half: Vector2 = world.site_size(site) / 2
	var foot := point + Vector2(0, half.y)
	var size := _house_size(site)
	if stage == 0:
		var corners := Layout.rectangle(Rect2(point - half, half * 2))
		for i in range(corners.size()):
			var start := screen(corners[i]); var end := screen(corners[(i + 1) % corners.size()])
			draw_dashed_line(start, end, Color("dbca95"), 1.3, 7 * zoom)
		for corner in [point - half, point + Vector2(half.x, -half.y), point + half, point + Vector2(-half.x, half.y)]:
			var p := screen(corner)
			draw_line(p, p - Vector2(0, 15) * zoom, Color("8b6542"), 4 * zoom)
		if selected_id == site.id and site.has("blueprint"): _work_sprite(site.blueprint.artwork, "stage_0", foot, size, Color(1, 1, 1, .3))
	else:
		if stage==5 and preload("res://scripts/house_appearance.gd").enabled(site):
			var texture:Texture2D=preload("res://scripts/house_appearance.gd").texture(site,library,world.days.phase().id=="night" and atmosphere.occupied.has(site.id))
			draw_texture_rect(texture,Rect2(screen(foot)-Vector2(size.x/2,size.y-8)*zoom,size*zoom),false)
		elif site.has("blueprint"): _work_sprite(site.blueprint.artwork, "stage_%s" % (stage - 1), foot, size)
		else:
			var texture: Texture2D = preload("res://scripts/building_visual.gd").texture(site,library,stage)
			draw_texture_rect(texture, Rect2(screen(foot) - Vector2(size.x / 2, size.y - 8) * zoom, size * zoom), false)
	var door_age:float=clock-float(atmosphere.door_changes.get(site.id,-100))
	if stage==5 and door_age<.65:
		var at:=screen(world.interior.outside(world.interior.room_for(site.id)))
		draw_rect(Rect2(at+Vector2(-8,-25)*zoom,Vector2(16*sin(door_age/.65*PI),18)*zoom),Color("493529"))
	var worker: String = world.work.claims.get(site.id, "")
	var job: Dictionary = world.work.jobs.get(worker, {})
	if stage < 5 and job.get("phase") == "building" and site.has("blueprint"):
		var fraction := clampf(float(job.time) / world.work.BUILD_SECONDS, 0, 1)
		_work_sprite(site.blueprint.artwork, "stage_%s" % stage, foot, size, Color(1, 1, 1, fraction * .55))
	if stage > 0 and stage < 4:
		# Temporary scaffold beside the actual footprint, never a replacement house.
		var p := screen(point + Vector2(half.x + .6, half.y))
		for side in [-1, 1]: draw_line(p + Vector2(side * 15, 0) * zoom, p + Vector2(side * 15, -120) * zoom, Color("a87d4c"), 4 * zoom)
		for i in range(5): draw_line(p + Vector2(-19, -i * 25) * zoom, p + Vector2(19, -i * 25) * zoom, Color("c6a06a"), 3 * zoom)
	if selected_id == site.id or hover_id == site.id:
		var label: String = [LocalText.text("ui.island_view.home_site"), LocalText.text("ui.island_view.foundation_complete"), LocalText.text("ui.island_view.frame_complete"), LocalText.text("ui.island_view.walls_complete"), LocalText.text("ui.island_view.roof_complete"), LocalText.text("ui.island_view.our_home")][stage]
		var p := screen(foot) + Vector2(-35, 40 * zoom)
		draw_string_outline(font, p, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 3, Color("263e32"))
		draw_string(font, p, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("fff0cb"))

func _add_fence_entries(entries: Array, start: Vector2, end: Vector2) -> void:
	var horizontal := absf(start.x - end.x) > absf(start.y - end.y)
	var count := maxi(1, int(ceil(start.distance_to(end) / (3.8 if horizontal else 2.2))))
	for i in range(count):
		var a := start.lerp(end, float(i) / count); var b := start.lerp(end, float(i + 1) / count)
		var midpoint := (a + b) / 2
		entries.append({"type": "fence", "y": midpoint.y, "value": {"position": [midpoint.x, midpoint.y], "start": a, "end": b}})

func default_zoom(id:String,point:Vector2)->float:
	return camera_defaults.at(world,id,point)

func show_region(id: String) -> void:
	last_human_region=world.actors.human.region_id
	region_id = id; placement_recipe = ""; selected_id = ""; hover_id = ""
	follow_player = false
	if id in ["home","dark","homelands"]: center = world.point(world.actors.human); zoom = default_zoom(id,center)
	else:
		var entry: Array=Places.section("camera").room
		center=Vector2(entry[0],entry[1]);zoom=default_zoom(id,center)

var ground_catalog:WeakRef
var ground_land:PackedVector2Array
var ground_grass:Array[PackedVector2Array]=[]
var ground_roads:Array[Dictionary]=[]
var ground_ponds:Array[Dictionary]=[]
func _ground_mesh()->void:
	if ground_catalog!=null and ground_catalog.get_ref()==world.catalog:return
	ground_catalog=weakref(world.catalog)
	ground_land=world.catalog.polygon(world.catalog.regions.home)
	ground_grass=Geometry2D.offset_polygon(ground_land,-1.9,Geometry2D.JOIN_ROUND)
	ground_roads.clear();ground_ponds.clear()
	var layout:Dictionary=world.catalog.regions.home.layout
	for road in layout.roads:
		for polygon in _path_polygons(Layout.points(road.points),float(road.width)):
			var bounds:=Rect2(polygon[0],Vector2.ZERO)
			for at in polygon:bounds=bounds.expand(at)
			ground_roads.append({"points":polygon,"bounds":bounds})
	for pond in layout.ponds:
		var at:=Vector2(pond.center[0],pond.center[1])
		var radius:=Vector2(pond.radius[0],pond.radius[1])
		var shore:=Layout.pond_shape(pond)
		ground_ponds.append({"at":at,"radius":radius,"shore":shore,"bounds":Rect2(at-radius,radius*2).grow(6),
			"rim":Geometry2D.offset_polygon(shore,.65),"inner":Geometry2D.offset_polygon(shore,-.65)})

func _draw_ground(viewport:Rect2)->void:
	_ground_mesh()
	var visible_tiles:=Rect2(local_point(viewport.position),viewport.size/(32*zoom))
	var water_poly := PackedVector2Array([local_point(Vector2.ZERO), local_point(Vector2(viewport.size.x, 0)), local_point(viewport.size), local_point(Vector2(0, viewport.size.y))])
	_surface(water_poly, textures.water, Color("80b3bd"), Vector2(clock * 0.005, sin(clock * .12) * .015))
	var coast := PackedVector2Array()
	for point in ground_land: coast.append(screen(point))
	coast.append(coast[0])
	draw_polyline(coast, Color(0.48, 0.83, 0.78, 0.42), 38 * zoom, true)
	draw_polyline(coast, Color(0.81, 0.91, 0.74, 0.8), 13 * zoom, true)
	_surface(ground_land,textures.sand,Color("f0d8a5"))
	for inner in ground_grass:_surface(inner,textures.grass,Color("a9ba9e"))
	for road in ground_roads:
		if visible_tiles.intersects(road.bounds):_surface(road.points,textures.sand,Color("d9cbaa"))
	for pond in ground_ponds:
		if not visible_tiles.intersects(pond.bounds):continue
		for rim in pond.rim:_surface(rim,textures.sand,Color("c9bb91"))
		_surface(pond.shore,textures.water,Color("78c0bb"),Vector2(clock*.003,0))
		for inner in pond.inner:_surface(inner,textures.water,Color("77aeb2"),Vector2(clock*.003,0))
		for i in range(11):
			var angle := i * .57
			var edge:Vector2=pond.at+Vector2(cos(angle),sin(angle))*(pond.radius+Vector2.ONE*.8)
			_sprite("rock" if i % 3 == 0 else "grass_clump", edge, .42 if i % 3 == 0 else .6)

func _add_house_fences(entries:Array)->void:
	for site in world.objects.values():
		if site.kind == "construction_site" and int(site.get("stage_index", 0)) == 5:
			for fence in Layout.yard_fences(world.point(site), world.site_size(site) / 2): _add_fence_entries(entries, fence[0], fence[1])

func _extra_entries(_entries:Array)->void:pass
func _draw_extra_entry(_entry:Dictionary)->bool:return false

func _wrap_speech(value:String,width:float,characters:bool=false)->String:
	var lines:PackedStringArray=[];var current:=""
	var separator:String="" if characters else " "
	for word in value.split(separator,false):
		var candidate:String=word if current.is_empty() else current+separator+word
		if not current.is_empty() and font.get_string_size(candidate,HORIZONTAL_ALIGNMENT_LEFT,-1,preload("res://scripts/ui_scale.gd").pixels(14)).x>width:lines.append(current);current=word
		else:current=candidate
	if not current.is_empty():lines.append(current)
	return "\n".join(lines)

func _draw_creation_flowers()->void:
	if world.flower_creation==null:return
	var visible:Rect2=get_viewport_rect().grow(20)
	var offset:=Vector2(14,19)*zoom
	var size:=Vector2(28,28)*zoom
	var colors:Dictionary={}
	for f in world.flower_creation.flowers.values():
		if f.region_id!=region_id:continue
		var at:Vector2=screen(Vector2(f.position[0],f.position[1]))
		if not visible.has_point(at):continue
		if not colors.has(f.color):colors[f.color]=preload("res://scripts/resort_renderer.gd").asset("rose-"+f.color)
		var tex:Texture2D=colors[f.color]
		if tex!=null:draw_texture_rect(tex,Rect2(at-offset,size),false)

var creation_textures: Dictionary={}
func _draw_world_creations()->void:
	var layer: RefCounted=world.flower_creation.creations
	var clip: Rect2=get_viewport_rect().grow(64)
	var mouse:=get_local_mouse_position()
	for row in layer.pieces.values():
		if row.region!=region_id:continue
		var at:=screen(world.point(row))
		if not clip.has_point(at):continue
		if not creation_textures.has(row.item):
			creation_textures[row.item]=load(preload("res://scripts/world_creations.gd").Catalog[row.item].texture)
		var texture: Texture2D=creation_textures[row.item]
		if texture!=null:
			var size:=Vector2(32,32)*zoom
			var ground:bool=preload("res://scripts/world_creations.gd").Catalog[row.item].get("ground",false)
			draw_texture_rect(texture,Rect2(at-size*(Vector2(.5,.5) if ground else Vector2(.5,.7)),size),false)
		var hovered:=Rect2(at-Vector2(16,24)*zoom,Vector2(32,32)*zoom).has_point(mouse)
		if not row.label.is_empty() and (row.item=="sign" or hovered):
			draw_string_outline(font,at+Vector2(-12,-20),row.label,HORIZONTAL_ALIGNMENT_LEFT,-1,13,3,Color("24392f"))
			draw_string(font,at+Vector2(-12,-20),row.label,HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("fff4db"))
		if row.item=="sign" and hovered and not str(row.get("author","")).is_empty():
			draw_string_outline(font,at+Vector2(-12,-37),row.author,HORIZONTAL_ALIGNMENT_LEFT,-1,13,3,Color("24392f"))
			draw_string(font,at+Vector2(-12,-37),row.author,HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("fff4db"))
		if row.created>layer.seen:draw_circle(at+Vector2(12,-12)*zoom,3,Color("fff0a0"))
