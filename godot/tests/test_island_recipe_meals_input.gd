extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
var failed:=false
func check(ok:bool,msg:String)->void:
	if not ok:failed=true;push_error(msg)
func _initialize()->void:call_deferred("run")
func mouse(at:Vector2)->void:
	for down in [true,false]:
		var e:=InputEventMouseButton.new();e.position=at;e.global_position=at;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;e.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0;root.push_input(e,true);await process_frame
func click(button:BaseButton)->bool:
	for i in range(2):await process_frame
	return await UI.click(self,button)
func run()->void:
	DirAccess.make_dir_recursive_absolute("/tmp/youqi-recipe-capture")
	if OS.get_environment("HABITAT_RECIPE_BOOK_ONLY")=="1":
		await run_case("dark-truffle-soup","npc.nora",true);print("RECIPE_BOOK failed=",failed);quit(1 if failed else 0);return
	if OS.get_environment("HABITAT_RECIPE_SIGNATURE_ONLY")=="1":
		for entry in [["honey-berry-apple","codex"],["sea-land-skewers","companion-2"],["harvest-stew","npc.mira"],["dark-truffle-soup","npc.nora"]]:await run_case(entry[0],entry[1],true)
		print("RECIPE_SIGNATURE failed=",failed);quit(1 if failed else 0);return
	for entry in [["honey-berry-apple","codex",true],["sea-land-skewers","companion-2",true],["harvest-stew","npc.mira",true],["dark-truffle-soup","npc.nora",true],["dark-truffle-soup","codex",false],["moon-clam-chowder","codex",false],["crab-corn-pot","codex",false],["glow-corn","codex",false],["star-moon-dessert","codex",false]]:
		await run_case(entry[0],entry[1],entry[2])
	print("RECIPE_CASES failed=",failed);quit(1 if failed else 0)
