extends "res://tests/test_brain_30min.gd"
## Explicit controlled mood fixture, not claimed player history.
func compare(index:int,axis:String)->Dictionary:
 await fresh_title(index)
 var w:RefCounted=game.world
 var total:=0.0;var actions:Dictionary={};var at:Array=[]
 for tick in 1200:
  w.hearts.profile("codex").mood=w.hearts.config.baseline.duplicate(true)
  w.hearts.profile("codex").mood[axis]=90.0
  w.advance(.25)
  var b:RefCounted=w.director.brains.codex
  total+=b.distance()*.25
  var action:String=b.current.get("action","")
  actions[action]=float(actions.get(action,0))+.25
  if tick%40==0:at.append({"at":tick*.25,"distance":b.distance(),"action":action})
  if tick%240==0:await process_frame
 return {"fixture_axis":axis,"fixed_value":90,"seconds":300,"distance_mean":total/300,"seconds_by_action":actions,"timeline":at}
func run()->void:
 base_directory=OS.get_environment("HABITAT_DATA_DIR");evidence=OS.get_environment("HABITAT_HEART_EVIDENCE")
 if evidence.is_empty():evidence=base_directory
 DirAccess.make_dir_recursive_absolute(evidence)
 node_added.connect(func(node):
  if node.get_script()!=null and node.get_script().resource_path=="res://scripts/main.gd":node.set_process(false);node.dialogue_adapter_factory=func(_id,_scope):return Fake.new())
 var joy:Dictionary=await compare(11,"joy")
 var budget:Array=[]
 for language in ["zh","en"]:
  TranslationServer.set_locale(language)
  var card:Dictionary=game.autonomy.heart_card("codex")
  var persona:Dictionary=preload("res://scripts/persona_cards.gd").card("codex")
  var instructions:String=FileAccess.get_file_as_string("res://content/connection-instructions.txt")
  var messages:Array=[{"role":"system","content":instructions+"\nFixed resident persona:\n"+str(persona.text)},{"role":"user","content":JSON.stringify({"card":card,"chat":"Choose your current intention from heart_request.available; return heart JSON. Do not issue resource actions."})}]
  var serialized:String=JSON.stringify(messages);var nonascii:=0
  for point in serialized.length():
   if serialized.unicode_at(point)>127:nonascii+=1
  budget.append({"language":language,"card_utf8_bytes":JSON.stringify(card).to_utf8_buffer().size(),"complete_messages_utf8_bytes":serialized.to_utf8_buffer().size(),"chars":serialized.length(),"conservative_estimated_tokens":int(ceil(float(serialized.length()-nonascii)/4))+nonascii,"method":"ASCII/4 + one per non-ASCII character; estimate, not provider tokenizer"})
 game.queue_free();await process_frame
 TranslationServer.set_locale("zh")
 var hurt:Dictionary=await compare(12,"hurt")
 var f:=FileAccess.open(evidence.path_join("heart-metrics.json"),FileAccess.WRITE);f.store_string(JSON.stringify({"mood_comparison":{"joy":joy,"hurt":hurt},"card_budget":budget},"\t"));f.close()
 print("HEART_METRICS ",checks," failed=",failed," joy=",joy.distance_mean," hurt=",hurt.distance_mean)
 game.queue_free();await process_frame;quit(1 if failed else 0)
