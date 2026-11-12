extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
const L=preload("res://scripts/localization.gd")
var opening:="standard"
var failures:=0
func _initialize()->void:call_deferred("run")
func check(v:bool,label:String)->void:
	if not v:failures+=1;push_error(label)
func run()->void:
	var base:=OS.get_environment("HABITAT_DATA_DIR")
	if not base.contains("youqi-"):quit(1);return
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO;OS.set_environment("HABITAT_OPENING","legacy")
	for region in ["home","moon","dark"]:
		var directory:=base.path_join(opening+"-"+region);OS.set_environment("HABITAT_DATA_DIR",directory)
		var w:=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");w.residents.provision(w)
		w.library=preload("res://scripts/character_library.gd").new();w.library.configure(directory)
		check(preload("res://scripts/world_opening.gd").apply(w,w.library,opening).ok,"authored opening "+opening)
		# Serialize legitimate inventory and viewpoint fixtures before production load.
		# No actor coordinates are changed once the scene starts.
		if region=="moon":w.actors.human.position=w.barbecues["moon.barbecue"].station.position.duplicate()
		if region=="dark":w.actors.human.region_id="dark";w.actors.human.position=w.dark.config.arrival.duplicate()
		var ids:Array=["codex","companion-2","npc.mira","npc.nora"];var skins:Array=["ai-gpt","ai-deepseek","ai-claude","ai-glm"]
		for i in ids.size():w.actors[ids[i]].appearance_id=skins[i];w.actors[ids[i]]["custom_appearance"]=true
		var wood:int=w.storage.count("wood");var mushrooms:int=w.storage.count("mushroom")
		# Host carry is normalized by production load; withdraw through visible UI below.
		check(preload("res://scripts/save_store.gd").save_world(w,directory),"serialized region fixture")
		var game:Node=load("res://scenes/main_v3.tscn").instantiate();game.world=w;root.add_child(game)
		game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.island_hud.set_process(false);game.chat.hide()
		for i in range(8):await process_frame
		L.select(directory,"en");game.island_hud.refresh();await process_frame
		var at:Vector2=w.point(w.actors.human)
		check(await UI.click(self,game.island_hud.stock_button) and game.storage_panel.visible,"real warehouse entry "+opening+region)
		var wood_rows:Array=UI.descendants(game.storage_panel.rows).filter(func(n):return n is HBoxContainer and n.get_child_count()==3 and n.get_child(0) is Label and n.get_child(0).text.begins_with(L.text("hud.wood")))
		check(wood_rows.size()==1 and await UI.click(self,wood_rows[0].get_child(2)),"real take one original wood before all-in "+region)
		check(await UI.click(self,game.storage_panel.deposit_button),"real all-in "+opening+region)
		check(w.actors.human.carry.is_empty() and w.storage.count("wood")==wood,"one original unit conserves "+region)
		var rows:Array=UI.descendants(game.storage_panel.rows).filter(func(n):return n is HBoxContainer and n.get_child_count()==3 and n.get_child(0) is Label and n.get_child(0).text.begins_with(L.text("hud.mushroom")))
		check(rows.size()==1,"mushroom available in same warehouse "+region)
		if rows.size()==1:
			var spin:SpinBox=rows[0].get_child(1);await UI.reveal(self,spin)
			var pos:=spin.get_global_rect().position+Vector2(spin.get_global_rect().size.x-7,spin.get_global_rect().size.y*.25)
			for down in [true,false]:
				var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.position=pos;event.global_position=pos;root.push_input(event,true);await process_frame
			check(await UI.click(self,rows[0].get_child(2)),"real take two "+region)
			check(int(w.actors.human.carry.get("mushroom",0))==2 and w.storage.count("mushroom")==mushrooms-2,"exact two mushrooms "+region)
		check(await UI.click(self,game.storage_panel.close_button),"close storage "+region)
		check(await UI.click(self,game.island_hud.stock_button) and game.storage_panel.visible,"reopen storage "+region)
		check(w.storage.count("mushroom")==mushrooms-2,"reopen same number "+region)
		check(w.point(w.actors.human)==at and not w._routes.has("human"),"source collection travel exactly zero "+region)
		game.queue_free();await process_frame;await process_frame
	OS.set_environment("HABITAT_DATA_DIR",base)
	print("Warehouse matrix ",opening," failures=",failures);quit(1 if failures else 0)
