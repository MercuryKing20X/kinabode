extends "res://tests/test_dialogue_bar_input.gd"
func run()->void:
	OS.set_environment("HABITAT_OPENING","showcase")
	var game:Node=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false)
	root.size=Vector2i(1280,800);await frames()
	var w:RefCounted=game.world;var id:String="orange-sunflower-girl"
	check(w.actors["npc.mira"].appearance_id==id,"new default appearance")
	check(game.library.artworks.has("orange-haired-girl"),"previous editable work retained")
	check(game.library.valid(game.library.artworks[id]),"new artwork respects original validator")
	var body:Image=game.library.texture(id,"down_0").get_image()
	var previous:Image=game.library.texture("orange-haired-girl","down_0").get_image()
	var ratio:float=float(body.get_used_rect().size.y)/previous.get_used_rect().size.y
	check(ratio>=1.05 and ratio<=1.08,"5-8 percent above previous orange")
	var api:RefCounted=preload("res://scripts/motion_atlas.gd").new()
	var fisher:RefCounted=preload("res://scripts/fishing_renderer.gd").new()
	var actor:Dictionary=w.actors["npc.mira"].duplicate(true)
	for action in ["walk","run","chop","gather","farm","gesture","eat"]:
		var columns:int=int(api.manifests[action].columns)
		for dir in ["down","left","right","up"]:
			actor.facing=dir
			for col in range(columns):check(api.texture(action,game.library,actor,col)!=null,"authored "+action+" "+dir+" "+str(col))
	var original:Dictionary=w.actors["npc.mira"]
	# Let original World movement bring the companions into the host's scene.
	w.activities.set_followers(["codex","companion-2","npc.mira","npc.nora"])
	for tick in range(800):w.advance(.1)
	game.chat.hide();game.view.follow_player=false;game.view.center=w.point(w.actors.human);game.view.zoom=1.2
	await frames(3);await capture("orange-default-group")
	# A real host command routes Orange through World and into an actual chop phase.
	check(await UI.click(self,game.dialogue_button),"real mouse opens command input")
	var input_at:Vector2=game.chat_input.get_global_rect().get_center()
	for down in [true,false]:
		var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.position=input_at;press.global_position=input_at;press.pressed=down;root.push_input(press,true);await process_frame
	for ch in "小橙砍一棵树":
		var key:=InputEventKey.new();key.unicode=ch.unicode_at(0);key.pressed=true;root.push_input(key,true);await process_frame
	var enter:=InputEventKey.new();enter.keycode=KEY_ENTER;enter.pressed=true;root.push_input(enter,true);await frames(2)
	game.chat.hide();var chopped:=false;var movement_shots:=0
	for tick in range(1800):
		game._process(.1)
		if w.actors["npc.mira"].activity=="walking" and movement_shots<6:
			game.view.center=w.point(w.actors["npc.mira"]);game.view.zoom=1.5;await frames(2);await capture("orange-real-run-"+str(movement_shots));movement_shots+=1
		if w.actors["npc.mira"].activity=="chopping":
			game.view.center=w.point(w.actors["npc.mira"]);game.view.zoom=1.5;await frames(2);await capture("orange-real-chop-no-book");chopped=true;break
	check(chopped,"real command reaches chop with authored no-book frames")
	w.command("npc.mira",{"intent":"stop"})
	# True mouse wardrobe selection can opt back into the old default.
	game.island_hud.refresh();await frames(2)
	check(await UI.click(self,game.island_hud.appearance_buttons["npc.mira"]),"real mouse opens orange wardrobe")
	await capture("orange-new-wardrobe-front")
	var panel:Node=game.island_hud.wardrobe
	var label:String=game.library.artworks["orange-haired-girl"].name
	var options:Array=UI.descendants(panel.grid).filter(func(node):return node is Button and node.get_meta("work_id","")=="orange-haired-girl")
	check(options.size()==1,"old work reachable in wardrobe")
	if options.size()==1:
		await UI.reveal(self,options[0]);check(await UI.click(self,options[0]),"real mouse chooses old orange")
		var confirm:Array=UI.descendants(panel).filter(func(node):return node is Button and node.text==preload("res://scripts/localization.gd").text("content.workshop.confirm"))
		if not confirm.is_empty():check(await UI.click(self,confirm[0]),"real mouse confirms wardrobe")
		check(w.actors["npc.mira"].appearance_id=="orange-haired-girl" and w.actors["npc.mira"].get("custom_appearance",false),"explicit old outfit remains custom")
		await capture("orange-old-wardrobe")
	var store=preload("res://scripts/save_store.gd")
	var save_dir:String=OS.get_environment("HABITAT_DATA_DIR").path_join("orange-migration")
	check(store.save_world(w,save_dir),"save explicit old wardrobe to isolated fixture")
	check(store.load_world(w,save_dir).get("loaded",false) and w.actors["npc.mira"].appearance_id=="orange-haired-girl","reload preserves explicit old appearance")
	w.actors["npc.mira"]["custom_appearance"]=false
	check(store.save_world(w,save_dir),"legacy default fixture saved without material changes")
	check(store.load_world(w,save_dir).get("loaded",false) and w.actors["npc.mira"].appearance_id==id,"reload migrates untouched previous default")
	store.apply_identity(w,{"npc.mira":{"appearance_id":"orange-haired-girl","custom_appearance":false}})
	check(w.actors["npc.mira"].appearance_id==id,"new-world retained default identity follows new default")
	store.apply_identity(w,{"npc.mira":{"appearance_id":"orange-haired-girl","custom_appearance":true}})
	check(w.actors["npc.mira"].appearance_id=="orange-haired-girl","new-world custom old identity preserved")
	print("ORANGE_SUNFLOWER ",checks," failed=",failed)
	game.queue_free();await frames();quit(1 if failed else 0)
