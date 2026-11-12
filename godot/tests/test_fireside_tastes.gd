extends SceneTree
var checks:=0
var failed:=false
func check(ok:bool,msg:String)->void:
	checks+=1
	if not ok:failed=true;push_error(msg)
func _initialize()->void:
	var w:=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");w.residents.provision(w);w.intelligence.activate_presets()
	check(w.error.is_empty(),"new optional favorite field strict catalog loads")
	var d:RefCounted=w.life.fireside.dialogue
	var fish:Dictionary={"food_id":"fish","category":"fish","name":"烤鱼","first_time":true,"fish":{"size_id":"giant","species_id":w.fishing.rules.species[0].id}}
	var choice:Dictionary=d.selection("companion-2",fish,3)
	check(choice.pool=="bbq-lively-food-fish" and choice.favorite,"specific pool wins and blue likes fish most")
	check(choice.extra.has("bbq-lively-special-first") and choice.extra.has("bbq-lively-special-giant") and choice.extra.has("bbq-lively-special-favorite"),"real first/giant/favorite facts create explicit extra reactions")
	var apple:Dictionary={"food_id":"apple","category":"fruit","name":"烤苹果","first_time":false}
	check(d.selection("codex",apple,2).favorite and d.selection("codex",apple,2).pool=="bbq-gentle-category-fruit","white fruit preference and category fallback")
	check(not d.selection("companion-2",apple,2).favorite,"likes everything does not falsely call all foods her favorite")
	var dish:Dictionary={"food_id":"turnip-soup","category":"dish","name":"萝卜汤","first_time":false}
	check(d.selection("npc.mira",dish,2).favorite and d.selection("npc.mira",dish,2).dish,"orange prefers complete dishes")
	var mushroom:Dictionary={"food_id":"mushroom","category":"mushroom","name":"烤蘑菇","first_time":false}
	check(d.selection("npc.nora",mushroom,0).favorite and d.selection("npc.nora",mushroom,0).pool=="bbq-quiet-category-mushroom","black mushroom pool is independent")
	var original:Dictionary=w.intelligence.catalog.speech.duplicate(true)
	w.intelligence.catalog.speech.erase("bbq-gentle-category-fruit")
	apple.first_time=true;check(d.selection("codex",apple,2).pool=="bbq-gentle-special-favorite","special facts used only after specific/category absent")
	apple.first_time=false
	w.intelligence.catalog.traits.gentle.favorite_foods=[]
	check(d.selection("codex",apple,3).pool=="bbq-gentle-hunger-very-hungry","hunger is the final fallback")
	w.intelligence.catalog.speech=original
	var lines:=0
	for id in original:
		if id.begins_with("bbq-"):
			check(original[id].lines.size()>=4 and not original[id].autonomy_output,"four authored lines per pool, no autonomy wake output");lines+=0 if original[id].context.begins_with("bbq_chat_") else original[id].lines.size()
	check(lines==304,"all 304 authored taste lines available")
	var invalid:Dictionary=w.intelligence.catalog.traits.lively.duplicate(true);invalid.favorite_foods=["invented_food"]
	check(not preload("res://scripts/intelligence_catalog.gd").valid("traits",invalid),"unknown food reference rejected")
	print("Fireside tastes: ",checks," checks, failed=",failed);quit(1 if failed else 0)
