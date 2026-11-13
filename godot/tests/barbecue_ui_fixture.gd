extends RefCounted
## UI/Integration — production/evidence/barbecue-v4 — BLOCKING real input binding.
static func descendants(node:Node)->Array:
	var result:Array=[]
	for child in node.get_children():result.append(child);result.append_array(descendants(child))
	return result
static func shown(game:Node,path:String)->Node:
	var script:Script=load(path)
	for node in game.get_children():
		if node.get_script()==script and not node.is_queued_for_deletion() and node.visible:return node
	return null
static func tab(tree:SceneTree,tabs:TabContainer,index:int)->bool:
	if tabs.current_tab==index:return true
	await tree.process_frame
	var bar:TabBar=tabs.get_tab_bar()
	# B: DIRECTION 2026-11-09 “去掉 ⚡，内容并回‘对话/指令’”。
	# The tab bar now shares a scroll panel with utilities; reveal its real header
	# before clicking, just as reveal() already scrolls actual command buttons.
	var ancestor:Node=bar.get_parent()
	while ancestor!=null:
		if ancestor is ScrollContainer:ancestor.ensure_control_visible(bar)
		ancestor=ancestor.get_parent()
	await tree.process_frame;await tree.process_frame
	var point:Vector2=bar.global_position+bar.get_tab_rect(index).get_center()
	var viewport:Viewport=bar.get_viewport()
	if viewport is Window and viewport.is_embedded():point+=Vector2(viewport.position);viewport=tree.root
	var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;viewport.push_input(motion,true)
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=point;event.global_position=point;event.pressed=down;event.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0;viewport.push_input(event,true);await tree.process_frame
	return tabs.current_tab==index
static func reveal(tree:SceneTree,control:Control)->void:
	var owner:Node=control
	while owner!=null and (owner.get_script()==null or owner.get_script().resource_path!="res://scripts/main.gd"):owner=owner.get_parent()
	if owner!=null and owner.watch_ui!=null and owner.watch_ui.menu_scroll.is_ancestor_of(control) and not owner.chat.visible:await click(tree,owner.dialogue_button)
	var pages:Array=[];var parent:Node=control
	while parent.get_parent()!=null:
		if parent.get_parent() is TabContainer:pages.push_front({"tabs":parent.get_parent(),"index":parent.get_index()})
		parent=parent.get_parent()
	for page in pages:await tab(tree,page.tabs,page.index)
	var ancestor:Node=control.get_parent()
	while ancestor!=null:
		if ancestor is ScrollContainer:ancestor.ensure_control_visible(control)
		ancestor=ancestor.get_parent()
	await tree.process_frame;await tree.process_frame
	if owner!=null and owner.journey.shortcuts.is_ancestor_of(control):
		owner.journey._process(0);await tree.process_frame
static func click(tree:SceneTree,button:BaseButton)->bool:
	if not is_instance_valid(button):return false
	await reveal(tree,button)
	if not is_instance_valid(button):return false
	# A real window can receive native mouse motion between injected events.
	# Put that mouse at the target too, then wait for queued container layouts.
	# This sends exactly one press/release and never emits pressed directly.
	var viewport:Viewport=button.get_viewport()
	var at:Vector2
	var last_rect:=Rect2()
	var stable:=0
	for frame in range(12):
		var rect:Rect2=button.get_global_rect()
		stable=stable+1 if rect==last_rect else 0
		last_rect=rect;at=rect.get_center()
		viewport=button.get_viewport()
		if viewport is Window and viewport.is_embedded():at+=Vector2(viewport.position);viewport=tree.root
		if DisplayServer.get_name()!="headless":
			if viewport is Window:viewport.grab_focus()
			viewport.warp_mouse(at)
		var motion:=InputEventMouseMotion.new();motion.position=at;motion.global_position=at;viewport.push_input(motion,true)
		await tree.process_frame
		if stable>=2:break
	var count:Dictionary={"pressed":0}
	var received:Callable=func():count.pressed+=1
	button.pressed.connect(received)
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0;event.position=at;event.global_position=at;viewport.push_input(event,true);await tree.process_frame
	if is_instance_valid(button):button.pressed.disconnect(received)
	if count.pressed!=1:
		var hover:Control=viewport.gui_get_hovered_control()
		print("UI real input rejected ",button.text," path=",button.get_path()," point=",at," before=",last_rect," after=",button.get_global_rect()," visible=",button.is_visible_in_tree()," viewport=",viewport," root_size=",tree.root.size," disabled=",button.disabled," hovered=",hover.get_path() if hover!=null else "none")
	return count.pressed==1
static func init_game(tree:SceneTree)->Node:
	OS.set_environment("HABITAT_OPENING","legacy");tree.root.size=Vector2i(1280,800);tree.root.content_scale_size=Vector2i.ZERO
	var game:Node=load("res://scenes/main_v3.tscn").instantiate();game.world=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");tree.root.add_child(game)
	game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.view.sound_enabled=false;game.island_hud.set_process(false);game.world.director.set_all_enabled(false);game.chat.hide()
	return game
