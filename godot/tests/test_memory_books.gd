extends SceneTree
const Books=preload("res://scripts/memory_books.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var dir:String=OS.get_environment("HABITAT_DATA_DIR");assert(dir.contains("youqi-"))
	var b:=Books.new();assert(b.setup(dir))
	assert(b.add("companion-2","world-old","real-event","facts","A true meal",{},2,"game",["human","companion-2"]))
	assert(not b.add("companion-2","world-old","real-event","facts","duplicate"))
	b.remember_chat("companion-2","world-old","chat-1","我喜欢下雨",2)
	var before:int=b.entries.size();assert(before==3)
	assert(b.export_data(dir.path_join("export.json")))
	var other:=Books.new();assert(other.setup(dir.path_join("import")))
	assert(other.import_data(dir.path_join("export.json")).ok);assert(other.entries.size()==before)
	assert(other.import_data(dir.path_join("export.json")).count==0)
	var tamper:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("export.json")));tamper.payload+=" "
	assert(b.atomic(dir.path_join("bad.json"),tamper));assert(not other.import_data(dir.path_join("bad.json")).ok)
	assert(b.export_html(dir.path_join("album.html"),false));assert(not FileAccess.get_file_as_string(dir.path_join("album.html")).contains("我喜欢下雨"))
	# Selected imports must not silently fall back to an older export beside a damaged file.
	assert(b.atomic(dir.path_join("invalid.json"),JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("export.json")))))
	assert(b.atomic(dir.path_join("invalid.json"),JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("export.json")))))
	var invalid:=FileAccess.open(dir.path_join("invalid.json"),FileAccess.WRITE);invalid.store_string("{");invalid.close()
	assert(not other.import_data(dir.path_join("invalid.json")).ok)
	var id:String=b.list_for("companion-2","facts")[0].id;assert(b.remove(id));assert(not JSON.stringify(b.card("companion-2")).contains(id))
	var reloaded:=Books.new();assert(reloaded.setup(dir));assert(reloaded.entries.size()==before-1);assert(not reloaded.entries.has(id))
	var e:Dictionary=reloaded.entries.values()[0];assert(reloaded.atomic(dir.path_join(e.id+".entry.json"),e))
	var file:=FileAccess.open(dir.path_join(e.id+".entry.json"),FileAccess.WRITE);file.store_string("broken");file.close()
	var recovered:=Books.new();assert(recovered.setup(dir));assert(recovered.entries.has(e.id))
	var raw_id:String="source-for-compression"
	assert(b.add("codex","test-world",raw_id,"facts","a longer original quotation",{"human_quote":true,"channel":"direct:codex"},4,"local",["human","codex"]))
	var old:Dictionary=b.list_for("codex","facts")[-1]
	assert(b.archive_quote(old));assert(not b.entries.has(old.id))
	var summary:Dictionary=b.list_for("codex","daily")[-1]
	assert(summary.params.quotes.has(old.id));assert(not JSON.stringify(b.card("codex","","group:all")).contains("quotation"))
	assert(b.remove(old.id));assert(not b.entries.has(summary.id))
	print("MEMORY_BOOKS_PASS count=",before," roundtrip/deletion/tamper/recovery/html")
	quit()
