extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
var game:Node
var failed:=false
var checks:=0
func check(value:bool,reason:String)->void:
	checks+=1
	if not value:failed=true;push_error(reason)
func _initialize()->void:call_deferred("run")
func key(code:int,unicode_value:int=0)->void:
	for down in [true,false]:
		var event:=InputEventKey.new();event.keycode=code;event.unicode=unicode_value;event.pressed=down;root.push_input(event,true);await process_frame
func run()->void:
	OS.set_environment("HABITAT_OPENING","legacy");root.size=Vector2i(960,640);root.content_scale_size=Vector2i.ZERO
	game=preload("res://tests/chat_composition_fixture.gd").new();game.world=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");root.add_child(game)
	game.save_enabled=false;game.set_process(false);game.view.set_process(false);await process_frame;await process_frame
	check(await UI.click(self,game.dialogue_button),"native product chat opens")
	var at:Vector2=game.chat_input.get_global_rect().get_center()
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.position=at;event.global_position=at;event.pressed=down;event.button_index=MOUSE_BUTTON_LEFT;root.push_input(event,true);await process_frame
	var text:String="大家去种地"
	for c in text:await key(KEY_NONE,c.unicode_at(0))
	check(game.chat_input.text==text,"real Unicode events enter the product LineEdit")
	var before:Dictionary=game.world.storage.saved()
	game.composing_fixture=true
	await key(KEY_ENTER)
	check(game.chat_input.text==text and not is_instance_valid(game.local_host_commands.card),"preedit Enter cannot submit or clear committed text")
	check(await UI.click(self,game.chat_send_button),"native send button receives click during preedit")
	check(game.chat_input.text==text and game.world.farms.host_grants.is_empty() and game.world.storage.saved()==before,"preedit send cannot authorize work or mutate stock")
	game.composing_fixture=false;await process_frame;await process_frame
	check(await UI.click(self,game.chat_send_button),"native send after composition ends")
	check(not is_instance_valid(game.local_host_commands.card) and game.chat_input.text.is_empty(),"committed ordinary text directly submits and clears after composition")
	check(not game.world.farms.orders.is_empty(),"only committed input may start real farm orders")
	check(game.world.storage.saved()==before,"starting routes does not pre-debit seeds")
	game.queue_free();await process_frame;print("CHAT_COMPOSITION_INPUT ",checks," failed=",failed);quit(1 if failed else 0)
