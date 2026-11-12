extends "res://tests/test_intelligence_core_input.gd"
func key(code:int,down:bool=true)->void:
	var event:=InputEventKey.new();event.keycode=code;event.pressed=down;root.push_input(event,true);await process_frame
func run()->void:
	await fresh()
	game.chat.hide()
	var portrait:Button=game.island_hud.avatar_buttons["npc.mira"]
	var at:Vector2=portrait.get_global_rect().get_center()
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=at;event.global_position=at;event.pressed=down;event.double_click=down;event.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0;root.push_input(event,true);await process_frame
	check(game.chat.visible and not game.group_chat and game.chat_actor=="npc.mira" and game.command_page.selected==["npc.mira"],"native portrait double-click keeps exact direct recipient through expand")
	preload("res://tests/dialogue_ui_fixture.gd").open(game,"codex")
	await process_frame;await process_frame
	check(not game.command_page.tabs.visible and game.chat_input.is_visible_in_tree(),"one input without command/talk tabs")
	game.chat_input.grab_focus()
	check(game._camera_keys_allowed(),"empty focused input permits camera")
	var before:Vector2=game.view.center
	await key(KEY_RIGHT);game._process(.1);await key(KEY_RIGHT,false)
	check(game.view.center.x>before.x,"actual right key pans camera with empty input")
	game.chat_input.text="hello";game.chat_input.caret_column=2
	before=game.view.center
	await key(KEY_RIGHT);game._process(.1);await key(KEY_RIGHT,false)
	check(game.view.center==before and game.chat_input.caret_column==3,"nonempty input owns arrow caret")
	await key(KEY_ESCAPE);await key(KEY_ESCAPE,false)
	# B: DIRECTION 2026-11-09 “Esc 或再点按钮收起”。 Arrow/caret assertions above remain unchanged.
	check(not game.chat_input.has_focus() and not game.chat.visible,"Escape collapses unified dialogue and returns game focus")
	game.chat_input.clear()
	check(await UI.click(self,game.dialogue_button),"native reopens collapsed dialogue")
	await key(KEY_ENTER);await key(KEY_ENTER,false)
	check(game.chat_input.has_focus(),"Enter returns input focus")
	await picture("unified-dialogue")
	game.queue_free();await process_frame
	print("UNIFIED_DIALOGUE_INPUT ",checks," failed=",failed);quit(1 if failed else 0)
