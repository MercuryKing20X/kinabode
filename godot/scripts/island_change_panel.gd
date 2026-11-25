extends AcceptDialog

const Words = preload("res://scripts/world_door_panel.gd")
const Creations = preload("res://scripts/world_creations.gd")
var game: Node
var rows: VBoxContainer
var last_input := 0
var started := false
var inspecting := false

func setup(host: Node) -> void:
	game = host
	size = Vector2i(560,430)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	rows=VBoxContainer.new()
	rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	last_input=Time.get_ticks_msec()
	confirmed.connect(mark_seen)

func input(event: InputEvent) -> bool:
	if not (event is InputEventKey or event is InputEventMouseButton) or not event.is_pressed() or event.is_echo():return false
	var now := Time.get_ticks_msec()
	var was_away := now-last_input>=300000
	last_input=now
	if inspecting and event is InputEventKey:
		inspecting=false
		game._return_to_player()
		return true
	if was_away and unseen():open(true)
	return false

func data() -> RefCounted:return game.world.flower_creation.creations
func unseen() -> bool:return data().seen < data().sequence
func mark_seen() -> void:
	data().seen=data().sequence
	game.world.revision+=1

func open(away: bool = false) -> void:
	title=Words.phrase("你不在的时候","While you were away") if away else Words.phrase("岛上日志","Island log")
	get_ok_button().text=Words.phrase("看过了","Mark as seen")
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	var source: RefCounted=data()
	if not away:
		for day in source.summaries:
			label(Words.phrase("第 %s 天：%s 处变化","Day %s: %s changes") % [day,int(source.summaries[day])])
	var groups: Dictionary={}
	for row in source.changes:
		if away and row.id<=source.seen:continue
		if not groups.has(row.actor):groups[row.actor]=[]
		groups[row.actor].append(row)
	if groups.is_empty():label(Words.phrase("还没有新变化。","No new changes yet."))
	for id in groups:
		var person: String=Words.phrase("你","You") if id=="human" else preload("res://scripts/localization.gd").resident(game.world,id)
		label(person)
		for row in groups[id]:
			var pair: Array={"placed":["摆放","Placed"],"removed":["拆除","Removed"],"named":["命名","Named"],"note":["留纸条","Left a note"],"diary":["写日记","Wrote a diary entry"],"structure_removed":["拆除建筑","Dismantled"]}[row.action]
			var name: Dictionary=Creations.Catalog.get(row.item,{"zh":row.description,"en":row.description})
			var time: String="%02d:%02d" % [int(float(row.minute)/60.0),int(row.minute)%60]
			label(Words.phrase("第 %d 天 %s · %s %s","Day %d %s · %s %s") % [int(row.day),time,Words.phrase(pair[0],pair[1]),Words.phrase(name.zh,name.en)])
			if not row.description.is_empty():label(row.description)
			if not row.reason.is_empty():label(row.reason)
			var go := Button.new()
			go.text=Words.phrase("去看看","Go see")
			go.size_flags_horizontal=Control.SIZE_SHRINK_END
			rows.add_child(go)
			go.pressed.connect(func():
				hide()
				game._toggle_atlas(false)
				var p:Vector2=game.world.point(row)
				if game.view.has_method("focus_location"):game.view.focus_location(p)
				else:
					game.view.show_region(row.region)
					game.view.follow_player=false
					game.view.center=p
				inspecting=true)
	popup_centered()

func label(line: String) -> void:
	var cell:=Label.new()
	cell.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	cell.text=line
	rows.add_child(cell)
