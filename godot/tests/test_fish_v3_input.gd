extends "res://tests/test_dialogue_bar_input.gd"
var game:Node
func step(seconds:float)->void:
	for tick in range(ceili(seconds/.1)):game._process(.1);game.view._process(.1)
	await frames(2)
func mouse(at:Vector2)->void:
	if DisplayServer.get_name()!="headless":root.warp_mouse(at)
	var motion:=InputEventMouseMotion.new();motion.position=at;motion.global_position=at;root.push_input(motion,true);await process_frame
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0;event.position=at;event.global_position=at;root.push_input(event,true);await process_frame
	await frames(2)
func matching(node:Node,key:String)->Array:
	var label:String=preload("res://scripts/localization.gd").text(key)
	return UI.descendants(node).filter(func(n):return n is Button and n.text==label)
func go_shore()->bool:
	var shores:Array=game.world.fishing.nearby_shores("human",32)
	if shores.is_empty():return false
	for shore in shores:
		var at:=Vector2(shore.position[0],shore.position[1]);game.view.center=at;game.view.follow_player=false
		await mouse(game.view.screen(at));await step(90)
		if not game.world.fishing.shore("human").is_empty():return true
	return false
func seed_for(species:String)->int:
	# Choose a seed for the original random roll. No fish or gameplay values are edited.
	var low:=1;var high:=0
	for entry in game.world.fishing.rules.species:
		high+=int(entry.weight)
		if entry.id==species:break
		low=high+1
	var probe:=RandomNumberGenerator.new()
	for seed_value in range(100000):
		probe.seed=seed_value
		var roll:int=probe.randi_range(1,100)
		if roll>=low and roll<=high:return seed_value
	return -1
func catch_from_ui(species:String)->Dictionary:
	check(await UI.click(self,game.actions_button),"real actions open")
	var options:Array=matching(game.action_dock.menu,"activities.fish")
	if options.is_empty():check(false,"fish action reachable");return {}
	check(await UI.click(self,options[0]),"mouse starts invitation")
	check(await UI.click(self,game.action_dock.popup.get_ok_button()),"mouse human-only fishing confirmation")
	if game.world.work.jobs.get("human",{}).get("intent")!="fish":check(false,"real fishing job accepted");return {}
	var before:Array=game.world.fishing.fish.keys()
	var picked:int=seed_for(species);check(picked>=0,"target species deterministic seed")
	game.world.fishing.rng.seed=picked
	for tick in range(1200):
		game._process(.1);game.view._process(.1)
		if not game.world.work.jobs.has("human"):break
	await frames(2)
	var caught:Array=game.world.fishing.fish.values().filter(func(f):return f.owner_id=="human" and f.id not in before)
	check(caught.size()==1 and caught[0].species_id==species,"one real committed catch "+species)
	return caught[0] if caught.size()==1 else {}
func open_pen(pen_id:String)->bool:
	var pen:Dictionary=game.world.fishing.pens[pen_id];var at:Vector2=game.world.catalog.rectangle(pen.rect).get_center()
	game.chat.hide();game.view.follow_player=false;game.view.center=at
	await mouse(game.view.screen(at))
	return game.fishing_panel.visible
func stock_ui(fish:Dictionary,pen_id:String)->bool:
	check(await open_pen(pen_id),"mouse opens real fishery")
	var panel:Node=game.fishing_panel;var index:int=panel.fish_ids.find(fish.id)
	if index<0:return false
	await mouse(panel.fish_list.global_position+panel.fish_list.get_item_rect(index).get_center())
	check(panel.selected_fish==fish.id,"mouse binds exact caught fish")
	var accepted:bool=await UI.click(self,panel.stock_button)
	var close:Array=matching(panel,"activities.close")
	if not close.is_empty():await UI.click(self,close[0])
	return accepted and game.world.fishing.fish[fish.id].location==pen_id
func hud_settled()->void:
	# Main simulation acceleration does not advance child Controls' real process timers.
	var until:int=Time.get_ticks_msec()+650
	while Time.get_ticks_msec()<until:await process_frame
