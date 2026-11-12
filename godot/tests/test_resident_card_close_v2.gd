extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
var checks:=0
var failed:=false
func check(ok:bool,msg:String)->void:
	checks+=1
	if not ok:failed=true;push_error(msg)
func _initialize()->void:call_deferred("run")
func mouse(pos:Vector2,button:int=MOUSE_BUTTON_LEFT)->void:
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=button;event.pressed=pressed;event.position=pos;event.global_position=pos;root.push_input(event,true);await process_frame
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"));OS.set_environment("HABITAT_OPENING","legacy");root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	var game:Node=UI.init_game(self);await process_frame;await process_frame
	var hud:Node=game.island_hud;var human:Dictionary=game.world.actors.human.duplicate(true)
	for size in [Vector2i(1280,800),Vector2i(960,640)]:
		root.size=size
		for mode in ["小","标准","大"]:
			hud.set_interface_size(mode,false);hud.refresh();await process_frame;await process_frame
			check(await UI.click(self,hud.resident_menus.codex),"mouse opens resident detail "+str(size)+mode)
			hud.refresh();await process_frame;await process_frame
			var bounds:=Rect2(Vector2.ZERO,Vector2(size));var header_rect:Rect2=hud.card_close.get_global_rect()
			check(hud.resident_card.visible and hud.card_close.text=="×" and bounds.encloses(header_rect),"fixed close in bounds "+str(size)+mode)
			var capture:String=OS.get_environment("HABITAT_FISH_CAPTURE")
			if not capture.is_empty() and mode=="标准":
				DisplayServer.window_set_size(size);await process_frame;await process_frame;await RenderingServer.frame_post_draw
				var image:Image=root.get_texture().get_image()
				if image.get_size()==size:image.save_png(capture.path_join("resident-detail-%dx%d.png"%[size.x,size.y]))
			var title_pos:Vector2=hud.card_close.global_position
			for i in range(7):await mouse(hud.card_scroll.get_global_rect().get_center(),MOUSE_BUTTON_WHEEL_DOWN)
			check(hud.card_close.global_position==title_pos and bounds.encloses(hud.card_close.get_global_rect()),"header stays fixed while content scrolls "+str(size)+mode)
			check(await UI.click(self,hud.card_close) and not hud.resident_card.visible,"actual x closes "+str(size)+mode)
			hud.refresh();await process_frame
			check(await UI.click(self,hud.resident_menus.codex),"reopen for outside click")
			await mouse(Vector2(300,160));check(not hud.resident_card.visible,"actual outside mouse closes")
			hud.refresh();await process_frame
			check(await UI.click(self,hud.resident_menus.codex),"reopen for Escape")
			var key:=InputEventKey.new();key.keycode=KEY_ESCAPE;key.pressed=true;root.push_input(key,true);await process_frame
			check(not hud.resident_card.visible,"actual Escape closes")
	check(game.world.actors.human==human,"closing detail never moves human")
	game.queue_free();await process_frame
	print("Resident detail close v2: ",checks," checks, failed=",failed);quit(1 if failed else 0)
