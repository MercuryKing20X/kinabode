extends SceneTree
var failed:=false
func check(ok:bool,label:String)->void:
	if not ok:failed=true;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var base:String=OS.get_environment("HABITAT_DATA_DIR")
	check(base.contains("youqi-"),"isolated data")
	var b:RefCounted=preload("res://scripts/memory_books.gd").new();b.setup(base)
	var start:int=Time.get_ticks_usec()
	for day in range(1,91):
		for i in range(40):b.add("codex","fixture","fact:%d:%d"%[day,i],"facts","第%d天一起在海边钓到大鱼，第%d件真实夹具事实。"%[day,i],{},day,"game",["human","codex"],day*100+i)
		b.add("codex","fixture","day:"+str(day),"daily","第%d天的每日摘要"%day,{},day,"fixture",["codex"],day*100+99)
	for i in range(120):
		var path:String="photos/1/"+str(i).sha256_text()+".png";var full:String=b.photo_path(path);DirAccess.make_dir_recursive_absolute(full.get_base_dir())
		var image:=Image.create(320,200,false,Image.FORMAT_RGB8);image.fill(Color(.3,.5,.7));image.save_png(full)
		var e:Dictionary=b.entries.values()[i];e.photo_id=path;b.atomic(b.directory.path_join(e.id+".entry.json"),e)
	var created:int=Time.get_ticks_usec()-start
	var measures:Dictionary={"entries":b.entries.size(),"photos":120,"fixture_create_ms":created/1000.0}
	start=Time.get_ticks_usec();var loaded:RefCounted=b.get_script().new();loaded.setup(base);measures.load_ms=(Time.get_ticks_usec()-start)/1000.0
	for level in ["medium","lifeblood"]:
		start=Time.get_ticks_usec();var card:Dictionary=loaded.card("codex","上次钓的那条大鱼","",level);measures[level+"_card_ms"]=(Time.get_ticks_usec()-start)/1000.0
		var used:=0
		for rows in card.values():
			for row in rows:used+=row.text.length()+64
		check(used<=(10000 if level=="lifeblood" else 2200),"card bounded "+level)
	start=Time.get_ticks_usec();check(loaded.export_html(base.path_join("album.html")),"album exported");measures.export_ms=(Time.get_ticks_usec()-start)/1000.0
	var cases:Array=[
		["上次钓的那条大鱼","海边钓到一条大鱼"],["你记得我喜欢什么","你说喜欢下雨"],
		["阿黑在哪下棋","阿黑在月台下棋"],["小蓝帮谁浇水","小蓝帮你浇水"],
		["第一次烧烤","第一次烧烤吃蘑菇"],["那封生日信","生日信夹在书里"],
		["海岸巨鱼","海岸钓到巨型鱼"],["我偏好的天气","你偏好雨天天气"],
		["收获番茄","收获箱有番茄"],["种植萝卜","种植田里萝卜"],
		["柚柚睡哪里","柚柚睡在椅子上"],["建成的小屋","小屋终于建成"],
		["营火旁唱歌","营火旁一起唱歌"],["去海边散步","海边慢慢散步"],
		["认识七天","认识七天纪念日"],["给你蓝莓","你给我蓝莓"],
		["昨晚看星星","昨晚看星星很开心"],["泳池一起玩","泳池一起玩水"],
		["小橙的花","小橙送来一朵花"],["月台的椅子","月台放了一把椅子"]]
	var hits:=0
	var qa:Array=[]
	for pair in cases:
		var ranked:Array=[]
		for candidate in cases:
			ranked.append({"text":candidate[1],"params":{},"participants":["codex"],"day":1})
		ranked.sort_custom(func(a,b):return loaded.relevance(a,pair[0])>loaded.relevance(b,pair[0]))
		var hit:bool=ranked[0].text==pair[1]
		if hit:hits+=1
		qa.append({"query":pair[0],"expected":pair[1],"actual":ranked[0].text,"hit":hit})
	measures.qa=qa
	measures.retrieval_hits=hits;measures.retrieval_count=20
	check(hits==20,"synonym retrieval pairs")
	loaded.atomic(base.path_join("benchmark.json"),measures);print("LIFEBLOOD_BENCHMARK ",JSON.stringify(measures));quit(1 if failed else 0)
