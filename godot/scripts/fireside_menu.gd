extends AcceptDialog
const LocalText=preload("res://scripts/localization.gd")
## Restaurant menu. Serving quantities remain internal to Fireside.
var life:RefCounted
var note:Label
var choices:Array=[]
var selected:=-1
var start_button:Button
var cards:Array=[]
var scale_value:=1.0
var scroll:ScrollContainer
var food_filter:="all"
var root_column:VBoxContainer
func setup(source:RefCounted,font:Font)->void:
	if not LocalText.events.changed.is_connected(refresh_locale):LocalText.events.changed.connect(refresh_locale)
	life=source;title=T("ui.bbq.menu_title");theme=Theme.new();theme.default_font=font;theme.default_font_size=16;dialog_hide_on_ok=false
	var parent:Node=get_parent()
	if parent.get("island_hud")!=null:
		add_theme_stylebox_override("panel",parent.island_hud.pixel_style());scale_value=1.0 # Unified ui_scale manager owns font and minimum-size multiplication.
	var col:=VBoxContainer.new();root_column=col;col.add_theme_constant_override("separation",12);add_child(col)
	label(col,T("ui.bbq.menu_title"),22)
	var filters:=OptionButton.new();filters.focus_mode=Control.FOCUS_NONE;col.add_child(filters)
	var modes:Array=["ready","all","dessert","soup","seafood","skewers","vegetable"]
	for mode in modes:filters.add_item(LocalText.text("content.cookbook.filter_"+mode))
	filters.select(maxi(0,modes.find(food_filter)))
	filters.item_selected.connect(func(index):food_filter=modes[index];refresh_locale())
	scroll=ScrollContainer.new();scroll.custom_minimum_size=Vector2(700,330);scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;col.add_child(scroll)
	var sections:=VBoxContainer.new();sections.size_flags_horizontal=Control.SIZE_EXPAND_FILL;sections.add_theme_constant_override("separation",14);scroll.add_child(sections)
	choices=life.fireside.menu()
	var original_order:Dictionary={}
	for i in range(choices.size()):original_order[choices[i].id]=i
	var available:Dictionary=life.fireside.available()
	var ranks:Dictionary={}
	for item in choices:ranks[item.id]=availability_rank(item,available)
	choices.sort_custom(func(a,b):return int(ranks[a.id])<int(ranks[b.id]) if ranks[a.id]!=ranks[b.id] else int(original_order[a.id])<int(original_order[b.id]))
	cards.resize(choices.size())
	for dish in [false,true]:
		label(sections,T("ui.bbq.dishes") if dish else T("ui.bbq.singles"),18)
		var grid:=GridContainer.new();grid.columns=2 if LocalText.revision().begins_with("en") and get_parent().get_viewport().get_visible_rect().size.x<1100 else 3;grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL;grid.add_theme_constant_override("h_separation",12);grid.add_theme_constant_override("v_separation",12);sections.add_child(grid)
		if not dish:
			var expand:=Button.new();expand.focus_mode=Control.FOCUS_NONE;expand.text=LocalText.text("content.cookbook.expand_basics");expand.set_meta("expand_basics",true);sections.add_child(expand);sections.move_child(expand,grid.get_index());grid.visible=false;expand.pressed.connect(func():grid.visible=not grid.visible)
		for index in range(choices.size()):
			var item:Dictionary=choices[index]
			if (item.category=="dish")!=dish:continue
			var details:Dictionary=life.world.recipes.metadata.get(str(item.id).trim_prefix("recipe:"),{})
			if food_filter=="ready" and int(item.maximum)==0:continue
			if food_filter not in ["all","ready"] and details.get("category","")!=food_filter:continue
			var card:=PanelContainer.new();card.size_flags_horizontal=Control.SIZE_EXPAND_FILL;card.custom_minimum_size.x=214;grid.add_child(card)
			if parent.get("island_hud")!=null:card.add_theme_stylebox_override("panel",parent.island_hud.pixel_style())
			var body:=VBoxContainer.new();body.add_theme_constant_override("separation",6);card.add_child(body)
			var row:=HBoxContainer.new();body.add_child(row)
			var icon:=TextureRect.new();icon.custom_minimum_size=Vector2(28,28);icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;icon.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
			var art_id:String="crop-"+str(item.ingredient)
			if ResourceLoader.exists("res://assets/island-food/"+str(item.ingredient)+".png") and item.category!="dish":icon.texture=load("res://assets/island-food/"+str(item.ingredient)+".png")
			elif item.category=="dish" and ResourceLoader.exists("res://assets/island-food/"+str(item.id).trim_prefix("recipe:")+".png"):icon.texture=load("res://assets/island-food/"+str(item.id).trim_prefix("recipe:")+".png")
			elif item.category=="dish" and ResourceLoader.exists("res://assets/island-food/bowl.png"):icon.texture=load("res://assets/island-food/bowl.png")
			elif life.world.library.artworks.has(art_id):icon.texture=life.world.library.texture(art_id,"mature")
			else:icon.texture=load("res://assets/island/mushrooms.png" if item.ingredient=="mushroom" else "res://assets/island/meal.png")
			row.add_child(icon);var food_label:=label(row,LocalText.content(item.name),16);food_label.set_meta("food_name",item.name)
			if item.id=="single:mushroom":label(body,T("ui.bbq.always_available"),13)
			for ingredient in item.ingredients:
				var need:int=int(item.ingredients[ingredient]);var have:int=int(life.fireside.available().get(ingredient,0))
				var ingredient_name:String=food_name(ingredient)
				if ingredient=="fish":
					var held:Dictionary=life.fireside.cooking_fish()
					var required:String=str(details.get("fish_species",""))
					have=0 if held.is_empty() or (not required.is_empty() and held.get("species_id")!=required) else 1
					for species in life.world.fishing.rules.species:
						if species.id==required:ingredient_name=LocalText.content(species.name);break
				var line:Label=label(body,T("ui.bbq.need_prefix")+ingredient_name+( " ×%s"%need if dish else ""),13)
				line.text+=(T("ui.bbq.available") if have>=need else T("ui.bbq.missing")%(need-have));line.modulate=Color.WHITE if have>=need else Color(.62,.62,.62)
			var origins:Array=[]
			for ingredient in item.ingredients:
				var origin:String=life.world.recipes.ingredient_island(ingredient)
				if not origin in origins:origins.append(origin)
			var origin_row:=HBoxContainer.new();body.add_child(origin_row)
			for origin in origins:
				var mark:=TextureRect.new();mark.texture=load("res://assets/island-food/island-"+origin+".png");mark.custom_minimum_size=Vector2(26,20);mark.tooltip_text=LocalText.text("content.cookbook.island_"+origin);origin_row.add_child(mark)
			if not origins.is_empty():label(body," · ".join(origins.map(func(origin):return LocalText.text("content.cookbook.island_"+origin))),13)
			var signature:String=str(details.get("signature_trait",""))
			for actor in life.world.actors:
				if actor!="human" and life.world.intelligence.tag(actor) in details.get("favorite_traits",[]):
					var favorite_row:=HBoxContainer.new();body.add_child(favorite_row)
					var portrait:=TextureRect.new();portrait.texture=life.world.library.texture(life.world.actors[actor].appearance_id,"down_0");portrait.custom_minimum_size=Vector2(22,28);portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;favorite_row.add_child(portrait)
					label(favorite_row,("♥ " if life.world.intelligence.tag(actor)==signature else "")+LocalText.resident(life.world,actor),13)
			label(body,T("ui.bbq.seconds")%item.seconds,13)
			if int(item.maximum)==0:
				card.modulate=Color(.78,.78,.78)
				label(body,T("ui.bbq.locked") if item.locked else hint("fish" if item.ingredients.has("fish") and life.fireside.cooking_fish().is_empty() else item.ingredient),13)
			var choose:=Button.new();choose.focus_mode=Control.FOCUS_NONE;choose.set_meta("menu_id",item.id);choose.text=T("ui.bbq.no_ingredients") if int(item.maximum)==0 else T("ui.bbq.choose");choose.disabled=int(item.maximum)==0;choose.custom_minimum_size.y=34;body.add_child(choose);choose.pressed.connect(select_food.bind(index));cards[index]=card
	note=label(col,T("ui.bbq.menu_note"),13);note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	start_button=Button.new();start_button.text=T("ui.bbq.start");start_button.custom_minimum_size=Vector2(200,48);col.add_child(start_button);start_button.pressed.connect(roast);start_button.disabled=true
	get_ok_button().hide()
	if not canceled.is_connected(queue_free):canceled.connect(queue_free)
	if not close_requested.is_connected(queue_free):close_requested.connect(queue_free)
	var first:int=choices.find_custom(func(item):return int(item.maximum)>0)
	if first>=0:select_food(first)
	if not about_to_popup.is_connected(fit):about_to_popup.connect(fit)
	if not size_changed.is_connected(fit_scroll):size_changed.connect(fit_scroll)
