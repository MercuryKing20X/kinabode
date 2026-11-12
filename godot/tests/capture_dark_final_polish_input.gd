extends "res://tests/capture_dark_island_input.gd"
## Narrow final checks: camera-only meal framing, ai-gpt torch run, and actual-time hungry boat refusal.
func run()->void:
	directory=OS.get_environment("HABITAT_DATA_DIR");assert(directory.contains("youqi-test-"));output=OS.get_environment("HABITAT_DARK_EVIDENCE");mode="showcase"
	OS.set_environment("HABITAT_OPENING","legacy");root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	game=load("res://scenes/main_v3.tscn").instantiate();game.world=World.new("res://content/home-v3/world.json");root.add_child(game);game.set_process(false);game.view.set_process(false);await process_frame;await process_frame;tick(.1)
	await wardrobe();check(await human_outfit(),"explicit mouse human safety confirmations install ai-gpt before trip")
	if not await voyage(true):finish({});return
	var w:RefCounted=game.world;var d:RefCounted=w.dark
	check(d.party.size()==4 and w.actors.values().all(func(a):return a.region_id=="dark"),"actual voyage retained every chosen companion through local work transitions")
	await camp_meal()
	if OS.get_environment("DARK_POLISH_MEAL_ONLY")=="1":finish({"scope":"meal after exact owned-local-job route acceptance; prior60frame torch proof retained"});return
	await dark_action(d.p(d.config.camp),"dark.barbecue","点火把")
	await walk(Vector2(48,98))
	check(await world_click(Vector2(105,98)),"real distant ground click for nondefault torch run")
	await tap(KEY_SPACE)
	check(game.view.follow_player,"real return-to-me Space input follows actual running human")
	var trace:Array=[];var anchors:Dictionary={}
	for index in range(60):
		tick(.05)
		var actor:Dictionary=w.actors.human;var moving:Dictionary=w.motion_state("human")
		var id:String=game.library.visual_appearance(actor);var table:Dictionary=game.view.dark_renderer.hands.get("works",{}).get(id,{})
		var row:int=["down","left","right","up"].find(actor.facing);var col:int=game.view.motion.run_column("human",w.intelligence.gait("human"))
		var hand:Array=table.get("run",[[],[],[],[]])[row][col] if table.has("run") and row>=0 else []
		anchors[JSON.stringify(hand)]=true
		trace.append({"index":index,"seconds":(index+1)*.05,"position":actor.position.duplicate(),"appearance":id,"running":w.is_running("human"),"moving":moving.get("moving",false),"facing":actor.facing,"run_atlas":not game.view.action_atlases.spec("run",game.library,actor).is_empty(),"column":col,"torch_held":d.torch.remaining>0 and not d.torch.planted,"hand_pixel":hand.duplicate(),"torch_seconds":d.torch.remaining})
		await shot("ai-gpt-torch-side-run-%02d"%index)
	check(trace.all(func(r):return r.appearance=="ai-gpt" and r.running and r.moving and r.facing=="right" and r.run_atlas and r.torch_held and r.hand_pixel.size()==2),"all60 real3second frames use ai-gpt independent side run and bound held torch")
	check(anchors.size()>=3,"running torch follows changing authored hand anchors")
	var file:=FileAccess.open(output.path_join("nondefault-torch-run-trace.json"),FileAccess.WRITE);file.store_string(JSON.stringify(trace,"  "));file.close()
	await wait_job()
	if OS.get_environment("DARK_POLISH_FOCUSED")=="1":
		check(game.links.values().all(func(link):return link._pid<=0),"focused final-polish zero model processes")
		finish({"run_frames":trace.size(),"unique_hand_anchors":anchors.size(),"hungry_proof":"prior mouse-final-polish129checks actual1800sec pass retained"});return
	# Wait through the actual original thresholds; never write hunger states or multipliers.
	for index in range(900):tick(2.0)
	check(d.party.all(func(id):return w.hunger.rank(id)==3),"actual1800seconds makes all selected companions very hungry under original multipliers")
	check(await voyage(false),"very hungry visitors still return with host")
	check(w.actors.values().all(func(a):return a.region_id=="home"),"no hungry companion left on dark island")
	if await world_click(d.p(d.config.home_dock),"dark.boat"):
		await press(game.dark_ui.menu,"叫伙伴一起去")
		var all_boxes:Array=UI.descendants(game.dark_ui.menu).filter(func(n):return n is CheckBox and n.text=="所有人")
		check(all_boxes.size()==1 and await UI.click(self,all_boxes[0]),"host actually attempts all-person invitation while very hungry")
		await press(game.dark_ui.menu,"选好了")
		check(game.dark_ui.selected.is_empty() and game.status.text.contains("很饿"),"all very hungry residents refuse new voyage and actual UI explains why")
		await pair("very-hungry-invitation-refusal")
	check(game.links.values().all(func(link):return link._pid<=0),"all final-polish inputs launch no model processes")
	finish({"run_frames":trace.size(),"unique_hand_anchors":anchors.size()})
