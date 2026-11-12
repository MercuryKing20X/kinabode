extends "res://tests/test_intelligence_core_input.gd"
func run()->void:
	await fresh()
	var w:RefCounted=game.world
	var human:Array=w.actors.human.position.duplicate()
	var before:int=w.storage.count("wood")
	var original_capabilities:Array=w.residents.capabilities(w.actors["npc.mira"]).duplicate()
	await text_input("小橙帮我砍一棵树")
	check(w.work.jobs.get("npc.mira",{}).get("intent")=="gather_wood","named social resident accepts scoped real chop")
	check(w.residents.capabilities(w.actors["npc.mira"])==original_capabilities and w.residents.supports(w.actors["npc.mira"],"chop") and w.host_issuing.is_empty(),"no permanent capability grant")
	var expected_wood:int=0
	for tick in 6000:
		var target:Dictionary=w.objects.get(w.work.jobs.get("npc.mira",{}).get("target_id",""),{})
		if target.get("kind")=="tree":expected_wood=int(w.forest.settings.large_wood if int(target.wood_yield)>8 else w.forest.settings.normal_wood)
		game._process(.1);game.local_host_commands._process(.1)
		if w.storage.count("wood")>before and not w.work.jobs.has("npc.mira"):break
	check(expected_wood>0 and w.storage.count("wood")==before+expected_wood,"one real tree chopped hauled and handed over")
	check(w.actors["npc.mira"].carry.is_empty(),"no cloned carry after actual deposit")
	var berries:int=w.storage.count("wild_berry")
	await text_input("小橙采集野莓")
	check(w.ingredients.resident_pending.has("npc.mira"),"named ingredient command starts real reserved route")
	for tick in 6000:
		game._process(.1);game.local_host_commands._process(.1)
		if not w.ingredients.resident_pending.has("npc.mira"):break
	if w.storage.count("wild_berry")!=berries+1 or not w.ingredients.ready_at.has("wild_berry"):print("ONE_LINE_INGREDIENT_PROBE before=",berries," after=",w.storage.count("wild_berry")," ready=",w.ingredients.ready_at," pending=",w.ingredients.resident_pending," actor=",w.actors["npc.mira"].position," route=",w._routes.get("npc.mira")," follow=",w.activities.following.has("npc.mira")," commanded=",w.activities.commanded("npc.mira")," tracked=",game.local_host_commands.tracked)
	check(w.storage.count("wild_berry")==berries+1 and w.ingredients.ready_at.has("wild_berry"),"real source committed once and enters original regrowth")
	await text_input("你们都跟牢我")
	check(w.activities.following.size()==4,"exact requested follow phrase")
	await text_input("别干了")
	check(w.activities.following.is_empty() and w.work.jobs.is_empty(),"exact stop releases all selected work and follow")
	check(w.actors.human.position==human,"host remained under player control")
	game.queue_free();await process_frame
	print("ONE_LINE_LABOR_INPUT ",checks," failed=",failed);quit(1 if failed else 0)
