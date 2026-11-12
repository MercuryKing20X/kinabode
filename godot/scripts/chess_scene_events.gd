extends RefCounted
## Visual reactions to public board facts. Never moves actors or changes game state.
static func hand(scene:Control,world:RefCounted,opponent:String,number:int,human_turn:bool,mover:String,event:String="move")->void:
	var dramatic:bool=event in ["big_self","big_you","capture_big","capture_hidden","chaos_opposite","chaos_selfcheck","check_self","check_you","threat","nearwin","nearlose"]
	var human_pose:String="thinking" if human_turn else "watch"
	if event in ["capture_you","goodmove"]:human_pose="happy"
	elif event in ["capture_self","check_you","chaos_selfcheck","nearwin"]:human_pose="tense"
	elif event=="nearlose":human_pose="proud"
	elif event in ["big_self","big_you","chaos_opposite"]:human_pose="surprised"
	elif number>0 and number%6==0 and mover=="human":human_pose="proud"
	scene.set_actor_pose("human",human_pose)
	for id in scene.companion_ids:
		if id==opponent:continue
		var tag:String=str(world.personality.tag(id))
		var mapping:Dictionary={"lively":"playful","laborious":"diligent"}
		if world.intelligence.compatibility:mapping={"curious":"playful","lively":"diligent"}
		tag=str(mapping.get(tag,tag))
		var action:String="watch"
		match tag:
			"playful":action="clap" if dramatic else "cheer" if number%3 else "surprised"
			"gentle":action="surprised" if dramatic else "thinking" if number%3 else "watch"
			"diligent":action="tense" if dramatic else "thinking" if number%3 else "cheer"
			"quiet":action="surprised" if dramatic else "yawn" if number%5==0 else "thinking" if number%3==0 else "watch"
		if world.hunger.rank(id)>=2:action="hunger"
		scene.set_actor_pose(id,action)
static func result(scene:Control,world:RefCounted,opponent:String,outcome:String)->void:
	scene.set_actor_pose("human","happy" if outcome=="win" else "sad" if outcome=="lose" else "thinking")
	for id in scene.companion_ids:
		var action:String="happy" if outcome=="lose" else "sad" if id==opponent and outcome=="win" else "clap" if outcome=="win" else "thinking"
		if world.hunger.rank(id)>=2 and id!=opponent:action="hunger"
		scene.set_actor_pose(id,action)

static func hunger(scene:Control,world:RefCounted,chatter:RefCounted,seen:Dictionary,opponent:String)->void:
	for id in scene.companion_ids:
		var rank:int=world.hunger.rank(id)
		if seen.has(id) and rank>int(seen[id]):
			scene.set_actor_pose(id,"hunger")
			chatter.request({"actor_id":id,"audience":id!=opponent,"category":"hunger","action":"hunger","priority":2})
		seen[id]=rank
		if rank>=2 and scene.actor_views[id].pose_time<=0:scene.set_actor_pose(id,"hunger")
