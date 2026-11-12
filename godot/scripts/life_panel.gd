extends VBoxContainer
const Text=preload("res://scripts/localization.gd")
var archive:Node
var actor_id:=""
var tabs:TabBar
var output:RichTextLabel
var chart:Control
var expand:Button
var export_button:Button
var expanded:=false
var data:Dictionary={}
func setup()->void:
	tabs=TabBar.new()
	for key in ["thoughts","dreams","self","wishes"]:tabs.add_tab(Text.text("gestation.tab_"+key))
	tabs.tab_changed.connect(func(_i):refresh());add_child(tabs)
	chart=Control.new();chart.custom_minimum_size=Vector2(260,100);chart.draw.connect(draw_curve);add_child(chart)
	output=RichTextLabel.new();output.bbcode_enabled=false;output.custom_minimum_size=Vector2(280,240);output.selection_enabled=true;add_child(output)
	expand=Button.new();expand.text=Text.text("gestation.expand");expand.focus_mode=Control.FOCUS_NONE;expand.pressed.connect(func():expanded=not expanded;refresh());add_child(expand)
	export_button=Button.new();export_button.text=Text.text("gestation.export");export_button.focus_mode=Control.FOCUS_NONE;export_button.pressed.connect(export_diary);add_child(export_button)
func bind(source:Node,id:String)->void:
	archive=source;actor_id=id;refresh()
func refresh()->void:
	if not is_instance_valid(archive) or actor_id.is_empty():return
	data=archive.snapshot(actor_id)
	for i in tabs.tab_count:tabs.set_tab_title(i,Text.text("gestation.tab_"+["thoughts","dreams","self","wishes"][i]))
	expand.text=Text.text("gestation.collapse" if expanded else "gestation.expand");export_button.text=Text.text("gestation.export")
	if data.is_empty():output.text=Text.text("gestation.empty");chart.queue_redraw();return
	var mood:Array[String]=[]
	for axis in archive.AXES:mood.append(Text.text("gestation."+axis)+" "+str(int(data.mood[axis])))
	var text:String=" · ".join(mood)+"\n"+Text.text("gestation.today_usage")+str(archive.today_usage(actor_id).tokens)+(" + ?" if archive.today_usage(actor_id).unknown_tokens else "")+" token\n\n"
	var rows:Array=data[["records","dreams","selves","wishes"][tabs.current_tab]].duplicate(true)
	if tabs.current_tab==0 and not expanded:rows=rows.slice(-50)
	rows.reverse()
	for row in rows:
		var icon:String="☀" if float(row.get("mood",data.mood).get("joy",50))>=60 else "☁"
		text+=icon+" "+Text.text("gestation.day")+" "+str(row.get("day",0))+" · "+Text.text("gestation.ai" if row.get("origin","")=="ai" else "gestation.local")+"\n"+archive.render_row(row)+"\n"
		if row.has("today"):text+=archive.render_today(row)+"\n"
		if row.has("status"):text+=Text.text("gestation."+str(row.status))+"\n"
		text+="\n"
	if output.text!=text:output.text=text
	chart.queue_redraw()
func draw_curve()->void:
	if data.is_empty():return
	var points:Array=data.curve.slice(-100)
	var colors:Array=[Color("ed9d46"),Color("9b877a"),Color("bc80ad"),Color("55aabe"),Color("b58383"),Color("85a56a")]
	for a in archive.AXES.size():
		for i in range(1,points.size()):
			var from:=Vector2(float(i-1)/maxi(1,points.size()-1)*chart.size.x,95-float(points[i-1].mood[archive.AXES[a]])*.9)
			var to:=Vector2(float(i)/maxi(1,points.size()-1)*chart.size.x,95-float(points[i].mood[archive.AXES[a]])*.9)
			chart.draw_line(from,to,colors[a],2)
func export_diary()->void:
	if not is_instance_valid(archive):return
	var path:String=archive.directory.path_join(actor_id.sha256_text()+"-diary.html")
	if archive.export_html(actor_id,path):OS.shell_open(path)
