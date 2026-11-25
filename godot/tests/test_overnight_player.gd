# DIRECTION 2026-11-07: 主角鱼直接入库；以原真实实例验证后续流程。
extends SceneTree
const ConstructionUI=preload("res://tests/standard_construction_ui_fixture.gd")
const World=preload("res://scripts/world_state.gd")
const Opening=preload("res://scripts/world_opening.gd")
const Library=preload("res://scripts/character_library.gd")
const WardrobeUI=preload("res://tests/barbecue_ui_fixture.gd")
const UI=preload("res://tests/test_camp_binding_v4.gd")
const CampPanel=preload("res://scripts/fireside_panel.gd")
const Invite=preload("res://scripts/fireside_invitation.gd")
const Menu=preload("res://scripts/fireside_menu.gd")
var game:Node
var w:RefCounted
var ui:SceneTree
var failures:=false
var checks:=0
var captures:String
var onlookers_seen:=[]
var evidence:Dictionary={}
var check_rows:Array=[]
var snapshot_rows:Array=[]
var checkpoints:Array=[]
var trace_path:String
func check(ok:bool, label:String)->void:
	checks+=1
	check_rows.append({"passed":ok,"label":label})
	if not ok:failures=true;push_error(label)
func _initialize()->void:call_deferred("run")
func _fire_diag_fields(value:Dictionary,keys:Array)->Dictionary:
	var result:Dictionary={}
	for key in keys:
		if not value.has(key):continue
		var v:Variant=value[key]
		if v is Vector2:result[key]=[v.x,v.y]
		elif typeof(v) in [TYPE_NIL,TYPE_BOOL,TYPE_INT,TYPE_FLOAT,TYPE_STRING]:result[key]=v
	return result
func _fire_diag_visible(node:Node)->bool:
	return is_instance_valid(node) and not node.is_queued_for_deletion() and (node is CanvasItem or node is Window) and bool(node.get("visible"))
func _fire_diag_snapshot(pos:Vector2,station_id:String)->Dictionary:
	var result:Dictionary={"point":[pos.x,pos.y],"station_id":station_id,"game_live":is_instance_valid(game),"world_live":is_instance_valid(w)}
	if not is_instance_valid(game) or game.is_queued_for_deletion() or not is_instance_valid(w):return result
	var view:Node=game.get("view")
	if not is_instance_valid(view) or view.is_queued_for_deletion():return result
	result["world_id"]=w.world_id;result["view_region"]=view.region_id;result["world_hit"]=view.hit(pos)
	var human:Dictionary=w.actors.get("human",{})
	result["human"]=_fire_diag_fields(human,["id","region_id","activity"])
	if human.get("position") is Array:result.human["position"]=human.position.duplicate()
	result["job"]=_fire_diag_fields(w.work.jobs.get("human",{}),["id","intent","source","target_id","phase","step","status","station_id","shared_activity_id","region_id"])
	var points:Array=[]
	for at in w._routes.get("human",[]):
		if at is Vector2:points.append([at.x,at.y])
	result["route"]={"size":points.size(),"first":points[0] if not points.is_empty() else null,"last":points[-1] if not points.is_empty() else null,"first_points":points.slice(0,32)}
	result["pending_camp"]=_fire_diag_fields(game.pending_camp,["station_id","action","target"])
	result["pending_fish"]=[]
	if is_instance_valid(w.fishing):
		for fish in w.fishing.fish.values():
			if fish.get("owner_id")=="human" and fish.get("location")=="pending":result.pending_fish.append(_fire_diag_fields(fish,["id","owner_id","location","species_id","size_id","color_id","source_id"]))
	result["speech_hits"]=[]
	var layout:Array=view.speech_layout();result["speech_layout_count"]=layout.size()
	for entry in layout:
		var box:Rect2=entry.box
		if not box.has_point(pos):continue
		var actor_id:String=str(entry.get("actor_id",""));var context:String=str(view.speech_by_actor.get(actor_id,{}).get("context",""))
		result.speech_hits.append({"actor_id":actor_id,"context":context,"need":context.begins_with("need_"),"box":[box.position.x,box.position.y,box.size.x,box.size.y]})
	var status_node:Node=game.get("status")
	if is_instance_valid(status_node) and not status_node.is_queued_for_deletion():result["status"]=str(status_node.get("text"))
	result["chat_visible"]=_fire_diag_visible(game.get("chat"))
	var hud:Node=game.get("island_hud")
	if is_instance_valid(hud) and not hud.is_queued_for_deletion():result["resident_card_visible"]=_fire_diag_visible(hud.get("resident_card"))
	result["camp_panels"]=[];result["visible_windows"]=[]
	for child in game.get_children():
		if not is_instance_valid(child) or child.is_queued_for_deletion():continue
		if child is Window and child.visible:result.visible_windows.append({"name":str(child.name),"title":child.title})
		var script:Script=child.get_script()
		if script==null or script.resource_path!="res://scripts/fireside_panel.gd":continue
		var bound:RefCounted=child.get("life");var bound_station:String=""
		if is_instance_valid(bound):bound_station=str(bound.station.get("id",""))
		result.camp_panels.append({"name":str(child.name),"visible":_fire_diag_visible(child),"station_id":bound_station})
	if w.barbecues.has(station_id) and not human.is_empty():
		var life:RefCounted=w.barbecues[station_id]
		result["human_fire_distance"]=w.point(human).distance_to(w.point(life.station)) if human.get("region_id")==life.station.region_id else null
	return result
