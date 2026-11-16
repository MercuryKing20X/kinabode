extends SceneTree
const FlowerPanel=preload("res://scripts/flower_panel.gd")
const UI=preload("res://tests/barbecue_ui_fixture.gd")
const L=preload("res://scripts/localization.gd")
var failures:=0
func check(value:bool,label:String)->void:
	if not value:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-"):quit(1);return
	root.content_scale_size=Vector2i.ZERO
	var panel:=FlowerPanel.new();root.add_child(panel);panel.theme=Theme.new();panel.theme.default_font=load("res://assets/fonts/NotoSansSC.ttf");panel.theme.default_font_size=18;panel.setup()
	var actions:Array=[];var placements:Array=[]
	panel.action_requested.connect(func(args):actions.append(args.duplicate(true)))
	panel.placement_requested.connect(func(args):placements.append(args.duplicate(true)))
	for extent in [Vector2i(960,640),Vector2i(1600,900)]:
		root.size=extent
		for locale in ["zh_CN","en"]:
			TranslationServer.set_locale(locale);panel.open("human","wood 20 · roses 100");await process_frame;await process_frame
			check(Rect2(Vector2.ZERO,Vector2(extent)).encloses(panel.panel.get_global_rect()),"flower panel fits "+str(extent)+locale)
			check(await UI.click(self,panel.trade_button),"real trade click")
			check(actions[-1]=={"intent":"trade_flowers","color":"red","quantity":10},"exact ten rose request")
			# Enter HI with real key events through focused LineEdit.
			panel.text_input.grab_focus()
			for code in [KEY_H,KEY_I]:
				var key:=InputEventKey.new();key.keycode=code;key.unicode=code;key.pressed=true;root.push_input(key,true);await process_frame
			check(panel.text_input.text=="HI","real key HI")
			check(await UI.click(self,panel.arrange_button),"real arrange click")
			check(placements[-1].get("text")=="HI" and not panel.visible,"HI position requested without inventory mutation")
			panel.text_input.clear();panel.open("human","wood 20")
			check(await UI.click(self,panel.pick_button) and placements[-1].intent=="pick_flower","real pickup request")
			panel.open("human","wood 20");check(await UI.click(self,panel.close_button) and not panel.visible,"real close")
			panel.open("human","wood 20");var escape:=InputEventKey.new();escape.keycode=KEY_ESCAPE;escape.pressed=true;root.push_input(escape,true);await process_frame;check(not panel.visible,"Escape")
	check(actions.size()==4 and placements.size()==8,"one request per real click")
	panel.queue_free();await process_frame;print("Flower panel real input failures=",failures);quit(1 if failures else 0)
