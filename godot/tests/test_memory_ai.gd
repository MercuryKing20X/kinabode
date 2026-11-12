extends SceneTree
const Books=preload("res://scripts/memory_books.gd")
class MaintenanceHost extends Node:
	var memory_books:RefCounted
	var immediate_turns:Dictionary={"codex":{"turn_key":"stub-letter-turn"}}
	var autonomy:Dictionary={"scheduler":RefCounted.new()}
func _initialize()->void:call_deferred("run")
func run()->void:
	var dir:String=OS.get_environment("HABITAT_DATA_DIR");assert(dir.contains("youqi-"))
	var b:=Books.new();assert(b.setup(dir))
	b.remember_chat("codex","world","msg-1","我喜欢下雨",1,"direct:codex")
	assert(b.add("codex","world","meal-real","facts","A real completed shared meal",{},1,"game",["human","codex"]))
	var sources:Array=b.ai_sources("codex","world");var allowed:Array=sources.map(func(e):return e.id)
	var quote:String=sources.filter(func(e):return e.human_quote and e.layer=="facts")[0].id
	var fact:String=sources.filter(func(e):return e.event_id=="meal-real")[0].id
	assert(b.accept_ai("codex","world","Codex-stub",[{"layer":"about_you","text":"You like rain.","source_ids":[quote]},{"layer":"feelings","text":"I enjoyed our shared meal.","source_ids":[fact]}],allowed,1).accepted==2)
	assert(b.accept_ai("codex","world","Codex-stub",[{"layer":"feelings","text":"A fictional event", "source_ids":["invented"]},{"layer":"about_you","text":"Incorrect source", "source_ids":[fact]}],allowed,1).rejected==2)
	# Disconnect/reload and switch to a different adapter. Stable resident identity owns storage.
	var second:=Books.new();assert(second.setup(dir));assert(JSON.stringify(second.card("codex")).contains("You like rain"))
	assert(second.accept_ai("codex","world","Other-provider-stub",[{"layer":"feelings","text":"That shared meal still matters to me.","source_ids":[fact]}],allowed,2).accepted==0) # merged by same layer + source, not duplicated on provider switch
	b.remember_chat("codex","world","msg-2","I like walking by the sea",2,"direct:codex")
	assert(second.setup(dir));var new_sources:Array=second.ai_sources("codex","world");var next_quote:String=new_sources.filter(func(e):return e.event_id=="msg-2" and e.layer=="facts")[0].id
	assert(second.accept_ai("codex","world","Other-provider-stub",[{"layer":"about_you","text":"You enjoy the sea.","source_ids":[next_quote]}],new_sources.map(func(e):return e.id),2).accepted==1)
	var returned:=Books.new();assert(returned.setup(dir));assert(JSON.stringify(returned.card("codex")).contains("You enjoy the sea"))
	assert(returned.list_for("codex","about_you").any(func(e):return e.source=="Other-provider-stub"))
	var letter:String="今天一起吃饭的时候，我很开心。你说你喜欢下雨，我就记住啦。吃完饭也有点舍不得，想再陪你待一小会儿。要是哪天海边下起雨，我们就听一会儿雨声，好不好？不用急着回答。想到今天能和你一起吃饭，心里还是暖暖的。"
	assert(b.letter_has_system_words("原话 ID"));assert(b.letter_has_system_words("引用ID"));assert(b.letter_has_system_words("笔记"));assert(b.letter_has_system_words("系统"))
	assert(not b.letter_has_system_words(letter))
	assert(returned.accept_ai("codex","world","Codex-stub",[{"layer":"letters","text":letter+"引用 ID", "source_ids":[fact]}],allowed,2,{"day":1}).rejected==1)
	assert(returned.list_for("codex","letters").is_empty())
	var writes:Array=[{"layer":"letters","text":letter,"source_ids":[fact,quote]},{"layer":"daily","text":"We shared a meal. You said you like rain.","source_ids":[fact,quote]}]
	assert(returned.add("codex","world","local-daily","daily","Local summary",{"source_ids":[fact]},1,"local",["codex"]))
	var notifications:Dictionary={"count":0};returned.entry_deleted.connect(func(_entry):notifications.count+=1)
	assert(returned.accept_ai("codex","world","Codex-stub",writes,allowed,2,{"day":1}).accepted==2)
	assert(not returned.list_for("codex","daily").any(func(e):return e.source=="local"));assert(notifications.count==0);assert(returned.entries.has(fact))
	assert(returned.accept_ai("codex","world","Other-provider-stub",writes,allowed,2,{"day":1}).accepted==0)
	assert(returned.accept_ai("codex","world","Codex-stub",[{"layer":"letters","text":letter,"source_ids":[next_quote]}],[next_quote],3,{"day":1}).accepted==0)
	assert(returned.accept_ai("codex","world","Codex-stub",[{"layer":"letters","text":letter,"source_ids":[fact]}],allowed,2).accepted==0)
	returned.remember_chat("codex","world","teach-1","以后我说小火苗就是叫大家烧烤",2,"direct:codex")
	assert(returned.learn("codex","world","teach-1","以后我说小火苗就是叫大家烧烤",2))
	assert(returned.resolve("codex","小火苗")=="叫大家烧烤")
	assert(returned.resolve("companion-2","小火苗")=="小火苗")
	assert(returned.export_html(dir.path_join("album.html")));assert(FileAccess.get_file_as_string(dir.path_join("album.html")).contains("Through her eyes") or FileAccess.get_file_as_string(dir.path_join("album.html")).contains("她眼里的你"))
	assert(returned.photo_path("../../signing.key").is_empty())
	assert(not JSON.stringify(returned.ai_sources("codex","world",0,"group:all")).contains("walking by the sea"))
	# Actual photo bytes survive a signed export/import, not just a dangling filename.
	var relative:String="photos/0/"+fact+".png";DirAccess.make_dir_recursive_absolute(dir.path_join("memories/photos/0"))
	var image:=Image.create(320,200,false,Image.FORMAT_RGBA8);image.fill(Color("345678"));assert(image.save_png(returned.photo_path(relative))==OK)
	returned.entries[fact].photo_id=relative;assert(returned.atomic(returned.directory.path_join(fact+".entry.json"),returned.entries[fact]))
	assert(returned.export_data(dir.path_join("photos.json")))
	var imported:=Books.new();assert(imported.setup(dir.path_join("photos-import")));assert(imported.import_data(dir.path_join("photos.json")).ok)
	assert(FileAccess.file_exists(imported.photo_path(relative)))
	assert(returned.remove(quote));assert(not JSON.stringify(returned.card("codex")).contains("You like rain"));assert(returned.list_for("codex","letters").is_empty())
	# Deleting a derived summary never deletes the true game event.
	assert(returned.entries.has(fact))
	assert(not returned.dirty_daily.is_empty())
	assert(returned.accept_ai("codex","world","Codex-stub",[{"layer":"daily","text":"Only the actual meal remains.","source_ids":[fact]}],[fact],3,{"day":2,"rebuild_days":[1]}).accepted==1)
	assert(returned.list_for("codex","daily").any(func(e):return e.text=="Only the actual meal remains." and e.day==1))
	returned.remember_chat("codex","world","forget-note","I like green tea",4,"direct:codex")
	var tea_sources:Array=returned.ai_sources("codex","world");var tea:String=tea_sources.filter(func(e):return e.event_id=="forget-note" and e.layer=="facts")[0].id
	var before_notes:int=returned.list_for("codex","about_you").size()
	assert(returned.accept_ai("codex","world","Codex-stub",[{"layer":"about_you","text":"You like green tea.","source_ids":[tea]}],[tea],4).accepted==1)
	assert(returned.list_for("codex","about_you").size()==before_notes)
	var tea_note:String=returned.list_for("codex","about_you").filter(func(e):return e.text=="You like green tea.")[0].id
	assert(returned.remove(tea_note));assert(not returned.entries.has(tea));assert(not JSON.stringify(returned.card("codex")).contains("green tea"))
	var host:=MaintenanceHost.new();host.memory_books=returned
	var life:=preload("res://scripts/memory_life.gd").new();life.owner_ref=weakref(host)
	life.attempts.codex={"day":1,"pending":false}
	life.maintenance.codex={"complete":false}
	var dirty:Array=[{"layer":"letters","text":letter+"原话 ID"}]
	life.check_letter_reply("codex",dirty,{"maintenance":true,"memory_request":{"day":1}})
	life.event("codex",{"kind":"state","state":"ready","turn_key":"stale"})
	assert(life.maintenance.has("codex") and not life.attempts.codex.pending)
	life.event("codex",{"kind":"state","state":"ready","turn_key":"stub-letter-turn"})
	assert(life.attempts.codex.pending and life.attempts.codex.rewrite and life.attempts.codex.day==1)
	life.check_letter_reply("codex",dirty,{"maintenance":true,"memory_request":{"day":1}})
	assert(life.letter_retries.is_empty())
	for ending in ["cancelled","disconnected","error"]:
		life.attempts.codex={"day":1,"pending":false}
		life.maintenance.codex={"complete":false}
		life.letter_retries.codex=1
		life.event("codex",{"kind":"state","state":ending,"turn_key":"stub-letter-turn"})
		assert(not life.attempts.codex.pending and life.letter_retries.is_empty() and life.maintenance.is_empty())
	life.attempts.codex={"day":1,"pending":true,"rewrite":true}
	life.letter_retries.codex=1
	life.cancel_pending("codex")
	assert(not life.attempts.codex.pending and life.letter_retries.is_empty())
	life.free();host.free()
	print("MEMORY_AI_PASS references/forgery/dedup/two-providers/reload/daily-letter/deletion/agreement")
	quit()
