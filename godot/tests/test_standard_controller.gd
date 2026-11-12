extends SceneTree
const World=preload("res://scripts/world_state.gd")
var checks:=0
var failed:=false
func check(ok:bool,msg:String)->void:
	checks+=1
	if not ok:failed=true;push_error(msg)
func _initialize()->void:call_deferred("run")
func run()->void:
	OS.set_environment("HABITAT_OPENING","standard")
	var game:Node=load("res://scenes/main_v3.tscn").instantiate();game.world=World.new("res://content/home-v3/world.json");root.add_child(game)
	root.size=Vector2i(1280,800);game.save_enabled=false;game.set_process(false);game.view.sound_enabled=false;await process_frame
	var w:RefCounted=game.world;var human:Dictionary=w.actors.human.duplicate(true)
	check(w.opening_id=="standard" and w.standard.config.companions.all(func(id):return not w.director.model_controlled(id)),"actual new standard startup uses four local controllers")
	game.choose_opening();await process_frame
	check(game.opening_picker.get_item_metadata(game.opening_picker.selected)=="standard" and game.opening_picker.item_count==2,"actual opening selector defaults standard and preserves showcase choice")
	game.opening_dialog.hide();game.opening_dialog.queue_free()
	game._show_opening_board();await process_frame
	var boards:Array=game.get_children().filter(func(n):return n is AcceptDialog and n.title.begins_with("告示板"))
	check(boards.size()==1 and w.standard.board().all(func(e):return not e.done),"notice board shows genuine incomplete world conditions")
	for b in boards:b.queue_free()
	# Exercise idle-only suggestions after the host dismisses default following.
	for id in w.director.routines:w.activities.default_follow_excluded[id]=true
	w.activities.dismiss()
	for frame in range(1200):
		w.advance(.1)
		if not w.proposals.snapshot().is_empty():break
	var cards:Array=w.proposals.snapshot().filter(func(card):return card.get("opening_hint",false))
	check(cards.size()==1 and cards[0].source=="local_rules","local opening hint reuses proposal card with honest source")
	if not cards.is_empty():
		var stock:int=preload("res://tests/backpack_fixture.gd").wood_total(w)
		check(w.proposals.respond_host(cards[0].id,true,game.proposal_host.start).ok,"explicit accept focuses construction target")
		check(w.actors.human==human and w.work.jobs.is_empty() and w._routes.get("human",[]).is_empty() and preload("res://tests/backpack_fixture.gd").wood_total(w)==stock,"accepting hint neither moves human nor builds or consumes")
	game.island_hud.activate_context("play.standard.camp")
	check(game.leisure_panel.visible and game.leisure_panel.site_id=="play.standard.camp" and game.leisure_panel.info.text.contains("6"),"camp construction entry shows actual configured price")
	game.leisure_panel.hide()
	for size in [Vector2i(1280,800),Vector2i(960,640)]:
		root.size=size
		for mode in ["小","标准","大"]:
			game.island_hud.set_interface_size(mode);game.island_hud.refresh();await process_frame;await process_frame
			check(Rect2(Vector2.ZERO,Vector2(size)).encloses(game.island_hud.residents_panel.get_global_rect()),"resident rows fit "+str(size)+mode)
			check(game.island_hud.appearance_buttons["codex"].text.is_empty() and game.island_hud.appearance_buttons["codex"].icon!=null,"wardrobe icon preserves visible source and hunger room")
	check(game.links.values().all(func(link):return link._pid<=0 and not link.is_busy()) and game.group_links.values().all(func(link):return link._pid<=0 and not link.is_busy()),"no real inference or lazy process starts")
	game.queue_free();await process_frame;await create_timer(.3).timeout
	print("Standard controller: ",checks," checks, failed=",failed);quit(1 if failed else 0)
