extends "res://tests/capture_route_latched.gd"
func run()->void:
	output=OS.get_environment("HABITAT_DARK_EVIDENCE");root.size=Vector2i(1280,800);root.gui_embed_subwindows=true;game=UI.init_game(self);await process_frame;await process_frame
	var w:RefCounted=game.world;w.actors.human.carry={"seed.pumpkin":1}
	await click_button(game.actions_button)
	var buttons:Array=UI.descendants(game.action_dock.menu).filter(func(n):return n is Button and n.text=="收进背包")
	await click_button(buttons[0])
	var tree:Dictionary={}
	for o in w.objects.values():
		if o.region_id=="home" and o.kind=="tree" and o.status=="mature" and not w.find_route("human",w.point(o)+Vector2(0,2)).is_empty():tree=o;break
	game.view.center=w.point(tree);game.view.follow_player=false;game.view.zoom=1.25
	for y in range(-150,1,10):
		var at:Vector2=game.view.screen(w.point(tree))+Vector2(0,y)
		if game.view.hit(at)==tree.id:await click(at);break
	for i in range(2000):
		game._process(.1);game.view._process(.1);await process_frame
		if not w.work.jobs.has("human") and not w._routes.has("human"):break
	await shot("pocketed-seed-real-tree")
	var ok:bool=tree.status!="mature" and int(w.actors.human.carry.get("seed.pumpkin",0))==1
	FileAccess.open(output.path_join("carry.json"),FileAccess.WRITE).store_string(JSON.stringify({"ok":ok,"carry":w.actors.human.carry,"tree_status":tree.status}));game.queue_free();await process_frame;quit(0 if ok else 1)
