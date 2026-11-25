extends PanelContainer

const Pieces=preload("res://scripts/world_creations.gd")
const Text=preload("res://scripts/localization.gd")
var game:Node
var selected:=""
var at:=Vector2.INF
var pending:Dictionary={}
var stock:Label
var notice:Label
var names:LineEdit
var choices:Dictionary={}
var previous_stock:=-1
var preview_at:=Vector2.INF
var preview_time:=0.0
var preview_problem:Dictionary={}
var line_start:=Vector2.INF
var queued_cells:Array[Vector2]=[]
var line_tool:CheckButton

func setup(host:Node)->void:
	game=host
	z_index=134
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	offset_left=-306;offset_right=-16;offset_top=52
	var stack:=VBoxContainer.new()
	add_child(stack)
	stock=Label.new();stack.add_child(stock)
	var group:=ButtonGroup.new()
	var scroll:=ScrollContainer.new()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y=310
	stack.add_child(scroll)
	var items:=VBoxContainer.new()
	items.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(items)
	for id in Pieces.Catalog:
		var row:Dictionary=Pieces.Catalog[id]
		var button:=Button.new()
		button.text=Pieces.phrase(row.zh,row.en)+" · "+str(int(row.material.wood))
		button.icon=load(row.texture);button.expand_icon=true
		button.add_theme_constant_override("icon_max_width",22)
		button.tooltip_text=Pieces.phrase("可通行","Walkable") if row.walkable else Pieces.phrase("会挡路","Blocks walking")
		button.alignment=HORIZONTAL_ALIGNMENT_LEFT
		button.button_group=group;button.toggle_mode=true
		items.add_child(button);choices[id]=button
		button.pressed.connect(func():choose(id))
	line_tool=CheckButton.new()
	line_tool.text=Pieces.phrase("刷直线","Paint a line")
	line_tool.toggled.connect(func(_on):line_start=Vector2.INF)
	stack.add_child(line_tool)
	for mode in ["remove_piece","name_place","remove_structure"]:
		var button:=Button.new()
		button.text={"remove_piece":Pieces.phrase("拆除摆件","Remove piece"),"name_place":Pieces.phrase("命名","Name"),"remove_structure":Pieces.phrase("拆除建筑","Remove structure")}[mode]
		button.button_group=group;button.toggle_mode=true
		stack.add_child(button);choices[mode]=button
		button.pressed.connect(func():choose(mode))
	names=LineEdit.new();names.max_length=120
	names.placeholder_text=Pieces.phrase("摆件名","Piece name")
	stack.add_child(names);names.hide()
	notice=Label.new();notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	notice.custom_minimum_size.x=250;stack.add_child(notice)
	Text.events.changed.connect(refresh_locale)
	hide()

func refresh_locale()->void:
	for id in Pieces.Catalog:
		var row:Dictionary=Pieces.Catalog[id]
		choices[id].text=Pieces.phrase(row.zh,row.en)+" · "+str(int(row.material.wood))
		choices[id].tooltip_text=Pieces.phrase("可通行","Walkable") if row.walkable else Pieces.phrase("会挡路","Blocks walking")
	choices.remove_piece.text=Pieces.phrase("拆除摆件","Remove piece")
	choices.name_place.text=Pieces.phrase("命名","Name")
	choices.remove_structure.text=Pieces.phrase("拆除建筑","Remove structure")
	line_tool.text=Pieces.phrase("刷直线","Paint a line")
	names.placeholder_text=Pieces.phrase("摆件名","Piece name")
	previous_stock=-1
	stock.text=""
	notice.text=""

func choose(id:String)->void:
	selected=id;at=Vector2.INF;preview_at=Vector2.INF
	line_start=Vector2.INF
	line_tool.visible=id=="path" or Pieces.Catalog.get(id,{}).get("ground",false)
	names.visible=id=="name_place"
	if names.visible:names.grab_focus()
	notice.text=""

func toggle()->void:
	if visible:cancel()
	else:show()

func cancel()->void:
	if not pending.is_empty() and is_same(game.world._routes.get("human"),pending.route):
		game.world._routes.erase("human")
		game.world._forced_runs.erase("human")
		game.world.actors.human.activity="idle"
	pending.clear()
	queued_cells.clear()
	if choices.has(selected):choices[selected].set_pressed_no_signal(false)
	choose("");hide()

func error_text(problem:Dictionary)->String:
	if problem.has("message"):return problem.message
	match problem.get("error"):
		"insufficient_materials":return Pieces.phrase("仓库木材不够。","The warehouse is short of wood.")
		"protected_or_missing":return Pieces.phrase("只能操作已摆下的摆件。","Only placed pieces can be changed.")
		"not_land":return Pieces.phrase("请选主岛或月牙岛的空地。","Choose ground on the main island or Crescent Island.")
		"unreachable":return Pieces.phrase("走不到那里。","There's no route to that spot.")
		"active_route":return Pieces.phrase("有人正从这里经过。","Someone is on their way through here.")
		"busy":return Pieces.phrase("先完成手头的事。","Finish what you're doing first.")
		"storage_full":return Pieces.phrase("仓库满了，放不下退回的材料。","The warehouse has no room for the refund.")
		"invalid_label":return Pieces.phrase("请输入一个简短的名字。","Enter a short name for the piece.")
		"protected_structure","dependent_facility":return Pieces.phrase("这座建筑仍受保护。","This structure is still protected.")
		"structure_in_use":return Pieces.phrase("有人正在使用这座建筑。","Someone is using this structure.")
		"structure_missing":return Pieces.phrase("这里没有已建建筑。","There is no completed structure here.")
		"last_camp":return Pieces.phrase("请先建好另一座能走到的营火。","Build another reachable campfire first.")
	return Pieces.phrase("这里放不下。","There's no room here.")

