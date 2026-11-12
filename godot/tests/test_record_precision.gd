extends SceneTree
func _initialize()->void:
	var directory:String=OS.get_environment("HABITAT_DATA_DIR");assert(directory.contains("youqi-test-"))
	DirAccess.make_dir_recursive_absolute(directory)
	var P=preload("res://scripts/resident_intelligence_preferences.gd");var R=preload("res://scripts/autonomy_records.gd")
	var prefs=P.new();prefs.setup(directory,"precision");var records=R.new(prefs)
	var at:=1793506048.125
	records.start("codex","real-test",[],at,100)
	var restored=P.new();restored.setup(directory,"precision");var read=R.new(restored)
	assert(read.read("codex").turns[0].at==at)
	prefs.settings.set_value(prefs.section("codex"),"autonomy_records",{"turns":[{"at":1793506000.0}],"gates":[],"notice_day":-1})
	assert(records.read("codex").turns[0].at==1793506000.0)
	print("Timestamp exact decimal roundtrip and legacy float read passed");quit()
