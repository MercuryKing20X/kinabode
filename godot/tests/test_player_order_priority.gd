extends "res://tests/test_intelligence_core_input.gd"

func physical_wood(w:RefCounted)->int:
	var total:int=w.storage.count("wood")
	for actor in w.actors.values():total+=int(actor.carry.get("wood",0))
	for drop in w.drops.values():total+=int(drop.wood)
	return total

func advance_one()->void:
	game._process(.1)
	game.local_host_commands._process(.1)

func run()->void:
	for id in ["codex","companion-2","npc.mira","npc.nora"]:
		await fresh()
		var w:RefCounted=game.world
		game.chat_actor=id
		game.group_chat=false
		w.activities.set_followers([])
		w.activities.opening_party.clear()
		var brain:RefCounted=w.director.brains[id]
		check(w.director.routines[id].enabled,"background enabled "+id)
		check(brain.intention.basic.accept({"reason":"Continue normal autonomous woodworking","steps":[{"action":"chop_and_haul","target":""}]},"local"),"real autonomous plan accepted "+id)
		for tick in range(1000):
			advance_one()
			if w.actors[id].activity=="chopping" and brain.owns_local_job():break
		var job:Dictionary=w.work.jobs.get(id,{}).duplicate(true)
		check(w.actors[id].activity=="chopping" and brain.owns_local_job(),"actually chopping "+id)
		var wood:=physical_wood(w)
		# Pine and Mira test planting; Snow and Nora test an explicit verbal call.
		var plant:bool=id in ["companion-2","npc.mira"]
		await text_input("帮我种萝卜" if plant else "过来")
		check(w.work.jobs.get(id,{}).get("id","")!=job.get("id",""),"player interrupted autonomous job "+id)
		check(physical_wood(w)==wood,"no physical wood changed during handover "+id)
		check(w.farms.active(id) if plant else w.activities.following.has(id),"actual player order started "+id)
		var resumed:=false
		var arrived:=false
		for tick in range(6000):
			advance_one()
			arrived=arrived or (w.farms.orders.get(id,{}).get("status")=="completed" if plant else w.point(w.actors[id]).distance_to(w.point(w.actors.human))<=4)
			if w.work.jobs.get(id,{}).get("id","")==job.get("id",""):
				resumed=true;break
			if tick%100==0:await process_frame
		check(arrived and resumed,"player order finished before exact chop job resumes "+id)
		var original_tree:Dictionary=w.objects.get(job.get("target_id",""),{})
		if original_tree.get("status")=="mature" and (not w.work.claims.has(original_tree.id) or w.work.claims[original_tree.id]==id):
			check(w.work.jobs.get(id,{}).get("target_id","")==original_tree.id,"available original tree retained "+id)
		if not resumed:print("PRIORITY ",id," order=",w.farms.orders.get(id,{})," pause=",brain.paused_wood," wait=",brain.paused_wood_wait_order," current=",brain.current," tree=",original_tree.get("status")," player_distance=",brain.distance())
		game.queue_free();await process_frame
	print("PLAYER_ORDER_PRIORITY ",checks," failed=",failed)
	quit(1 if failed else 0)
