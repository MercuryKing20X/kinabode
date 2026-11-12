extends SceneTree
const World=preload("res://scripts/world_state.gd")
const Parser=preload("res://scripts/farm_commands.gd")
var failed:=false
var checks:=0
func check(okay:bool,label:String)->void:
	checks+=1
	if not okay:failed=true;push_error(label)
func _initialize()->void:
	var w:=World.new("res://content/home-v3/world.json");w.residents.provision(w);var p:=Parser.new()
	var before:Dictionary=w.storage.saved();var actors:Dictionary=w.actors.duplicate(true)
	for text in ["全部去种菜","你们都去把地种了","大家去种地","你们都去收菜","所有人跟我来","大家别跟了","大家到营火集合","所有人去南岛集合","everyone plant turnips","all of you harvest","allofyou follow me"]:
		var parsed:Dictionary=p.parse_command(w,text)
		check(parsed.get("ok",false) and parsed.actor_ids.size()==w.actors.size()-1,"all recipients pure parse "+text)
	var pair:Dictionary=p.parse_command(w,"小蓝和小橙去种萝卜")
	check(pair.get("ok",false) and pair.actor_ids==["companion-2","npc.mira"] and pair.crop_id=="turnip","named Chinese pair")
	var english:Dictionary=p.parse_command(w,"Skye and Clem plant turnips")
	check(english.get("ok",false) and english.actor_ids==["companion-2","npc.mira"] and english.crop_id=="turnip","English canonical names and plural crop")
	check(not p.parse_command(w,"大家帮我种香蕉").get("ok",true),"unknown crop never silently becomes mixed")
	check(w.storage.saved()==before and w.actors==actors and w.work.jobs.is_empty() and w.farms.host_grants.is_empty(),"parse has no jobs stock identity or authority mutation")
	w.actors["npc.mira"].name="橘灯"
	var custom:Dictionary=p.parse_command(w,"小蓝和橘灯一起去收菜")
	check(custom.actor_ids==["companion-2","npc.mira"] and custom.action=="ready","custom resident name")
	w.actors["npc.mira"].name="Amber"
	check(p.parse_command(w,"Amber follow me").actor_ids==["npc.mira"],"custom English name")
	check(p.parse_command(w,"Amberly follow me",["codex"]).actor_ids==["codex"],"English name whole word boundary")
	check(p.parse(w,"帮我种萝卜").get("ok",false),"old single parser remains supported")
	var sequence:Dictionary=p.parse_command(w,"小蓝小橙去收菜，收完来营火")
	check(sequence.get("ok",false) and sequence.action=="ready" and sequence.get("next_text")=="到营火","two steps preserve first action and follow-up")
	var excluded:Dictionary=p.parse_command(w,"除了阿黑大家跟我来")
	check(excluded.get("ok",false) and "npc.nora" not in excluded.actor_ids and excluded.actor_ids.size()==3,"excluded resident stays out")
	for row in [["去砍树","chop"],["去种菜","plant"],["过来","follow"],["跟我走","follow"],["你在干嘛","query_state"],["come here","follow"],["plant vegetables","plant"]]:
		var parsed:Dictionary=p.parse_command(w,row[0],["codex"])
		check(parsed.get("ok",false) and parsed.action==row[1],"common phrase "+row[0])
	print("LOCAL_HOST_PARSE ",checks," failed=",failed);quit(1 if failed else 0)
