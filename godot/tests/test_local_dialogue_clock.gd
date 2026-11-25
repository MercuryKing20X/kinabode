extends SceneTree
const W=preload("res://scripts/world_state.gd")
const F=preload("res://tests/cooking_fixture.gd")
class NoNeeds extends "res://scripts/resident_needs.gd":
	func choose(_world:RefCounted,_id:String)->Dictionary:return {}
class NoScenes extends "res://scripts/scene_speech.gd":
	func choose(_id:String)->Dictionary:return {}
var checks:=0
var failed:=false
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failed=true;push_error(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"))
	var w:=W.new()
	# Advance real time with the resident disabled; this is a clock-boundary unit,
	# independent from the separate600-second real viewport observation.
	w.advance(90)
	w.activities.default_follow_excluded.codex=true
	w.local_companion.set_enabled(true)
	var dialogue:RefCounted=w.director.local_dialogue
	dialogue.next_check=w.director.time
	var before:int=w.director.serial
	var speech_rng:int=w.local_companion.rng.state
	var action_rng:int=w.local_companion.decision_rng.state
	var scale:float=w.director.moods.interval("codex","speech")*w.personality.speech_scale("codex")
	dialogue.advance(1,false)
	check(dialogue.spoken_ready and dialogue.try_spoken() and w.director.serial==before+1,"one positive tick can deliver one genuinely eligible authored line")
	var gap:float=w.local_companion.next_speech-w.local_companion.time
	check(w.local_companion.rng.state==speech_rng and gap>=float(w.local_companion.config.speech_interval[0])*scale and gap<=float(w.local_companion.config.speech_interval[1])*scale,"actual new spoken line keeps original authored cadence and leaves the old speech RNG untouched")
	check(w.local_companion.decision_rng.state==action_rng,"new presentation cadence cannot consume the original movement RNG")
	var new_cadence:RandomNumberGenerator=dialogue.cadence_rngs.codex.rng
	var new_state:int=new_cadence.state
	var initial_cadence:=RandomNumberGenerator.new();initial_cadence.seed=w.local_companion.rng.seed
	check(new_state!=initial_cadence.state,"actual accepted delivery samples its own original-seed presentation stream")
	speech_rng=w.local_companion.rng.state
	check(not dialogue.spoken_ready and not dialogue.try_spoken() and w.director.serial==before+1,"a consumed spoken opportunity cannot be retried in the same advance")
	check(w.local_companion.rng.state==speech_rng,"consumed opportunity rejects without spending resident speech RNG")
	dialogue.spoken_ready=true
	before=w.director.serial
	dialogue.advance(0,false)
	check(not dialogue.spoken_ready and not dialogue.try_spoken() and w.director.serial==before,"advance zero clears stale opportunity and delivers no new spoken line")
	dialogue.next_check=INF
	dialogue.spoken_opportunity=true
	dialogue.advance(1,false)
	check(not dialogue.spoken_ready and not dialogue.try_spoken() and w.director.serial==before,"original optional-layer next-check isolation suppresses spoken as well as thoughts")
	dialogue.next_check=w.director.time
	dialogue.advance(1,false)
	w.local_companion.set_held(true)
	check(not dialogue.try_spoken() and not dialogue.spoken_ready and not dialogue.try_spoken() and w.director.serial==before,"a rejected held attempt consumes the opportunity without delivery or retry")
	check(not dialogue.spoken_opportunity,"a rejected attempt consumes the retained opportunity rather than retrying every frame")
	check(is_same(dialogue.cadence_rngs.codex.rng,new_cadence) and new_cadence.state==new_state,"all consumed, zero-delta, INF and held rejections leave the presentation RNG undrawn and unreplaced")
	print("Local dialogue clock boundaries: ",checks," failed=",failed);quit(1 if failed else 0)
