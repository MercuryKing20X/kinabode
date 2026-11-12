# DIRECTION 2026-11-07: 主角鱼直接入库；以原真实实例验证后续流程。
extends SceneTree
## Integration: authentic home-coast fish -> boat -> third fire -> invitation/meal/save.
## This system fixture is not a substitute for the separately reported mouse mode.
const World=preload("res://scripts/world_state.gd")
const Library=preload("res://scripts/character_library.gd")
const Opening=preload("res://scripts/world_opening.gd")
const Save=preload("res://scripts/save_store.gd")
const Fish=preload("res://tests/fishing_fixture.gd")
const BBQ=preload("res://tests/barbecue_fixture.gd")
const B=preload("res://tests/backpack_fixture.gd")
const UI=preload("res://tests/barbecue_ui_fixture.gd")
var failed:=false
var checks:=0
var base_dir:String
var results:Array=[]
var game:Node
func check(ok:bool,label:String)->void:
	checks+=1;results.append({"check":label,"passed":ok})
	if not ok:failed=true;push_error(label)
func _initialize()->void:call_deferred("run")
func fresh(label:String,opening:String)->RefCounted:
	var w:=World.new("res://content/home-v3/world.json")
	check(w.error.is_empty(),"catalog loads "+label+": "+w.error)
	w.residents.provision(w);w.library=Library.new();w.library.configure(base_dir.path_join(label))
	check(Opening.apply(w,w.library,opening).ok,"authored opening "+opening)
	w.intelligence.activate_presets();w.hunger.start();w.director.set_all_enabled(false)
	if w.standard.active():w.standard.install_sites(w.library)
	return w
func persisted_fish_equal(actual:Dictionary,original:Dictionary)->bool:
	# SaveStore writes JSON: compare every persisted key after the same numeric encoding.
	return actual==JSON.parse_string(JSON.stringify(original))
func fish_locations(w:RefCounted,id:String)->int:
	var n:int=1 if w.fishing.fish.has(id) else 0
	for life in w.barbecues.values():
		if life.fireside.state.get("current",{}).get("fish",{}).get("id")==id:n+=1
	return n
func save_reload(w:RefCounted,label:String,opening:String,id:String)->RefCounted:
	var path:String=base_dir.path_join(label)
	check(Save.save_world(w,path),"writes isolated genuine progress "+label)
	var next:RefCounted=fresh(label+"-read",opening)
	var loaded:Dictionary=Save.load_world(next,path)
	check(loaded.get("ok",false) and loaded.get("loaded",false),"strict schema7 reload "+label+": "+str(loaded))
	check(next.actors.human.region_id=="dark" and fish_locations(next,id)==1,"same fish ID exists exactly once after reload "+label)
	check(next.work.jobs.is_empty() and next.work.claims.is_empty() and next._routes.is_empty(),"reload never resumes a route/job/seat claim "+label)
	return next
func run()->void:
	base_dir=OS.get_environment("HABITAT_DATA_DIR");assert(base_dir.contains("youqi-test-"))
	if OS.get_environment("HABITAT_DARK_GRILL_INPUT")=="1":await mouse_case()
	else:
		for opening in ["showcase","standard"]:system_case(opening)
	var output:String=OS.get_environment("HABITAT_DARK_EVIDENCE")
	if not output.is_empty():
		var f:=FileAccess.open(output.path_join("direct-grill-results.json"),FileAccess.WRITE);f.store_string(JSON.stringify({"mode":"mouse" if OS.get_environment("HABITAT_DARK_GRILL_INPUT")=="1" else "system","checks":checks,"failed":failed,"results":results},"  "))
	print("Dark direct grill: ",checks," checks failed=",failed," mode=",OS.get_environment("HABITAT_DARK_GRILL_INPUT"))
	quit(1 if failed else 0)
