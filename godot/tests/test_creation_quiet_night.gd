extends SceneTree
const Books=preload("res://scripts/memory_books.gd")
const Life=preload("res://scripts/memory_life.gd")
const Text=preload("res://scripts/localization.gd")
const StoragePanel=preload("res://scripts/storage_panel.gd")
class Host extends Node:
	var world:RefCounted
	var memory_books:RefCounted
func _initialize()->void:call_deferred("run")
func run()->void:
	var dir:String=OS.get_environment("HABITAT_DATA_DIR");assert(dir.contains("youqi-"))
	var host:=Host.new();root.add_child(host)
	host.world=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json")
	host.world.residents.provision(host.world)
	host.world.residents.provision(host.world)
	host.world.director.set_all_enabled(false)
	host.memory_books=Books.new();assert(host.memory_books.setup(dir))
	var life:=Life.new();life.owner_ref=weakref(host)
	life.write_evening_pages();assert(host.memory_books.entries.is_empty())
	var stock:Dictionary=host.world.storage.saved()
	var ticks:=0
	while host.world.days.phase().id!="night" and ticks<1500:
		host.world.advance(1);ticks+=1
	assert(host.world.days.day()==1 and host.world.days.phase().id=="night")
	assert(host.memory_books.entries.is_empty())
	life.write_evening_pages()
	var total:int=host.memory_books.entries.size()
	for id in host.world.director.routines:
		var facts:Array=host.memory_books.list_for(id,"facts");var diary:Array=host.memory_books.list_for(id,"daily")
		assert(facts.size()==1 and diary.size()==1)
		assert(facts[0].source=="game" and facts[0].day==1 and facts[0].world_id==host.world.world_id)
		assert(facts[0].params.legacy.phase==host.world.days.phase().id)
		assert(facts[0].params.legacy.weather_id==host.world.weather.current().id)
		assert(diary[0].params.source_ids==[facts[0].id])
	assert(host.world.storage.saved()==stock)
	life.write_evening_pages();assert(host.memory_books.entries.size()==total)
	var removed:Dictionary=host.memory_books.list_for("codex","daily")[0]
	assert(host.memory_books.remove(removed.id));life.write_evening_pages()
	assert(host.memory_books.list_for("codex","daily").is_empty())
	var reload:=Books.new();assert(reload.setup(dir));host.memory_books=reload
	life.write_evening_pages();assert(reload.list_for("codex","daily").is_empty())
	var source:Dictionary=reload.list_for("companion-2","facts")[0]
	assert(reload.remove(source.id));life.write_evening_pages()
	assert(reload.list_for("companion-2","facts").is_empty() and reload.list_for("companion-2","daily").is_empty())
	for locale in ["zh","en"]:
		Text.select(dir,locale)
		for color in ["red","white","yellow","pink"]:
			assert(StoragePanel.item_name(host.world,"rose_"+color)==Text.text("flowers."+color))
			assert(StoragePanel.item_name(host.world,"rose_"+color)!="flowers."+color)
	host.world.director.set_controller("codex","local")
	var panel:=preload("res://scripts/memory_book_panel.gd").new();root.add_child(panel);panel.setup(reload,host.world);panel.open()
	# The new mail action is reached by real dropdown and button mouse input.
	assert(await preload("res://tests/barbecue_ui_fixture.gd").click(self,panel.tabs))
	var popup:PopupMenu=panel.tabs.get_popup()
	var at:Vector2=Vector2(popup.size.x*.5,2.5*float(popup.size.y)/popup.item_count)
	var viewport:Viewport=popup
	if popup.is_embedded():at+=Vector2(popup.position);viewport=root
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=at;event.global_position=at;event.pressed=down;viewport.push_input(event,true);await process_frame
	assert(panel.tabs.selected==2)
	assert(panel.rows.has_node("request_local_letter"))
	assert(await preload("res://tests/barbecue_ui_fixture.gd").click(self,panel.rows.get_node("request_local_letter")))
	assert(reload.list_for("codex","letters").size()==1)
	host.world.director.set_controller("codex","model");panel.refresh()
	assert(not panel.rows.has_node("request_local_letter"))
	panel.queue_free()
	life.free();host.queue_free();await process_frame
	print("CREATION_QUIET_NIGHT_PASS current night/weather/source grounded four pages/deletion reload/no inventory change/eight rose labels actual_advance=",ticks)
	quit()
