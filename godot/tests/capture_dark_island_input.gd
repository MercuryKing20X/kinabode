extends SceneTree
## UI/Integration — production/evidence/2026-11-01-黑暗岛 — BLOCKING input, ADVISORY visuals.
## Player actions ONLY originate in InputEvent mouse/key events. State reads choose/check targets.
const UI=preload("res://tests/barbecue_ui_fixture.gd")
const B=preload("res://tests/backpack_fixture.gd")
const World=preload("res://scripts/world_state.gd")
var game:Node
var output:String
var directory:String
var mode:String
var failed:=false
var checks:=0
var results:Array=[]
var speech_seen:Dictionary={}
var fps_home:=0.0
func check(ok:bool,label:String)->void:
	checks+=1;results.append({"opening":mode,"check":label,"passed":ok})
	if not ok:failed=true;push_error(mode+": "+label)
func _initialize()->void:call_deferred("run")
func tick(delta:float=.1)->void:
	game._process(delta);game.view._process(delta)
	for event in game.world.director.events:
		if str(event.get("context","")).begins_with("dark_"):speech_seen[str(event.serial)]=event.duplicate(true)
func mouse(pos:Vector2,button:int=MOUSE_BUTTON_LEFT,viewport:Viewport=null)->void:
	if viewport==null:viewport=root
	var motion:=InputEventMouseMotion.new();motion.position=pos;motion.global_position=pos;viewport.push_input(motion,true)
	for down in [true,false]:
		var e:=InputEventMouseButton.new();e.position=pos;e.global_position=pos;e.button_index=button;e.pressed=down;e.button_mask=MOUSE_BUTTON_MASK_LEFT if down and button==MOUSE_BUTTON_LEFT else 0;viewport.push_input(e,true);await process_frame
func key(code:int,down:bool=true,viewport:Viewport=null)->void:
	if viewport==null:viewport=root
	var e:=InputEventKey.new();e.keycode=code;e.physical_keycode=code;e.pressed=down;Input.parse_input_event(e);viewport.push_input(e,true);await process_frame
func tap(code:int,viewport:Viewport=null)->void:await key(code,true,viewport);await key(code,false,viewport)
func camera(at:Vector2)->void:
	for axis in [0,1]:
		var distance:float=at[axis]-game.view.center[axis]
		if absf(distance)<.02:continue
		var code:int=(KEY_RIGHT if distance>0 else KEY_LEFT) if axis==0 else (KEY_DOWN if distance>0 else KEY_UP)
		await key(code,true)
		tick(absf(distance)*32*game.view.zoom/1240)
		await key(code,false)
	await process_frame
func shot(label:String)->void:
	game.island_hud.refresh();game.view.queue_redraw();await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	check(image.get_size()==root.size,"viewport dimensions "+label)
	image.save_png(output.path_join(mode+"-"+label+"-%dx%d.png"%[root.size.x,root.size.y]))
func pair(label:String)->void:
	for dimensions in [Vector2i(1280,800),Vector2i(960,640)]:
		DisplayServer.window_set_size(dimensions);root.size=dimensions;await process_frame;await shot(label)
	DisplayServer.window_set_size(Vector2i(1280,800));root.size=Vector2i(1280,800);await process_frame
func button(node:Node,text:String)->Button:
	for n in UI.descendants(node):
		if n is Button and n.text==text and n.is_visible_in_tree():return n
	return null
func press(node:Node,text:String)->bool:
	var b:Button=button(node,text)
	if b==null:check(false,"button reachable "+text);return false
	var ok:bool=await UI.click(self,b);check(ok,"mouse presses "+text);return ok
func world_click(at:Vector2,wanted:String="")->bool:
	await camera(at)
	var candidates:Array=[Vector2.ZERO,Vector2(0,-12),Vector2(0,-40),Vector2(-12,-30),Vector2(12,-30),Vector2(27,0),Vector2(-27,0),Vector2(0,27)]
	if wanted.contains("tree"):
		for y in range(-180,1,12):
			for x in range(-90,91,12):candidates.append(Vector2(x,y))
	for offset in candidates:
		var pos:Vector2=game.view.screen(at)+offset*game.view.zoom
		if game.view.hit(pos)==wanted:
			await mouse(pos);return true
	check(false,"target has hit pixels "+wanted+" actual="+game.view.hit(game.view.screen(at)))
	return false