func finish(details:Dictionary)->void:
	var file:=FileAccess.open(output.path_join("final-polish-input.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failed":failed,"results":results,"details":details},"  "));file.close()
	game.queue_free();await process_frame;print("Dark final-polish input: ",checks," checks failed=",failed);quit(1 if failed else 0)

func camp_meal()->void:
	var w:RefCounted=game.world;var d:RefCounted=w.dark
	if not await walk(d.p(d.config.camp)+Vector2(0,4)):return
	if not await dark_action(d.p(d.config.camp),"dark.barbecue","火边 · 生火 / 烧烤"):return
	var panel:Node=UI.shown(game,"res://scripts/fireside_panel.gd")
	if panel==null:check(false,"dark camp panel reachable");return
	check(await UI.click(self,panel.light_button),"real mouse lights dark camp")
	await wait_job();check(await UI.click(self,panel.roast_button),"real mouse opens dark meal invitation")
	var invite:Node=UI.shown(game,"res://scripts/fireside_invitation.gd")
	if invite==null:check(false,"dark meal invitation reachable");return
	check(await UI.click(self,invite.all_box) and await UI.click(self,invite.get_ok_button()),"real mouse selects all and confirms dark diners")
	var menu:Node=UI.shown(game,"res://scripts/fireside_menu.gd")
	if menu==null:check(false,"dark meal menu reachable");return
	var index:int=menu.choices.find_custom(func(c):return c.id=="single:mushroom")
	if index<0:check(false,"real mushrooms available");return
	var expand:Button=UI.descendants(menu).filter(func(n):return n is Button and n.get_meta("expand_basics",false))[0]
	check(await UI.click(self,expand),"real mouse expands basic grills")
	var choose:Button=UI.descendants(menu).filter(func(n):return n is Button and n.get_meta("menu_id","")=="single:mushroom")[0]
	menu.scroll.ensure_control_visible(choose);await process_frame;await process_frame
	check(await UI.click(self,choose) and await UI.click(self,menu.start_button),"real mouse commits actual mushroom meal")
	var captured:=false
	for i in range(2400):
		tick(.1)
		if not captured and d.life.fireside.state.current.get("eaten",0)>=1:
			captured=true;await pair("early-meal-camera-frame")
		if i==200:
			var debug:Dictionary={"fireside":d.life.fireside.state.duplicate(true),"jobs":w.work.jobs.duplicate(true),"routes":{},"local":{}}
			for id in d.party:
				debug.routes[id]={"route":w._routes.get(id,[]),"owns_follow":d.companions.owns_follow(id),"owns_local":w.director.routines[id].owns_route}
				debug.local[id]=w.director.state(id)
			var file:=FileAccess.open(output.path_join("meal-20second-diagnostic.json"),FileAccess.WRITE);file.store_string(JSON.stringify(debug,"  "));file.close()
		if d.life.fireside.state.current.get("eaten",0)>=5:break
	check(d.life.fireside.state.current.get("eaten",0)>=5,"all five physically eat at third camp")
	check(d.party.all(func(id):return w.hunger.rank(id)==0),"all real diners finish full")
	await pair("five-diners-framed")
	var hud:Rect2=game.island_hud.residents_panel.get_global_rect()
	for dimensions in [Vector2i(1280,800),Vector2i(960,640)]:
		DisplayServer.window_set_size(dimensions);root.size=dimensions;await process_frame;game.island_hud.refresh();await process_frame
		hud=game.island_hud.residents_panel.get_global_rect()
		var no_overlap:=true
		for id in d.party+["human"]:
			var actor:Dictionary=w.actors[id];var art:Dictionary=game.library.artworks[game.library.visual_appearance(actor)];var at:Vector2=game.view.screen(w.point(actor))
			var body:=Rect2(at-Vector2(art.anchor[0],art.anchor[1])*game.view.zoom,Vector2(art.width,art.height)*game.view.zoom)
			if body.intersects(hud):no_overlap=false
		check(no_overlap,"actual diner sprite bounds clear resident HUD "+str(dimensions))
		await shot("meal-no-hud-occlusion")
	root.size=Vector2i(1280,800);DisplayServer.window_set_size(root.size);await process_frame
	for i in range(2100):
		tick(.1)
		if not d.life.fireside.active() or d.life.fireside.circle_closed:break
	await tap(KEY_ESCAPE)
