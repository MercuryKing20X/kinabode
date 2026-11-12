extends "res://tests/test_intelligence_core_input.gd"
func step_until_done(limit:float=240)->void:
	for i in int(limit*10):
		game._process(.1);game.local_host_commands._process(.1)
		if i%100==0:await process_frame
		if i>10 and game.local_host_commands.tracked.is_empty():break
func run()->void:
	await fresh()
	await text_input("大家砍树")
	var w:RefCounted=game.world
	check(w.work.jobs.values().filter(func(j):return j.intent=="gather_wood" and j.tree_count==3).size()==4,"four exact three-tree jobs start on fresh standard world")
	var job_ids:Array=w.work.jobs.values().map(func(j):return j.id)
	await picture("four-real-chop-start")
	await step_until_done(300)
	print("WOOD_RESULTS ",w.work.events.filter(func(e):return e.get("job_id","") in job_ids)," tracked=",game.local_host_commands.tracked)
	check(w.work.events.filter(func(e):return e.get("status")=="completed" and e.get("job_id","") in job_ids).size()==4,"all four real wood receipts completed")
	check(w.activities.following.size()==4,"all four restore previous follow")
	await picture("four-real-chop-return")
	await text_input("小白去建设")
	w=game.world
	var build_id:String=str(w.work.jobs.get("codex",{}).get("id",""))
	check(w.work.jobs.get("codex",{}).get("intent")=="build","construction text starts original one-stage work")
	await step_until_done()
	check(w.work.events.any(func(e):return e.actor_id=="codex" and e.status=="completed" and e.get("job_id","")==build_id),"one-stage construction committed completion")
	check(w.activities.following.has("codex"),"builder returns to follow")
	await picture("stage-return")
	game.queue_free();await process_frame
	print("RESORT_COMMAND_REPAIRS ",checks," failed=",failed);quit(1 if failed else 0)