func wait_job(limit:int=4000)->void:
	for i in range(limit):
		tick(.1)
		if not game.world._routes.has("human") and not game.world.work.jobs.has("human") and game.world.dark.pending.is_empty():break
	await process_frame;await process_frame
func walk(at:Vector2)->bool:
	if not await world_click(at):return false
	await wait_job()
	var ok:bool=game.world.point(game.world.actors.human).distance_to(at)<.3
	check(ok,"mouse route reaches "+str(at));return ok
func dark_action(at:Vector2,wanted:String,text:String)->bool:
	if text=="点一堆火 · 2 木材":
		if not await walk(at):return false
		if not await UI.click(self,game.dark_ui.fire_button):return false
		await wait_job();return true
	if not await world_click(at,wanted):return false
	if not await press(game.dark_ui.menu,text):return false
	await wait_job();return true
func wardrobe()->void:
	for id in {"codex":"ai-gpt","companion-2":"ai-deepseek","npc.mira":"ai-claude","npc.nora":"ai-glm"}:
		var works:Dictionary={"codex":"ai-gpt","companion-2":"ai-deepseek","npc.mira":"ai-claude","npc.nora":"ai-glm"}
		game.island_hud.refresh();await process_frame
		check(await UI.click(self,game.island_hud.appearance_buttons[id]),"mouse opens wardrobe "+id)
		await select_outfit(works[id])
		check(game.world.actors[id].appearance_id==works[id],"four actual AI outfits bound "+id)
func select_outfit(work_id:String)->void:
	var panel:Node=game.island_hud.wardrobe
	var label:String=game.library.artworks[work_id].name
	var matches:Array=UI.descendants(panel.grid).filter(func(n):return n is Button and n.text.begins_with(label))
	check(matches.size()==1,"outfit exists "+work_id)
	if matches.is_empty():return
	var target:Button=matches[0];var scroll:ScrollContainer=panel.grid.get_parent()
	for i in range(40):
		if scroll.get_global_rect().has_point(target.get_global_rect().get_center()):break
		await mouse(scroll.get_global_rect().get_center(),MOUSE_BUTTON_WHEEL_DOWN)
	check(await UI.click(self,target),"mouse selects "+work_id)
	await press(panel,"确定")
func popup_item(m:MenuButton,id:int)->bool:
	# A press-only menu opening preserves the popup until its actual item click.
	var opening:=InputEventMouseButton.new();opening.position=m.get_global_rect().get_center();opening.global_position=opening.position;opening.button_index=MOUSE_BUTTON_LEFT;opening.pressed=true;opening.button_mask=MOUSE_BUTTON_MASK_LEFT;root.push_input(opening,true);await process_frame
	var popup:PopupMenu=m.get_popup();var index:int=popup.get_item_index(id)
	if index<0:return false
	var at:Vector2=Vector2(popup.position)+Vector2(popup.size.x*.5,(index+.5)*popup.size.y/popup.item_count)
	await mouse(at);await process_frame
	return not popup.visible
func human_outfit()->bool:
	var settings:Array=UI.descendants(game.island_hud).filter(func(n):return n is MenuButton and n.text=="设置")
	if settings.is_empty():check(false,"settings available for explicit human outfit");return false
	await popup_item(settings[0],90)
	var dialogs:Array=UI.descendants(game).filter(func(n):return n is ConfirmationDialog and n.title=="我自己的外观" and n.visible)
	if dialogs.is_empty():check(false,"human wardrobe safety dialog via real menu input");await tap(KEY_ESCAPE);return false
	check(await UI.click(self,dialogs[0].get_ok_button()),"mouse explicitly opens human wardrobe")
	await select_outfit("ai-gpt")
	dialogs=UI.descendants(game).filter(func(n):return n is ConfirmationDialog and n.title=="更换我的外观" and n.visible)
	if dialogs.is_empty():check(false,"human final appearance confirmation");return false
	check(await UI.click(self,dialogs[0].get_ok_button()),"mouse confirms human nondefault outfit")
	var ok:bool=game.world.actors.human.appearance_id=="ai-gpt";check(ok,"human actual nondefault appearance")
	return ok
