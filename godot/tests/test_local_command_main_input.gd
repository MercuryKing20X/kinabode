extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
var failed:=false
var checks:=0
var game:Node
func check(okay:bool,label:String)->void:
	checks+=1
	if not okay:failed=true;push_error(label)
func _initialize()->void:call_deferred("run")
func text_input(text:String,send_by_button:bool=false)->void:
	if not game.chat.visible:check(await UI.click(self,game.dialogue_button),"native opens real product chat")
	await process_frame;await process_frame
	var at:Vector2=game.chat_input.get_global_rect().get_center()
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=at;event.global_position=at;event.pressed=down;root.push_input(event,true);await process_frame
	for index in range(text.length()):
		for down in [true,false]:
			var event:=InputEventKey.new();event.unicode=text.unicode_at(index);event.pressed=down;root.push_input(event,true);await process_frame
			game._process(.016)
	check(game.chat_input.text==text,"native actual product input retains text")
	if send_by_button:
		RenderingServer.force_draw(false)
		if DisplayServer.get_name()!="headless":root.get_texture().get_image().save_png("/tmp/youqi-command-main-"+str(root.size.x)+"-before-send.png")
		check(await UI.click(self,game.chat_send_button),"native send button")
	else:
		for down in [true,false]:
			var event:=InputEventKey.new();event.keycode=KEY_ENTER;event.pressed=down;root.push_input(event,true);await process_frame
func run()->void:
	game=UI.init_game(self);await process_frame;await process_frame
	root.size=Vector2i(1280,800) if OS.get_environment("HABITAT_COMMAND_LARGE")=="1" else Vector2i(960,640);await process_frame;await process_frame
	RenderingServer.force_draw(false)
	if DisplayServer.get_name()!="headless":root.get_texture().get_image().save_png("/tmp/youqi-command-main-"+str(root.size.x)+"-start.png")
	var initial_plots:Dictionary=game.world.farms.plots.duplicate(true)
	var initial_stock:Dictionary=game.world.storage.saved();var initial_human:Array=game.world.actors.human.position.duplicate()
	var preview:Dictionary=game.world.farms.preview_host_orders(game.world.actors.keys().filter(func(id):return id!="human"),"ready","","")
	var expected_harvest:Dictionary={};var unique_plots:Dictionary={}
	for row in preview.rows:
		if not row.allowed:continue
		for pid in row.plot_ids:
			check(not unique_plots.has(pid),"real plots never overlap")
			unique_plots[pid]=true
			var crop:String=initial_plots[pid].crop_id
			expected_harvest[crop]=int(expected_harvest.get(crop,0))+int(game.world.farms.crops[crop].yield)
			expected_harvest["seed."+crop]=int(expected_harvest.get("seed."+crop,0))+1
	await text_input("大家去收菜")
	var coordinator:Node=game.local_host_commands
	check(not is_instance_valid(coordinator.card),"ordinary group harvest executes without card")
	check(game.world.farms.orders.size()==4,"four actual independent farm orders start from Enter")
	for tick in range(16000):
		game._process(.1);coordinator._process(.1)
		if game.world.farms.orders.values().all(func(order):return order.status=="completed") or game.world.farms.orders.values().any(func(order):return order.status=="paused"):break
	if not game.world.farms.orders.values().all(func(order):return order.status=="completed"):
		print("COMMAND_FARM_BLOCKER orders=",game.world.farms.orders," jobs=",game.world.work.jobs," grants=",game.world.farms.host_grants)
		preload("res://scripts/save_store.gd").save_world(game.world,OS.get_environment("HABITAT_DATA_DIR").path_join("farm-blocker"))
	check(game.world.farms.orders.values().all(func(order):return order.status=="completed"),"all actual group harvests reach completion")
	check(game.world.actors.human.position==initial_human,"no text command moved the human")
	check(game.world.farms.host_grants.is_empty(),"per-order grants revoked after completion")
	check(coordinator.tracked.is_empty(),"coordinator waits for exact completed order tokens")
	for item in expected_harvest:check(game.world.storage.count(item)==int(initial_stock.items.get(item,0))+int(expected_harvest[item]),"exact confirmed real harvest and retained seed warehouse conservation "+item)
	for item in initial_stock.items:
		if not expected_harvest.has(item):check(game.world.storage.count(item)==int(initial_stock.items[item]),"unrelated real stock unchanged "+item)
	await text_input("一朵云在笑",true)
	check(game.chat_input.text.is_empty() and JSON.stringify(game.dialogue.histories).contains("一朵云在笑"),"chat text is delivered into the unified history")
	game.queue_free();await process_frame
	print("LOCAL_COMMAND_MAIN_INPUT ",checks," failed=",failed);quit(1 if failed else 0)
