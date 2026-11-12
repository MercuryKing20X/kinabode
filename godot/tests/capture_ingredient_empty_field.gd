extends "res://tests/test_ingredient_native_input.gd"
func run()->void:
	game=UI.init_game(self);await process_frame;await process_frame
	var w:RefCounted=game.world
	var field:Dictionary=w.farms.farms["farm.theirs"]
	if not w.farms.ready("farm.theirs") or not w.farms.farm_plots("farm.theirs").all(func(p):return p.crop_id.is_empty()):print("EMPTY CAPTURE invalid source");quit(1);return
	await click_world(w.point(w.farms.farm_plots("farm.theirs")[0]))
	for child in UI.descendants(game.farm_panel):
		if child is Button and child.text=="×":await UI.click(self,child);break
	await capture("south-empty-field",w.catalog.rectangle(field.rect).get_center())
	print("EMPTY FIELD actual saved native production state PASS")
	game.queue_free();await process_frame;quit()
