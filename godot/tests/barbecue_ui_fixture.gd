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
	while owner!=null and not (owner.has_method("_open_model_settings") and owner.get("island_hud")!=null):owner=owner.get_parent()
	if owner!=null and owner.watch_ui!=null and is_instance_valid(owner.watch_ui.menu_scroll) and owner.watch_ui.menu_scroll.is_ancestor_of(control) and not owner.chat.visible:await click(tree,owner.dialogue_button)
	if owner!=null and is_instance_valid(control) and is_instance_valid(owner.island_hud) and owner.island_hud.residents_collapsed:
		var hud:Control=owner.island_hud
		if control==hud.manage_connections or control in hud.appearance_buttons.values() or control in hud.resident_menus.values():
			await click(tree,hud.collapse_residents)
	if not is_instance_valid(control):return
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
	if is_instance_valid(control) and owner!=null and owner.journey.shortcuts.is_ancestor_of(control):
		owner.journey._process(0);await tree.process_frame
static func button_locator(button:BaseButton)->Dictionary:
	var owner:Node=button
	while owner!=null and (owner.get_script()==null or owner.get_script().resource_path!="res://scripts/main.gd"):owner=owner.get_parent()
	var metadata:Dictionary={}
	for key in button.get_meta_list():metadata[key]=button.get_meta(key)
	var result:Dictionary={"original":weakref(button),"parent":weakref(button.get_parent()),"path":button.get_path(),"text":button.text,"tooltip":button.tooltip_text,"class":button.get_class(),"metadata":metadata}
	if owner!=null and button.has_meta("fish_id") and owner.island_hud.notifications.is_ancestor_of(button):
		result["fish_binding"]={"owner":weakref(owner),"id":button.get_meta("fish_id"),"world":weakref(owner.world)}
	if owner!=null and owner.command_page!=null:
		for key in owner.command_page.buttons:
			if owner.command_page.buttons[key]==button:
				result["command"]={"owner":weakref(owner),"key":key,"selected":owner.command_page.selected.duplicate(),"category":owner.command_page.category,"world":weakref(owner.world)}
	return result
static func resolve_button(locator:Dictionary)->BaseButton:
	if locator.has("fish_binding"):
		var binding:Dictionary=locator.fish_binding;var owner:Node=binding.owner.get_ref()
		if not is_instance_valid(owner) or owner.world!=binding.world.get_ref():return null
		var matches:Array=descendants(owner.island_hud.notifications).filter(func(n):return n is BaseButton and n.get_meta("fish_id","")==binding.id and n.text==locator.text)
		return matches[0] if matches.size()==1 else null
	if locator.has("command"):
		var binding:Dictionary=locator.command;var owner:Node=binding.owner.get_ref()
		if not is_instance_valid(owner) or owner.world!=binding.world.get_ref() or owner.command_page.selected!=binding.selected or owner.command_page.category!=binding.category:return null
		var current:BaseButton=owner.command_page.buttons.get(binding.key)
		if is_instance_valid(current) and not current.is_queued_for_deletion() and current.text==locator.text:return current
		return null
	var original:BaseButton=locator.original.get_ref()
	if is_instance_valid(original) and not original.is_queued_for_deletion():return original
	var parent:Node=locator.parent.get_ref()
	if not is_instance_valid(parent):return null
	var matches:Array=[]
	for child in parent.get_children():
		if not child is BaseButton or child.is_queued_for_deletion() or child.get_class()!=locator["class"] or child.text!=locator.text:continue
		if locator.text.is_empty() and child.tooltip_text!=locator.tooltip:continue
		if child.get_meta_list().size()!=locator.metadata.size():continue
		var same:=true
		for key in locator.metadata:
			if not child.has_meta(key) or child.get_meta(key)!=locator.metadata[key]:same=false;break
		if same:matches.append(child)
	return matches[0] if matches.size()==1 else null
static func click(tree:SceneTree,button:BaseButton)->bool:
	if not is_instance_valid(button):return false
	var locator:Dictionary=button_locator(button)
	await reveal(tree,button)
	button=resolve_button(locator)
	if not is_instance_valid(button):return false
	# Rebuilding command menus replace nodes during genuine layout waits. Resolve
	# the same command and exact selected actors before each frame; never use a
	# similarly labelled command from another scope or click a stale node.
	var viewport:Viewport
	var at:Vector2
	var last_rect:=Rect2()
	var last_id:=0
	var stable:=0
	for frame in range(12):
		button=resolve_button(locator)
		if not is_instance_valid(button):print("UI target vanished before input ",locator.path);return false
		var rect:Rect2=button.get_global_rect()
		stable=stable+1 if rect==last_rect and button.get_instance_id()==last_id else 0
		last_id=button.get_instance_id();last_rect=rect
		at=button.get_global_transform_with_canvas()*(button.size*.5)
		viewport=button.get_viewport()
		if viewport is Window and viewport.is_embedded():at+=Vector2(viewport.position);viewport=tree.root
		if DisplayServer.get_name()!="headless":
			if viewport is Window:viewport.grab_focus()
			viewport.warp_mouse(at)
		var motion:=InputEventMouseMotion.new();motion.position=at;motion.global_position=at;viewport.push_input(motion,true)
		await tree.process_frame
		var current:BaseButton=resolve_button(locator)
		if is_instance_valid(current) and current.get_instance_id()==last_id and current.get_global_rect()==last_rect and stable>=2:button=current;break
		button=current
	if not is_instance_valid(button) or button.get_instance_id()!=last_id or button.get_global_rect()!=last_rect:return false
	var count:Dictionary={"pressed":0}
	var received:Callable=func():count.pressed+=1
	button.pressed.connect(received)
	# Deliver one genuine pair without yielding to a periodic menu rebuild
	# between button-down and button-up. No direct signal or callback dispatch.
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0;event.position=at;event.global_position=at;viewport.push_input(event,true)
		# MenuButton opens on down. Let its existing deferred popup placement
		# run before release, so the release stays over the opener.
		if down and button is MenuButton:await tree.process_frame
	await tree.process_frame
	if is_instance_valid(button):button.pressed.disconnect(received)
	if count.pressed!=1:
		var hover:Control=viewport.gui_get_hovered_control()
		print("UI real input rejected ",locator.text," path=",locator.path," point=",at," before=",last_rect," root_size=",tree.root.size," hovered=",hover.get_path() if hover!=null else "none"," target_alive=",is_instance_valid(button))
	return count.pressed==1
static func init_game(tree:SceneTree,opening:String="legacy")->Node:
	OS.set_environment("HABITAT_OPENING",opening);tree.root.size=Vector2i(1280,800);tree.root.content_scale_size=Vector2i.ZERO
	var game:Node=load("res://scenes/main_v3.tscn").instantiate();game.world=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");tree.root.add_child(game)
	game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.view.sound_enabled=false;game.island_hud.set_process(false);game.world.director.set_all_enabled(false);game.chat.hide()
	return game
