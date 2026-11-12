extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
const F=preload("res://tests/cooking_fixture.gd")
const Save=preload("res://scripts/save_store.gd")
var failures:Array=[]
var records:Array=[]
var game:Node
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->void:
	if not value:failures.append(label);push_error(label)
func point_at(w:RefCounted,id:String,region:String,at:Variant)->void:
	# Disposable pre-invitation scenario fixture only; accepted movement/eating is untouched.
	var p:Vector2=Vector2(at[0],at[1]) if at is Array else at
	w.actors[id].region_id=region;w.actors[id].position=[p.x,p.y];w.actors[id].activity="idle"
func run()->void:
	var opening:String=OS.get_environment("BBQ_MATRIX_OPENING")
	var station:String=OS.get_environment("BBQ_MATRIX_STATION")
	if opening.is_empty():opening="showcase"
	if station.is_empty():station="home.barbecue"
	for state in ["idle","return_visit","storage_delivery","chess","after_chess","bridge","other_island","very_hungry_follow","full","indoors","fishing","farm_command","just_loaded"]:
		if state!=(OS.get_environment("BBQ_MATRIX_STATE") if not OS.get_environment("BBQ_MATRIX_STATE").is_empty() else "idle"):continue
		var initial=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json")
		initial.residents.provision(initial);initial.library=preload("res://scripts/character_library.gd").new();initial.library.configure(OS.get_environment("HABITAT_DATA_DIR"))
		check(preload("res://scripts/world_opening.gd").apply(initial,initial.library,opening).ok,"prepare actual "+opening)
		check(Save.save_world(initial,OS.get_environment("HABITAT_DATA_DIR")),"persist isolated opening fixture")
		game=UI.init_game(self);await process_frame
		var w:RefCounted=game.world
		check(w.opening_id==opening,"loaded exact "+opening)
		game.chat.hide();w.intelligence.activate_presets()
		if opening=="standard":
			game.house_panel.open_site("home.house.01");await process_frame
			check(await UI.click(self,game.house_panel.build_all_button),"host native completion prerequisite")
			game.house_panel.hide()
		if w.storage.count("mushroom")<3:check(F.mushroom(w),"finite real forage fixture")
		var life:RefCounted=w.barbecues[station]
		var center:Vector2=w.point(life.station)
		var at:Vector2=center+Vector2(2.5,0)
		for angle in range(16):
			var p:Vector2=center+Vector2.from_angle(angle*TAU/16)*2.5
			if w.walkable(life.station.region_id,p):at=p;break
		point_at(w,"human",life.station.region_id,at)
		for pair in [["codex","ai-gpt"],["companion-2","ai-deepseek"],["npc.mira","ai-claude"],["npc.nora","ai-glm"]]:w.actors[pair[0]].appearance_id=pair[1]
		var ids:Array=["companion-2","npc.mira"]
		var readiness:Dictionary={}
		for index in range(ids.size()):
			var id:String=ids[index]
			w.actors[id].appearance_id="ai-deepseek" if index==0 else "ai-claude"
			var start:Vector2=center+Vector2(8+index*2,3)
			if not w.walkable(life.station.region_id,start):start=at+Vector2(index+1,2)
			point_at(w,id,life.station.region_id,start)
			var r:RefCounted=w.director.routines[id];r.enabled=true
			w.hunger.ensure(id)
			if state=="return_visit":
				r._move_to(at+Vector2(index+1,1));r.kind="return_visit"
			elif state=="storage_delivery":
				check(F.withdraw(w,id,"wood",1),"finite guest wood fixture");w.deliveries.request(id)
			elif state in ["chess","fishing","farm_command"]:
				# Task snapshots model existing host-owned in-flight work. Never advanced.
				w.work.jobs[id]={"id":"matrix-owned-"+id,"intent":"play_gomoku" if state=="chess" else "fish" if state=="fishing" else "farm_plant","phase":"matrix_host_busy","target_id":"play.gomoku","time":0.0}
			elif state=="after_chess":r.visual_quiet_until=w.director.time+8
			elif state=="other_island":point_at(w,id,"home" if life.station.region_id!="home" else "dark",w.map_anchor("plaza.center"))
			elif state=="very_hungry_follow":w.hunger.states[id].elapsed=w.hunger.config.thresholds[3];w.hunger.states[id].full_meal=false
			elif state=="full":w.hunger.states[id].elapsed=0;w.hunger.states[id].full_meal=true
			elif state=="indoors":point_at(w,id,"room.home.house.01",Vector2(13.5,7))
			elif state=="bridge":
				if life.station.region_id=="dark":point_at(w,id,"dark",Vector2(34+index,115))
				elif station=="homelands.barbecue":point_at(w,id,"home",Vector2(81+index,155))
				else:point_at(w,id,"home",w.map_anchor("moon.bridge.east"))
		if state=="very_hungry_follow":w.advance(.1)
		if state=="just_loaded":
			var directory:String=OS.get_environment("HABITAT_DATA_DIR").path_join("reload-"+opening+station.replace(".","-"))
			check(Save.save_world(w,directory),"save existing state");check(Save.load_world(w,directory).ok,"actual schema7 reload")
		for id in ids:readiness[id]=life.fireside.can_invite([id]).duplicate(true)
		# Native fire/light/invitation/confirm/food/start UI is the acceptance path.
		game.view.show_region(life.station.region_id);game.view.center=center;game._show_barbecue_menu(station)
		await process_frame
		var panel:Node=UI.shown(game,"res://scripts/fireside_panel.gd")
		check(panel!=null,"camp panel "+state)
		if panel==null:game.queue_free();await process_frame;continue
		check(await UI.click(self,panel.light_button),"native light "+state)
		check(await UI.click(self,panel.roast_button),"native invitation "+state)
		var invitation:Node=UI.shown(game,"res://scripts/fireside_invitation.gd")
		if invitation==null:check(false,"missing invite");game.queue_free();await process_frame;continue
		for id in ids:check(await UI.click(self,invitation.checks[id]),"native select "+id)
		check(await UI.click(self,invitation.get_ok_button()),"native next "+state)
		var menu:Node=UI.shown(game,"res://scripts/fireside_menu.gd")
		check(menu!=null,"food menu "+state)
		var accepted:Array=life.fireside.selected_guests.duplicate()
		if menu!=null:
			check(await UI.click(self,menu.start_button),"native roast "+state)
			for tick in range(1600):
				# Busy fixture snapshots remain untouched; they must be rejected.
				if state in ["chess","fishing","farm_command"]:break
				w.advance(.1)
				if accepted.all(func(id):return id in life.fireside.state.current.get("eaters",[])):break
		for id in ids:
			var eaten:bool=id in life.fireside.state.get("current",{}).get("eaters",[])
			var reason:String=str(readiness[id].get("message",readiness[id].get("error","")))
			records.append({"opening":opening,"station":station,"state":state,"actor":id,"appearance":w.actors[id].appearance_id,"precheck":readiness[id],"selected":id in accepted,"ate":eaten,"reason":reason,"status":game.status.text})
			check(eaten if readiness[id].ok else id not in accepted and not reason.is_empty(),"arrival or explained refusal "+opening+"/"+station+"/"+state+"/"+id)
		game.queue_free();await process_frame
	var out:String=OS.get_environment("BBQ_MATRIX_OUTPUT")
	if not out.is_empty():
		var f:=FileAccess.open(out.path_join(opening+"-"+station+"-"+OS.get_environment("BBQ_MATRIX_STATE")+".json"),FileAccess.WRITE);f.store_string(JSON.stringify({"records":records,"failures":failures},"\t"));f.close()
	print("BBQ_MATRIX ",opening," ",station," ",records.size()," failures=",failures)
	quit(1 if not failures.is_empty() else 0)
