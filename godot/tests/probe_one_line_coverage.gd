extends SceneTree
func _initialize()->void:
	var w:=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");w.residents.provision(w)
	var parser:=preload("res://scripts/farm_commands.gd").new()
	var source:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://../production/evidence/2026-11-05-智能一句话与跟随/coverage-cases.json"))
	if not source is Array or source.is_empty():
		push_error("Missing or invalid command-coverage fixture; set HABITAT_PRIVATE_TEST_FIXTURES for this suite")
		quit(2);return
	var rows:Array=source
	var counts:Dictionary={};var failures:Array=[]
	for row in rows:
		var result:Dictionary=parser.parse_command(w,row.text)
		var expected:String="ready" if row.meaning=="sequence" else row.meaning
		row["parsed"]=result.get("ok",false) and result.get("action")==expected
		row["actual_action"]=result.get("action","")
		if row.parsed:counts[row.meaning]=int(counts.get(row.meaning,0))+1
		else:row["reason"]="parser does not resolve the expected action";failures.append(row.id)
	var output:Dictionary={"total":rows.size(),"parsed_counts":counts,"failed_ids":failures,"executed_in_this_probe":0,"rows":rows}
	var file:=FileAccess.open("/tmp/youqi-one-line-coverage.json",FileAccess.WRITE);file.store_string(JSON.stringify(output,"  "));file.close()
	print("COVERAGE_DIAGNOSTIC total=",rows.size()," parse_failures=",failures.size()," execution=not_run");quit()