func mouse(pos:Vector2,button:int=MOUSE_BUTTON_LEFT)->void:
	# Observe only fire-body entries; the existing input sequence is unchanged.
	var station_id:String="";var signal_owner:WeakRef
	var observed:Dictionary={"clicked":0,"need_clicked":0,"events":[]}
	var clicked_counter:Callable;var need_counter:Callable
	if is_instance_valid(game) and not game.is_queued_for_deletion() and is_instance_valid(w):
		var candidate:Node=game.get("view")
		if is_instance_valid(candidate) and not candidate.is_queued_for_deletion():
			var hit:String=candidate.hit(pos)
			if w.barbecues.has(hit):
				station_id=hit;signal_owner=weakref(candidate)
				clicked_counter=func(object_id:String,at:Vector2):observed.clicked+=1;observed.events.append({"kind":"clicked","id":object_id,"position":[at.x,at.y]})
				need_counter=func(actor_id:String,kind:String):observed.need_clicked+=1;observed.events.append({"kind":"need_clicked","actor_id":actor_id,"need":kind})
				candidate.connect("clicked",clicked_counter);candidate.connect("need_clicked",need_counter)
				print("FIRE_CLICK_OBSERVE ",JSON.stringify({"phase":"before_motion","state":_fire_diag_snapshot(pos,station_id),"signals":observed}))
	var motion:=InputEventMouseMotion.new();motion.position=pos;motion.global_position=pos;root.push_input(motion,true)
	await process_frame
	var hovered:Control=root.gui_get_hovered_control()
	var live_game:bool=is_instance_valid(game) and not game.is_queued_for_deletion()
	var diagnostic_view:Node=game.get("view") if live_game else null
	var diagnostic_hud:Node=game.get("island_hud") if live_game else null
	var diagnostic_upper:Control=diagnostic_hud.get("upper_status") if is_instance_valid(diagnostic_hud) and not diagnostic_hud.is_queued_for_deletion() else null
	print("WORLD_CLICK_DIAGNOSTIC ",{"point":pos,"world_hit":diagnostic_view.hit(pos) if is_instance_valid(diagnostic_view) and not diagnostic_view.is_queued_for_deletion() else "unavailable","hovered":str(hovered.get_path()) if is_instance_valid(hovered) else "none","upper":diagnostic_upper.get_global_rect() if is_instance_valid(diagnostic_upper) and not diagnostic_upper.is_queued_for_deletion() else Rect2()})
	if not station_id.is_empty():print("FIRE_CLICK_OBSERVE ",JSON.stringify({"phase":"before_press","state":_fire_diag_snapshot(pos,station_id),"signals":observed}))
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=button;event.pressed=pressed
		event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0;event.position=pos;event.global_position=pos
		root.push_input(event,true);await process_frame
		if not station_id.is_empty():print("FIRE_CLICK_OBSERVE ",JSON.stringify({"phase":"after_press" if pressed else "after_release","state":_fire_diag_snapshot(pos,station_id),"signals":observed}))
	if signal_owner!=null:
		var emitter:Node=signal_owner.get_ref()
		if is_instance_valid(emitter) and not emitter.is_queued_for_deletion():
			if emitter.is_connected("clicked",clicked_counter):emitter.disconnect("clicked",clicked_counter)
			if emitter.is_connected("need_clicked",need_counter):emitter.disconnect("need_clicked",need_counter)
func click_button(button:Button)->bool:
	if button==null:return false
	await WardrobeUI.reveal(self,button)
	await process_frame;await process_frame
	game.game_audio.advance(.13)
	var button_label:String=button.text
	# B: DIRECTION 2026-11-09 “底部 [对话/指令][地图][托管]”，原 primary-only 音效断言保留。
	var primary:bool=button_label.begins_with("跟随") or button_label in ["对话/指令","Chat / commands","⚡","展开","对话","聊聊","动作","集合","解散","手册","设置","直接烧烤","放入渔场","放生","稍后","全部放入渔场"]
	var parent:Node=button.get_parent()
	while parent!=null:
		if parent is AcceptDialog and parent.get_ok_button()==button:
			primary=parent.title in ["邀请谁一起吃","邀请一起钓鱼","选择参与者","跟在你身边"] or (parent.title.begins_with("一起烧烤") and parent.title.ends_with("选择伙伴"))
			break
		parent=parent.get_parent()
	# The trace is a bounded ring; counting the entire ring can hide a new
	# click when an older click is evicted. Compare this press's audio time only.
	var press_time:float=snappedf(game.game_audio.clock,.001)
	var audio_before:int=game.game_audio.trace.filter(func(e):return e.action=="scheduled" and e.event=="ui.click" and e.time==press_time).size()
	var seen:Dictionary={"count":0};button.pressed.connect(func():seen.count+=1,CONNECT_ONE_SHOT)
	var pos:Vector2=button.get_global_rect().get_center();var viewport:Viewport=button.get_viewport()
	if viewport is Window and viewport.is_embedded():pos+=Vector2(viewport.position);viewport=root
	var motion:=InputEventMouseMotion.new();motion.position=pos;motion.global_position=pos;viewport.push_input(motion,true)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
		event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0;event.position=pos;event.global_position=pos
		viewport.push_input(event,true);await process_frame
	var audio_after:int=game.game_audio.trace.filter(func(e):return e.action=="scheduled" and e.event=="ui.click" and e.time==press_time).size()
	check((audio_after>audio_before)==primary,"button click primary-only audio: "+button_label)
	return seen.count==1