func system_case(opening:String)->void:
	var w:RefCounted=fresh(opening,opening)
	check(w.fishing.fish.is_empty(),opening+": starts with no counterfeit fish")
	check(Fish.coast(w,"human"),opening+": World route reaches original natural home coast")
	var fish:Dictionary=Fish.catch_one(w,"human").duplicate(true)
	check(not fish.is_empty() and fish.get("owner_id")=="human" and fish.get("location")=="storage",opening+": original fishing job commits one owned pending instance")
	if fish.is_empty():return
	var id:String=fish.id
	check(w.fishing.known_water(fish.source_id) and not str(fish.source_id).begins_with("dark"),opening+": original sea provenance retained, no new dark sea")
	check(w.work.visual_events.any(func(e):return e.kind=="fish_caught_shadow" and e.get("fish",{}).get("id")==id),opening+": real catch visual fact references same ID")
	check(fish_locations(w,id)==1 and w.fishing.fish.values().filter(func(fish):return fish.owner_id=="human" and fish.location=="storage").size()==1,opening+": one unique pending fish before voyage")
	var journal:Dictionary=w.journal.saved().duplicate(true)
	check(Fish.walk(w,"human",w.dark.config.home_arrival),opening+": carry exact fish along World route to north boat")
	check(preload("res://tests/fishing_fixture.gd").unplaced(w)==fish and w.actors.human.carry.is_empty(),opening+": route keeps fish separate from ordinary backpack")
	var wood:int=B.wood_total(w)
	var travel:Dictionary=w.dark.travel(["codex"])
	check(travel.get("ok",false),opening+": host voyage accepts genuine held fish: "+str(travel))
	if not travel.get("ok",false):return
	check(w.actors.human.region_id=="dark" and w.actors.codex.region_id=="dark",opening+": host and invited diner arrive together")
	check(preload("res://tests/fishing_fixture.gd").unplaced(w)==fish and fish_locations(w,id)==1 and B.wood_total(w)==wood,opening+": boat neither duplicates fish nor consumes materials")
	var pending_read:RefCounted=save_reload(w,opening+"-pending",opening,id)
	check(persisted_fish_equal(preload("res://tests/fishing_fixture.gd").unplaced(pending_read),fish),opening+": pending fish and provenance survive dark reload")
	check(BBQ.approach(w,"dark.barbecue"),opening+": normal World route reaches third fire while holding fish")
	var f:RefCounted=w.barbecues["dark.barbecue"].fireside
	check(not f.burning(),opening+": third barbecue starts cold independently of permanent camp light")
	var result:Dictionary=f.direct_grill(id)
	check(result.get("ok",false),opening+": actual direct grill accepted: "+str(result))
	if not result.get("ok",false):return
	check(B.wood_total(w)==wood-2 and int(w.barbecues["dark.barbecue"].station.fuel_used)==2,opening+": cold third fire consumes exactly two authentic wood")
	check(preload("res://tests/fishing_fixture.gd").unplaced(w).is_empty() and not w.fishing.fish.has(id) and fish_locations(w,id)==1 and f.state.current.fish==fish,opening+": same ID atomically moves once from pending to third meal")
	check(w.journal.saved()==journal,opening+": catch discovery is not deleted or replayed")
	var cooking_read:RefCounted=save_reload(w,opening+"-cooking",opening,id)
	var loaded_fire:RefCounted=cooking_read.barbecues["dark.barbecue"].fireside
	check(persisted_fish_equal(loaded_fire.state.current.fish,fish) and loaded_fire.state.invited.is_empty() and not loaded_fire.state.consent,opening+": reload preserves exact meal fish but clears consent/invitation")
	var paid:int=B.wood_total(w)
	check(not f.direct_grill(id).ok and B.wood_total(w)==paid and fish_locations(w,id)==1,opening+": repeat placement rejects without second debit or second fish")
	check(f.invite_direct(["codex"]).ok,opening+": host explicitly invites actual boat companion")
	for i in range(1800):
		w.advance(.05)
		if f.state.current.eaters.has("codex"):break
	check(f.state.current.ready and f.state.current.eaters==["codex"] and int(f.state.current.eaten)==1 and "human" not in f.state.current.eaters,opening+": invited companion really cooks/seats/eats; human never eats direct fish")
	check(w.hunger.rank("codex")==0 and fish_locations(w,id)==1,opening+": real eating restores satiety without recreating fish")
	var meal_read:RefCounted=save_reload(w,opening+"-eaten",opening,id)
	check(meal_read.barbecues["dark.barbecue"].fireside.state.current.eaters==["codex"],opening+": actual consumed fact survives save/reload")
func tick(delta:float=.1)->void:
	game._process(delta);game.view._process(delta)
