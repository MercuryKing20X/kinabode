extends SceneTree
const Glyphs=preload("res://tests/ui_glyph_audit.gd")
const Text=preload("res://scripts/localization.gd")

func _initialize() -> void:
	var errors: Array[String] = []
	var zh := {};var en := {};var covered := {}
	var compiled_paths:PackedStringArray=ProjectSettings.get_setting("internationalization/locale/translations",PackedStringArray())
	for path in _files("res://content/i18n", ".csv"):
		var csv:=FileAccess.open(path,FileAccess.READ)
		if csv==null:errors.append("Missing translation CSV: "+path);continue
		var header:=csv.get_csv_line()
		if header!=PackedStringArray(["keys","zh","en"]):errors.append("Invalid locale columns: "+path)
		var row_number:=1
		var resources:Array=[]
		while not csv.eof_reached():
			var fields:=csv.get_csv_line();row_number+=1
			if fields.size()==1 and fields[0].is_empty():continue
			if fields.size()!=3:errors.append("Malformed translation row %s:%d"%[path,row_number]);continue
			if resources.is_empty():
				for locale in ["zh","en"]:
					var compiled:String=path.trim_suffix(".csv")+"."+locale+".translation"
					if compiled not in compiled_paths:errors.append("Unregistered translation: "+compiled)
					resources.append(load(compiled) if ResourceLoader.exists(compiled) else null)
			for index in resources.size():
				if resources[index]==null or resources[index].get_message(fields[0])!=fields[index+1]:
					errors.append("Compiled translation differs from CSV: %s:%d:%s"%[path,row_number,header[index+1]])
			if fields[0].is_empty() or zh.has(fields[0]):errors.append("Empty/duplicate key: "+fields[0])
			if fields[1].is_empty() or fields[2].is_empty():errors.append("Missing locale value: "+fields[0])
			for index in [1,2]:Glyphs.check(fields[index],"%s:%d:%s"%[path,row_number,header[index]],errors)
			zh[fields[0]]=fields[1];en[fields[0]]=fields[2]
			if fields[0].begins_with("content.") or fields[0].begins_with("resident."):covered[fields[1]]=true
			if _placeholders(fields[1])!=_placeholders(fields[2]):errors.append("Placeholder mismatch: "+fields[0])
	if zh.is_empty():errors.append("No translation keys loaded")
	var fixture_errors:Array[String]=[]
	_check_content({"zh":"故意缺少译文"},"negative-fixture",{},fixture_errors)
	if fixture_errors.is_empty():errors.append("Missing-translation negative fixture was not detected")
	fixture_errors.clear()
	_check_content([["缺英译"],[""]],"negative-parallel-list",{},fixture_errors)
	if fixture_errors.is_empty():errors.append("Missing parallel English line was not detected")
	var scripts := _files("res://scripts", ".gd")
	var references:Dictionary={}
	var literal:=RegEx.new()
	literal.compile("\\bT\\(\\s*[\"']([A-Za-z0-9_.-]+)[\"']\\s*\\)")
	for path in scripts:
		Glyphs.scripts(path,errors)
		var source := FileAccess.get_file_as_string(path)
		var lines:=source.split("\n")
		for line_no in range(lines.size()):
			var line: String = lines[line_no]
			if line.strip_edges().begins_with("#"): continue
			for match in literal.search_all(line):
				references[match.get_string(1)]="%s:%d"%[path,line_no+1]
			var next:String=lines[line_no+1] if line_no+1<lines.size() else ""
			if _untranslated_literal(line) and not _inline_bilingual(line) and not _split_bilingual(line,next): errors.append("Untranslated CJK: %s:%d" % [path, line_no + 1])
	Text.ensure()
	for key in references:
		if not zh.has(key):
			errors.append("Missing literal translation %s: %s"%[key,references[key]])
			continue
		for locale in ["zh_CN","en"]:
			TranslationServer.set_locale(locale)
			var expected:String=zh[key] if locale=="zh_CN" else en[key]
			if Text.text(key)!=expected:errors.append("Wrong runtime translation %s (%s)"%[key,locale])
	TranslationServer.set_locale("zh_CN")
	var content := _files("res://content", ".json")
	for path in content:
		if path.contains("/i18n/"): continue
		var source := FileAccess.get_file_as_string(path)
		var value:Variant=JSON.parse_string(source)
		if path.contains("/personas/") and path.ends_with(".zh.json"):
			var english:Variant=JSON.parse_string(FileAccess.get_file_as_string(path.trim_suffix(".zh.json")+".en.json"))
			if not value is Dictionary or not english is Dictionary or not value.get("sections") is Array or not english.get("sections") is Array:
				errors.append("Missing English persona: "+path)
				continue
			var sections:Array=value.sections
			var equivalents:Array=english.sections
			if sections.size()!=equivalents.size():errors.append("Mismatched persona sections: "+path)
			else:
				for i in sections.size():_check_content([sections[i],equivalents[i]],path+".sections["+str(i)+"]",covered,errors)
			continue
		_check_content(value,path,covered,errors)
	for error in errors: push_error(error)
	var report:=OS.get_environment("HABITAT_TRANSLATION_REPORT")
	if not report.is_empty():FileAccess.open(report,FileAccess.WRITE).store_string(JSON.stringify({"keys":zh.size(),"errors":errors},"  "))
	print("Translation check: %d keys, %d literal T keys, %d errors" % [zh.size(),references.size(),errors.size()])
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
		if value.size()==2 and value[0] is Array and value[1] is Array and not value[0].is_empty() and value[0].size()==value[1].size() and value[0].all(func(line):return line is String) and value[1].all(func(line):return line is String) and value[0].any(func(line):return _contains_cjk(line)) and value[1].all(func(line):return not line.is_empty() and not _contains_cjk(line)):
			for i in value[0].size():
				if _placeholders(value[0][i])!=_placeholders(value[1][i]):errors.append("Placeholder mismatch: "+path+"["+str(i)+"]")
			return
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
			if not (path=="res://content/flower-glyphs.json.font" and str(key).length()==1 and value[key] is String and str(value[key]).replace("0","").replace("1","").replace("/","").is_empty()):
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
	var literals:=RegEx.new()
	literals.compile("[\"']([^\"']+)[\"']")
	var tokens:=literals.search_all(line)
	var latin:=RegEx.new();latin.compile("[A-Za-z]{2}")
	var has_english:bool=tokens.any(func(m):return not _contains_cjk(m.get_string(1)) and latin.search(m.get_string(1))!=null)
	if " else " in line and (" if en " in line or " if english " in line or 'if locale=="zh"' in line or "begins_with(\"en\")" in line) and has_english:return true
	if '"zh":' in line and '"en":' in line and has_english:return true
	if tokens.any(func(m):return " / " in m.get_string(1) and _contains_cjk(m.get_string(1).get_slice(" / ",0)) and latin.search(m.get_string(1).get_slice(" / ",1))!=null):return true
	if " else " in line and "%" in line and has_english and (".phrase([" in line or "lines.append([" in line):return true
	if ("lines.append([" in line or "Outing.phrase([" in line) and "%" in line and has_english and tokens.size()==2 and _placeholders(tokens[0].get_string(1))==_placeholders(tokens[1].get_string(1)):return true
	if "regex.compile(" in line and tokens.size()==1 and "A-Za-z" in line and "(?:" in line and "|" in line:return true
	if ("text.to_lower()" in line or "lower.contains(" in line or "regex.compile(" in line) and (".contains(" in line or " in [" in line or ".any(" in line or "regex.compile(" in line) and has_english:return true
	if ("begins_with(\"en\")" in line or "begins_with(\"zh\")" in line) and " else " in line:
		var choices:=RegEx.new()
		choices.compile("[\"']([^\"']+)[\"']")
		return choices.search_all(line).any(func(m):return (m.get_end()<=line.find(" if ") or m.get_start()>line.find(" else ")+5) and m.get_string(1).length()>1 and not _contains_cjk(m.get_string(1)))
	return line.contains("text.contains(") and line.contains("text.to_lower()")
func _split_bilingual(line:String,next:String)->bool:
	return line.strip_edges().begins_with("var zh:String=") and next.strip_edges().begins_with("var en:String=") and not _untranslated_literal(next) and '\"' in next
