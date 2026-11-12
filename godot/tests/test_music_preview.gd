extends SceneTree
const Audio=preload("res://scripts/game_audio.gd")
const Preview=preload("res://scripts/music_preview.gd")
const Helper=preload("res://tests/test_barbecue_v2.gd")
var checks:=0
var failed:=false
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failed=true;push_error(message)
func _initialize()->void:call_deferred("run")
func nodes(node:Node)->Array:
	var found:Array=[node]
	for child in node.get_children():found.append_array(nodes(child))
	return found
func click(dialog:Window,button:Button)->void:
	var at:Vector2=button.get_global_rect().get_center()
	var viewport:Viewport=button.get_viewport()
	if viewport is Window and viewport.is_embedded():at+=Vector2(viewport.position);viewport=root
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=at;event.global_position=at;event.pressed=pressed;event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
		viewport.push_input(event,true);await process_frame
func run()->void:
	var temp:String=OS.get_environment("HABITAT_DATA_DIR");assert(temp.contains("youqi-test-"))
	root.size=Vector2i(960,640)
	var helper:=Helper.new();var w:RefCounted=helper.fresh(temp)
	var view:Node=preload("res://scripts/island_view.gd").new();view.world=w;view.library=w.library;view.font=load("res://assets/fonts/NotoSansSC.ttf");root.add_child(view);view.set_process(false);view.center=w.point(w.actors.human)
	var audio:=Audio.new();root.add_child(audio);audio.setup(w,view,temp)
	for i in range(30):audio.advance(.2)
	await process_frame
	var original:String=""
	for item in audio.active:
		if str(item.event).begins_with("music.") and item.target>0:original=item.event
	check(not original.is_empty(),"actual scene music playing before preview")
	var levels:Dictionary=audio.levels.duplicate();var duck:float=audio.duck_gain
	var settings:=AcceptDialog.new();root.add_child(settings);settings.popup_centered(Vector2i(600,500));await process_frame
	var dialog:AcceptDialog=Preview.open(settings,audio)
	for i in range(4):await process_frame
	check(Preview.open(settings,audio)==dialog,"duplicate open reuses nested dialog")
	check(dialog.get_parent()==settings,"preview is nested under active exclusive settings")
	check(dialog.theme.default_font==load("res://assets/fonts/NotoSansSC.ttf"),"Chinese uses original default font")
	check(nodes(dialog).filter(func(n):return n is LinkButton).size()==8,"eight source rows shown")
	check(audio.active.all(func(item):return not str(item.event).begins_with("music.") or float(item.target)==0.0),"opening preview suspends scene music immediately")
	var first:Button=null;var second:Button=null
	for node in nodes(dialog):
		if not node is Button or node is LinkButton:continue
		if node.text==preload("res://scripts/localization.gd").text("ui.music.day"):first=node
		if node.text==preload("res://scripts/localization.gd").text("ui.music.dusk"):second=node
	check(first!=null and second!=null,"first two preview controls present")
	for button in [first,second]:
		await click(dialog,button);await process_frame
		for i in range(25):audio.advance(.2)
		await process_frame
		check(audio.active.filter(func(item):return str(item.event).begins_with("music.") and item.target>0).size()==1,"native input leaves exactly one active music target")
		check(audio.active.any(func(item):return str(item.key).begins_with("sound-test:music.") and item.native_started and item.gain>0),"preview reaches native Dummy playback")
		check(audio.active.all(func(item):return not str(item.key).begins_with("music:") or item.gain==0.0),"scene music inaudible throughout preview")
	check(audio.levels==levels and audio.duck_gain==duck,"preview preserves Music bus and original duck")
	var close:=InputEventKey.new();close.keycode=KEY_ESCAPE;close.pressed=true;root.push_input(close,true) if dialog.is_embedded() else dialog.push_input(close,true)
	for i in range(3):await process_frame
	check(not audio.music_preview_active,"native Escape closes preview")
	check(not audio.active.any(func(item):return str(item.key).begins_with("sound-test:music.")),"close removes all preview streams")
	check(audio.active.any(func(item):return item.event==original and item.target>0),"close immediately restores original scene target")
	for i in range(25):audio.advance(.2)
	await process_frame
	check(audio.active.any(func(item):return item.event==original and item.gain>0 and item.native_started),"original scene resumes native playback")
	audio.shutdown();settings.queue_free();audio.queue_free();view.queue_free();helper.free();await process_frame;await create_timer(.1).timeout
	print("Music preview: ",checks," checks; native mouse and Escape, Dummy")
	quit(1 if failed else 0)