func voyage(invite:bool)->bool:
	var d:RefCounted=game.world.dark
	if not await world_click(d.p(d.config.dock if d.here() else d.config.home_dock),"dark.boat"):return false
	if invite:
		await press(game.dark_ui.menu,"叫伙伴一起去")
		var all_boxes:Array=UI.descendants(game.dark_ui.menu).filter(func(n):return n is CheckBox and n.text=="所有人")
		check(all_boxes.size()==1 and await UI.click(self,all_boxes[0]),"top all selects actual boat invitees")
		await press(game.dark_ui.menu,"选好了")
	var manifest:Dictionary={"requested":game.dark_ui.selected.duplicate(),"actors":{}}
	for id in game.world.actors:
		if id!="human":manifest.actors[id]={"region":game.world.actors[id].region_id,"job":game.world.work.jobs.get(id,{}).duplicate(true),"control":game.world.director.state(id).duplicate(true)}
	var log_file:=FileAccess.open(output.path_join(mode+"-boat-manifest-"+str(invite)+".json"),FileAccess.WRITE);log_file.store_string(JSON.stringify(manifest,"  "));log_file.close()
	await pair("boat-confirm")
	var origin:String=game.world.actors.human.region_id
	await press(game.dark_ui.menu,"回主岛" if origin=="dark" else "出发")
	await wait_job();await process_frame;await create_timer(.8).timeout;await process_frame
	check(game.world.actors.human.region_id!=origin,"actual boat fade crosses region")
	return game.world.actors.human.region_id!=origin
func chop(id:String)->bool:
	var w:RefCounted=game.world
	if not await world_click(w.point(w.objects[id]),id):return false
	check(w.work.jobs.get("human",{}).get("intent")=="chop","mouse starts real chop "+id)
	var planted:=false
	for i in range(4000):
		tick(.1)
		if w.dark.here() and w.dark.torch.planted and w.actors.human.activity=="chopping" and not planted:
			planted=true;await shot("torch-planted-chop")
		if not w.work.jobs.has("human") and not w._routes.has("human"):break
	for i in range(10):tick(.1)
	check(w.objects[id].status=="stump","mouse chop completes actual tree "+id)
	if w.dark.here():check(planted and not w.dark.torch.planted,"mouse hand work plants and automatically lifts torch")
	return w.objects[id].status=="stump"
func run()->void:
	directory=OS.get_environment("HABITAT_DATA_DIR");assert(directory.contains("youqi-test-"));output=OS.get_environment("HABITAT_DARK_EVIDENCE")
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1280,800)
	for opening in ["showcase","standard"]:
		mode=opening;speech_seen={};OS.set_environment("HABITAT_DATA_DIR",directory.path_join(opening));OS.set_environment("HABITAT_OPENING","legacy" if opening=="showcase" else "standard")
		game=load("res://scenes/main_v3.tscn").instantiate();game.world=World.new("res://content/home-v3/world.json");root.add_child(game);game.set_process(false);game.view.set_process(false)
		await process_frame;await process_frame;tick(.1)
		await wardrobe();await pair("main-default-human-four-outfits")
		fps_home=await measure_fps()
		if opening=="standard":await chop("home.tree.01");await chop("home.tree.02")
		await camera(game.world.dark.p(game.world.dark.config.home_dock));await pair("north-dock-default")
		if await voyage(true):await explore()
		check(game.links.values().all(func(link):return link._pid<=0),"zero model processes throughout mouse acceptance")
		game.queue_free();await process_frame;await process_frame
	var file:=FileAccess.open(output.path_join("acceptance-input.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failed":failed,"results":results},"  "));file.close()
	print("Dark mouse acceptance: ",checks," checks failed=",failed);quit(1 if failed else 0)
