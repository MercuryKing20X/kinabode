extends SceneTree
const World=preload("res://scripts/world_state.gd")
const Data=preload("res://scripts/intelligence_catalog.gd")
var checks:=0
var failed:=false
func check(ok:bool,msg:String)->void:
	checks+=1
	if not ok:failed=true;push_error(msg)
func _initialize()->void:call_deferred("run")
func run()->void:
	var w:=World.new();w.residents.provision(w)
	check(w.error.is_empty(),"intelligence config loads")
	var old:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/personalities.json"))
	check(w.personality.config==old,"migrated profile projection is exactly equal")
	var residents:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/residents.json"))
	for actor in residents.residents:
		if actor.role=="human":continue
		check(w.residents.definitions[actor.id].preferences==actor.preferences,actor.id+" exact preferences")
		check(w.intelligence.preset(actor.id).main_trait is String,actor.id+" independent preset")
	var invalid:Dictionary=w.intelligence.catalog.traits.gentle.duplicate(true);invalid["unknown"]=true
	check(not Data.valid("traits",invalid),"unknown field rejected")
	invalid=w.intelligence.catalog.traits.gentle.duplicate(true);invalid.hunger_multiplier=true
	check(not Data.valid("traits",invalid),"bool cannot be a number")
	var before:Dictionary=w.actors.codex.duplicate(true);var memory:Dictionary=w.memories.saved();var rel:Dictionary=w.relationships.saved()
	check(w.intelligence.assign("codex","resident-blue"),"host can assign preset")
	check(w.actors.codex==before and w.memories.saved()==memory and w.relationships.saved()==rel,"assignment preserves resident identity and history")
	check(not w.intelligence.assign("human","resident-blue"),"human intelligence assignment rejected")
	print("Intelligence migration: ",checks," checks, failed=",failed);quit(1 if failed else 0)
