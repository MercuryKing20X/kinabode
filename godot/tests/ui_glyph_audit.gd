extends RefCounted

static var font:FontFile
static var checked:Dictionary

static func missing(value:String)->Array[String]:
	if font==null:
		font=preload("res://assets/fonts/NotoSansSC.ttf").duplicate()
		font.allow_system_fallback=false
		font.fallbacks=[]
	var result:Array[String]=[]
	for index in value.length():
		var code:=value.unicode_at(index)
		if code in [8,9,10,13]:continue # Control codes do not have glyphs.
		if not checked.has(code):checked[code]=font.has_char(code)
		if checked[code]:continue
		var display:="%s (U+%04X)"%[String.chr(code),code]
		if not result.has(display):result.append(display)
	return result

static func check(value:String,path:String,errors:Array[String])->void:
	var absent:=missing(value)
	if not absent.is_empty():errors.append("Missing UI glyph %s: %s"%[path,", ".join(absent)])

# Match quoted GDScript literals before comments, including escaped quotes and
# multiline strings. Scan all literals so custom draw calls are covered too.
static func scripts(path:String,errors:Array[String])->void:
	var source:=FileAccess.get_file_as_string(path)
	var tokens:=RegEx.new()
	tokens.compile("(?s)#[^\r\n]*|\"\"\"(.*?)\"\"\"|'''(.*?)'''|\"((?:\\\\.|[^\"\\\\])*)\"|'((?:\\\\.|[^'\\\\])*)'")
	var line:=1
	var previous:=0
	for token in tokens.search_all(source):
		if token.get_string().begins_with("#"):continue
		var raw:=token.get_string()
		var delim:=3 if raw.begins_with("\"\"\"") or raw.begins_with("'''") else 1
		if previous<token.get_start():line+=source.count("\n",previous,token.get_start())
		previous=token.get_start()
		check(raw.substr(delim,raw.length()-delim*2).c_unescape(),"%s:%d"%[path,line],errors)
