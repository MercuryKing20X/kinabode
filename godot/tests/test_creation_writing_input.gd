extends "res://tests/test_local_command_main_input.gd"
const Text=preload("res://scripts/localization.gd")
class Fake extends "res://scripts/companion_link.gd":
	var sent:Array=[]
	func _start()->bool:return true
	func _send(message:Dictionary)->bool:sent.append(message.duplicate(true));return false
func option(picker:OptionButton,index:int)->void:
	check(await UI.click(self,picker),"open actual dropdown")
	await process_frame
	var popup:PopupMenu=picker.get_popup()
	var at:Vector2=Vector2(popup.size.x*.5,(index+.5)*float(popup.size.y)/picker.item_count)
	var viewport:Viewport=popup
	if popup.is_embedded():at+=Vector2(popup.position);viewport=root
	var motion:=InputEventMouseMotion.new();motion.position=at;motion.global_position=at;viewport.push_input(motion,true)
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=at;event.global_position=at;event.pressed=down;viewport.push_input(event,true);await process_frame
func shot(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	await process_frame;await process_frame;RenderingServer.force_draw(false)
	var output:String=OS.get_environment("HABITAT_CREATION_MEDIA")
	if output.is_empty():output=OS.get_environment("HABITAT_DATA_DIR")
	DirAccess.make_dir_recursive_absolute(output)
	root.get_texture().get_image().save_png(output.path_join(name+".png"))
func run()->void:
	var dir:String=OS.get_environment("HABITAT_DATA_DIR");assert(dir.contains("youqi-"));OS.set_environment("HABITAT_OPENING","standard")
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	game=load("res://scenes/main_v3.tscn").instantiate()
	game.dialogue_adapter_factory=func(_id,_scope):return Fake.new()
	game.world=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json")
	root.add_child(game);game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.island_hud.set_process(false);game.memory_life.set_process(false)
	await process_frame;await process_frame
	game.chat_actor="companion-2"
	await text_input("我喜欢玫瑰，也喜欢和你一起在岛上玩。")
	check(game.memory_books.list_for("companion-2","facts").any(func(e):return e.params.get("human_quote",false) and e.text.contains("玫瑰")),"real typed preference retained")
	game.chat.hide();game._refresh_conversation_holds()
	game.world.director.set_all_enabled(false)
	var storage:Dictionary=game.world.storage.saved()
	var steps:=0
	while game.world.days.phase().id!="night" and steps<1500:
		game.world.advance(1);steps+=1
	check(game.world.days.phase().id=="night" and game.world.days.day()==1,"real advance reaches first night")
	game.memory_life._process(1.1)
	for id in game.world.director.routines:
		check(game.memory_books.list_for(id,"daily").any(func(e):return e.world_id==game.world.world_id and e.day==1),"night page "+id)
	check(game.world.storage.saved()==storage,"writing preserves real storage")
	var diary:Dictionary=game.memory_books.list_for("companion-2","daily")[0]
	check(diary.params.source_ids.any(func(id):return game.memory_books.entries[id].text.contains("玫瑰")),"night diary cites exact typed event")
	check(game.memory_books.write_local_letter("companion-2",game.world.world_id,1,game.world.forest.clock),"grounded local letter after real conversation")
	game.book_panel.open()
	for locale in ["zh","en"]:
		Text.select(dir,locale);await process_frame
		await option(game.book_panel.tabs,5)
		check(game.book_panel.tabs.selected==5,"native mouse opens diary")
		await option(game.book_panel.partner,1)
		await shot("diary-"+locale)
		check(game.book_panel.rows.get_child_count()>0,"diary page rendered "+locale)
	for link in game.links.values():check(link is Fake and link.sent.is_empty(),"prebuilt fake receives zero calls")
	check(game.memory_books.export_data(dir.path_join("night-writing.json")),"diaries and letters signed export")
	var imported:=preload("res://scripts/memory_books.gd").new();check(imported.setup(dir.path_join("new-world")),"separate archive opens")
	check(imported.import_data(dir.path_join("night-writing.json")).ok,"all writings import independently from world")
	print("CREATION_WRITING_INPUT ",checks," failed=",failed," actual_advance_seconds=",steps)
	game.queue_free();await process_frame;quit(1 if failed else 0)