func advance(delta:float=.1)->void:
	game._process(delta);game.view._process(delta)
	# The simulation may be accelerated, but accepted cue edges must pass an
	# actual engine idle so the real native player dispatch is exercised.
	if game.game_audio.active.any(func(item):return not item.get("native_started",false)):
		await process_frame

func wait_route()->bool:
	for i in range(3000):
		await advance()
		if not w._routes.has("human"):return true
	return false
func screenshot(name:String)->void:
	if captures.is_empty() or DisplayServer.get_name()=="headless":return
	game.view.queue_redraw();game.island_hud.refresh()
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var im:Image=root.get_texture().get_image()
	assert(im.get_size()==root.size);assert(im.save_png(captures.path_join(name+".png"))==OK)
	snapshot_rows.append({"file":name+".png","width":root.size.x,"height":root.size.y,"world_time":w.forest.clock,"onlookers":onlookers_seen.duplicate()})
func ready_uninvited_onlookers(life:RefCounted)->Array:
	var fire:RefCounted=life.fireside;var center:Vector2=w.point(life.station)
	var ring:=0.0
	for offset in fire.config.seat_offsets:ring=maxf(ring,Vector2(offset[0],offset[1]).length())
	var cue_config:Dictionary=game.view.hungry_onlooker.config
	var ready:Array=[]
	for id in ["codex","npc.mira","npc.nora"]:
		var actor:Dictionary=w.actors[id];var movement:Dictionary=w.motion_state(id)
		var distance:float=w.point(actor).distance_to(center)
		if actor.region_id!=life.station.region_id or w.hunger.rank(id)<2 or w.work.jobs.has(id) or w._routes.has(id):continue
		if movement.get("moving",false) or float(movement.get("still_seconds",0))<.3:continue
		if distance<ring+float(cue_config.seat_margin) or distance>float(cue_config.radius):continue
		if life.seats().any(func(seat):return w.point(actor).distance_to(w.point(seat))<float(cue_config.seat_margin)):continue
		ready.append(id)
	return ready
func prepare_uninvited_onlookers(life:RefCounted)->bool:
	# Establish the existing pose's physical precondition through real host input.
	# The far-approach check is already complete; no actor position is assigned.
	var current:Node=ui.shown_script(CampPanel)
	if current!=null:
		for pressed in [true,false]:
			var escape:=InputEventKey.new();escape.keycode=KEY_ESCAPE;escape.pressed=pressed
			root.push_input(escape,true);await process_frame
		if is_instance_valid(current) and current.visible:return false
	if not await click_button(game.gathering_button):return false
	if not game.follow_ui.all_box.button_pressed and not await click_button(game.follow_ui.all_box):return false
	if not await click_button(game.follow_ui.menu.get_ok_button()):return false
	var center:Vector2=w.point(life.station);var found:=false
	for radius in [5.5,6.5,7.5]:
		for offset in [Vector2.DOWN,Vector2.UP,Vector2.RIGHT,Vector2.LEFT]:
			var at:Vector2=center+offset*radius
			game.view.center=at;game.view.follow_player=false;game.view.peek_elapsed=0
			if not w.walkable("home",at) or not game.view.hit(game.view.screen(at)).is_empty() or w.find_route("human",at).is_empty():continue
			await mouse(game.view.screen(at))
			if not await wait_route():continue
			for tick in range(300):
				await advance()
				if tick>=10 and not ready_uninvited_onlookers(life).is_empty() and w.activities.following.keys().all(func(id):return not w._routes.has(id)):found=true;break
			if found:break
		if found:break
	if not await click_button(game.gathering_button):return false
	if game.follow_ui.all_box.button_pressed and not await click_button(game.follow_ui.all_box):return false
	if not await click_button(game.follow_ui.menu.get_ok_button()):return false
	game.view.center=center;game.view.follow_player=false;game.view.peek_elapsed=0
	await mouse(game.view.screen(center))
	if not await wait_route():return false
	await process_frame;await process_frame
	checkpoint("onlooker_precondition")
	return found and not ready_uninvited_onlookers(life).is_empty() and ui.shown_script(CampPanel)!=null

func modes()->Array:
	return ["showcase"]
