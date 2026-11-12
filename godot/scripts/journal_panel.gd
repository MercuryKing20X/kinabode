class_name JournalPanel
extends Control
const LocalText=preload("res://scripts/localization.gd")
var _locale_static:Dictionary={}
func T(key:String)->String:
	var value:String=LocalText.text(key);_locale_static[value]=key;return value
func _refresh_static(node:Node)->void:
	if node is Control and (node is Label or (node is Button and not node is OptionButton)):
		if not node.has_meta("locale_key") and _locale_static.has(node.text):node.set_meta("locale_key",_locale_static[node.text])
		if node.has_meta("locale_key"):node.text=T(str(node.get_meta("locale_key")))
	for child in node.get_children():_refresh_static(child)
var world: RefCounted
var renderer: RefCounted
var card: PanelContainer
var actors: OptionButton
var status: Label
var heading: Label
var large_picture:TextureRect
var description: Label
var detail: Label
var species_list: VBoxContainer
var grid: GridContainer
var progress_labels: Dictionary={}
var species_id:=""
var selected_id:=""
var last_revision:=""
var book_footer:Label
var book_title:Label
var elapsed:=0.0

func button(parent: Node,text: String,callback: Callable) -> Button:
	var result:=Button.new();result.focus_mode=Control.FOCUS_NONE;result.text=text;result.pressed.connect(callback);parent.add_child(result);return result
func label(parent: Node,text: String,point_size: int=18) -> Label:
	var result:=Label.new();result.text=text;result.add_theme_font_size_override("font_size",point_size);result.add_theme_color_override("font_color",Color("fff4db"));parent.add_child(result);return result
func setup(source: RefCounted,fish_renderer: RefCounted) -> void:
	world=source;renderer=fish_renderer;set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);mouse_filter=Control.MOUSE_FILTER_IGNORE
	card=PanelContainer.new();add_child(card);card.set_anchors_and_offsets_preset(Control.PRESET_CENTER);card.offset_left=-540;card.offset_right=540;card.offset_top=-360;card.offset_bottom=360
	var style:=StyleBoxFlat.new();style.bg_color=Color("eee1bc");style.border_color=Color("506354");style.set_border_width_all(5);style.set_corner_radius_all(12)
	for side in ["left","right","top","bottom"]:style.set("content_margin_"+side,18)
	card.add_theme_stylebox_override("panel",style)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",10);card.add_child(column)
	var top:=HBoxContainer.new();column.add_child(top)
	var title:=label(top,LocalText.content(world.journal.config.title),26);book_title=title;title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	actors=OptionButton.new();actors.custom_minimum_size.x=180;top.add_child(actors);actors.item_selected.connect(func(_index):selected_id="";refresh(true))
	button(top,T("activities.book_close"),hide)
	status=label(column,"")
	var body:=HBoxContainer.new();body.size_flags_vertical=Control.SIZE_EXPAND_FILL;body.add_theme_constant_override("separation",18);column.add_child(body)
	var species_scroll:=ScrollContainer.new();species_scroll.custom_minimum_size.x=174;species_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;species_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;body.add_child(species_scroll)
	species_list=VBoxContainer.new();species_list.custom_minimum_size.x=174;species_scroll.add_child(species_list)
	for id in world.journal.config.species:
		var option:=button(species_list,"",func():species_id=id;selected_id="";refresh(true));option.custom_minimum_size.y=48;progress_labels[id]=option
	var page:=VBoxContainer.new();page.size_flags_horizontal=Control.SIZE_EXPAND_FILL;page.add_theme_constant_override("separation",8);body.add_child(page)
	heading=label(page,"",24);description=label(page,"");description.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	large_picture=TextureRect.new();large_picture.custom_minimum_size=Vector2(260,100);large_picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;large_picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;page.add_child(large_picture)
	var scroll:=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;page.add_child(scroll)
	grid=GridContainer.new();grid.columns=4;grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL;grid.add_theme_constant_override("h_separation",8);grid.add_theme_constant_override("v_separation",8);scroll.add_child(grid)
	detail=label(column,T("activities.choose_card"),17);detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;detail.custom_minimum_size.y=52
	book_footer=label(column,T("activities.journal_help"),16);book_footer.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	species_id=world.journal.config.species[0];hide()
	if not LocalText.events.changed.is_connected(refresh_locale):LocalText.events.changed.connect(refresh_locale)