func mouse(at:Vector2)->void:
	var motion:=InputEventMouseMotion.new();motion.position=at;motion.global_position=at;root.push_input(motion,true)
	for down in [true,false]:
		var e:=InputEventMouseButton.new();e.position=at;e.global_position=at;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;e.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0;root.push_input(e,true);await process_frame
func key(code:int,down:bool)->void:
	var e:=InputEventKey.new();e.keycode=code;e.physical_keycode=code;e.pressed=down;Input.parse_input_event(e);root.push_input(e,true);await process_frame
func camera(at:Vector2)->void:
	for axis in [0,1]:
		var distance:float=at[axis]-game.view.center[axis]
		if absf(distance)<.02:continue
		var code:int=(KEY_RIGHT if distance>0 else KEY_LEFT) if axis==0 else (KEY_DOWN if distance>0 else KEY_UP)
		await key(code,true);tick(absf(distance)*32*game.view.zoom/1240);await key(code,false)
	await process_frame
func world_mouse(at:Vector2,wanted:String="")->bool:
	await camera(at)
	for offset in [Vector2.ZERO,Vector2(0,-12),Vector2(0,-40),Vector2(-12,-30),Vector2(12,-30),Vector2(27,0),Vector2(-27,0),Vector2(0,27)]:
		var screen:Vector2=game.view.screen(at)+offset*game.view.zoom
		if game.view.hit(screen)==wanted:await mouse(screen);return true
	check(false,"real mouse target reachable "+wanted+" at="+str(at));return false
func button(node:Node,label:String)->Button:
	for n in UI.descendants(node):
		if n is Button and n.text==label and n.is_visible_in_tree():return n
	return null
func press(node:Node,label:String)->bool:
	var b:Button=button(node,label)
	if b==null:check(false,"visible mouse button "+label);return false
	var accepted:bool=await UI.click(self,b);check(accepted,"mouse presses "+label);return accepted
func wait_game()->void:
	for i in range(5000):
		tick(.1)
		if not game.world.work.jobs.has("human") and not game.world._routes.has("human") and game.world.dark.pending.is_empty():break
	await process_frame;await process_frame
func photo(label:String)->void:
	game.view.queue_redraw();game.island_hud.refresh();await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var image:Image=root.get_texture().get_image()
	check(image.get_size()==root.size,"real viewport "+label)
	image.save_png(OS.get_environment("HABITAT_DARK_EVIDENCE").path_join("direct-grill-"+label+".png"))