func stations()->Array:return ["home.barbecue"]
func run()->void:
	var temp:String=OS.get_environment("HABITAT_DATA_DIR");assert(temp.contains("youqi-test-"))
	captures=OS.get_environment("HABITAT_MOTION_CAPTURES")
	if captures.is_empty():captures=OS.get_environment("HABITAT_OVERNIGHT_EVIDENCE")
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	for mode in modes():
		for station_id in stations():
			print("CAMP CASE ",mode," ",station_id)
			var case_dir:String=temp.path_join(mode+station_id.replace(".","-"))
			trace_path=captures.path_join("player-"+mode+"-"+station_id+"-events.jsonl") if not captures.is_empty() else temp.path_join("events.jsonl")
			OS.set_environment("HABITAT_AUDIO_TRACE",trace_path)
			if FileAccess.file_exists(trace_path):DirAccess.remove_absolute(trace_path)
			OS.set_environment("HABITAT_DATA_DIR",case_dir)
			OS.set_environment("HABITAT_OPENING","legacy" if mode=="showcase" else "standard")
			w=World.new("res://content/home-v3/world.json");w.residents.provision(w)
			w.library=Library.new();w.library.configure(case_dir)
			check(Opening.apply(w,w.library,mode).ok,"actual opening "+mode)
			w.intelligence.activate_presets();w.hunger.start()
			game=load("res://scenes/main_v3.tscn").instantiate();game.world=w;game.dialogue_adapter_factory=func(_id,_scope):return preload("res://tests/test_intent_input.gd").IntentFake.new()
			root.add_child(game)
			game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.island_hud.set_process(false)
			ui=UI.new();ui.game=game;ui.w=w
			await process_frame;await process_frame;game.chat.hide()
			await create_timer(.25).timeout
			for layout_frame in range(6):await process_frame
			# Isolate the host-led meal from independently lit local meals and
			# local harvesting. These residents can still follow, eat and show
			# hunger through their ordinary engine systems. Their adapter is fake.
			for id in w.director.routines:w.director.set_controller(id,"model")
			game._open_audio_settings();await process_frame
			check(WardrobeUI.descendants(game.audio_dialog).any(func(n):return n is Label and n.text==preload("res://scripts/localization.gd").text("ui.audio.music_ready")),"actual settings displays ready licensed music")
			check(WardrobeUI.descendants(game.audio_dialog).any(func(n):return n is Button and n.text==preload("res://scripts/localization.gd").text("ui.music.preview")),"actual settings exposes music preview and sources")
			game.audio_dialog.hide()
			var hud:Node=game.island_hud
			var voice_before:Dictionary={}
			for resident in w.director.routines:voice_before[resident]=game.game_audio.voice(w,resident)
			var assignments:Dictionary={"codex":"ai-gpt","companion-2":"ai-deepseek","npc.mira":"ai-claude","npc.nora":"ai-glm"}
			for actor_id in assignments:
				hud.refresh();await process_frame;await process_frame
				check(await WardrobeUI.click(self,hud.appearance_buttons[actor_id]),mode+" actual wardrobe button "+actor_id)
				var wardrobe:Node=hud.wardrobe;await process_frame;await process_frame
				check(wardrobe.visible and wardrobe.selected_actor==actor_id,mode+" wardrobe binds resident "+actor_id)
				var matches:Array=WardrobeUI.descendants(wardrobe.grid).filter(func(n):return n is Button and n.get_meta("work_id","")==assignments[actor_id])
				check(matches.size()==1,mode+" target appearance exists "+assignments[actor_id])
				if matches.is_empty():continue
				var target:Button=matches[0];var scroll:ScrollContainer=wardrobe.grid.get_parent()
				for attempt in range(30):
					if scroll.get_global_rect().has_point(target.get_global_rect().get_center()):break
					await mouse(scroll.get_global_rect().get_center(),MOUSE_BUTTON_WHEEL_DOWN)
				check(await WardrobeUI.click(self,target) and wardrobe.selected_work==assignments[actor_id],mode+" actual appearance selection "+actor_id)
				var confirm:Array=WardrobeUI.descendants(wardrobe).filter(func(n):return n is Button and n.text=="确定")
				check(confirm.size()==1 and await WardrobeUI.click(self,confirm[0]) and w.actors[actor_id].appearance_id==assignments[actor_id],mode+" actual confirm changes selected appearance "+actor_id)
			for resident in assignments:check(voice_before[resident]==game.game_audio.voice(w,resident),"wardrobe preserves voice of "+resident)
			if mode=="standard":
				var required:int=ConstructionUI.required_wood(w,station_id)
				for chop in range(ceili(float(maxi(0,required-w.storage.count("wood")))/float(w.forest.settings.normal_wood))+1):
					if w.storage.count("wood")>=required:break
					var trees:Array=w.objects.values().filter(func(o):return o.kind=="tree" and o.status=="mature" and not w.work.claims.has(o.id))
					trees.sort_custom(func(a,b):return w.point(a).distance_squared_to(w.point(w.actors.human))<w.point(b).distance_squared_to(w.point(w.actors.human)))
					var tree:Dictionary={};var at:=Vector2.ZERO;var tree_click:=Vector2.ZERO
					for candidate in trees:
						at=w.point(candidate);game.view.center=at;game.view.follow_player=false;game.view.zoom=1
						for lift in [40,80,120,160,200]:
							var pixel:Vector2=game.view.screen(at)-Vector2(0,lift)
							if game.view.hit(pixel)==candidate.id and ConstructionUI.unobstructed_tree_click(game.view,pixel):tree=candidate;tree_click=pixel;break
						if not tree.is_empty():break
					check(not tree.is_empty(),"a real tree has a clear mouse hit")
					if tree.is_empty():continue
					await mouse(tree_click)
					check(w.work.jobs.get("human",{}).get("intent") in ["chop","gather_wood"],"mouse starts real tree job")
					for frame in range(5000):
						await advance()
						if not w.work.jobs.has("human"):break
				var fire_at:Vector2=w.point(w.barbecues[station_id].station);game.view.center=fire_at
				await mouse(game.view.screen(fire_at))
				check(game.leisure_panel.visible,"mouse opens actual unbuilt camp")
				var builders:Array=WardrobeUI.descendants(game.leisure_panel).filter(func(n):return n is Button and n.text=="选择建造者 · 施工")
				check(builders.size()==1 and await WardrobeUI.click(self,builders[0]),"mouse opens builder selection")
				for id in game.participant_picker.toggles:
					var box:CheckBox=game.participant_picker.toggles[id]
					if box.button_pressed!=(id=="human"):check(await WardrobeUI.click(self,box),"mouse chooses only host builder")
				check(await WardrobeUI.click(self,game.participant_picker.get_ok_button()),"mouse confirms real construction")
				for frame in range(8000):
					await advance()
					if not w.work.jobs.has("human"):break
				check(w.standard.ready(station_id),"actual material delivery finishes camp without preset grants")
				game.leisure_panel.hide()
			# Advance actual elapsed time without changing hunger parameters or inventory.
			for elapsed in range(2400):
				if assignments.keys().all(func(id):return w.hunger.rank(id)>=2):break
				await advance(.5)
			check(assignments.keys().all(func(id):return w.hunger.rank(id)>=2),"real elapsed time makes companions hungry")
			var life:RefCounted=w.barbecues[station_id];var center:Vector2=w.point(life.station)
			for direction in [Vector2.UP,Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT]:
				var found:=false
				for angle in [-.6,-.3,0.0,.3,.6]:
					var p:Vector2=center+direction.rotated(angle)*4.5
					if w.walkable(life.station.region_id,p):found=true;break
				check(found,mode+" "+station_id+" four-direction walkable point")
			var ground:=Vector2.INF
			game.view.center=center;game.view.follow_player=false;game.view.zoom=1
			for i in range(32):
				var p:Vector2=center+Vector2.from_angle(TAU*i/32)*4.0
				if w.walkable("home",p) and game.view.hit(game.view.screen(p)).is_empty() and not w.find_route("human",p).is_empty():ground=p;break
			check(ground.is_finite(),mode+" "+station_id+" has clickable ground close to fire")
			if ground.is_finite():
				await mouse(game.view.screen(ground))
				if not w._routes.has("human"):print("GROUND DEBUG ",mode," ",station_id," destination=",ground," actual=",w.point(w.actors.human)," hit=",game.view.hit(game.view.screen(ground))," status=",game.status.text," cat=",w.cat.position," menus=",WardrobeUI.descendants(game).filter(func(n):return n is Window and n.visible).map(func(n):return n.title))
				check(w._routes.has("human") and await wait_route() and w.point(w.actors.human).distance_to(ground)<.01,mode+" "+station_id+" surrounding ground click walks normally")
			check(await click_button(game.gathering_button),mode+" opens actual persistent-follow picker near fire")
			check((game.follow_ui.all_box.button_pressed or await click_button(game.follow_ui.all_box)) and await click_button(game.follow_ui.menu.get_ok_button()),mode+" explicitly selects all followers")
			for tick in range(950):await advance()
			check(w.activities.following.size()==4,mode+" selected follow persists beyond old sixty-second hold")
			# Following ends close to the player, unlike the retired assembly ring.
			# Explicitly walk the selected group outside the seating circle before
			# ending follow; the unchanged later onlooker test requires that location.
			var outside:=Vector2.INF
			for offset in [Vector2(0,8.5),Vector2(0,-8.5),Vector2(8.5,0),Vector2(-8.5,0)]:
				var candidate:Vector2=center+offset
				if w.walkable("home",candidate) and w.segment_clear("home",w.point(w.actors.human),candidate):outside=candidate;break
			check(outside.is_finite(),mode+" actual follow has reachable outer-ring preparation")
			if outside.is_finite():
				game.view.center=outside;game.view.follow_player=false;await process_frame
				await mouse(game.view.screen(outside));check(await wait_route(),mode+" player really walks selected followers to outer ring")
				for tick in range(300):
					await advance()
					if w.activities.following.keys().all(func(id):return not w._routes.has(id)):break
			check(await click_button(game.gathering_button) and (not game.follow_ui.all_box.button_pressed or await click_button(game.follow_ui.all_box)) and await click_button(game.follow_ui.menu.get_ok_button()),mode+" explicitly unchecks all followers")
			check(w.activities.following.is_empty(),mode+" unchecking ends persistent follow")
			var far:=Vector2.INF
			for i in range(32):
				var p:Vector2=center+Vector2.from_angle(TAU*i/32)*16
				game.view.center=p;game.view.follow_player=false;game.view.zoom=1
				if w.walkable("home",p) and game.view.hit(game.view.screen(p)).is_empty() and not w.find_route("human",p).is_empty():far=p;break
			check(far.is_finite(),mode+" "+station_id+" reachable distant ground")
			if not far.is_finite():game.queue_free();ui.free();continue
			game.view.center=far;await mouse(game.view.screen(far))
			check(w._routes.has("human") and await wait_route() and w.point(w.actors.human).distance_to(center)>=15,mode+" "+station_id+" mouse walks to distant start")
			# The preceding long walk restores follow after the real five-second camera timeout.
			# Inspect the distant fire with a fresh explicit peek before actual mouse input.
			game.view.center=center;game.view.follow_player=false;game.view.peek_elapsed=0;await process_frame
			check(game.view.hit(game.view.screen(center))==station_id,mode+" "+station_id+" fire body mouse hit")
			if not captures.is_empty():await screenshot("approach-"+station_id+"-far")
			await mouse(game.view.screen(center))
			check(not game.pending_camp.is_empty() and w._routes.has("human"),mode+" "+station_id+" fire click creates real route")
			if not captures.is_empty():
				for i in range(8):await advance()
				await screenshot("approach-"+station_id+"-walking")
			check(await wait_route(),mode+" "+station_id+" route arrives")
			await process_frame;await process_frame
			var panel:Node=ui.shown_script(CampPanel)
			check(panel!=null and life.fireside.near("human",5),mode+" "+station_id+" panel opens after arrival within five")
			if panel==null:game.queue_free();ui.free();continue
			if not captures.is_empty():await screenshot("approach-"+station_id+"-arrived")
			if ready_uninvited_onlookers(life).is_empty():
				check(await prepare_uninvited_onlookers(life),mode+" actual uninvited onlooker is naturally stopped in the legal outer ring before roasting")
				panel=ui.shown_script(CampPanel)
				if panel==null:check(false,mode+" actual camp panel reopens after real follow preparation");game.queue_free();ui.free();continue
			var before:int=int(life.fireside.available().get("wood",0))
			check(await click_button(panel.light_button) and life.fireside.burning() and int(life.fireside.available().get("wood",0))==before-2,mode+" "+station_id+" actual mouse lights real fire")
			if mode=="showcase":panel.hide();await screenshot("approach-"+station_id+"-lit");panel.show()
			check(await click_button(panel.roast_button),mode+" "+station_id+" mouse selects barbecue")
			var invite:Node=ui.shown_script(Invite)
			if invite==null:check(false,mode+" "+station_id+" invitation appears");game.queue_free();ui.free();continue
			check(await click_button(invite.checks["companion-2"]) and invite.selected_ids()==["companion-2"],mode+" "+station_id+" explicitly invite only blue")
			check(await click_button(invite.get_ok_button()),mode+" "+station_id+" next")
			var menu:Node=ui.shown_script(Menu)
			if menu==null:check(false,mode+" "+station_id+" menu appears");game.queue_free();ui.free();continue
			var expand:Button=WardrobeUI.descendants(menu).filter(func(n):return n is Button and n.get_meta("expand_basics",false))[0]
			check(await click_button(expand),"native expands basic grills")
			var mushroom_button:Button=WardrobeUI.descendants(menu).filter(func(n):return n is Button and n.get_meta("menu_id","")=="single:mushroom")[0]
			menu.scroll.ensure_control_visible(mushroom_button);await process_frame;await process_frame
			check(await click_button(mushroom_button),"native selects exact real mushroom")
			check(await click_button(menu.start_button),mode+" "+station_id+" actual mouse roasts")
			var captured:=false;var swallow_seen:=false;var drool_seen:=false;var described:=false
			for tick in range(3000):
				await advance()
				for watcher in assignments:
					var cue:Dictionary=game.view.hungry_onlooker.presentation(w,watcher,game.view.clock)
					if not cue.is_empty():
						if watcher not in onlookers_seen:onlookers_seen.append(watcher)
						swallow_seen=swallow_seen or float(cue.nod)>0
						drool_seen=drool_seen or bool(cue.drool)
				if not described and w.work.jobs.values().any(func(j):return j.get("phase")=="fire_eat"):
					described=true;checkpoint("first_eating")
				if not captured and not onlookers_seen.is_empty() and w.work.jobs.values().any(func(j):return j.get("phase")=="fire_eat"):
					captured=true
					for dimensions in [Vector2i(1280,800),Vector2i(960,640)]:
						root.size=dimensions;game.view.center=center
						await screenshot("player-"+mode+"-"+station_id+"-onlookers-"+str(dimensions.x))
					root.size=Vector2i(1280,800)
				if life.fireside.state.current.get("eaten",0)>=2:break
			check(not w.hunger.rushing("npc.mira"),mode+" uninvited orange never rushes")
			check(life.fireside.state.current.get("eaten",0)==2 and "npc.mira" not in life.fireside.state.current.eaters,mode+" "+station_id+" only invited and host really eat")
			check(not onlookers_seen.is_empty(),mode+" actual uninvited onlookers outside seats")
			print("ONLOOKERS ",onlookers_seen," swallow=",swallow_seen," drool=",drool_seen)
			evidence["onlookers"]={"actors":onlookers_seen.duplicate(),"swallow_seen":swallow_seen,"drool_seen":drool_seen,"voice_before":voice_before,"voice_after":game.game_audio.voice(w,"companion-2")}
			await fishing_and_call(mode,station_id)
			validate_events(mode,station_id)
			evidence.merge({"opening":mode,"station":station_id,"checks":check_rows,"screenshots":snapshot_rows,"checkpoints":checkpoints,"input":"root viewport actual mouse press/release through UI and scene hit","time":"actual World advance; no actor-position assignment or resource grants","trace":trace_path,"passed":not failures},true)
			var record:=FileAccess.open(captures.path_join("player-"+mode+"-"+station_id+"-summary.json") if not captures.is_empty() else temp.path_join("player-summary.json"),FileAccess.WRITE)
			record.store_string(JSON.stringify(evidence,"  "));record=null
			game.queue_free();ui.free();await process_frame;await process_frame
	print("Overnight real mouse: ",checks," checks, failed=",failures)
	quit(1 if failures else 0)