func fish_diagnostics(entries:Array)->void:
	var evidence:String=OS.get_environment("HABITAT_UI_EVIDENCE")
	var rows:Array=[]
	for entry in entries:
		for frame in range(4):
			var texture:Texture2D=game.view.fishing_renderer.texture(entry.species_id,entry.color_id,game.world.fishing.rules,frame,"pen")
			var image:Image=texture.get_image();var used:Rect2i=image.get_used_rect()
			rows.append({"id":entry.id,"species":entry.species_id,"scale":entry.scale,"frame":frame,"texture_size":[texture.get_width(),texture.get_height()],"used_rect":[used.position.x,used.position.y,used.size.x,used.size.y]})
			if not evidence.is_empty():image.save_png(evidence.path_join(entry.species_id+"-pen-"+str(frame)+".png"))
	print("FISH_FRAME_DIAGNOSTICS ",JSON.stringify(rows))
	if not evidence.is_empty():
		var file:=FileAccess.open(evidence.path_join("fish-frame-diagnostics.json"),FileAccess.WRITE);file.store_string(JSON.stringify(rows,"  "));file.close()
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-"))
	OS.set_environment("HABITAT_OPENING","showcase");root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	game=load("res://scenes/main_v3.tscn").instantiate();game.dialogue_adapter_factory=func(_id,_scope):return preload("res://tests/test_intent_input.gd").IntentFake.new()
	root.add_child(game);game.save_enabled=false;game.set_process(false);game.view.set_process(false);await frames(3)
	var w:RefCounted=game.world
	check(w.fishing.rules.species.size()==23 and w.journal.config.species.size()==23,"23 species in rules and journal")
	check(await UI.click(self,game.actions_button),"mouse actions to journal")
	var books:Array=matching(game.action_dock.menu,"activities.fish_journal")
	check(not books.is_empty() and await UI.click(self,books[0]),"mouse opens fish journal")
	check(game.journal_panel.visible and game.journal_panel.progress_labels.size()==23,"23 actual journal controls")
	await capture("fish-journal-old")
	var scroll:ScrollContainer=game.journal_panel.species_list.get_parent();scroll.ensure_control_visible(game.journal_panel.progress_labels.clownfish);await frames(2)
	check(await UI.click(self,game.journal_panel.progress_labels.clownfish),"mouse new clownfish page")
	await capture("fish-journal-new")
	var closes:Array=matching(game.journal_panel,"activities.book_close")
	if not closes.is_empty():await UI.click(self,closes[0])
	check(await go_shore(),"real mouse route to valid coast")
	var old:Dictionary=await catch_from_ui("bean")
	if old.is_empty():quit(1);return
	var pen_id:String=w.fishing.pens.keys()[0]
	check(await stock_ui(old,pen_id),"real old catch stocked")
	check(await go_shore(),"mouse returns to coast")
	var fresh:Dictionary=await catch_from_ui("clownfish")
	if fresh.is_empty():quit(1);return
	check(await stock_ui(fresh,pen_id),"real new catch stocked")
	game.view.center=w.catalog.rectangle(w.fishing.pens[pen_id].rect).get_center();game.view.follow_player=false;game.view.queue_redraw();await hud_settled();fish_diagnostics([old,fresh]);await capture("fish-old-new-swimming")
	check(w.fishing.residents_fish(pen_id).any(func(f):return f.id==old.id) and w.fishing.residents_fish(pen_id).any(func(f):return f.id==fresh.id),"old and new unique fish coexist")
	check(await go_shore(),"mouse coast for second new fish")
	var dinner:Dictionary=await catch_from_ui("clownfish")
	if dinner.is_empty():quit(1);return
	game.chat.hide();game.view.center=w.point(w.life.station);game.view.follow_player=false
	await mouse(game.view.screen(w.point(w.life.station)));await step(90)
	var panel:Node=UI.shown(game,"res://scripts/fireside_panel.gd");check(panel!=null,"mouse routed to camp panel")
	if panel==null:quit(1);return
	check(await UI.click(self,panel.light_button),"real paid fire lighting")
	check(await UI.click(self,panel.roast_button),"real barbecue invitation")
	var invite:Node=UI.shown(game,"res://scripts/fireside_invitation.gd")
	if invite==null:check(false,"invite exists");quit(1);return
	for id in invite.checks:
		if not invite.checks[id].disabled and w.life.fireside.can_invite([id]).get("ok",false):
			check(await UI.click(self,invite.checks[id]),"mouse selects one eligible real diner");break
	check(await UI.click(self,invite.get_ok_button()),"host confirms dinner")
	var menu:Node=UI.shown(game,"res://scripts/fireside_menu.gd")
	if menu==null:check(false,"menu exists");quit(1);return
	var choices:Array=UI.descendants(menu).filter(func(n):return n is Button and n.get_meta("menu_id","")=="recipe:clownfish-skewer")
	check(choices.size()==1 and await UI.click(self,choices[0]),"mouse selects real new species dish")
	var cook_seconds:float=float(menu.choices[menu.selected].seconds)
	check(await UI.click(self,menu.start_button),"mouse confirms new dish")
	check(not w.fishing.fish.has(dinner.id) and w.life.fireside.state.current.get("fish",{}).get("id")==dinner.id,"only second new fish transfers into dish")
	check(w.fishing.fish.has(fresh.id),"stocked new fish preserved")
	await step(cook_seconds+.5);await hud_settled();await capture("fish-new-dish")
	check(w.life.fireside.state.current.get("ready",false),"new species dish genuinely cooked")
	print("FISH_V3_INPUT ",checks," failed=",failed);game.queue_free();await frames();quit(1 if failed else 0)