func mouse_case()->void:
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	OS.set_environment("HABITAT_OPENING","legacy")
	game=load("res://scenes/main_v3.tscn").instantiate();game.world=World.new("res://content/home-v3/world.json");root.add_child(game)
	game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.island_hud.set_process(false);game.chat.hide()
	await process_frame;await process_frame;tick(.1)
	var w:RefCounted=game.world
	check(w.error.is_empty() and w.opening_id=="showcase","mouse fixture uses authored showcase, no world/carry injection")
	var shore:Dictionary={}
	for candidate in w.fishing.nearby_shores("human"):
		var at:=Vector2(candidate.position[0],candidate.position[1]);await camera(at)
		if game.view.hit(game.view.screen(at)).is_empty():shore=candidate;break
	check(not shore.is_empty(),"observed natural shore has clickable ground")
	if shore.is_empty():game.queue_free();await process_frame;return
	check(await world_mouse(Vector2(shore.position[0],shore.position[1])),"mouse clicks original home coast")
	await wait_game();check(not w.fishing.shore("human").is_empty(),"mouse walk arrives at actual valid coast")
	await press(game,"动作");await press(game.action_dock.menu,"钓鱼")
	check(game.action_dock.popup.visible and await UI.click(self,game.action_dock.popup.get_ok_button()),"mouse confirms only human fishing at current shore")
	check(w.work.jobs.get("human",{}).get("intent")=="fish","actual input starts original fishing job")
	await wait_game()
	var fish:Dictionary=preload("res://tests/fishing_fixture.gd").unplaced(w).duplicate(true)
	check(not fish.is_empty(),"real mouse fishing commits unique fish")
	if fish.is_empty():game.queue_free();await process_frame;return
	var id:String=fish.id;await photo("home-real-catch")
	check(await world_mouse(w.dark.p(w.dark.config.home_dock),"dark.boat"),"mouse clicks north boat while holding same fish")
	await press(game.dark_ui.menu,"叫伙伴一起去")
	var choices:Array=UI.descendants(game.dark_ui.menu).filter(func(n):return n is CheckBox and n.text=="所有人")
	check(choices.size()==1 and await UI.click(self,choices[0]),"mouse selects boat companions")
	await press(game.dark_ui.menu,"选好了");await press(game.dark_ui.menu,"出发")
	await wait_game();await create_timer(.8).timeout;await process_frame;tick(.1)
	check(w.dark.here() and preload("res://tests/fishing_fixture.gd").unplaced(w)==fish and fish_locations(w,id)==1,"mouse voyage keeps original unique pending fish on dark arrival")
	if not w.dark.here():game.queue_free();await process_frame;return
	# Boat invitation may truthfully skip busy residents; invite an actual passenger to eat.
	var passengers:Array=w.actors.keys().filter(func(actor_id):return actor_id!="human" and w.actors[actor_id].region_id=="dark")
	check(not passengers.is_empty(),"mouse boat carries at least one actually accepted companion")
	if passengers.is_empty():game.queue_free();await process_frame;return
	var diner:String=str(passengers[0])
	await photo("dark-arrival-held-fish")
	await press(game,"直接烧烤")
	var dialogs:Array=UI.descendants(game).filter(func(n):return n is ConfirmationDialog and n.visible and n.title=="选择营火")
	check(dialogs.size()==1,"mouse fish card opens explicit fire choice")
	if dialogs.is_empty():game.queue_free();await process_frame;return
	var lists:Array=UI.descendants(dialogs[0]).filter(func(n):return n is OptionButton)
	check(lists.size()==1 and lists[0].get_item_metadata(lists[0].selected)=="dark.barbecue" and lists[0].get_item_text(lists[0].selected).contains("黑暗岛"),"nearest actual default choice identifies black island third fire")
	if lists.is_empty():game.queue_free();await process_frame;return
	var before:int=B.wood_total(w)
	check(await UI.click(self,dialogs[0].get_ok_button()),"mouse confirms third fire")
	await wait_game()
	var fire:RefCounted=w.barbecues["dark.barbecue"].fireside
	check(fire.state.get("current",{}).get("fish",{}).get("id")==id and fish_locations(w,id)==1 and not w.fishing.fish.has(id),"mouse route atomically moves same fish once into third fire")
	check(B.wood_total(w)==before-2,"mouse cold direct fish burns exactly two authentic wood from authorized box")
	var panel:Node=UI.shown(game,"res://scripts/fireside_panel.gd")
	check(panel!=null and panel.invite_button!=null,"third fire displays invitation for actual waiting fish")
	if panel==null or panel.invite_button==null:game.queue_free();await process_frame;return
	check(await UI.click(self,panel.invite_button),"mouse requests eating invitation")
	var invitation:Node=UI.shown(game,"res://scripts/fireside_invitation.gd")
	check(invitation!=null,"direct fish invitation visible")
	if invitation==null:game.queue_free();await process_frame;return
	check(await UI.click(self,invitation.checks[diner]) and await UI.click(self,invitation.get_ok_button()),"mouse explicitly invites one real boat companion")
	for i in range(1800):
		tick(.05)
		if fire.state.current.eaters.has(diner):break
	if fire.state.current.eaters!=[diner]:
		var diag:Dictionary={"fire":fire.state.duplicate(true),"jobs":w.work.jobs.duplicate(true),"own_fire_jobs":fire.jobs.duplicate(),"actors":w.actors.duplicate(true),"status":game.status.text,"diner":diner,"diner_control":w.director.state(diner),"dark_routes":w.dark.companions.owned.keys(),"routes":str(w._routes),"hunger":w.hunger.rank(diner),"chat_busy":game._resident_chat_busy(diner)}
		var df:=FileAccess.open(OS.get_environment("HABITAT_DARK_EVIDENCE").path_join("mouse-failure.json"),FileAccess.WRITE);df.store_string(JSON.stringify(diag,"  "));df.close()
	check(fire.state.current.eaters==[diner] and "human" not in fire.state.current.eaters and fish_locations(w,id)==1,"mouse companion actual eating retains one fish receipt, human never eats")
	await photo("third-fire-real-meal")
	check(game.links.values().all(func(link):return link._pid<=0),"mouse path creates no model process")
	game.queue_free();await process_frame;await process_frame
