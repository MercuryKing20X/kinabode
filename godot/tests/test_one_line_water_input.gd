extends "res://tests/test_intelligence_core_input.gd"
func run()->void:
	await fresh()
	var w:RefCounted=game.world
	await text_input("小白帮我种萝卜")
	var planted:String=""
	for tick in 6000:
		game._process(.05)
		for plot in w.farms.plots.values():
			if not str(plot.crop_id).is_empty() and not plot.watered:planted=plot.id;break
		if not planted.is_empty():break
	check(not planted.is_empty(),"original real seed commits before watering")
	await text_input("别干了")
	var before:Dictionary=w.storage.saved()
	var count_before:int=w.farms.plots.values().filter(func(p):return not str(p.crop_id).is_empty()).size()
	await text_input("大家浇水")
	for tick in 6000:
		game._process(.1);game.local_host_commands._process(.1)
		if w.farms.plots[planted].watered and not w.farms.active("codex"):break
	check(w.farms.plots[planted].watered,"native water command really waters the retained dry plant")
	check(w.farms.plots.values().filter(func(p):return not str(p.crop_id).is_empty()).size()==count_before,"water never plants empty plots")
	check(w.storage.saved()==before,"water never spends extra seeds")
	game.queue_free();await process_frame
	print("ONE_LINE_WATER_INPUT ",checks," failed=",failed);quit(1 if failed else 0)