func fishing_and_call(mode:String,station_id:String)->void:
	var target:Dictionary={}
	var coasts:Array=w.fishing.coast_points.duplicate()
	coasts.sort_custom(func(a,b):return Vector2(a.position[0],a.position[1]).distance_squared_to(w.point(w.actors.human))<Vector2(b.position[0],b.position[1]).distance_squared_to(w.point(w.actors.human)))
	for spot in coasts:
		var p:=Vector2(spot.position[0],spot.position[1])
		if (p.x < -20)!=(station_id=="moon.barbecue"):continue
		game.view.center=p;game.view.follow_player=false;game.view.zoom=1
		if game.view.hit(game.view.screen(p)).is_empty() and not w.find_route("human",p).is_empty():target=spot;break
	check(not target.is_empty(),mode+" actual clickable coast")
	if target.is_empty():return
	await mouse(game.view.screen(Vector2(target.position[0],target.position[1])))
	check(await wait_route() and not w.fishing.shore("human").is_empty(),mode+" actual host route to coast")
	check(await click_button(game.actions_button),mode+" opens actions")
	var buttons:Array=WardrobeUI.descendants(game.action_dock.menu).filter(func(n):return n is Button and n.text=="钓鱼")
	check(buttons.size()==1 and await click_button(buttons[0]),mode+" selects fishing")
	check(await click_button(game.action_dock.popup.get_ok_button()),mode+" casts through fishing UI")
	for tick in range(3000):
		await advance()
		if not preload("res://tests/fishing_fixture.gd").unplaced(w).is_empty():break
	var fish:Dictionary=preload("res://tests/fishing_fixture.gd").unplaced(w)
	check(not fish.is_empty(),mode+" actual catch")
	if fish.is_empty():return
	game.island_hud.notices_signature="";game.island_hud.refresh();await process_frame;await process_frame
	var grills:Array=WardrobeUI.descendants(game.island_hud.notifications).filter(func(n):return n is Button and n.get_meta("fish_id","")==fish.id)
	var clicked_grill:bool=not grills.is_empty() and await WardrobeUI.click(self,grills[0])
	if not clicked_grill:
		print("OVERNIGHT_FISH_CARD ",{"fish":fish.id,"view":game.view.region_id,"visible":game.island_hud.notifications.is_visible_in_tree(),"collapsed":game.island_hud.notices_collapsed,"expanded":game.island_hud.expanded_notice,"candidate":grills.size(),"rect":grills[0].get_global_rect() if not grills.is_empty() and is_instance_valid(grills[0]) else Rect2()})
	check(clicked_grill,mode+" fish card grill")
	var choices:Array=game.get_children().filter(func(n):return n is ConfirmationDialog and n.title=="选择营火" and n.visible)
	check(choices.size()==1,mode+" fire picker")
	if choices.is_empty():return
	# Picker defaults to host's actual island. No direct station/action invocation.
	check(await click_button(choices[0].get_ok_button()),mode+" chooses default island fire")
	for tick in range(4000):
		await advance()
		if not w.fishing.fish.has(fish.id):break
	var life:RefCounted=w.barbecues[station_id]
	check(life.fireside.state.get("current",{}).get("fish",{}).get("id")==fish.id,mode+" same fish arrives on selected island fire")
	var panel:Node=ui.shown_script(CampPanel)
	check(panel!=null,mode+" direct fire panel")
	if panel==null:return
	panel.refresh()
	check(panel.invite_button!=null and await click_button(panel.invite_button),mode+" call from fire")
	var invite:Node=ui.shown_script(Invite)
	if invite==null:check(false,"call invite appears");return
	checkpoint("before_call_orange")
	check(await click_button(invite.checks["npc.mira"]) and await click_button(invite.get_ok_button()),mode+" calls previously uninvited orange")
	for tick in range(1400):
		await advance()
		if w.work.jobs.get("npc.mira",{}).get("phase")=="fire_eat":break
	check(w.work.jobs.get("npc.mira",{}).get("phase")=="fire_eat",mode+" called partner arrives and really eats")
	game.view.center=w.point(life.station);game.view.follow_player=false
	await screenshot(mode+"-direct-eat-"+station_id)
	# Normal, actual elapsed DayCycle progression; no clock/phase assignment.
	for tick in range(15000):
		await advance()
		if w.days.phase().id=="night":break
	for tick in range(100):await advance()
	check(w.days.phase().id=="night",mode+" reaches actual night")
	check(game.links.values().all(func(link):return link._pid<=0),mode+" zero model processes")

