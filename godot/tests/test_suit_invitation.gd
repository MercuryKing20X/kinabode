extends "res://tests/test_intelligence_core_input.gd"
func run()->void:
	await fresh()
	var w:RefCounted=game.world
	var ids:Array=["codex","companion-2","npc.mira","npc.nora"]
	for id in ids:
		w.actors[id]["capabilities"]=["social"]
		check(w.residents.supports(w.actors[id],"build_house"),"legacy capabilities do not suppress work "+id)
	var lib:RefCounted=game.library
	check(lib.artworks.has("suit-hulk"),"new artwork loaded")
	check(not w.assign_appearance("codex","suit-hulk"),"host-only appearance enforced")
	game.island_hud.wardrobe.open_for("human",true)
	await process_frame;await process_frame
	var button:Button=null
	for item in game.island_hud.wardrobe.grid.get_children():
		for child in item.get_children():
			if child is Button and child.get_meta("work_id","")=="suit-hulk":button=child
	check(button!=null,"human wardrobe contains suit")
	# Scroll selected entry into view before native input.
	if button!=null:
		game.island_hud.wardrobe.grid.get_parent().ensure_control_visible(button)
		await process_frame
		check(await UI.click(self,button),"native select suit")
		check(game.island_hud.wardrobe.selected_work=="suit-hulk","selection bound")
		# Commit uses the same protected host confirmation handler.
		game.island_hud.wardrobe._commit(true)
		check(w.actors.human.appearance_id=="suit-hulk","human appearance changed")
	await picture("suit-equipped")
	game.island_hud.wardrobe.open_for("codex")
	await process_frame;await process_frame
	var absent:=true
	for item in game.island_hud.wardrobe.grid.get_children():
		for child in item.get_children():
			if child is Button and child.get_meta("work_id","")=="suit-hulk":absent=false
	check(absent,"partner wardrobe excludes suit")
	await picture("partner-wardrobe")
	game.island_hud.wardrobe.hide()
	game.participant_picker.open_for({"intent":"build_house","target_id":"home.codex"})
	await process_frame;await process_frame
	for id in ids:check(not game.participant_picker.toggles[id].disabled,"four helpers eligible "+id)
	await picture("four-helpers")
	check(await UI.click(self,game.participant_picker.all_box),"native select all")
	for id in ids:check(game.participant_picker.toggles[id].button_pressed,"all selected "+id)
	game.participant_picker.hide()
	w.hunger.ensure("npc.mira");w.hunger.states["npc.mira"].elapsed=float(w.hunger.config.thresholds[3])
	game.participant_picker.open_for({"intent":"build_house","target_id":"home.codex"})
	check(game.participant_picker.toggles["npc.mira"].disabled,"highest hunger disabled")
	check(not game.participant_picker.toggles["npc.mira"].tooltip_text.is_empty(),"hunger has reason")
	game.participant_picker.hide()
	var atlas:=preload("res://scripts/motion_atlas.gd").new()
	for direction in ["down","left","right","up"]:
		w.actors.human.facing=direction
		for action in ["walk","run","eat","chop","gather"]:
			for col in int(atlas.manifests[action].columns):check(atlas.texture(action,lib,w.actors.human,col)!=null,"suit frame "+action+direction+str(col))
	print("SUIT_INVITATION checks=",checks," failed=",failed)
	game.queue_free();await process_frame;quit(1 if failed else 0)
