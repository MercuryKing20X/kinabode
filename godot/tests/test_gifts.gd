extends SceneTree
const Places=preload("res://scripts/map_locations.gd")
const F=preload("res://tests/cooking_fixture.gd")
const B=preload("res://tests/backpack_fixture.gd")
const Fake=preload("res://tests/test_overnight_autonomy.gd").Fake
const Save=preload("res://scripts/save_store.gd")
var checks:=0
var failed:=false
var directory: String
func _initialize() -> void:call_deferred("run")
func check(ok: bool,text: String) -> void:
	checks+=1
	if not ok:failed=true;push_error(text)
func give(receiver: String,quantity: int=1) -> Dictionary:return {"intent":"give","receiver_id":receiver,"item_id":"turnip","quantity":quantity}
func near(world: RefCounted,mover: String,other: String) -> bool:
	var point: Vector2=world.point(world.actors[other])
	for offset in [Vector2(1,0),Vector2(-1,0),Vector2(0,1),Vector2(0,-1)]:
		if world.walkable(world.actors[other].region_id,point+offset):return F.job(world,mover,{"intent":"move","x":point.x+offset.x,"y":point.y+offset.y})
	return false
func prepared() -> RefCounted:
	var world:=F.fresh()
	check(F.harvest(world,"turnip"),"real harvest before gift")
	check(near(world,"human","codex"),"human explicitly walks close through World")
	check(F.withdraw(world,"codex","turnip"),"own genuine gift inventory allocated after approach")
	return world
func reload_world(world: RefCounted,name: String) -> RefCounted:
	var path:=directory.path_join(name);check(Save.save_world(world,path),"save "+name)
	var loaded:=F.fresh();check(Save.load_world(loaded,path).ok,"reload "+name);return loaded
