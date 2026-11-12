extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
const Commands=preload("res://scripts/local_host_commands.gd")
var failed:=false
var checks:=0
var game:Node
func check(okay:bool,label:String)->void:
	checks+=1
	if not okay:failed=true;push_error(label)
func _initialize()->void:call_deferred("run")
func type_text(edit:LineEdit,text:String)->void:
	for down in [true,false]:
		var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=down;click.position=edit.get_global_rect().get_center();click.global_position=click.position;root.push_input(click,true);await process_frame
	for index in range(text.length()):
		for down in [true,false]:
			var event:=InputEventKey.new();event.unicode=text.unicode_at(index);event.pressed=down;root.push_input(event,true);await process_frame
func run()->void:
	game=UI.init_game(self);await process_frame;await process_frame
	# Native component harness: Main text-send integration has its own acceptance.
	var coordinator:Node=Commands.new(game);game.add_child(coordinator)
	var input:=LineEdit.new();input.position=Vector2(340,350);input.size=Vector2(500,44);game.island_hud.add_child(input)
	input.text_submitted.connect(func(text):coordinator.submit(text,["codex"],"test-component"))
	await type_text(input,"小蓝和小橙跟我来")
	for down in [true,false]:
		var enter:=InputEventKey.new();enter.keycode=KEY_ENTER;enter.pressed=down;root.push_input(enter,true);await process_frame
	check(not is_instance_valid(coordinator.card),"ordinary typed command directly executes")
	var original:Dictionary=game.world.storage.saved();var positions:Dictionary=game.world.actors.duplicate(true)
	check(game.world.activities.following.keys().size()==2 and game.world.activities.following.has("companion-2") and game.world.activities.following.has("npc.mira"),"only named followers start")
	check(game.world.storage.saved()==original,"following uses no materials")
	check(game.world.point(game.world.actors.human)==Vector2(positions.human.position[0],positions.human.position[1]),"host never moved by text command")
	for tick in range(1000):game.world.advance(.1);coordinator._process(.1)
	input.clear();await type_text(input,"大家别跟了")
	for down in [true,false]:
		var enter:=InputEventKey.new();enter.keycode=KEY_ENTER;enter.pressed=down;root.push_input(enter,true);await process_frame
	check(not is_instance_valid(coordinator.card) and game.world.activities.following.is_empty(),"native unfollow uses original release path")
	var summary:Dictionary=coordinator.submit("我说一颗云",[],"test-component")
	check(summary.handled and not summary.parsed and summary.examples.size()==3 and not summary.reply.line.is_empty(),"unknown gives personality response and three localized examples")
	game.queue_free();await process_frame
	print("LOCAL_COMMAND_CARD_INPUT ",checks," failed=",failed);quit(1 if failed else 0)
