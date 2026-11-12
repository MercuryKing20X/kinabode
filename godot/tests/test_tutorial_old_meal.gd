extends "res://tests/test_standard_opening.gd"
## Explicit isolated replica of retained canonical meal facts, not a playthrough.
func run()->void:
	var dir:String=OS.get_environment("HABITAT_DATA_DIR")
	var w:RefCounted=fresh(dir)
	check(Opening.apply(w,w.library,"standard").ok,"replica standard")
	w.standard.tutorial_step=3
	var roster:Array=w.standard.config.companions.duplicate()
	var foods:Dictionary={}
	for id in roster:foods[id]=[{"food_id":"mushroom","name":"烤蘑菇","category":"mushroom","first_time":true,"first_time_known":true}]
	var source:String="0123456789abcdef01234567"
	check(w.memories.record_event("shared_barbecue",source,roster,{"version":2,"activity_id":source,"station_id":"home.barbecue","place_id":"home","attended":roster,"consumed_by":roster,"foods":foods,"roles":{"light":"codex","roast":"codex"}}),"valid retained four-person meal")
	check(Save.save_world(w,dir.path_join("old")),"replica saves empty first meal")
	var loaded:RefCounted=fresh(dir.path_join("reload"))
	check(Save.load_world(loaded,dir.path_join("old")).ok,"replica reload")
	var count:int=loaded.memories.records.size()
	loaded.standard.advance(.1)
	check(loaded.standard.first_meal==source,"DIRECTION: companions suffice without human")
	check(loaded.memories.records.size()==count,"old proof adds no replayed memory")
	print("OLD_MEAL ",checks," failed=",failed);quit(1 if failed else 0)
