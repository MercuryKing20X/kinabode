extends SceneTree
const World=preload("res://scripts/world_state.gd")
func _initialize()->void:
	var output:Array=[]
	for follow in [false,true]:
		for baseline in [true,false]:
			var w:=World.new("res://content/home-v3/world.json");w.residents.provision(w);w.intelligence.activate_presets();w.hunger.start()
			for id in w.director.routines:
				var r:RefCounted=w.director.routines[id];r.enabled=true;r.chatter=true;r.rng.seed=42+hash(id)
				if baseline:r.config=r.config.duplicate(true);r.config.speech_interval=[32.0,55.0]
			if baseline:w.director.moods.config=w.director.moods.config.duplicate(true);w.director.moods.config.village_gap=14.0
			if baseline:
				for observer in [w.hunger,w.days,w.personality,w.relationships,w.wishes,w.fishing.life]:
					observer.config=observer.config.duplicate(true)
					for key in ["personal_gap","village_gap"]:
						if observer.config.has(key):observer.config[key]=float(observer.config[key])*2
			if follow:w.activities.set_followers(w.actors.keys().filter(func(id):return id!="human"))
			var counts:Dictionary={};var times:Array=[];var seen:int=0
			for tick in 6000:
				w.advance(.1)
				for event in w.director.events:
					if event.serial<=seen:continue
					seen=event.serial;counts[event.actor_id]=int(counts.get(event.actor_id,0))+1;times.append(event.time)
			output.append({"baseline":baseline,"follow":follow,"seconds":600,"count":times.size(),"per_actor":counts,"seconds_per_line":600.0/maxi(1,times.size())})
	var file:=FileAccess.open("/tmp/youqi-one-line-speech-observation.json",FileAccess.WRITE);file.store_string(JSON.stringify(output,"  "));file.close()
	print("SPEECH_OBSERVATION ",JSON.stringify(output));quit()
