extends SceneTree
var checks:=0
var failed:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var w:=preload("res://scripts/world_state.gd").new();w.residents.provision(w)
	var art:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/fish-art.json"))
	var names:Array=["noodle","eel","kite","cutlass"]
	for id in names:
		var sprite:Dictionary=art.sprites[id]
		check(sprite.width>28 and sprite.rows.size()==sprite.height and sprite.rows.all(func(row):return row.length()==sprite.width),id+" independent wide pixel grid")
		check(w.journal.entries.filter(func(e):return e.species_id==id).size()==16,id+" has all journal combinations")
		check(w.fishing.rules.species.any(func(s):return s.id==id),id+" in catch table")
	check(w.fishing.rules.species.reduce(func(n,s):return n+int(s.weight),0)==100,"species weights total 100")
	check(w.fishing.rules.species.filter(func(s):return int(s.weight)<=8).reduce(func(n,s):return n+int(s.weight),0)==20,"rare weight no higher than original 20 percent")
	var day_count:=0;var night_count:=0
	w.fishing.rng.seed=412
	for n in range(5000):
		if w.fishing.pick_species().id=="cutlass":day_count+=1
	check(day_count==0,"daytime never selects cutlass")
	w.advance(w.days.day_seconds*.81)
	check(w.days.phase().id=="night","actual DayCycle enters night")
	for n in range(5000):
		if w.fishing.pick_species().id=="cutlass":night_count+=1
	check(night_count>0,"night can select cutlass")
	var renderer:=preload("res://scripts/fishing_renderer.gd").new()
	for id in names:
		var texture:Texture2D=renderer.texture(id,"cream",w.fishing.rules)
		check(texture!=null and texture.get_width()>28,id+" runtime actual texture uses original wide grid")
	var lines:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/fish-first-tastes.json"))
	var additions:Array=["koi","catfish","clownfish","moonfish","seahorse","angler","ghost","butterfly","puffer","rainbow","tuna"]
	var legacy_lines:Dictionary={"noodle":"第一次吃面条鱼，细细的真有趣。","eel":"第一次吃鳗鱼，好香呀。","kite":"第一次吃风筝鱼，尾巴长长的。","cutlass":"第一次吃带鱼，银亮亮的鱼真香。"}
	check(names.all(func(id):return lines.get(id)==legacy_lines[id]),"all four original first-taste lines remain exact")
	check(lines.size()==15 and (names+additions).all(func(id):return lines.has(id) and lines[id] is String and not str(lines[id]).is_empty()),"one first-taste line per original and newly authorized fish")
	var font:Font=load("res://assets/fonts/NotoSansSC.ttf")
	for id in names+additions:
		for index in range(lines[id].length()):check(font.has_char(lines[id].unicode_at(index)),id+" first-taste glyph exists")
	print("New fish: ",checks," checks failed=",failed,"; engine fixture, not player input")
	quit(1 if failed else 0)
