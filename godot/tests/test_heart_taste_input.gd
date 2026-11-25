extends "res://tests/test_barbecue_ui_v4.gd"
const UI=preload("res://tests/barbecue_ui_fixture.gd")
class Fake extends "res://scripts/companion_link.gd":
	func _start()->bool:return false
	func _send(_message:Dictionary)->bool:return false
var records:Array=[]
func run()->void:
	OS.set_environment("HABITAT_OPENING","legacy")
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	game=load("res://scenes/main_v3.tscn").instantiate()
	game.dialogue_adapter_factory=func(_id,_scope):return Fake.new()
	game.world=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");root.add_child(game)
	game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.view.sound_enabled=false;game.island_hud.set_process(false);w=game.world;w.director.set_all_enabled(true);game.chat.hide()
	await process_frame;await process_frame
	check(walk(w.life),"host arrives by real World route")
	print("TASTE_STOCK ",w.storage.saved())
	for number in range(1,4):await dinner("single:mushroom",number)
	await dinner("single:turnip",1)
	await dinner("single:blueberry",1)
	var favorites:Array=w.memories.records.filter(func(entry):return entry.kind=="favorite_taste" and entry.facts.actor_id=="codex")
	check(favorites.size()==1 and favorites[0].facts.food_id=="blueberry" and favorites[0].participants.has("human"),"first actual favourite meal records canonical shared fact")
	check(not w.memories.engine_facts_valid("favorite_taste",{"actor_id":"codex","food_id":"mushroom","meal_id":"0".repeat(24)},["codex"],w.actors),"staple cannot forge a favourite proof")
	check(not w.memories.engine_facts_valid("favorite_taste",{"actor_id":"human","food_id":"blueberry","meal_id":"0".repeat(24)},["human"],w.actors),"human cannot receive companion favourite proof")
	check(not w.memories.engine_facts_valid("favorite_taste",{"actor_id":"codex","food_id":"blueberry","meal_id":"bad"},["codex"],w.actors),"invalid meal identity rejects favourite proof")
	var media:String=OS.get_environment("HABITAT_HEART_TASTE_MEDIA")
	if not media.is_empty():
		DirAccess.make_dir_recursive_absolute(media);game.chat.hide();game.brain_panel.hide();game.view.follow_actor="codex";game.view.follow_player=true
		game.island_hud.residents_panel.hide();game.island_hud.notifications.hide();game.steward.panel.hide()
		for frame in 120:
			for tick in 5:w.advance(.1)
			game.view.center=w.point(w.actors["codex"]);game.view._process(.5)
			await process_frame;await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(media.path_join("taste-heart-%03d.png"%frame))
		FileAccess.open(media.path_join("taste-symbols.json"),FileAccess.WRITE).store_string(JSON.stringify(w.hearts.symbol_counts,"  "))
	var saved_mood:Dictionary=w.hearts.mood("codex")
	check(w.memories.query("codex",{"kind":"favorite_taste"}).get("total",0)==1,"our days exposes only actual favourite")
	var saved_count:int=w.life.fireside.dialogue.mushroom_count("codex")
	var path:String=OS.get_environment("HABITAT_DATA_DIR").path_join("taste-save")
	var Store=preload("res://scripts/save_store.gd")
	check(Store.save_world(w,path),"actual taste state saves")
	var helper=preload("res://tests/test_barbecue_v2.gd").new()
	var restored=helper.fresh(path.path_join("read"));helper.free()
	check(Store.load_world(restored,path).ok,"taste and heart validate on reload")
	print("RELOAD_TASTE before=",saved_mood," after=",restored.hearts.mood("codex")," counts=",saved_count," / ",restored.life.fireside.dialogue.mushroom_count("codex"))
	var loaded_mood:Dictionary=restored.hearts.mood("codex")
	check(saved_mood.keys().all(func(axis):return is_equal_approx(float(saved_mood[axis]),float(loaded_mood[axis]))) and restored.life.fireside.dialogue.mushroom_count("codex")==saved_count,"JSON roundtrip retains each mood axis and exact same-day staple count without replay")
	var output:String=OS.get_environment("HABITAT_HEART_EVIDENCE")
	if not output.is_empty():FileAccess.open(output.path_join("taste-input.json"),FileAccess.WRITE).store_string(JSON.stringify({"records":records,"checks":checks,"failed":failed},"  "))
	game.queue_free();await process_frame;print("HEART TASTE INPUT ",checks," checks failed=",failed);quit(1 if failed else 0)
func dinner(menu_id:String,number:int)->void:
	var fire:RefCounted=w.life.fireside
	if not fire.circle_closed:fire.end_circle("host ends previous meal")
	check(walk(w.life),"host walks to fire before menu")
	game._show_barbecue_menu("home.barbecue");await process_frame;await process_frame
	var panel:Node=UI.shown(game,"res://scripts/fireside_panel.gd")
	if not fire.burning():check(await UI.click(self,panel.light_button),"real light mouse input")
	check(await UI.click(self,panel.roast_button),"real barbecue mouse input")
	var invitation:Node=UI.shown(game,"res://scripts/fireside_invitation.gd")
	for box in invitation.checks.values():box.set_pressed_no_signal(false)
	check(await UI.click(self,invitation.checks["codex"]) and await UI.click(self,invitation.get_ok_button()),"real selected resident invitation and next")
	var menu:Node=UI.shown(game,"res://scripts/fireside_menu.gd")
	var expand:Array=UI.descendants(menu).filter(func(n):return n is Button and n.has_meta("expand_basics"))
	if not expand.is_empty():check(await UI.click(self,expand[0]),"expand actual basic menu")
	var choices:Array=UI.descendants(menu).filter(func(n):return n is Button and n.get_meta("menu_id","")==menu_id)
	check(choices.size()==1 and not choices[0].disabled,"real stock makes requested food selectable")
	if choices.is_empty() or choices[0].disabled:return
	check(await UI.click(self,choices[0]) and await UI.click(self,menu.start_button),"actual choose and start cooking")
	var stock_before:Dictionary=w.storage.saved().duplicate(true)
	var before:float=w.hearts.mood("codex").joy
	var serial:int=w.director.serial;var speech:Array=[]
	for frame in range(900):
		w.advance(.1)
		for event in w.director.events:
			if int(event.serial)<=serial:continue
			serial=event.serial
			if event.actor_id=="codex" and str(event.context).begins_with("fireside_"):speech.append(event.text)
		if fire.circle_closed:break
	check("codex" in fire.state.current.get("eaters",[]),"invited resident really completes meal")
	check(w.hunger.rank("codex")==0,"actual meal still fills hunger")
	if menu_id=="single:mushroom":check(w.storage.saved()==stock_before,"free staple never consumes food stock")
	else:
		check(w.storage.saved()==stock_before,"cooked receipt commits once at real start, no later inventory changes")
	if menu_id=="single:mushroom":check(fire.dialogue.mushroom_count("codex")==number,"actual repeated mushroom count "+str(number))
	var kind:String="mushroom" if menu_id=="single:mushroom" else "favorite" if menu_id=="single:blueberry" else "ordinary"
	var expected:String=fire.dialogue.taste_line("codex",kind,number,"zh")
	check(expected in speech,"true first-chew taste reaches original speech gate: "+expected)
	records.append({"menu":menu_id,"number":number,"speech":speech,"expected_zh":expected,"example_en":fire.dialogue.taste_line("codex",kind,number,"en"),"joy_before":before,"joy_after":w.hearts.mood("codex").joy,"count":fire.dialogue.mushroom_count("codex"),"memories":w.memories.records.duplicate(true)})
	close_windows();await process_frame