func run() -> void:
	directory=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(1);return
	var world:=prepared();var total:=F.amount(world,"turnip");var human: Dictionary=world.actors.human.duplicate(true)
	var bad:=give("human");bad["giver_id"]="human"
	check(not world.command("codex",bad).ok and world.actors.human==human,"model cannot borrow human source identity")
	check(not world.command("codex",give("codex")).ok,"self transfer rejected")
	check(not world.command("codex",give("human",99)).ok and F.amount(world,"turnip")==total,"insufficient own item rejects entire gift")
	check(world.command("codex",give("human",2)).ok,"atomic two-crop gift")
	check(world.actors.human.carry.turnip==2 and F.amount(world,"turnip")==total and world.actors.human.position==human.position,"direct human receipt respects original bag and movement")
	check(world.memories.records.size()==1 and world.memories.records[0].kind=="gift" and world.memories.records[0].participants.size()==2,"only giver and receiver in real gift fact")
	world.command("codex",{"intent":"stop"});world.advance(.1)
	var loaded:=reload_world(world,"received")
	check(F.amount(loaded,"turnip")==total and loaded.actors.human.carry.get("turnip",0)==0 and loaded.storage.count("turnip")==world.storage.count("turnip")+2 and loaded.work.jobs.is_empty(),"post-transfer cancel/reload neither duplicates nor consumes")
	check(world.memories.valid_saved(world.memories.saved(),world.actors,world.world_id),"gift canonical validation")
	check(world.deposit_all("codex").ok and F.job(world,"codex",{"intent":"move","x":Places.point("p_51_44").x,"y":Places.point("p_51_44").y}) and F.withdraw(world,"codex","turnip",1) and not world.command("codex",give("human")).ok and F.amount(world,"turnip")==total,"distance failure is whole rejection and never auto-walks")
	check(near(world,"human","npc.mira") and world.command("human",give("npc.mira")).ok,"explicit human gift can give local resident owned items")
	loaded=reload_world(world,"local-receiver")
	check(loaded.actors["npc.mira"].carry.get("turnip")==1 and F.amount(loaded,"turnip")==total,"local received inventory persists under same schema7/carry limit")
	# Full bag from actual wood, no inventory injection.
	world=prepared();var library:=preload("res://scripts/character_library.gd").new();library.configure(directory.path_join("art"));world.library=library
	check(B.wood(world,8,"human"),"real 24 wood hauled")
	check(world.take_storage_host("wood",20).ok,"real warehouse load fills exactly20")
	world.command("human",{"intent":"stop"});check(near(world,"human","codex"),"full recipient explicitly walks close")
	var before: String=world.memories._canonical(world.actors)
	check(not world.command("codex",give("human")).ok and world.memories._canonical(world.actors)==before,"capacity failure changes neither actor at all")
	check(F.job(world,"human",{"intent":"store"}) and B.wood(world,14,"human"),"real materials for indoor region rejection")
	var selected: Dictionary=world.command("human",{"intent":"select_blueprint","target_id":"home.house.01","blueprint_id":"cottage"})
	var planned: Dictionary=world.command("human",{"intent":"build_house","target_id":"home.house.01"})
	for frame in range(18000):
		world.advance(.15)
		if world.projects.plans.get("human",{}).get("status") in ["completed","blocked"]:break
	check(selected.ok and planned.ok and world.projects.plans.get("human",{}).get("status")=="completed" and F.job(world,"human",{"intent":"enter","target_id":"home.house.01"}),"real house completion and entry")
	check(not world.command("codex",give("human")).ok and world.actors.human.region_id!="home","different regions reject without remote transfer")
	# No material moves while a real inventory task could overwrite a bundle.
	world=prepared();check(world.command("human",{"intent":"chop","target_id":"home.tree.01"}).ok,"real recipient task starts")
	before=world.memories._canonical(world.actors)
	check(not world.command("codex",give("human")).ok and world.memories._canonical(world.actors)==before,"busy inventory cannot lose a received item to later task assignment")
	# Real UI path can only give human's own inventory.
	var game: Node=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false);root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
	await process_frame
	game.world.director.set_all_enabled(false);game.view.sound_enabled=false;game.chat.hide();game.chat_input.release_focus()
	check(F.harvest(game.world,"turnip") and F.withdraw(game.world,"human","turnip") and near(game.world,"codex","human"),"actual human UI inventory prepared")
	game.gift_panel.open("codex")
	var output:=OS.get_environment("HABITAT_OVERNIGHT_CAPTURE_DIR")
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	for size in [Vector2i(1280,800),Vector2i(960,640)]:
		root.size=size;await process_frame;await process_frame
		check(root.get_visible_rect().encloses(game.gift_panel.get_global_rect()),"gift panel fits "+str(size))
		if not output.is_empty():
			await RenderingServer.frame_post_draw
			var image:=root.get_texture().get_image();check(image.get_size()==size,"actual gift image "+str(size));image.save_png(output.path_join("gifts-%dx%d.png"%[size.x,size.y]))
	var combined: int=F.amount(game.world,"turnip");game.gift_panel.quantity.value=1;game.gift_panel.send_gift()
	check(game.world.actors.codex.carry.get("turnip")==1 and F.amount(game.world,"turnip")==combined,"matching human UI click transfers one real crop")
	check(game.links.values().all(func(link):return link._pid==-1),"gifts never start inference by themselves")
	game.dialogue_adapter_factory=func(_id,_scope):return Fake.new()
	for connection in game.links.values():connection.queue_free()
	game.links.clear();game.world.director.set_controller("codex","model");game._ensure_link("codex");game.link=game.links.codex
	game.resident_connections.preferences.enable_autonomy("codex",true);game.autonomy.player_input();game.autonomy.scheduler.enqueue("codex","gift-round","house_completed","真实事件测试输入")
	for frame in range(6):game._process(1)
	check(game.autonomy.scheduler.active.has("codex"),"fake budgeted autonomous round can begin while carrying own crop")
	game.links.codex._accept_event({"kind":"action","id":"give-own","command":give("human")})
	game.links.codex.complete()
	check(game.world.actors.codex.carry.is_empty() and F.amount(game.world,"turnip")==combined and game.autonomy.scheduler.usage("codex").calls==1,"model gives only own real crop within actual autonomy tool and call budget")
	game.queue_free();await process_frame
	print("Gifts: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)
