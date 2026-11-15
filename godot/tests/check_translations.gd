extends SceneTree

func _initialize() -> void:
	var errors: Array[String] = []
	var zh := {};var en := {};var covered := {}
	for path in _files("res://content/i18n", ".csv"):
		var csv:=FileAccess.open(path,FileAccess.READ)
		if csv==null:errors.append("Missing translation CSV: "+path);continue
		var header:=csv.get_csv_line()
		if header!=PackedStringArray(["keys","zh","en"]):errors.append("Invalid locale columns: "+path)
		var row_number:=1
		while not csv.eof_reached():
			var fields:=csv.get_csv_line();row_number+=1
			if fields.size()==1 and fields[0].is_empty():continue
			if fields.size()!=3:errors.append("Malformed translation row %s:%d"%[path,row_number]);continue
			if fields[0].is_empty() or zh.has(fields[0]):errors.append("Empty/duplicate key: "+fields[0])
			if fields[1].is_empty() or fields[2].is_empty():errors.append("Missing locale value: "+fields[0])
			zh[fields[0]]=fields[1];en[fields[0]]=fields[2]
			if fields[0].begins_with("content.") or fields[0].begins_with("resident."):covered[fields[1]]=true
			if _placeholders(fields[1])!=_placeholders(fields[2]):errors.append("Placeholder mismatch: "+fields[0])
	if zh.is_empty():errors.append("No translation keys loaded")
	var fixture_errors:Array[String]=[]
	_check_content({"zh":"故意缺少译文"},"negative-fixture",{},fixture_errors)
	if fixture_errors.is_empty():errors.append("Missing-translation negative fixture was not detected")
	var scripts := _files("res://scripts", ".gd")
	for path in scripts:
		var source := FileAccess.get_file_as_string(path)
		for line_no in range(source.split("\n").size()):
			var line: String = source.split("\n")[line_no]
			if line.strip_edges().begins_with("#"): continue
			if _untranslated_literal(line) and not _inline_bilingual(line): errors.append("Untranslated CJK: %s:%d" % [path, line_no + 1])
	var content := _files("res://content", ".json")
	for path in content:
		if path.contains("/i18n/"): continue
		var source := FileAccess.get_file_as_string(path)
		_check_content(JSON.parse_string(source),path,covered,errors)
	for error in errors: push_error(error)
	var report:=OS.get_environment("HABITAT_TRANSLATION_REPORT")
	if not report.is_empty():FileAccess.open(report,FileAccess.WRITE).store_string(JSON.stringify({"keys":zh.size(),"errors":errors},"  "))
	print("Translation check: %d keys, %d errors" % [zh.size(), errors.size()])
	quit(1 if not errors.is_empty() else 0)

func _contains_cjk(text: String) -> bool:
	for i in text.length():
		var code := text.unicode_at(i)
		if code >= 0x3400 and code <= 0x9fff: return true
	return false

func _untranslated_literal(line: String) -> bool:
	var quote := "";var literal := "";var escaped := false
	for i in line.length():
		var char := line.substr(i,1)
		if quote.is_empty():
			if char=="#":break
			if char in ["\"", "'"]:quote=char;literal=""
		elif escaped:literal+=char;escaped=false
		elif char=="\\":escaped=true
		elif char==quote:
			if _contains_cjk(literal):return true
			quote=""
		else:literal+=char
	return false

func _placeholders(text: String) -> Array[String]:
	var result: Array[String] = []; var regex := RegEx.new(); regex.compile("%[-+0-9.]*[sdif]|\\{[A-Za-z_][A-Za-z_0-9]*\\}")
	for match in regex.search_all(text): result.append(match.get_string())
	result.sort()
	return result

func _files(root: String, extension: String) -> Array[String]:
	var result: Array[String] = []; var dir := DirAccess.open(root)
	if dir == null: return result
	dir.list_dir_begin()
	var item := dir.get_next()
	while not item.is_empty():
		var path := root.path_join(item)
		if dir.current_is_dir(): result.append_array(_files(path, extension))
		elif item.ends_with(extension): result.append(path)
		item = dir.get_next()
	dir.list_dir_end(); return result

func _check_content(value:Variant,path:String,covered:Dictionary,errors:Array[String])->void:
	if value is String:
		if _contains_cjk(value) and not covered.has(value):errors.append("Untranslated content: "+path+": "+value)
	elif value is Array:
		if value.size()==2 and value[0] is String and value[1] is String and _contains_cjk(value[0]) and not _contains_cjk(value[1]) and not value[1].is_empty():
			if _placeholders(value[0])!=_placeholders(value[1]):errors.append("Placeholder mismatch: "+path)
			return
		for index in range(value.size()):_check_content(value[index],path+"["+str(index)+"]",covered,errors)
	elif value is Dictionary:
		if value.has("zh") and value.has("en"):
			var z:Variant=value.zh;var e:Variant=value.en
			if z is String and e is String and not e.is_empty() and not _contains_cjk(e):
				if _placeholders(z)!=_placeholders(e):errors.append("Placeholder mismatch: "+path)
			elif z is Array and e is Array and z.size()==e.size() and not e.is_empty():
				for i in z.size():_check_content([z[i],e[i]],path+".zh["+str(i)+"]",covered,errors)
			else:errors.append("Missing bilingual value: "+path)
			for key in value:
				if key not in ["zh","en"]:_check_content(value[key],path+"."+str(key),covered,errors)
			return
		for key in value:
			_check_content(key,path+".key",covered,errors)
			_check_content(value[key],path+"."+str(key),covered,errors)

func _inline_bilingual(line:String)->bool:
	# Only explicit paired literals / localized-input comparisons count, not arbitrary ASCII.
	var pairs:=RegEx.new()
	pairs.compile("[\"']([^\"']+)[\"']\\s*,\\s*[\"']([^\"']+)[\"']")
	var remainder:=line
	for m in pairs.search_all(line):
		if _contains_cjk(m.get_string(1)) and not _contains_cjk(m.get_string(2)) and not m.get_string(2).is_empty():remainder=remainder.replace(m.get_string(),"PAIR")
	if not _untranslated_literal(remainder):return true
	return line.contains("text.contains(") and line.contains("text.to_lower()")
