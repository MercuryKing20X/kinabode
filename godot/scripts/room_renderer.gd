class_name RoomRenderer
extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
var shell: Texture2D = preload("res://assets/interior/room.png")

func draw(view: Node2D) -> void:
	var world: RefCounted = view.world
	var region: String = view.region_id
	view.draw_rect(view.get_viewport_rect(), Color("1e342e"))
	# The shell is empty architecture; residents and every usable object are separate.
	view.draw_texture_rect(shell, Rect2(view.screen(Vector2(-3.225, -6.2)), Vector2(32.45, 20.48) * 32 * view.zoom), false)
	var rooms:Dictionary=world.interior.rooms()
	if rooms.has(region):
		var site:Dictionary=world.objects[rooms[region].site_id]
		if preload("res://scripts/house_appearance.gd").enabled(site):themed_details(view,site)
	var entries: Array = []
	for item in world.interior.furniture.values():
		if item.region_id != region or not world.interior.placed(item): continue
		if item.recipe_id == "rug": furniture(view, item)
		else: entries.append({"y": item.position[1], "type": "furniture", "value": item})
	for actor in world.actors.values():
		if actor.region_id == region: entries.append({"y": actor.position[1] + .1, "type": "actor", "value": actor})
	for actor in view.world.actors.values():
		if actor.region_id==region:view.fishing_renderer.held_back(view,actor)
	entries.sort_custom(func(a, b): return a.y < b.y)
	for entry in entries:
		if entry.type == "actor": view._actor(entry.value)
		else: furniture(view, entry.value)
	var door_at: Vector2 = view.screen(world.interior.door(region) + Vector2(0, 1.6))
	view.draw_string(view.font, door_at - Vector2(21, 0), LocalText.text("ui.room_renderer.yard"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("fff4db"))
	var candidate: Dictionary = preview(view)
	if not candidate.is_empty():
		var valid: bool = world.interior.placement(region, candidate, candidate.get("id", ""))
		var box: Rect2 = world.interior.area(candidate)
		view.draw_rect(Rect2(view.screen(box.position), box.size * 32 * view.zoom), Color(.5, .85, .65, .3) if valid else Color(.95, .3, .3, .35))
		furniture(view, candidate, .65)
	view._draw_social_gestures()
	view._draw_resident_labels()

func preview(view: Node2D) -> Dictionary:
	var actor: Dictionary = view.world.actors.human
	var carried: String = str(actor.get("furniture_id", ""))
	var recipe: String = view.placement_recipe
	if recipe.is_empty() and carried.is_empty(): return {}
	var item: Dictionary = view.world.interior.furniture[carried].duplicate(true) if not carried.is_empty() else {"id": "", "recipe_id": recipe, "artwork": view.library.artworks["furniture-" + recipe], "facing": "down"}
	var p: Vector2 = view.local_point(view.get_viewport().get_mouse_position()).floor() + Vector2(.5, .5)
	item.position = [p.x, p.y]; item.region_id = view.region_id
	return item

func furniture(view: Node2D, item: Dictionary, alpha: float = 1) -> void:
	var art: Dictionary = item.artwork
	if art.is_empty(): art = view.library.artworks["furniture-" + str(item.recipe_id)]
	var frame := "up" if item.facing == "up" else "down"
	var texture: Texture2D = view.library.frozen_texture(art, frame)
	var p: Vector2 = view.screen(view.world.point(item))
	var size: Vector2 = Vector2(art.width, art.height) * view.zoom
	if item.recipe_id == "lamp":
		view.draw_set_transform(p - Vector2(0, 32) * view.zoom, 0, Vector2(1, .5))
		view.draw_circle(Vector2.ZERO, (75 + sin(view.clock * 1.4) * 2) * view.zoom, Color(1, .75, .35, .07 * alpha))
		view.draw_set_transform(Vector2.ZERO)
	view.draw_texture_rect(texture, Rect2(p - Vector2(art.anchor[0], art.anchor[1]) * view.zoom, size), false, Color(1, 1, 1, alpha))

func hit(view: Node2D, mouse: Vector2) -> String:
	var p: Vector2 = view.local_point(mouse)
	if Rect2(12, 7.8, 3, 4.3).has_point(p): return "room.exit"
	var items: Array = view.world.interior.furniture.values().filter(func(item): return item.region_id == view.region_id and view.world.interior.placed(item))
	items.sort_custom(func(a, b): return a.position[1] > b.position[1])
	for item in items:
		if item.recipe_id == "rug": continue
		var art: Dictionary = item.artwork if not item.artwork.is_empty() else view.library.artworks["furniture-" + item.recipe_id]
		var rect := Rect2(view.screen(view.world.point(item)) - Vector2(art.anchor[0], art.anchor[1]) * view.zoom, Vector2(art.width, art.height) * view.zoom)
		if rect.has_point(mouse): return item.id
	for item in items:
		if item.recipe_id == "rug" and view.world.interior.area(item).has_point(p): return item.id
	return ""


func themed_details(view:Node2D,site:Dictionary)->void:
	# Wall accents and ornaments are cosmetic, never furniture/inventory instances.
	var owner:String=preload("res://scripts/house_appearance.gd").owner(site)
	var tones:Dictionary={"human":Color("bd9873"),"codex":Color("a4b5b3"),"companion-2":Color("c1a2a7"),"npc.mira":Color("a38666"),"npc.nora":Color("787c8f")}
	var tint:Color=tones[owner];tint.a=.16
	view.draw_rect(Rect2(view.screen(Vector2(1,1)),Vector2(24,8)*32*view.zoom),tint)
	for i in range(4):
		var at:Vector2=view.screen(Vector2(4+i*5,1.2))
		var size:float=32*view.zoom
		var dark:=Color("594b40");var light:=Color("cbb58a")
		if owner=="codex":
			view.draw_rect(Rect2(at,Vector2(.6,.3)*size),Color("ac7e5f"))
			view.draw_circle(at+Vector2(.3,-.15)*size,.19*size,Color("668969"))
			view.draw_circle(at+Vector2(.25,-.25)*size,.09*size,Color("c69fa9"))
		elif owner=="npc.nora":
			for j in range(4):
				view.draw_rect(Rect2(at+Vector2(j*.12,0)*size,Vector2(.09,.4)*size),Color("8f8b9b") if j%2==0 else light)
		elif owner=="npc.mira":
			view.draw_line(at,at+Vector2(0,.5)*size,light,3*view.zoom)
			view.draw_line(at+Vector2(-.15,0)*size,at+Vector2(.18,0)*size,dark,5*view.zoom)
		elif owner=="companion-2":
			view.draw_rect(Rect2(at,Vector2(.6,.12)*size),light)
			for j in range(3):view.draw_circle(at+Vector2(.12+j*.17,-.12)*size,.08*size,Color("bb977b"))
		else:
			view.draw_rect(Rect2(at,Vector2(.5,.35)*size),dark)
			view.draw_rect(Rect2(at+Vector2(.05,.05)*size,Vector2(.4,.25)*size),light)
