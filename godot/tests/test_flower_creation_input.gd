extends "res://tests/test_brain_input.gd"
class CreationFake extends "res://scripts/companion_link.gd":
	var sent:Array=[]
	func uses_intents()->bool:return true
	func _start()->bool:return true
	func _send(message:Dictionary)->bool:sent.append(message.duplicate(true));return true
func raw_ground(at:Vector2)->void:
	game.chat.hide();game.view.center=at;game.view.follow_player=false;await process_frame
	var p:Vector2=game.view.screen(at)
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=p;event.global_position=p;event.pressed=down;root.push_input(event,true);await process_frame
func advance_until_idle(who:String,limit:int=12000)->void:
	for i in limit:
		game._process(.1)
		if not game.world._routes.has(who) and not game.world.flower_creation.active(who):return
		if i%200==0:await process_frame
	check(false,"route and flower job complete before timeout "+who)
func run()->void:
	base_directory=OS.get_environment("HABITAT_DATA_DIR");media=OS.get_environment("HABITAT_FLOWER_MEDIA");evidence=base_directory
	if media.is_empty():media=base_directory
	DirAccess.make_dir_recursive_absolute(media)
	root.size=Vector2i(1600,900);root.content_scale_size=Vector2i.ZERO
	node_added.connect(func(node):
		if node.get_script()!=null and node.get_script().resource_path=="res://scripts/main.gd":node.set_process(false);node.dialogue_adapter_factory=func(_id,_scope):return CreationFake.new())
	OS.set_environment("HABITAT_OPENING","showcase")
	game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game);current_scene=game
	for frame in 12:await process_frame
	game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.island_hud.set_process(false);game.chat.hide()
	for link in game.links.values():check(link is CreationFake,"prebuilt fake connection")
	print("FLOWER_INPUT setup")
	var w:RefCounted=game.world
	w.storage.restore({"items":{"wood":60,"rose_red":400,"rose_white":100}})
	# Real world click initiates the one World route across the bridge, never actor writes.
	await raw_ground(Vector2(43,210));await advance_until_idle("human")
	check(w.point(w.actors.human).distance_to(Vector2(43,210))<1.5,"real mouse walks across bridge to stall")
	await raw_ground(Vector2(43,208));check(game.flower_panel.visible,"actual stall click opens panel")
	var before:int=w.storage.count("wood");var roses:int=w.storage.count("rose_red")
	check(await UI.click(self,game.flower_panel.trade_button),"actual trade ten roses")
	check(w.storage.count("wood")==before-5 and w.storage.count("rose_red")==roses+10,"real atomic warehouse trade")
	print("FLOWER_INPUT trade")
	if DisplayServer.get_name()!="headless":await shot("flower-stall-zh")
	TranslationServer.set_locale("en");game.flower_panel.refresh();
	if DisplayServer.get_name()!="headless":await shot("flower-stall-en")
	TranslationServer.set_locale("zh_CN")
	# Locate an entire 5x7 HI rectangle using host validation, then select it with real input.
	var chosen:=Vector2(INF,INF)
	for x in range(25,125):
		for y in range(175,237):
			var p:=Vector2(x,y);var offsets:Array=w.flower_creation.pixels({"text":"HI"})
			if offsets.all(func(offset):return w.flower_creation.space("home",p+offset)) and w.point(w.actors.human).distance_to(p)<35:chosen=p;break
		if is_finite(chosen.x):break
	check(is_finite(chosen.x),"find actual open HI ground")
	var field:Vector2=game.flower_panel.text_input.get_global_rect().get_center()
	for down in [true,false]:
		var mouse:=InputEventMouseButton.new();mouse.button_index=MOUSE_BUTTON_LEFT;mouse.position=field;mouse.global_position=field;mouse.pressed=down;root.push_input(mouse,true);await process_frame
	check(game.flower_panel.text_input.has_focus(),"actual flower input receives focus above the HUD")
	for code in [KEY_H,KEY_I]:
		var event:=InputEventKey.new();event.keycode=code;event.unicode=code;event.pressed=true;root.push_input(event,true);await process_frame
	check(await UI.click(self,game.flower_panel.arrange_button),"actual HI place mode")
	await raw_ground(chosen);await advance_until_idle("human")
	check(w.flower_creation.flowers.size()==w.flower_creation.pixels({"text":"HI"}).size(),"real HI committed")
	if DisplayServer.get_name()!="headless":
		game.view.center=chosen+Vector2(5,3);game.view.zoom=game.view.default_zoom("home",chosen);game.chat.hide();await shot("flower-hi")
	game._open_flowers();check(await UI.click(self,game.flower_panel.pick_button),"actual pickup mode")
	var near_flowers:Array=w.flower_creation.flowers.values();near_flowers.sort_custom(func(a,b):return Vector2(a.position[0],a.position[1]).distance_to(w.point(w.actors.human))<Vector2(b.position[0],b.position[1]).distance_to(w.point(w.actors.human)));var one:Dictionary=near_flowers[0];await raw_ground(Vector2(one.position[0],one.position[1]));await advance_until_idle("human")
	check(w.flower_creation.flowers.size()==w.flower_creation.pixels({"text":"HI"}).size()-1,"picked one actual rose")
	# A local typed request chooses a personality pattern and returns through World.
	w.actors["companion-2"].appearance_id=w.actors.codex.appearance_id
	await text_input("小蓝摆个爱心")
	check(w.flower_creation.active("companion-2"),"real typed local heart accepted with alternate appearance")
	await advance_until_idle("companion-2")
	check(w.flower_creation.flowers.values().any(func(f):return f.actor_id=="companion-2" and f.label=="heart"),"local heart actually committed")
	check(w.point(w.actors["companion-2"]).distance_to(w.point(w.actors.human))<4,"local arranger returns near human")
	if DisplayServer.get_name()!="headless":
		var heart:Array=w.flower_creation.flowers.values().filter(func(f):return f.actor_id=="companion-2" and f.label=="heart")
		var center:=Vector2.ZERO
		for flower in heart:center+=Vector2(flower.position[0],flower.position[1])
		game.view.center=center/maxi(1,heart.size());game.view.zoom=game.view.default_zoom("home",game.view.center);game.chat.hide();await shot("flower-heart")
	# Prebuilt offline adapter receives one bound autonomous turn and chooses its own text.
	w.director.set_controller("codex","model");w.activities.release_follow("codex")
	game.chat.hide();game.chat_input.release_focus();game.autonomy.refresh_support()
	game.resident_connections.preferences.choose("codex","medium")
	check(game.resident_connections.preferences.enable_autonomy("codex",true),"fixture explicitly enables original autonomy")
	game.autonomy.player_input();game.autonomy.scheduler.enqueue("codex","flower-test","house_completed","fixture")
	for i in 60:game._process(.1)
	var connection:Node=game.links.codex
	check(not connection.sent.is_empty(),"prebuilt stub receives original budgeted request")
	connection._accept_event({"kind":"intent_result","turn_key":connection.turn_key,"speech":"用白玫瑰写一个心。","intents":[{"action":"arrange_flowers","text":"心","color":"white"},{"action":"gift_flower","color":"white"}]})
	connection._accept_event({"kind":"state","state":"ready","turnComplete":true,"turn_key":connection.turn_key})
	var gift_shot:=false
	for i in 12000:
		game._process(.1)
		if not gift_shot and w.actors.codex.activity=="local_offer_flower" and DisplayServer.get_name()!="headless":
			game.view.center=w.point(w.actors.codex);game.view.zoom=1;await shot("flower-gift");gift_shot=true
		if i%200==0:await process_frame
		if not game.intentions.plans.has("codex") and not w.flower_creation.active("codex"):break
	check(w.flower_creation.flowers.values().any(func(f):return f.actor_id=="codex" and f.label=="心"),"bound AI stub chose and placed true text")
	check(w.flower_creation.first_received,"first actual AI rose delivery records first receipt")
	if DisplayServer.get_name()!="headless":
		for frame in 12:await process_frame
		var gifts:Array=game.memory_books.entries.values().filter(func(e):return e.params.get("legacy",{}).get("kind","")=="gift_flower" and e.params.get("legacy",{}).get("first",false))
		check(not gifts.is_empty(),"canonical gift in Our Days")
		if not gifts.is_empty():check(not gifts[0].photo_id.is_empty() and FileAccess.file_exists(game.memory_books.directory.path_join(gifts[0].photo_id)),"first gift automatic real album photo")
	check(not game.memory_books.entries.values().filter(func(e):return e.resident_id=="codex" and e.layer=="facts").is_empty(),"actual gift has retained memory")
	game.resident_connections.preferences.enable_autonomy("codex",false)
	# Main-island single rose also goes through UI and the original crossing route.
	await raw_ground(Vector2(52,70));await advance_until_idle("human")
	var mainland:=Vector2(INF,INF)
	for x in range(35,80):
		for y in range(45,95):
			if w.flower_creation.space("home",Vector2(x,y)) and w.point(w.actors.human).distance_to(Vector2(x,y))<30:mainland=Vector2(x,y);break
		if is_finite(mainland.x):break
	game._open_flowers();check(await UI.click(self,game.flower_panel.single_button),"mainland real single placement mode")
	await raw_ground(mainland);print("FLOWER_MAIN request ",mainland," ",game.status.text);await advance_until_idle("human");print("FLOWER_MAIN final ",w.point(w.actors.human)," ",game.status.text)
	check(w.flower_creation.flowers.has(w.flower_creation.key("home",mainland)),"main island actual rose")
	print("Flower world input failed=",failed)
	quit(1 if failed else 0)
