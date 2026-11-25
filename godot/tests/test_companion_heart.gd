extends SceneTree
const W=preload("res://scripts/world_state.gd")
const S=preload("res://scripts/save_store.gd")
var checks:=0
var failed:=false
func check(on:bool,label:String)->void:
	checks+=1
	if not on:failed=true;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):quit(1);return
	var world:=W.new();world.residents.provision(world);world.director.set_all_enabled(false)
	var hearts:RefCounted=world.hearts
	check(hearts.mood("codex").size()==6,"all companions have the six life axes even offline")
	var speed:float=world.movement_speed("codex");var relationship:Variant=world.relationships.saved().duplicate(true)
	check(hearts.change("codex",{"joy":999},"favorite",true),"AI mood accepted as bounded presentation delta")
	check(hearts.mood("codex").joy==58,"AI change clamped to configured8")
	var before:Dictionary=hearts.mood("codex")
	check(not hearts.change("codex",{"joy":NAN},"bad") and hearts.mood("codex")==before,"NaN whole delta rejected atomically")
	hearts.change("codex",{"joy":25},"favorite")
	check(hearts.choice_score("codex","follow")>0,"happy makes social choice more attractive")
	hearts.change("npc.nora",{"hurt":25},"rejected");hearts.change("npc.nora",{"hurt":25},"rejected")
	check(hearts.choice_score("npc.nora","follow")<0 and hearts.choice_score("npc.nora","sea_watch")>0,"hurt favors solitude over approach")
	hearts.change("companion-2",{"tired":25},"work")
	check(hearts.choice_score("companion-2","local_sit")>0,"tired favors original resting executor")
	check(world.movement_speed("codex")==speed and world.relationships.saved()==relationship,"feelings do not change physical speed or relation scores")
	var old:float=hearts.mood("codex").joy;world.advance(1)
	check(hearts.mood("codex").joy<old,"real delta slowly returns toward baseline")
	var path:String=OS.get_environment("HABITAT_DATA_DIR").path_join("heart")
	var saved:Dictionary=hearts.saved()
	check(S.save_world(world,path),"optional schema7 heart save")
	var restored:=W.new();restored.residents.provision(restored)
	check(S.load_world(restored,path).ok,"reload saved hearts")
	check(restored.hearts.saved()==saved,"exact feelings and reasons survive reload")
	var copy:Dictionary=hearts.saved();copy.profiles.codex.mood.joy=INF
	check(not hearts.valid(copy,world.actors),"nonfinite save rejected")
	copy=hearts.saved();copy.profiles.codex.extras={"mushrooms":{"day":1,"count":3}}
	check(hearts.valid(copy,world.actors),"bounded daily mushroom counts persist")
	copy.profiles.codex.extras.mushrooms.count=1.5
	check(not hearts.valid(copy,world.actors),"fractional count rejected")
	TranslationServer.set_locale("en");check(hearts.summary("codex").name=="happy","English mood labels")
	TranslationServer.set_locale("zh");check(hearts.summary("codex").reason=="吃到了喜欢的料理","Chinese factual mood reason")
	print("Companion heart: %d checks failed=%s"%[checks,failed]);quit(1 if failed else 0)