func actor_id() -> String:return str(actors.get_item_metadata(actors.selected)) if actors.item_count>0 else "human"
func open(id: String="human") -> void:
	_fit_language_layout()
	actors.clear()
	for actor in world.actors.values():
		actors.add_item(T("activities.read_resident")+LocalText.resident(world,actor.id));actors.set_item_metadata(actors.item_count-1,actor.id)
		if actor.id==id:actors.select(actors.item_count-1)
	selected_id="";show();refresh(true)
func refresh(force: bool=false) -> void:
	if actors.item_count==0:return
	var summary: Dictionary=world.journal.summary(actor_id())
	if not force and last_revision==summary.revision:return
	last_revision=summary.revision
	status.text=T("activities.journal_count")%[LocalText.resident(world,actor_id()),summary.discovered,summary.total]
	for id in progress_labels:
		var found: Dictionary=world.journal.query(actor_id(),{"species_id":id,"status":"caught"})
		progress_labels[id].text=LocalText.content(world.journal.label("species",id))+"  "+str(found.total)+"/"+str(world.journal.config.colors.size()*world.journal.config.sizes.size())
	heading.text=LocalText.content(world.journal.label("species",species_id));description.text=LocalText.content(world.journal.config.descriptions[species_id])
	large_picture.texture=renderer.texture(species_id,"cream",world.fishing.rules)
	large_picture.modulate=Color.WHITE if world.journal.maximum(actor_id(),species_id)>0 else Color(.3,.4,.35,.35)
	for spec in world.fishing.rules.species:
		if spec.id!=species_id:continue
		description.text+="\n"+T("fishv3.hints")%[T("fishv3.island."+str(spec.get("island","main"))),T("fishv3."+str(spec.get("appearance","night" if spec.get("night_only",false) else "any"))),T("fishv3."+str(spec.get("weather","any")))]+"\n"+T("fishv3.maximum")%world.journal.maximum(actor_id(),species_id)
	for child in grid.get_children():grid.remove_child(child);child.queue_free()
	var result: Dictionary=world.journal.query(actor_id(),{"species_id":species_id,"limit":world.journal.config.page_limit})
	for entry in result.entries:
		var tile:=preload("res://scripts/journal_card.gd").new();tile.entry=entry;tile.renderer=renderer;tile.rules=world.fishing.rules;tile.font=get_theme_default_font();tile.chosen=entry.id==selected_id;tile.size_flags_horizontal=Control.SIZE_EXPAND_FILL;grid.add_child(tile)
		tile.selected.connect(select_entry)
	if selected_id.is_empty():detail.text=T("activities.choose_card")
	else:
		for entry in result.entries:
			if entry.id==selected_id:show_detail(entry)
func select_entry(entry: Dictionary) -> void:
	selected_id=entry.id
	for tile in grid.get_children():tile.chosen=tile.entry.id==selected_id;tile.queue_redraw()
	show_detail(entry)
func show_detail(entry: Dictionary) -> void:
	var title: String=LocalText.content(entry.species_name)+" · "+LocalText.content(entry.color_name)+" · "+LocalText.content(entry.size_name)
	if not entry.caught:detail.text=title+T("activities.empty_page");return
	var first: Dictionary=entry.first_catch
	var local_time: int=int(first.caught_at)+int(Time.get_time_zone_from_system().bias)*60
	var date:=Time.get_datetime_string_from_unix_time(local_time).replace("T"," ")
	var source: String=LocalText.content(world.fishing.seas[world.fishing.sea_id(first.source_id)].name)
	detail.text=title+T("activities.first_catch")+date+" · "+source+T("activities.height")%first.scale
func _process(delta: float) -> void:
	if not visible:return
	elapsed+=delta
	if elapsed>=.5:elapsed=0;refresh()

func refresh_locale()->void:
	_fit_language_layout()
	_refresh_static(self);book_title.text=LocalText.content(world.journal.config.title)
	for index in range(actors.item_count):actors.set_item_text(index,T("activities.read_resident")+LocalText.resident(world,str(actors.get_item_metadata(index))))
	last_revision="";refresh(true)

func _fit_language_layout()->void:
	var english:bool=LocalText.revision().begins_with("en");z_index=120 if english else 0
	var bounds:Vector2=get_viewport_rect().size
	var width:float=minf(1080,bounds.x-40) if english else 1080.0
	var height:float=minf(720,bounds.y-40) if english else 720.0
	card.offset_left=-width/2;card.offset_right=width/2;card.offset_top=-height/2;card.offset_bottom=height/2
	for text_label in [book_title,status,heading,description,detail,book_footer]:
		if is_instance_valid(text_label):text_label.add_theme_color_override("font_color",Color("fff4db"))
