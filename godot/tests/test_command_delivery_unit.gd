extends SceneTree
func _initialize()->void:
	var commands=preload("res://scripts/local_host_commands.gd").new()
	assert(commands.tree_count("大家砍树")==3)
	assert(commands.tree_count("砍5棵树")==5)
	assert(commands.tree_count("砍两棵")==2)
	assert(commands.tree_count("cut 999 trees")==100)
	var world=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json")
	world.residents.provision(world);world.hunger.start()
	var needs=preload("res://scripts/resident_needs.gd").new()
	var before=world.storage.saved()
	var candidate=needs.choose(world,"companion-2")
	assert(candidate.kind=="hungry")
	needs.delivered("companion-2","hungry",world.director.time)
	assert(needs.choose(world,"companion-2").get("kind")!="hungry")
	assert(world.storage.saved()==before and world.work.jobs.is_empty())
	for kind in needs.content:
		for tag in needs.content[kind]:
			assert(needs.content[kind][tag].zh.size()>=4 and needs.content[kind][tag].en.size()>=4)
	for kind in needs.content:
		var voices:Array=[]
		for tag in needs.content[kind]:
			assert(needs.content[kind][tag] not in voices)
			voices.append(needs.content[kind][tag])
	needs.delivered("companion-2","hungry",world.director.time,world)
	assert(needs.waiting.has("companion-2"))
	assert(needs.choose(world,"companion-2").get("kind")!="satisfied")
	needs.delivered("companion-2","satisfied",world.director.time,world)
	assert(not needs.waiting.has("companion-2"))
	commands.free()
	print("COMMAND_DELIVERY_UNIT passed")
	quit()
