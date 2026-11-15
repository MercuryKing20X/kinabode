extends RefCounted
## Native input and committed physical facts, shared by the soak and viewport checks.
var owner:WeakRef
var t:SceneTree:
	get:return owner.get_ref()
var game:Node:
	get:return t.game
var w:RefCounted:
	get:return game.world
func _init(tree:SceneTree)->void:owner=weakref(tree)
func mouse(at:Vector2,button:int=MOUSE_BUTTON_LEFT)->void:
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.position=at;event.global_position=at;event.button_index=button;event.pressed=down;t.root.push_input(event,true);await t.process_frame
func advance(seconds:float)->void:
	for tick in ceili(seconds/.25):
		game._process(.25)
		if tick%80==0:await t.process_frame
func settle()->void:
	for tick in 2400:
		game._process(.25)
		if not w.work.jobs.has('human') and not w._routes.has('human'):break
		if tick%80==0:await t.process_frame
func world_click(point:Vector2,lift:float=0)->void:
	game.chat.hide();game.brain_panel.hide();game.view.follow_player=false;game.view.center=point;game.view.zoom=1
	await t.process_frame;await mouse(game.view.screen(point)-Vector2(0,lift))
func matching(node:Node,key:String)->Array:
	var label:String=preload('res://scripts/localization.gd').text(key)
	return t.UI.descendants(node).filter(func(n):return n is Button and n.text==label)
func build_camp()->bool:
	var site:Dictionary=w.leisure.sites['play.standard.camp']
	await world_click(w.point(site));await t.process_frame
	if not game.leisure_panel.visible:return false
	var buttons:Array=matching(game.leisure_panel,'panels.choose_builder_build')
	if buttons.is_empty() or not await t.UI.click(t,buttons[0]):return false
	for who in game.participant_picker.toggles:
		var box:CheckBox=game.participant_picker.toggles[who]
		if box.button_pressed!=(who=='human') and not await t.UI.click(t,box):return false
	if not await t.UI.click(t,game.participant_picker.get_ok_button()):return false
	await settle();game.leisure_panel.hide()
	return site.complete
func fish()->Dictionary:
	for shore in w.fishing.nearby_shores('human',32):
		await world_click(Vector2(shore.position[0],shore.position[1]));await settle()
		if not w.fishing.shore('human').is_empty():break
	if w.fishing.shore('human').is_empty():return {}
	if not await t.UI.click(t,game.actions_button):return {}
	var buttons:Array=matching(game.action_dock.menu,'activities.fish')
	if buttons.is_empty() or not await t.UI.click(t,buttons[0]):return {}
	if not await t.UI.click(t,game.action_dock.popup.get_ok_button()):return {}
	var before:Array=w.fishing.fish.keys();await settle()
	var caught:Array=w.fishing.fish.values().filter(func(f):return f.owner_id=='human' and f.id not in before)
	return caught[0] if caught.size()==1 else {}
func chop()->Dictionary:
	var trees:Array=w.objects.values().filter(func(o):return o.kind=='tree' and o.status=='mature')
	trees.sort_custom(func(a,b):return w.point(a).distance_squared_to(w.point(w.actors.human))<w.point(b).distance_squared_to(w.point(w.actors.human)))
	var selected:Dictionary={}
	for tree in trees:
		game.view.center=w.point(tree);game.view.follow_player=false;await t.process_frame
		for lift in [40,80,120,160,200]:
			var at:Vector2=game.view.screen(w.point(tree))-Vector2(0,lift)
			if game.view.hit(at)!=tree.id:continue
			await mouse(at);selected=tree;break
		if not selected.is_empty():break
	return selected
func run()->Dictionary:
	var selected:Dictionary=await chop()
	t.check(not selected.is_empty() and w.work.jobs.get('human',{}).get('intent')=='chop','native tree click starts original human chop')
	await settle();await advance(35)
	t.check(not selected.is_empty() and selected.status=='stump','human tree really falls')
	# Gather the actual configured construction and ignition costs before carrying a fish.
	for extra_tree in 3:
		if w.storage.count('wood')>=w.leisure.cost(w.leisure.sites['play.standard.camp'])+int(w.life.fireside.config.wood):break
		await chop();await settle()
	var built:bool=await build_camp();t.check(built,'native builder picker completes real paid standard camp')
	await advance(35)
	var caught:Dictionary=await fish();t.check(not caught.is_empty(),'native fishing input commits one real human catch')
	await advance(45)
	var replies:Dictionary={};var receipts:Array=[]
	for id in w.director.brains:
		var actual:Array=w.director.brains[id].interactions.receipts.filter(func(row):return row.event=='host_reply' and row.scene in ['host_tree','host_built','host_fish','host_big_fish','host_rare_fish'])
		replies[id]=actual.size();receipts.append_array(actual)
		t.check(not actual.is_empty(),'resident responds to actual human chop/catch/build '+id)
	for scene in ['host_tree','host_built']:
		t.check(receipts.any(func(row):return row.scene==scene),'real input has a delivered '+scene+' reply')
	t.check(receipts.any(func(row):return row.scene in ['host_fish','host_big_fish','host_rare_fish']),'real catch has a delivered fish reply')
	for row in receipts:t.check(not str(row.proof).is_empty() and not row.reasons.is_empty(),'committed reply has proof and reason')
	if t.has_method('capture_committed_mind'):await t.capture_committed_mind('codex')
	# Original direct grill: the exact caught fish, four explicit guests, no synthetic food.
	var fed:=false
	if built and not caught.is_empty():
		var fire:RefCounted=w.life.fireside
		var helper=preload('res://tests/barbecue_fixture.gd')
		if helper.approach(w):
			var cooked:Dictionary=fire.direct_grill(caught.id)
			print("REAL_MEAL_COOK ",cooked," station=",w.life.station.id," clock=",w.director.time," wood=",w.storage.count("wood"))
			if cooked.ok:
				var guests:Array=w.director.brains.keys()
				var invitation:Dictionary=fire.invite_direct(guests)
				print("REAL_MEAL_INVITE ",invitation)
				if invitation.ok:
					for tick in 1200:
						game._process(.25)
						if guests.all(func(id):return w.hunger.rank(id)==0):fed=true;break
						if tick%80==0:await t.process_frame
		if fed:fire.end_circle('explicit test host leaves the finished meal')
	print('REAL_MEAL_FINAL ',fire_snapshot(), ' elapsed=',w.director.time)
	t.check(fed,'all four become full by eating the one real caught fish')
	var telemetry:=preload('res://scripts/brain_report.gd').new()
	for tick in 1440:w.advance(.25);telemetry.sample(w,.25)
	var full:Dictionary=telemetry.finish(w,t.evidence.path_join('full-after-real-meal'))
	for id in full.actors:
		var ranks:Dictionary=full.actors[id].ranks
		t.check(ranks.has('0') and float(ranks['0'].seconds)>60,'nonvacuous full interval '+id)
		if ranks.has('0'):t.check(float(ranks['0'].food)/float(ranks['0'].seconds)<=.1,'full food time <=10% '+id)
		var brain:RefCounted=w.director.brains[id]
		t.check(not brain.candidates().slice(0,3).any(func(c):return c.action=='food'),'full food not in top three '+id)
	return {'replies':replies,'receipts':receipts,'fish':caught,'built':built,'fed':fed,'clock':w.forest.clock}

func fire_snapshot()->Dictionary:return {"state":w.life.fireside.state,"hunger":w.hunger.states,"jobs":w.work.jobs,"wood":w.storage.count("wood"),"forest_clock":w.forest.clock,"days":w.days.day()}
