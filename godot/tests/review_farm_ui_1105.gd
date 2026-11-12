extends "res://tests/test_local_command_main_input.gd"
## Independent review only. Uses native product input, cancels all previews; no farming is issued.
const Text=preload("res://scripts/localization.gd")
var notes:Array=[]
func press(code:Key,shift:bool=false)->void:
	for down in [true,false]:
		var e:=InputEventKey.new();e.keycode=code;e.pressed=down;e.shift_pressed=shift;root.push_input(e,true);await process_frame
func capture(id:String)->void:
	await process_frame;await RenderingServer.frame_post_draw
	if DisplayServer.get_name()!="headless":root.get_texture().get_image().save_png(OS.get_environment("HABITAT_DATA_DIR").path_join(id+".png"))
func run()->void:
	game=UI.init_game(self);await process_frame;await process_frame
	for size in [Vector2i(1280,800),Vector2i(960,640)]:
		root.size=size;DisplayServer.window_set_size(size);await process_frame;await process_frame
		var stock:Dictionary=game.world.storage.saved();var orders:Dictionary=game.world.farms.orders.duplicate(true)
		await text_input("大家去收菜")
		var card:Node=game.local_host_commands.card
		check(is_instance_valid(card) and card.visible,"review actual typed group card "+str(size))
		if not is_instance_valid(card):break
		check(card.boxes.size()==4,"review card contains all four names")
		var focus:Array=[];var checkbox_seen:bool=false;var cancel_seen:bool=false
		for n in range(18):
			await press(KEY_TAB)
			var owner:Control=card.gui_get_focus_owner()
			if owner!=null:
				focus.append({"type":owner.get_class(),"text":str(owner.get("text"))})
				if owner is CheckBox and not owner.disabled:
					checkbox_seen=true;var before:bool=owner.button_pressed;await press(KEY_SPACE);check(owner.button_pressed!=before,"Space toggles actual focused checkbox");await press(KEY_SPACE)
				if owner==card.get_cancel_button():cancel_seen=true
		check(checkbox_seen and cancel_seen,"Tab reaches participants and cancel")
		check(card.position.x>=0 and card.position.y>=0 and card.position.x+card.size.x<=size.x and card.position.y+card.size.y<=size.y,"group card remains in actual viewport")
		notes.append({"size":str(size),"focus":focus,"rect":[card.position.x,card.position.y,card.size.x,card.size.y]})
		await capture("group-card-keyboard-"+str(size.x));await press(KEY_ESCAPE)
		check(game.world.storage.saved()==stock and game.world.farms.orders==orders and game.world.farms.host_grants.is_empty(),"Escape cancels preview without material or authority effects")
		# Native mouse opens farm panel/helper dialog; keyboard exits without submitting.
		game.chat.hide();game.view.follow_player=false;var plot:Dictionary=game.world.farms.farm_plots("farm.home")[0];game.view.center=game.world.point(plot);await process_frame
		var at:Vector2=game.view.screen(game.world.point(plot))
		for down in [true,false]:
			var e:=InputEventMouseButton.new();e.position=at;e.global_position=at;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;root.push_input(e,true);await process_frame
		check(game.farm_panel.visible,"native field panel reachable")
		check(await UI.click(self,game.farm_panel.helpers_button),"native helper invitation reachable")
		var invite:Node=UI.shown(game,"res://scripts/farm_invitation.gd")
		check(invite!=null and invite.checks.size()==4,"field invitation all four")
		if invite!=null:
			await capture("field-invitation-"+str(size.x));await press(KEY_ESCAPE)
			check(not is_instance_valid(invite) or not invite.visible,"Escape exits field invitation")
		game.farm_panel.hide()
	var f:=FileAccess.open(OS.get_environment("HABITAT_DATA_DIR").path_join("review.json"),FileAccess.WRITE);f.store_string(JSON.stringify({"notes":notes,"checks":checks,"failed":failed},"  "));f.close()
	game.queue_free();await process_frame;print("FARM_UI_REVIEW ",checks," failed=",failed);quit(1 if failed else 0)