func availability_rank(item:Dictionary,stock:Dictionary)->int:
	if int(item.maximum)>0:return 0
	if item.locked:return 2
	var missing:=0
	var present:=false
	for ingredient in item.ingredients:
		var have:int=int(stock.get(ingredient,0))
		if ingredient=="fish":
			var held:Dictionary=life.fireside.cooking_fish()
			var required:String=str(life.world.recipes.metadata.get(str(item.id).trim_prefix("recipe:"),{}).get("fish_species",""))
			have=1 if not held.is_empty() and (required.is_empty() or held.get("species_id")==required) else 0
		if have>0:present=true
		if have<int(item.ingredients[ingredient]):missing+=1
	return 1 if present and missing==1 else 2
func label(parent:Node,text:String,pixels:int)->Label:
	var l:=Label.new();l.text=text;
	if LocalText.revision().begins_with("en"):l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;l.custom_minimum_size.x=150
	l.add_theme_font_size_override("font_size",maxi(20 if pixels==22 else 16 if pixels>=16 else 13,roundi(pixels*scale_value)));parent.add_child(l);return l
func food_name(id:String)->String:
	if id in life.world.recipes.INGREDIENT_IDS and LocalText.entries.has("content.ingredients."+id):return LocalText.text("content.ingredients."+id)
	return {"mushroom":T("ui.bbq.food_mushroom"),"fish":T("ui.bbq.food_fish"),"turnip":T("ui.bbq.food_turnip"),"pumpkin":T("ui.bbq.food_pumpkin"),"tomato":T("ui.bbq.food_tomato"),"apple":T("ui.bbq.food_apple"),"blueberry":T("ui.bbq.food_blueberry")}.get(id,id)
