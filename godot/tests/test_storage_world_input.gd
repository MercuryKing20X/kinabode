extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
const L=preload("res://scripts/localization.gd")
var failures:=0
var game:Node
var seen_delivery:=false
func _initialize()->void:call_deferred("run")
func check(v:bool,label:String)->void:
	if not v:failures+=1;push_error(label)
func button(label:String)->BaseButton:
	for node in UI.descendants(game):
		if node is BaseButton and node.is_visible_in_tree() and node.text==label:return node
	return null
func step(delta:float=.1)->void:
	game._process(delta);game.view._process(delta)
func key(code:int)->void:
	for down in [true,false]:
		var event:=InputEventKey.new();event.keycode=code;event.pressed=down;root.push_input(event,true);await process_frame
func capture(label:String)->void:
	var out:=OS.get_environment("HABITAT_PLAYTEST_CAPTURE")
	if out.is_empty() or DisplayServer.get_name()=="headless":return
	game.island_hud.refresh()
	DirAccess.make_dir_recursive_absolute(out);await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(label+".png"))
func run()->void:
	var directory:=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-"):quit(1);return
	OS.set_environment("HABITAT_OPENING","legacy");root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	var w:=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");w.residents.provision(w)
	w.library=preload("res://scripts/character_library.gd").new();w.library.configure(directory)
	preload("res://scripts/world_opening.gd").apply(w,w.library,"showcase");w.intelligence.activate_presets()
	w.actors["companion-2"].appearance_id="ai-deepseek";w.actors["companion-2"]["custom_appearance"]=true
	check(preload("res://scripts/save_store.gd").save_world(w,directory),"isolated initial save")
	game=load("res://scenes/main_v3.tscn").instantiate();game.world=w;root.add_child(game)
	game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.island_hud.set_process(false);game.chat.hide();w.director.set_all_enabled(false)
	for i in range(8):await process_frame
	L.select(directory,"en");step(0);await process_frame
	check(w.take_storage_host("wood",3).ok,"fixture explicitly withdraws three genuine units after reload")
	var before:int=w.storage.count("wood");var origin:Vector2=w.point(w.actors.human)
	check(await UI.click(self,game.island_hud.stock_button),"real HUD storage opens")
	check(game.storage_panel.visible,"storage visible")
	check(await UI.click(self,game.storage_panel.deposit_button),"real deposit all")
	check(w.actors.human.carry.is_empty() and w.storage.count("wood")==before+3,"deposit quantity exact")
	var candidates:Array=UI.descendants(game.storage_panel.rows).filter(func(n):return n is HBoxContainer and n.get_child_count()==3 and n.get_child(0) is Label and n.get_child(0).text.begins_with(L.text("hud.mushroom")))
	check(candidates.size()==1,"mushroom row exact")
	if candidates.size()==1:
		var row:HBoxContainer=candidates[0];var spin:SpinBox=row.get_child(1)
		await UI.reveal(self,spin)
		var at:Vector2=spin.get_global_rect().position+Vector2(spin.get_global_rect().size.x-7,spin.get_global_rect().size.y*.25)
		for down in [true,false]:
			var event:=InputEventMouseButton.new();event.pressed=down;event.button_index=MOUSE_BUTTON_LEFT;event.position=at;event.global_position=at;root.push_input(event,true);await process_frame
		check(await UI.click(self,row.get_child(2)),"real take out selected two")
		check(int(w.actors.human.carry.get("mushroom",0))==2,"two mushrooms in carry")
	check(await UI.click(self,game.storage_panel.close_button),"real close")
	check(w.point(w.actors.human)==origin and not w._routes.has("human"),"storage travel distance exactly zero")
	check(await UI.click(self,game.actions_button),"real actions menu")
	check(await UI.tab(self,game.action_dock.action_tabs,1),"native everyone section")
	check(await UI.click(self,button(L.text("storage.ask_wood"))),"real companion chopping command")
	check(game.participant_picker.visible,"participant selector visible")
	check(await UI.click(self,game.participant_picker.get_ok_button()),"real host confirms Skye")
	check(w.work.jobs.has("companion-2"),"Skye owns genuine chop command")
	var old_stock:int=w.storage.count("wood");var carry_seen:=false
	var reserved_stop:=Vector2.INF
	for i in range(1400):
		if w.deliveries.pending.has("companion-2"):reserved_stop=w.deliveries.visit_slot("companion-2")
		step(.2)
		if int(w.actors["companion-2"].carry.get("wood",0))>0:
			carry_seen=true
			check(w.storage.count("wood")==old_stock,"no remote deposit before actual handover")
		if w.storage.count("wood")==old_stock+3:
			seen_delivery=true
			check(w.work.visual_events.any(func(e):return e.kind=="storage_text" and e.actor_id=="companion-2" and e.get("storage_text","").contains("3")),"hand over emits real actor head caption")
			await capture("storage-partner-handover");break
		if i%40==0:await process_frame
	check(carry_seen and seen_delivery,"carry travels to real host and deposits three")
	check(w.actors["companion-2"].carry.is_empty() and reserved_stop.is_finite() and w.point(w.actors["companion-2"]).distance_to(reserved_stop)<=.5 and not w._routes.has("companion-2"),"real stopped arrival and exact handover")
	check(w.point(w.actors.human)==origin,"partner never moves human")
	print("Storage world input failures=",failures," handover=",seen_delivery)
	game.queue_free();await process_frame;quit(1 if failures else 0)
