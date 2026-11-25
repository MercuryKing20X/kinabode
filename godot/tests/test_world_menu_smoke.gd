extends SceneTree

const UI=preload("res://tests/barbecue_ui_fixture.gd")
const Pool=preload("res://scripts/connection_session_pool.gd")
class Stub extends "res://scripts/companion_link.gd":
	func _start()->bool:return false
	func _send(_payload:Dictionary)->bool:return false

var game:Node
var failures:=0
var checks:=0

func _initialize()->void:run.call_deferred()

func verify(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func key(code:Key)->void:
	for down in [true,false]:
		var event:=InputEventKey.new()
		event.keycode=code;event.physical_keycode=code;event.pressed=down
		root.push_input(event,true)
		await process_frame

func windows(node:Node)->Array:
	var visible:Array=[]
	for child in node.get_children():
		if child is Window and child.visible:visible.append(child)
		visible.append_array(windows(child))
	return visible

func close_panels(previous:Array)->void:
	for window in windows(game):
		if window is PopupMenu:await key(KEY_ESCAPE)
		elif window is ConfirmationDialog:await UI.click(self,window.get_cancel_button())
		elif window is AcceptDialog:await key(KEY_ESCAPE)
	await key(KEY_ESCAPE)
	for node in UI.descendants(game):
		if not is_instance_valid(node) or not node is PanelContainer or not node.is_visible_in_tree() or node in previous:continue
		var buttons:=UI.descendants(node)
		for button in buttons:
			if not is_instance_valid(button) or not button is Button or not button.is_visible_in_tree():continue
			if button.text in ["×","✕","关闭","Close","返回","Back"]:
				await UI.click(self,button)
				break
		# The next case needs the original view even for panels with a nested
		# navigation state or a close control outside their own tree.
		if is_instance_valid(node) and node.is_visible_in_tree():node.hide()
	if game.company!=null and game.company.camera.active:await key(KEY_SPACE)

func menu(button:MenuButton)->void:
	var popup:=button.get_popup()
	for index in popup.item_count:
		if popup.is_item_separator(index) or popup.is_item_disabled(index):continue
		# The title and archive transitions replace the scene under this
		# menu walker and are exercised by their own startup/save cases.
		if button==game.island_hud.settings_menu and popup.get_item_id(index) in [99,101]:continue
		var previous:=UI.descendants(game).filter(func(node):return node is PanelContainer and node.is_visible_in_tree())
		verify(await UI.click(self,button) and popup.visible,"opened menu: "+button.text)
		var expected:=popup.get_item_id(index)
		var selected:Array[int]=[]
		var got:=func(id:int):selected.append(id)
		popup.id_pressed.connect(got)
		popup.set_focused_item(index)
		await key(KEY_ENTER)
		popup.id_pressed.disconnect(got)
		verify(selected==[expected],"activated item: "+str(expected))
		await close_panels(previous)

func run()->void:
	var data:=OS.get_environment("HABITAT_DATA_DIR")
	if not data.begins_with("/tmp/") and not data.begins_with("/var/folders/"):quit(2);return
	root.size=Vector2i(1280,800)
	var opening:=OS.get_environment("HABITAT_MENU_SMOKE_OPENING")
	if opening not in ["standard","showcase"]:quit(2);return
	set_meta("title_opening",opening)
	Pool.obtain(self,data).factory=func(_id):return Stub.new()
	game=load("res://scenes/main_v3.tscn").instantiate()
	game.dialogue_adapter_factory=func(_id,_scope):return Stub.new()
	root.add_child(game)
	for frame in 12:await process_frame
	verify(game.world.opening_id==opening,"opening selected")
	var hud:Control=game.island_hud
	var door:Button=hud.find_child("WorldDoor",true,false)
	verify(await UI.click(self,door) and game.world_door_dialog.visible,"door panel opens")
	verify(await UI.click(self,door) and not game.world_door_dialog.visible,"door panel closes")
	var placement:Button=hud.find_child("WorldPlacement",true,false)
	verify(await UI.click(self,placement) and game.world_placement.visible,"placement opens")
	await key(KEY_ESCAPE)
	verify(not game.world_placement.visible,"placement closes")
	verify(await UI.click(self,game.dialogue_button) and game.chat.visible,"dialogue opens")
	await key(KEY_ESCAPE)
	verify(not game.chat.visible,"dialogue closes")
	verify(await UI.click(self,game.journey.map_button) and game.journey.shortcuts.visible,"map shortcuts open")
	await key(KEY_ESCAPE)
	verify(not game.journey.shortcuts.visible,"map shortcuts close")
	verify(await UI.click(self,game.gathering_button) and game.follow_ui.menu.visible,"follow options open")
	await UI.click(self,game.follow_ui.menu.get_ok_button())
	verify(not game.follow_ui.menu.visible,"follow options close")
	var shown:=UI.descendants(game).filter(func(node):return node is PanelContainer and node.is_visible_in_tree())
	if hud.stock_button.is_visible_in_tree():verify(await UI.click(self,hud.stock_button),"warehouse opens")
	await close_panels(shown)
	verify(await UI.click(self,hud.collapse_residents),"resident roster toggles")
	verify(await UI.click(self,hud.collapse_residents),"resident roster returns")
	await menu(game.handbook_menu)
	await menu(hud.settings_menu)
	verify(await UI.click(self,hud.watch_button),"watch button accepts input")
	await key(KEY_ESCAPE)
	print("WORLD_MENU_SMOKE ",opening," checks=",checks," failures=",failures)
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