func hint(id:String)->String:return T("ui.bbq.mushroom_hint") if id=="mushroom" else T("ui.bbq.fish_hint") if id=="fish" else T("ui.bbq.orchard_prefix")+food_name(id) if id in ["apple","blueberry"] else T("ui.bbq.field_prefix")+food_name(id)
func fit()->void:
	var bounds:Vector2i=get_parent().get_viewport().get_visible_rect().size
	size=Vector2i(mini(830,bounds.x-48),mini(590,bounds.y-64));position=(bounds-size)/2;fit_scroll()
func fit_scroll()->void:
	if scroll==null:return
	var bounds:Vector2=get_parent().get_viewport().get_visible_rect().size
	if LocalText.revision().begins_with("en"):
		scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
		scroll.custom_minimum_size=Vector2(minf(700,bounds.x-120),mini(320,maxi(150,int(bounds.y)-340)))
	else:scroll.custom_minimum_size=Vector2(700,mini(390,maxi(180,int(bounds.y)-235)))
func select_food(index:int)->void:
	selected=index;var item:Dictionary=choices[index];start_button.disabled=int(item.maximum)==0
	note.text=LocalText.content(item.name)+T("ui.bbq.selected_suffix")
func roast()->void:
	if selected<0:return
	var result:Dictionary=life.fireside.roast_host(choices[selected].id)
	if not result.get("ok",false):note.text=str(result.get("message",result.get("error",T("ui.bbq.start_failed"))));return
	if get_parent().has_method("_frame_camp"):get_parent()._frame_camp(life.station.id)
	queue_free()

var locale_labels:Dictionary={}
func T(key:String)->String:
	var result:=LocalText.text(key);locale_labels[LocalText.source(key)]=key;locale_labels[result]=key;locale_labels[str(LocalText.entries.get(key,{}).get("en",result))]=key;return result
func refresh_locale()->void:
	if not is_instance_valid(root_column):return
	var previous:int=selected;var scroll_at:int=scroll.scroll_vertical;var font:Font=theme.default_font
	root_column.get_parent().remove_child(root_column);root_column.queue_free();cards.clear();locale_labels.clear()
	setup(life,font)
	if previous>=0 and previous<choices.size():select_food(previous)
	scroll.scroll_vertical=scroll_at;fit()
func _refresh_locale_nodes(node:Node)->void:
	for property in ["text","title","ok_button_text"]:
		if not node.get_property_list().any(func(p):return p.name==property):continue
		var value:Variant=node.get(property)
		if value is String and locale_labels.has(value):node.set(property,LocalText.text(locale_labels[value]))
	if node is Label and node.has_meta("food_name"):node.text=LocalText.content(str(node.get_meta("food_name")))
	for child in node.get_children():_refresh_locale_nodes(child)
