extends PanelContainer
const Catalog=preload("res://scripts/workshop_catalog.gd")
const FAN_APPEARANCES=["ai-gpt","ai-claude","ai-gemini","ai-grok","ai-deepseek","ai-glm","ai-qwen","ai-kimi"]
const LocalText=preload("res://scripts/localization.gd")
var _locale_static:Dictionary={}
func T(key:String)->String:
	var value:String=LocalText.text(key);_locale_static[value]=key;return value
func _mark_static(node:Node)->void:
	var fields:Array=[]
	if node is Label or (node is Button and not node is OptionButton):fields.append("text")
	if node is Window:fields.append("title")
	if node is AcceptDialog:fields.append_array(["dialog_text","ok_button_text"])
	if node is ConfirmationDialog:fields.append("cancel_button_text")
	if node is LineEdit:fields.append("placeholder_text")
	for field in fields:
		if _locale_static.has(str(node.get(field))):node.set_meta("workshop_locale_"+field,_locale_static[str(node.get(field))])
	for child in node.get_children():_mark_static(child)
func _refresh_static(node:Node)->void:
	for field in ["text","title","dialog_text","ok_button_text","cancel_button_text","placeholder_text"]:
		if node.has_meta("workshop_locale_"+field):node.set(field,T(str(node.get_meta("workshop_locale_"+field))))
	for child in node.get_children():_refresh_static(child)
## Host-only appearance selection. Preview never mutates the world.
var game:Node
var resident_list:VBoxContainer
var grid:GridContainer
var preview:TextureRect
var detail:Label
var selected_actor:=""
var selected_work:=""
var direction:="down"
var human_mode:=false
func setup(host:Node)->void:
	game=host;set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);offset_left=24;offset_right=-24;offset_top=24;offset_bottom=-70
	var outer:=VBoxContainer.new();add_child(outer)
	var header:=HBoxContainer.new();outer.add_child(header)
	var title:=Label.new();title.text=T("content.workshop.wardrobe");title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(title)
	_add_button(header,T("content.workshop.close_180"),hide)
	var content:=HBoxContainer.new();content.size_flags_vertical=Control.SIZE_EXPAND_FILL;outer.add_child(content)
	var scroll:=ScrollContainer.new();scroll.custom_minimum_size=Vector2(190,0);content.add_child(scroll)
	resident_list=VBoxContainer.new();resident_list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(resident_list)
	var right:=VBoxContainer.new();right.size_flags_horizontal=Control.SIZE_EXPAND_FILL;content.add_child(right)
	var upper:=HBoxContainer.new();right.add_child(upper)
	preview=TextureRect.new();preview.custom_minimum_size=Vector2(128,150);preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;preview.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;upper.add_child(preview)
	var info:=VBoxContainer.new();info.size_flags_horizontal=Control.SIZE_EXPAND_FILL;upper.add_child(info)
	detail=Label.new();detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;info.add_child(detail)
	var dirs:=HBoxContainer.new();info.add_child(dirs)
	for pair in [[T("content.workshop.front"),"down"],[T("content.workshop.left"),"left"],[T("content.workshop.right"),"right"],[T("content.workshop.back"),"up"]]:
		var d:String=pair[1];_add_button(dirs,pair[0],func():direction=d;refresh_preview())
	var works_scroll:=ScrollContainer.new();works_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;right.add_child(works_scroll)
	grid=GridContainer.new();grid.columns=4;grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL;works_scroll.add_child(grid)
	var footer:=HBoxContainer.new();right.add_child(footer)
	_add_button(footer,T("content.workshop.restore_original_appearance"),restore_default)
	_add_button(footer,T("content.workshop.confirm"),apply_selection)
	hide()
	_mark_static(self)
	if not LocalText.events.changed.is_connected(refresh_locale):LocalText.events.changed.connect(refresh_locale)

func _add_button(parent:Node,text:String,callback:Callable)->Button:
	var b:=Button.new();b.focus_mode=Control.FOCUS_NONE;b.text=text;b.custom_minimum_size.y=32;parent.add_child(b);b.pressed.connect(callback);return b
func open_for(id:String,allow_human:=false)->void:
	if not game.world.actors.has(id):return
	if game.world.actors[id].role=="human" and not allow_human:return
	human_mode=allow_human and game.world.actors[id].role=="human"
	selected_actor=id;selected_work=str(game.world.actors[id].appearance_id);direction="down";rebuild();show()
