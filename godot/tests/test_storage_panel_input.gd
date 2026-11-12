extends SceneTree
const StoragePanel=preload("res://scripts/storage_panel.gd")
const F=preload("res://tests/cooking_fixture.gd")
const UI=preload("res://tests/barbecue_ui_fixture.gd")
const L=preload("res://scripts/localization.gd")
var failures:=0
func check(value:bool,label:String)->void:
	if not value:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-"):quit(1);return
	root.content_scale_size=Vector2i.ZERO
	var world:=F.fresh();world.storage.restore({"items":{"wood":6,"mushroom":4,"seed.turnip":2}});world.actors.human.carry={"wood":3}
	var panel:=StoragePanel.new();root.add_child(panel);panel.setup(world)
	var emitted:Dictionary={"deposit":0,"take":0}
	panel.deposit_all_requested.connect(func():emitted.deposit+=1)
	panel.take_requested.connect(func(_item,_quantity):emitted.take+=1)
	L.ensure()
	for size in [Vector2i(960,640),Vector2i(1280,800)]:
		root.size=size
		for locale in ["zh_CN","en"]:
			TranslationServer.set_locale(locale);panel.open();await process_frame;await process_frame
			check(panel.panel.get_global_rect().end.x<=size.x and panel.panel.get_global_rect().end.y<=size.y,"panel fits "+str(size))
			check(await UI.click(self,panel.deposit_button),"actual deposit button")
			var takes:Array=UI.descendants(panel.rows).filter(func(n):return n is Button)
			check(takes.size()==3 and await UI.click(self,takes[0]),"actual item take button")
			check(await UI.click(self,panel.close_button) and not panel.visible,"actual close button")
			panel.open();var key:=InputEventKey.new();key.keycode=KEY_ESCAPE;key.pressed=true;root.push_input(key,true);await process_frame;check(not panel.visible,"Escape closes")
			panel.open();var click:=InputEventMouseButton.new();click.position=Vector2(3,3);click.pressed=true;click.button_index=MOUSE_BUTTON_LEFT;root.push_input(click,true);await process_frame;check(not panel.visible,"outside click closes")
	check(emitted.deposit==4 and emitted.take==4,"UI emits exactly once and owns no inventory")
	check(world.actors.human.carry=={"wood":3} and world.storage.count("wood")==6,"UI never mutates material state")
	panel.queue_free();await process_frame;print("Storage panel input failures=",failures);quit(1 if failures else 0)