func run_case(recipe_id:String,guest:String,signature:bool)->void:
	var dir:String=OS.get_environment("HABITAT_DATA_DIR");assert(dir.contains("youqi-test-"));OS.set_environment("HABITAT_OPENING","legacy")
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO;DisplayServer.window_move_to_foreground()
	var w:=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");w.residents.provision(w);w.library=preload("res://scripts/character_library.gd").new();w.library.configure(dir);assert(preload("res://scripts/world_opening.gd").apply(w,w.library,"showcase").ok);w.intelligence.activate_presets();w.hunger.start()
	w.world_id="recipe-fixture-"+recipe_id
	if recipe_id=="dark-truffle-soup":w.barbecue_tastes.known=false # Legacy taste history stays unknown; this new recipe cannot have been eaten before expansion.
	# Explicit isolated stock/unique fish fixture; never a claim of gathered materials.
	var costs:Dictionary=w.recipes.recipe_catalog[recipe_id].ingredients
	var stock_before:Dictionary={}
	var portraits:Array=["ai-gpt","ai-deepseek","ai-claude","ai-glm"]
	var residents:Array=["codex","companion-2","npc.mira","npc.nora"]
	for n in range(4):w.actors[residents[n]].appearance_id=portraits[n]
	if w.recipes.recipe_catalog[recipe_id].fish:
		w.fishing.add_fish({"id":"fish-000000000000000000000000","owner_id":"human","location":"pending","source_id":"home.sea.east","species_id":"eel","size_id":"person","color_id":"cream","scale":1})

	for id in w.director.routines:w.director.routines[id].rng.seed=hash("speech-input:"+str(id))
	var g:Node=load("res://scenes/main_v3.tscn").instantiate();g.world=w;g.dialogue_adapter_factory=func(_id,_scope):return preload("res://tests/test_intent_input.gd").IntentFake.new()
	root.add_child(g);g.save_enabled=false;g.set_process(false);g.view.set_process(false);g.island_hud.set_process(false);g.chat.hide();print("speech input init");await process_frame;await process_frame
	if recipe_id=="dark-truffle-soup":await book_capture(g,recipe_id,"unknown",false)
	for ingredient in costs:w.storage.add({ingredient:20})
	w.storage.add({"wood":20})
	for ingredient in costs:stock_before[ingredient]=w.storage.count(ingredient)
	if recipe_id=="dark-truffle-soup":
		# Explicit retained-discovery fixture; gather input is covered by the ingredient suite.
		for ingredient in costs:
			if ingredient not in w.ingredients.discovered:w.ingredients.discovered.append(ingredient)
		await book_capture(g,recipe_id,"known",true)
	g.view.center=w.point(w.life.station);g.view.follow_player=false;g.view.zoom=1
	await mouse(g.view.screen(w.point(w.life.station)))
	for i in range(5000):
		g._process(.05);g.view._process(.05)
		if UI.shown(g,"res://scripts/fireside_panel.gd")!=null:break
	print("speech input walked");var panel:Node=UI.shown(g,"res://scripts/fireside_panel.gd");check(panel!=null,"mouse fire route opens panel")
	if panel==null:quit(1);return
	check(await click(panel.light_button),"mouse lights real fire");check(await click(panel.roast_button),"mouse barbecue")
	print("speech input opened invitation");var invite:Node=UI.shown(g,"res://scripts/fireside_invitation.gd");check(invite!=null,"invitation opens")
	if invite==null:quit(1);return
	check(await click(invite.checks[guest]) and await click(invite.get_ok_button()),"mouse invites bound guest")
	print("speech input opened menu");var menu:Node=UI.shown(g,"res://scripts/fireside_menu.gd");check(menu!=null,"menu opens")
	if menu==null:quit(1);return
	var recipe_index:int=menu.choices.find_custom(func(d):return d.id=="recipe:"+recipe_id)
	check(recipe_index>=0,"recipe present")
	if recipe_index<0:g.queue_free();return
	var choose:Button=UI.descendants(menu).filter(func(n):return n is Button and n.get_meta("menu_id","")=="recipe:"+recipe_id)[0]
	menu.scroll.ensure_control_visible(choose);await process_frame;await process_frame
	check(await click(choose) and await click(menu.start_button),"native recipe select/start")
	var signature_seen:bool=not signature
	var exclusive:String=str(w.recipes.metadata.get(recipe_id,{}).get("signature_line",""))
	for tick in range(6000):
		g._process(.05);g.view._process(.05)
		if signature and str(g.view.speech_by_actor.get(guest,{}).get("text",""))==exclusive and not signature_seen:
			signature_seen=true;g.view.queue_redraw();await process_frame;await process_frame;RenderingServer.force_draw(false)
			if DisplayServer.get_name()!="headless":root.get_texture().get_image().save_png("/tmp/youqi-recipe-capture/"+recipe_id+"-signature-line.png")
		if guest in w.life.fireside.state.get("current",{}).get("eaters",[]) and signature_seen:break
	check(signature_seen,"exclusive signature text genuinely delivered")
	check(guest in w.life.fireside.state.get("current",{}).get("eaters",[]),"bound guest actually finished")
	check(recipe_id in w.barbecue_tastes.get("cooked",[]),"real cooked-ready discovery committed")
	for ingredient in costs:check(w.storage.count(ingredient)==int(stock_before[ingredient])-int(costs[ingredient]),"actual warehouse debit "+ingredient)
	var entries:Array=w.memories.records.filter(func(r):return r.kind=="signature_taste" and r.facts.recipe_id==recipe_id)
	check(entries.size()==(1 if signature else 0),"signature ownership memory exclusive")
	if signature:
		check(w.read_memories("human",{"kind":"signature_taste"}).total==1,"human truly witnessed signature in Our Days")
		var saved_memories:Dictionary=w.memories.saved()
		var old_preset:String=w.intelligence.preset_id(guest)
		check(w.intelligence.assign(guest,"resident-black" if old_preset!="resident-black" else "resident-white"),"isolated intelligence switch")
		check(w.memories.valid_saved(saved_memories,w.actors,w.world_id),"earned signature remains valid after intelligence change")
		w.memories.restore(saved_memories)
		check(w.read_memories("human",{"kind":"signature_taste"}).total==1,"reloaded retained witnessed signature remains readable")
		w.intelligence.assign(guest,old_preset)
	if recipe_id=="dark-truffle-soup":await book_capture(g,recipe_id,"cooked",true)
	await process_frame;await process_frame;RenderingServer.force_draw(false)
	if DisplayServer.get_name()!="headless":root.get_texture().get_image().save_png("/tmp/youqi-recipe-capture/"+recipe_id+"-"+guest+".png")
	g.queue_free();await process_frame

func key(code:int,viewport:Viewport)->void:
	for down in [true,false]:
		var event:=InputEventKey.new();event.keycode=code;event.pressed=down;viewport.push_input(event,true);await process_frame
func book_capture(g:Node,recipe_id:String,state:String,known:bool)->void:
	check(await click(g.handbook_menu),"native handbook opens")
	var popup:PopupMenu=g.handbook_menu.get_popup()
	var index:int=-1
	for i in range(popup.item_count):
		if popup.get_item_metadata(i)=="recipes":index=i
	check(index>=0,"cookbook entry exists")
	await mouse(Vector2(popup.position)+Vector2(popup.size.x*.5,(index+.5)*float(popup.size.y)/float(popup.item_count)))
	await process_frame;await process_frame
	var book:Node=UI.shown(g,"res://scripts/recipe_book.gd")
	check(book!=null,"native cookbook opens")
	if book==null:return
	var named:Array=UI.descendants(book).filter(func(n):return n is Label and str(n.text).begins_with(g.world.recipes.recipe_catalog[recipe_id].name))
	check((not named.is_empty())==known,"cookbook visibility "+state)
	if state=="cooked" and not named.is_empty():check("做过" in named[0].text,"cookbook actual cooked status")
	RenderingServer.force_draw(false)
	if DisplayServer.get_name()!="headless":root.get_texture().get_image().save_png("/tmp/youqi-recipe-capture/book-"+state+".png")
	check(await click(book.get_ok_button()),"native book close")