func rebuild()->void:
	z_index=120 if LocalText.revision().begins_with("en") else 0
	for node in resident_list.get_children():node.queue_free()
	for node in grid.get_children():node.queue_free()
	for id in game.world.actors:
		var actor:Dictionary=game.world.actors[id]
		if (actor.role=="human") != human_mode:continue
		var actor_id:String=id
		var current_id:String=game.library.visual_appearance(actor)
		var resident_button:=_add_button(resident_list,LocalText.resident(game.world,id)+"\n"+Catalog.work_name(game.library.artworks[current_id],current_id),func():selected_actor=actor_id;selected_work=str(game.world.actors[actor_id].appearance_id);refresh_preview())
		resident_button.set_meta("resident_id",actor_id)
		if game.island_hud!=null and game.island_hud.avatar_buttons.has(actor_id):resident_button.icon=game.island_hud.avatar_buttons[actor_id].icon
	for id in game.library.artworks:
		var art:Dictionary=game.library.artworks[id]
		if art.get("kind","character")!="character":continue
		if "human_only" in art.get("tags",[]) and not human_mode:continue
		var work_id:String=id
		var item:=VBoxContainer.new();grid.add_child(item)
		var thumbnail:=TextureRect.new();thumbnail.texture=game.library.texture(id,"down_0");thumbnail.custom_minimum_size=Vector2(96,105);thumbnail.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;thumbnail.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;thumbnail.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;item.add_child(thumbnail)
		thumbnail.mouse_filter=Control.MOUSE_FILTER_STOP
		thumbnail.gui_input.connect(func(event):
			if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:selected_work=work_id;refresh_preview())
		var b:=_add_button(item,Catalog.work_name(art,id)+(T("content.workshop.incomplete") if "spare" in art.get("tags",[]) else ""),func():selected_work=work_id;refresh_preview())
		if work_id in FAN_APPEARANCES:
			var notice:=_add_button(item,"i",_show_fan_notice)
			notice.set_meta("fan_notice",work_id)
			notice.tooltip_text=T("wardrobe.fan_notice_title")
		b.set_meta("work_id",work_id)
		b.custom_minimum_size.x=140
		b.tooltip_text=T("content.workshop.ai_character") if "spare" in art.get("tags",[]) else T("content.workshop.original_work") if id in ["human-starter","white-haired-girl","blue-haired-girl","orange-haired-girl","black-scarf-girl"] else T("content.workshop.custom")
		thumbnail.tooltip_text=b.tooltip_text;b.clip_text=not LocalText.revision().begins_with("en")
		if LocalText.revision().begins_with("en"):b.text=b.text.replace(" · ","\n")
	refresh_preview()
func refresh_preview()->void:
	if not game.library.artworks.has(selected_work):
		detail.text=T("content.workshop.work_unavailable_right_now_your_selection_is_safe");preview.texture=null;return
	var art:Dictionary=game.library.artworks[selected_work];var frame:=direction+"_0"
	if not art.frames.has(frame):frame=str(art.frames.keys()[0])
	preview.texture=game.library.texture(selected_work,frame)
	detail.text=LocalText.resident(game.world,selected_actor)+" · "+Catalog.work_name(art,selected_work)
	if "spare" in art.get("tags",[]):detail.text+=T("content.workshop.nmissing_actions_pickup_carrying_and_chopping_still_use_reused_or")
func restore_default()->void:
	selected_work=game.world.residents.appearance_for(selected_actor);refresh_preview()
func apply_selection()->void:
	if human_mode:
		var confirm:=ConfirmationDialog.new();confirm.title=T("content.workshop.change_my_appearance");confirm.dialog_text=T("content.workshop.change_your_appearance_to_the_selected_work");confirm.ok_button_text=T("content.workshop.confirm");confirm.cancel_button_text=T("content.workshop.cancel");add_child(confirm)
		confirm.confirmed.connect(func():_commit(true);confirm.queue_free())
		confirm.canceled.connect(confirm.queue_free);confirm.popup_centered();return
	_commit(false)
func _commit(human:bool)->void:
	if game.world.assign_appearance(selected_actor,selected_work,human,human):
		var message:String=LocalText.resident(game.world,selected_actor)+T("content.workshop.changed_appearance")
		game.status.text=message
		get_tree().create_timer(3.0).timeout.connect(func():
			if is_instance_valid(game) and game.status.text==message:game.status.text="")
		game.view.queue_redraw()
		if game.island_hud!=null:game.island_hud.portrait_keys.erase(selected_actor);game.island_hud.refresh()
		hide()

func refresh_locale()->void:
	z_index=120 if LocalText.revision().begins_with("en") else 0
	_refresh_static(self)
	for button_node in resident_list.get_children():
		if button_node.has_meta("resident_id"):
			var id:String=str(button_node.get_meta("resident_id"));var current:String=game.library.visual_appearance(game.world.actors[id])
			button_node.text=LocalText.resident(game.world,id)+"\n"+Catalog.work_name(game.library.artworks[current],current)
	for item in grid.get_children():
		for button_node in item.get_children():
			if button_node.has_meta("fan_notice"):button_node.tooltip_text=T("wardrobe.fan_notice_title")
			if button_node.has_meta("work_id"):
				var id:String=str(button_node.get_meta("work_id"));var art:Dictionary=game.library.artworks[id]
				button_node.text=Catalog.work_name(art,id)+(T("content.workshop.incomplete") if "spare" in art.get("tags",[]) else "")
				button_node.clip_text=not LocalText.revision().begins_with("en")
				if LocalText.revision().begins_with("en"):button_node.text=button_node.text.replace(" · ","\n")
	if not selected_actor.is_empty():refresh_preview()

func _show_fan_notice()->void:
	var notice:=AcceptDialog.new()
	notice.title=T("wardrobe.fan_notice_title")
	notice.dialog_text=T("wardrobe.fan_notice")
	notice.dialog_autowrap=true
	notice.ok_button_text=T("content.workshop.confirm")
	add_child(notice)
	_mark_static(notice)
	notice.confirmed.connect(notice.queue_free)
	notice.canceled.connect(notice.queue_free)
	notice.popup_centered(Vector2i(mini(520,int(get_viewport_rect().size.x)-48),200))