func validate_events(mode:String,station_id:String)->void:
	var file:=FileAccess.open(trace_path,FileAccess.READ)
	check(file!=null,"Dummy event trace exists")
	if file==null:return
	var events:Array=[];var counts:Dictionary={};var native_counts:Dictionary={};var maximum:Dictionary={};var native_maximum:Dictionary={}
	while file.get_position()<file.get_length():
		var row:Variant=JSON.parse_string(file.get_line())
		if not row is Dictionary:continue
		events.append(row)
		if row.get("action")=="scheduled":
			var key:String=row.event;counts[key]=int(counts.get(key,0))+1;maximum[key]=maxi(int(maximum.get(key,0)),int(row.get("instances",0)))
		elif row.get("action")=="native_start":
			var key:String=row.event;native_counts[key]=int(native_counts.get(key,0))+1;native_maximum[key]=maxi(int(native_maximum.get(key,0)),int(row.get("instances",0)))
	for key in maximum:check(int(maximum[key])<=int(game.game_audio.catalog.events[key].max_instances),"actual concurrent cap "+key)
	for key in ["ui.click","ui.open","ui.close","ui.invite","fire.ignite","ambience.fire","ambience.sizzle","fishing.cast","fishing.water","fishing.bite","fishing.reel","fish.flap","ui.fish_card","meal.bite","meal.chew","meal.satisfied","ambience.birds","ambience.insects"]:
		check(counts.has(key)==(key not in ["ui.open","ui.close"]),mode+" "+station_id+" actual audio event follows primary-only rule "+key)
	for key in ["ui.click","ui.open","ui.close","ui.invite","fire.ignite","ambience.fire","ambience.sizzle","fishing.cast","fishing.water","fishing.bite","fishing.reel","fish.flap","ui.fish_card","meal.bite","meal.chew","meal.satisfied","ambience.birds","ambience.insects"]:
		check(native_counts.has(key)==(key not in ["ui.open","ui.close"]),mode+" "+station_id+" native audio follows primary-only rule "+key)
	for key in native_maximum:check(int(native_maximum[key])<=int(game.game_audio.catalog.events[key].max_instances),"actual native concurrent cap "+key)
	check(native_counts.keys().any(func(key):return str(key).begins_with("voice.")),"actual native companion voice starts")
	check(not native_counts.keys().any(func(key):return str(key).begins_with("hunger.")),"hunger has no native audio playback")
	check(native_counts.keys().any(func(key):return str(key).begins_with("step.")),"actual native footsteps start")
	check(counts.keys().any(func(key):return str(key).begins_with("voice.")),"accepted real bubble has companion blips")
	check(not counts.keys().any(func(key):return str(key).begins_with("hunger.")),"real hunger never schedules audio")
	check(counts.keys().any(func(key):return str(key).begins_with("step.")),"real displacement has footsteps")
	var music_ids:Array=game.game_audio.catalog.events.keys().filter(func(key):return str(key).begins_with("music."))
	check(music_ids.size()==8,"exactly eight licensed production scenes")
	for scene in ["day","dusk","night","rain","fireside","moon","dark","their"]:
		var id:String="music."+scene
		check(game.game_audio.catalog.events.has(id),"licensed music scene exists "+scene)
		if not game.game_audio.catalog.events.has(id):continue
		var clip:Dictionary=game.game_audio.catalog.events[id].variants.A
		var source:Dictionary=game.game_audio.catalog.sources[clip.source_id]
		check(source.kind=="licensed_music" and source.license=="CC-BY-4.0" and source.parameters.author=="Kevin MacLeod" and FileAccess.get_sha256(clip.file)==clip.sha256,"licensed author and exact audio hash "+scene)
	check(events.any(func(row):return row.get("action")=="scheduled" and str(row.get("event","")).begins_with("music.")),"real production music is scheduled")
	check(events.any(func(row):return row.get("action")=="mix" and str(row.get("event","")).begins_with("music.") and float(row.get("gain",0))>0),"real production music has nonzero mixed gain")
	check(native_counts.keys().any(func(key):return str(key).begins_with("music.")),"real production music reaches native Dummy playback")
	evidence["audio"]={"counts":counts,"native_start_counts":native_counts,"maximum_concurrent":maximum,"native_maximum_concurrent":native_maximum,"rows":events.size(),"driver":"Dummy","music_duck_observed":events.any(func(row):return row.get("action")=="mix" and row.get("event","").begins_with("music.") and float(row.get("duck_db",0))<0)}

func checkpoint(label:String)->void:
	var row:Dictionary={"label":label,"time":w.forest.clock,"residents":{}}
	for id in w.actors:
		var a:Dictionary=w.actors[id];var r:RefCounted=w.director.routines.get(id)
		row.residents[id]={"position":a.position.duplicate(),"activity":a.activity,"hunger":w.hunger.rank(id),"route":w._routes.has(id),"phase":w.work.jobs.get(id,{}).get("phase",""),"held":r.held if r!=null else false,"blocked":r.blocked() if r!=null else false}
	checkpoints.append(row);print("PLAYER CHECKPOINT ",JSON.stringify(row))