func active()->bool:
	return visible and not selected.is_empty() and game.view.visible and game.view.region_id==game.world.actors.human.region_id

func action()->String:
	return selected if selected in ["remove_piece","name_place","remove_structure"] else "place_piece"

func step()->Dictionary:
	return {"position":[at.x,at.y],"item":selected,"label":names.text.strip_edges()}

func map_input(event:InputEvent)->bool:
	if not active():return false
	if event is InputEventMouseMotion:
		at=game.view.local_point(event.position).round()
		return false
	if not (event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT):return false
	at=game.view.local_point(event.position).round()
	if game.autonomy!=null:game.autonomy.player_input()
	queued_cells.clear()
	if line_tool.visible and line_tool.button_pressed:
		if not line_start.is_finite():
			line_start=at
			notice.text=Pieces.phrase("选择直线的终点。","Choose the end of the line.")
			return true
		var origin:=line_start
		var difference:=at-origin
		line_start=Vector2.INF
		if difference.length()>23 or (difference.x!=0 and difference.y!=0):
			notice.text=Pieces.phrase("请选择同一行或列，最多 24 格。","Choose the same row or column, up to 24 tiles.")
			return true
		for i in range(1,int(difference.length())+1):queued_cells.append(origin+difference.sign()*i)
		at=origin
	start_at()
	return true

func start_at()->void:
	var w:RefCounted=game.world
	var layer:RefCounted=w.flower_creation.creations
	var args:=step()
	var kind:=action()
	var problem:Dictionary
	if kind=="remove_structure":
		args["target"]=""
		var distance:=4.0
		for site in w.leisure.sites.values():
			var d:float=w.point(site).distance_to(at)
			if site.complete and d<distance:args.target=site.id;distance=d
		for camp in w.barbecues.values():
			var d:float=w.point(camp.station).distance_to(at)
			if w.standard.ready(camp.station.id) and d<=distance:args.target=camp.station.id;distance=d
		problem=layer.structure_check(args.target)
		if problem.is_empty():at=w.point(w.barbecues[args.target].station if w.barbecues.has(args.target) else w.leisure.sites[args.target])
	else:problem=layer.check("human",kind,args)
	if problem.is_empty() and not w.flower_creation.preflight("human").ok:problem={"error":"busy"}
	if problem.is_empty() and w.actors.human.has("furniture_id"):problem={"error":"busy"}
	if not problem.is_empty():notice.text=error_text(problem);queued_cells.clear();return
	var route:Array[Vector2]=layer.approach("human",at)
	if not w._apply_route("human",route):notice.text=error_text({"error":"unreachable"});queued_cells.clear();return
	pending={"action":kind,"step":args,"route":w._routes.human,"generation":w.session_generation,"region":w.actors.human.region_id,"at":route.back(),"delay":0.0}
	notice.text=""

func _process(delta:float)->void:
	var w:RefCounted=game.world
	var layer:RefCounted=w.flower_creation.creations
	if visible:
		var quantity:int=w.storage.count("wood")
		if quantity!=previous_stock:
			stock.text=Pieces.phrase("仓库木材：%d","Warehouse wood: %d")%quantity
			previous_stock=quantity
		preview_time+=delta
		if active() and action()!="remove_structure" and at.is_finite() and (at!=preview_at or preview_time>.3):
			preview_at=at;preview_time=0
			preview_problem=layer.check("human",action(),step(),true)
	if pending.is_empty():return
	var route:Variant=w._routes.get("human")
	if pending.generation!=w.session_generation or pending.region!=w.actors.human.region_id or (route!=null and not is_same(route,pending.route)):pending.clear();queued_cells.clear();return
	if route!=null:return
	if w.point(w.actors.human).distance_to(pending.at)>.2 or not w.flower_creation.preflight("human").ok:pending.clear();queued_cells.clear();return
	pending.delay+=delta
	if pending.delay<(1.5 if pending.action=="remove_structure" else .45):return
	var result:String=layer.remove_structure("human",pending.step.target,"") if pending.action=="remove_structure" else layer.commit("human",pending.action,pending.step,"")
	notice.text="" if result.is_empty() else error_text(layer.last_refusal.get("human",{"error":result}))
	pending.clear();preview_at=Vector2.INF
	if not result.is_empty():queued_cells.clear()
	elif not queued_cells.is_empty():
		at=queued_cells.pop_front()
		start_at()

func draw_preview(view:Node2D)->void:
	if not active() or not at.is_finite() or preview_at!=at or get_global_rect().has_point(view.get_global_mouse_position()):return
	var p:Vector2=view.screen(at)
	var width:float=32.0*view.zoom
	var fill:=Color(.22,.88,.48,.35) if preview_problem.is_empty() else Color(1,.27,.20,.45)
	var rect:=Rect2(p-Vector2.ONE*width/2,Vector2.ONE*width)
	view.draw_rect(rect,fill)
	fill.a=1.0
	view.draw_rect(rect,fill,false,2.0)
