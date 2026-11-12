class_name FreePixelCanvas
extends Control

signal changed
signal edited
var library: RefCounted
var art: Dictionary = {}
var frame := "down_0"
var layer := 0
var color := Color("f4dca5")
var eraser := false
var fill_tool := false
var pixel_scale := 4.0
var undo_stack: Array = []
var redo_stack: Array = []
var _image: Texture2D
var _painting := false
var _last := Vector2i(-1, -1)

func refresh() -> void:
	_image = ImageTexture.create_from_image(library.render(art, frame))
	queue_redraw()
	changed.emit()

func checkpoint() -> void:
	edited.emit()
	undo_stack.append({"frame": frame, "layers": art.frames[frame].duplicate(true)})
	if undo_stack.size() > 40: undo_stack.pop_front()
	redo_stack.clear()

func checkpoint_outfit() -> void:
	edited.emit()
	undo_stack.append({"frame": frame, "outfit": art.get("outfit", {}).duplicate(true), "had_outfit": art.has("outfit")})
	if undo_stack.size() > 40: undo_stack.pop_front()
	redo_stack.clear()

func undo() -> void:
	if undo_stack.is_empty(): return
	var previous: Dictionary = undo_stack.pop_back()
	if previous.has("had_outfit"):
		redo_stack.append({"frame":frame,"outfit":art.get("outfit",{}).duplicate(true),"had_outfit":art.has("outfit")})
		if previous.had_outfit: art.outfit = previous.outfit
		else: art.erase("outfit")
		edited.emit(); refresh(); return
	redo_stack.append({"frame": previous.frame, "layers": art.frames[previous.frame].duplicate(true)})
	art.frames[previous.frame] = previous.layers
	frame = previous.frame; layer = clampi(layer, 0, art.frames[frame].size() - 1)
	edited.emit(); refresh()

func redo() -> void:
	if redo_stack.is_empty(): return
	var next: Dictionary = redo_stack.pop_back()
	if next.has("had_outfit"):
		undo_stack.append({"frame":frame,"outfit":art.get("outfit",{}).duplicate(true),"had_outfit":art.has("outfit")})
		if next.had_outfit: art.outfit = next.outfit
		else: art.erase("outfit")
		edited.emit(); refresh(); return
	undo_stack.append({"frame": next.frame, "layers": art.frames[next.frame].duplicate(true)})
	art.frames[next.frame] = next.layers
	frame = next.frame; layer = clampi(layer, 0, art.frames[frame].size() - 1)
	edited.emit(); refresh()

func _draw() -> void:
	if art.is_empty(): return
	var bounds := Vector2(art.width, art.height) * pixel_scale
	for y in range(0, int(bounds.y), 16):
		for x in range(0, int(bounds.x), 16):
			draw_rect(Rect2(x, y, 16, 16), Color("303e46") if (x / 16 + y / 16) % 2 == 0 else Color("37464e"))
	if _image != null: draw_texture_rect(_image, Rect2(Vector2.ZERO, bounds), false)

func _index() -> int:
	var value := "#00000000" if eraser else "#" + color.to_html(true)
	var index: int = art.palette.find(value)
	if index < 0:
		index = art.palette.size()
		art.palette.append(value)
	return index

func paint(point: Vector2i) -> void:
	if point.x < 0 or point.y < 0 or point.x >= art.width or point.y >= art.height: return
	var pixels: Array = art.frames[frame][layer].pixels
	var index := _index()
	var offset := point.y * int(art.width) + point.x
	if fill_tool:
		var original: int = int(pixels[offset])
		if original == index: return
		var queue: Array[int] = [offset]
		pixels[offset] = index
		var head := 0
		while head < queue.size():
			var item := queue[head]; head += 1
			var x := item % int(art.width)
			var y := item / int(art.width)
			for neighbor in [Vector2i(x - 1, y), Vector2i(x + 1, y), Vector2i(x, y - 1), Vector2i(x, y + 1)]:
				if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= art.width or neighbor.y >= art.height: continue
				var n: int = neighbor.y * int(art.width) + neighbor.x
				if int(pixels[n]) == original:
					pixels[n] = index
					queue.append(n)
	else: pixels[offset] = index

func _gui_input(event: InputEvent) -> void:
	if art.is_empty(): return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_painting = event.pressed
		if _painting:
			checkpoint()
			_last = Vector2i(event.position / pixel_scale)
			paint(_last)
			refresh()
		accept_event()
	elif event is InputEventMouseMotion and _painting and not fill_tool:
		var point := Vector2i(event.position / pixel_scale)
		var steps := maxi(absi(point.x - _last.x), absi(point.y - _last.y))
		for i in range(steps + 1): paint(Vector2i(Vector2(_last).lerp(Vector2(point), float(i) / maxf(steps, 1))))
		_last = point
		refresh()
		accept_event()

func finish_stroke() -> void:
	_painting = false; _last = Vector2i(-1, -1)

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree(): finish_stroke()
