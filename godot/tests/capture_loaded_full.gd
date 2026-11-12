extends "res://tests/capture_route_latched.gd"
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"));output=OS.get_environment("HABITAT_DARK_EVIDENCE");root.size=Vector2i(1280,800)
	game=UI.init_game(self);await process_frame;await process_frame
	var w:RefCounted=game.world;var save:Script=preload("res://scripts/save_store.gd")
	w.actors.human.carry={"tomato":19,"seed.pumpkin":1};w.actors.human.erase("pocketed")
	var chest:Dictionary={"id":"storage","items":w.storage._items,"capacity":9007199254740991,"kind":"storage","region_id":"home","position":w.actors.human.position};w.storage.add({"wood":159})
	assert(save.save_world(w,OS.get_environment("HABITAT_DATA_DIR")));assert(save.load_world(w,OS.get_environment("HABITAT_DATA_DIR")).ok)
	var before:int=w.life.item_count({"id":"storage","items":w.storage._items,"capacity":9007199254740991,"kind":"storage","region_id":"home","position":w.actors.human.position}.items)+w.life.item_count(w.actors.human.carry)
	game._process(.01);game.view._process(.01)
	var untouched:bool=not w.actors.human.get("pocketed",false) and not game.status.text.is_empty()
	await shot("loaded-full-retained")
	game.view.center=w.point(chest);game.view.follow_player=false
	await click(game.view.screen(w.point(chest))+Vector2(0,-15))
	for i in range(3000):
		await step()
		if not w.work.jobs.has("human") and not w._routes.has("human") and i>20:break
	await step();await shot("space-freed-auto-pocket")
	var ok:bool=untouched and w.actors.human.get("pocketed",false) and int(w.actors.human.carry.get("seed.pumpkin",0))+int(w.storage._items.get("seed.pumpkin",0))==1 and w.life.item_count(w.storage._items)+w.life.item_count(w.actors.human.carry)==before
	FileAccess.open(output.path_join("full.json"),FileAccess.WRITE).store_string(JSON.stringify({"ok":ok,"retained_on_load":untouched,"carry_after":w.actors.human.carry,"item_total":before,"pocketed":w.actors.human.get("pocketed",false)},"  "))
	game.queue_free();await process_frame;quit(0 if ok else 1)