func explore()->void:
	var w:RefCounted=game.world;var d:RefCounted=w.dark
	check(w.actors.keys().filter(func(id):return id!="human").all(func(id):return w.actors[id].region_id=="dark"),"invited four companions actually arrive")
	await pair("arrival-default-human")
	var before:int=B.wood_total(w)
	await dark_action(d.p(d.config.camp),"dark.barbecue","点火把")
	check(d.torch.remaining>0 and B.wood_total(w)==before-1,"mouse first torch costs exactly one from actual boxes")
	await pair("torch-default-human")
	await walk(Vector2(49,97))
	await world_click(Vector2(69,97))
	for i in range(12):tick(.25);await shot("side-running-%02d"%i)
	await wait_job();await pair("dark-outside-camp-default")
	check(not d.permanent(w.point(w.actors.human)) and game.dark_ui.return_button.visible,"return-to-light button shown only outside permanent light")
	check(await UI.click(self,game.dark_ui.return_button),"mouse requests nearest real light")
	await wait_job();check(d.permanent(w.point(w.actors.human)),"normal World route returns to permanent light")
	await dark_action(d.p(d.config.camp),"dark.barbecue","点火把")
	var fire_a:=Vector2(44,82);var fire_b:=Vector2(44,66)
	await dark_action(fire_a,"","点一堆火 · 2 木材");check(d.fires.size()==1,"mouse first permanent fire")
	await dark_action(fire_a+Vector2(3,0),"","点一堆火 · 2 木材")
	check(d.fires.size()==1 and game.status.text.contains("够亮"),"nearby fire rejected with explanation")
	await dark_action(fire_b,"","点一堆火 · 2 木材");check(d.fires.size()==2,"mouse second permanent fire")
	await dark_action(fire_b,"dark.fire.1","点火把")
	await chop("dark.tree.00")
	var area:Dictionary=d.config.areas.filter(func(a):return a.has("beacon"))[0]
	await dark_action(d.p(area.beacon),"dark.beacon."+str(area.id),"点亮灯台 · 6 木材")
	for i in range(30):tick(.1)
	check(area.id in d.beacons,"mouse lights whole authored area")
	check(w.memories.records.any(func(e):return e.kind=="dark_beacon"),"actual beacon commit creates Our Days memory")
	await pair("lit-beacon-default-human")
	# Normal autosave followed by whole game-scene shutdown/recreation, never internal Save calls.
	for i in range(45):tick(.1)
	var state:Dictionary=d.saved();var before_restart:float=d.torch.remaining
	game.queue_free();await process_frame;await process_frame
	game=load("res://scenes/main_v3.tscn").instantiate();game.world=World.new("res://content/home-v3/world.json");root.add_child(game);game.set_process(false);game.view.set_process(false);await process_frame;await process_frame
	w=game.world;d=w.dark
	check(w.actors.human.region_id=="dark" and d.fires==state.fires and d.beacons==state.beacons,"normal scene restart loads actual dark people and lights")
	check(absf(float(d.torch.remaining)-before_restart)<.1,"restart keeps torch time without offline advancement")
	await pair("reload-dark-default-human")
	await walk(Vector2(84,79))
	var remaining:float=d.torch.remaining
	if remaining>20.1:
		for i in range(ceili((remaining-19.5)/.5)):tick(.5)
	await pair("torch-warning")
	check(d.torch.remaining>0 and d.torch.remaining<=20 and game.dark_ui.hint.visible,"actual countdown shrinks torch and displays warning")
	for i in range(45):tick(.5)
	check(d.torch.remaining==0,"mouse lit torch expires after actual countdown")
	await pair("torch-out")
	check(await UI.click(self,game.dark_ui.return_button),"mouse returns after torch expiry")
	await wait_job()
	await dark_action(d.p(area.beacon),"dark.beacon."+str(area.id),"点火把")
	if await human_outfit():await pair("dark-nondefault-human")
	await camp_meal()
	await map_screen()
	if mode=="showcase":await fire_stress()

	var retained:Dictionary={}
	for event in speech_seen.values():retained[event.actor_id]=event.text
	var f:=FileAccess.open(output.path_join(mode+"-dark-speech.json"),FileAccess.WRITE);f.store_string(JSON.stringify(speech_seen,"  "));f.close()
	check(retained.size()==4,"all four personalities delivered actual dark speech")
	if await voyage(false):
		await pair("return-main-human-current-outfit")
		var moon:Vector2=w.point(w.barbecues["moon.barbecue"].station)+Vector2(8,8)
		if await walk(moon):await pair("moon-human-current-outfit-no-fog")

	check(w.actors.values().all(func(a):return a.region_id=="home"),"every dark visitor returns together")

func measure_fps()->float:
	game.set_process(true);game.view.set_process(true)
	for i in range(24):await process_frame
	var started:int=Time.get_ticks_usec()
	for i in range(120):await process_frame
	var fps:float=120000000.0/float(Time.get_ticks_usec()-started)
	game.set_process(false);game.view.set_process(false)
	return fps
func camp_meal()->void:
	var w:RefCounted=game.world;var d:RefCounted=w.dark
	if not await walk(d.p(d.config.camp)+Vector2(0,4)):return
	if not await dark_action(d.p(d.config.camp),"dark.barbecue","火边 · 生火 / 烧烤"):return
	var panel:Node=UI.shown(game,"res://scripts/fireside_panel.gd")
	if panel==null:check(false,"dark camp barbecue panel reachable");return
	check(await UI.click(self,panel.light_button),"mouse lights third camp using real two wood")
	await wait_job()
	check(await UI.click(self,panel.roast_button),"mouse starts barbecue invitation at third camp")
	var invite:Node=UI.shown(game,"res://scripts/fireside_invitation.gd")
	if invite==null:check(false,"third camp invitation reachable");return
	check(await UI.click(self,invite.all_box),"mouse invites all at third camp")
	check(await UI.click(self,invite.get_ok_button()),"mouse confirms actual camp guests")
	var menu:Node=UI.shown(game,"res://scripts/fireside_menu.gd")
	if menu==null:check(false,"third camp menu reachable");return
	var index:int=menu.choices.find_custom(func(c):return c.id=="single:mushroom")
	if index<0:check(false,"real mushroom recipe available");return
	var choose:Button=UI.descendants(menu.cards[index]).filter(func(n):return n is Button)[0]
	for attempt in range(40):
		if menu.scroll.get_global_rect().has_point(choose.get_global_rect().get_center()):break
		await mouse(menu.scroll.get_global_rect().get_center(),MOUSE_BUTTON_WHEEL_DOWN)
	check(await UI.click(self,choose),"mouse chooses actual mushrooms")
	check(await UI.click(self,menu.start_button),"mouse commits third camp roast")
	for i in range(2400):
		tick(.1)
		if d.life.fireside.state.current.get("eaten",0)>=5:break
	check(d.life.fireside.state.current.get("eaten",0)>=5,"all five physically eat at third camp")
	check(d.party.all(func(id):return w.hunger.rank(id)==0),"actual diners become full only after finishing")
	await pair("third-camp-meal-circle")
	# Let the original bounded circle finish naturally; no hidden stop function.
	for i in range(2100):
		tick(.1)
		if not d.life.fireside.active() or d.life.fireside.circle_closed:break
	await tap(KEY_ESCAPE)
func map_screen()->void:
	var popup:PopupMenu=game.handbook_menu.get_popup();var id:=-1
	for i in range(popup.item_count):
		if popup.get_item_metadata(i)=="map":id=popup.get_item_id(i);break
	if id<0:check(false,"handbook map entry exists");return
	await popup_item(game.handbook_menu,id)
	check(game.atlas.visible,"real handbook click opens map")
	await pair("handbook-lit-map")
	await tap(KEY_ESCAPE)
func fire_stress()->void:
	var w:RefCounted=game.world;var d:RefCounted=w.dark
	# Actual hand work harvests the authored trees; never inject inventory or light IDs.
	for id in w.objects.keys():
		if str(id).begins_with("dark.tree.") and w.objects[id].status=="mature":
			if d.torch.remaining<50:
				var near:Vector2=d.nearest_light()
				if near.is_finite():await walk(near)
				await dark_action(d.p(d.config.camp),"dark.barbecue","点火把")
			await chop(id)
	var candidates:Array=[]
	for y in range(24,114,10):
		for x in range(19,145,10):
			var at:=Vector2(x,y)
			if d.fire_site(at) and not d.permanent(at):candidates.append(at)
	var attempted:=0
	for at in candidates:
		if d.fires.size()>=30:break
		if not d.fire_site(at) or d.permanent(at) or d.fires.any(func(f):return d.p(f.position).distance_to(at)<float(d.config.fire_spacing)):continue
		if int(d.life.fireside.available().get("wood",0))<2:break
		if d.torch.remaining<50:
			var lights:Array=d.light_sources();lights.sort_custom(func(a,b):return w.point(w.actors.human).distance_to(d.p(a.position))<w.point(w.actors.human).distance_to(d.p(b.position)))
			var nearest:Dictionary=lights[0]
			if nearest.position==d.config.camp:await dark_action(d.p(d.config.camp),"dark.barbecue","点火把")
			else:
				var index:int=d.fires.find_custom(func(f):return f.position==nearest.position)
				await dark_action(d.p(nearest.position),"dark.fire."+str(index),"点火把")
		attempted+=1;await dark_action(at,"","点一堆火 · 2 木材")
	check(d.fires.size()==30,"thirty permanent fires created only by real mouse actions and real wood")
	var dark_fps:float=await measure_fps()
	var perf:=FileAccess.open(output.path_join("performance-real-input.json"),FileAccess.WRITE);perf.store_string(JSON.stringify({"width":root.size.x,"height":root.size.y,"home_fps":fps_home,"dark_fps":dark_fps,"fires":d.fires.size(),"attempted":attempted,"real_mouse":true},"  "));perf.close()
	await pair("thirty-real-fires")
