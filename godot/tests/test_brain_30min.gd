extends "res://tests/test_local_command_main_input.gd"
class Fake extends "res://scripts/companion_link.gd":
	var sent:Array=[]
	func _start()->bool:return false
	func _send(message:Dictionary)->bool:sent.append(message);return false
var evidence:String
var base_directory:String
var sequences:Array=[]
func fresh_title(index:int)->void:
	OS.set_environment("HABITAT_DATA_DIR",base_directory.path_join("run-"+str(index)))
	OS.set_environment("HABITAT_BRAIN_SEED","701")
	OS.set_environment("HABITAT_OPENING","standard")
	preload("res://tests/deterministic_environment.gd").streams.clear()
	var title:Node=load("res://scenes/title.tscn").instantiate();root.add_child(title);current_scene=title
	for frame in 12:await process_frame
	check(await UI.click(self,title.menu.get_node("new")),"real mouse starts standard from title")
	var transition_deadline:int=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<transition_deadline:
		await process_frame
		if is_instance_valid(current_scene) and current_scene.get("world")!=null:break
	game=current_scene
	check(game.get("world")!=null and game.world.opening_id=="standard","actual new standard world")
	if game.get("world")==null:quit(1);return
	game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.island_hud.set_process(false);game.chat.hide()
	for link in game.links.values():check(link is Fake,"prebuilt connections use fake factory")
	check(game.world.director.time==0,"no automatic frame before the input-free simulation")

func sample(index:int)->Dictionary:
	await fresh_title(index)
	var w:RefCounted=game.world
	var initial:Dictionary=w.storage.saved().duplicate(true)
	var plots:Dictionary=w.farms.plots.duplicate(true)
	var interactions:Dictionary={};var interaction_seq:Array=[];var delivered_lines:Dictionary={};var approached:Dictionary={}
	var counts:Dictionary={};var distance:Dictionary={};var idle:Dictionary={};var max_idle:Dictionary={};var seq:Array=[];var timeline:Array=[]
	var no_labor:=true;var conserved:=true
	for id in w.director.brains:interactions[id]=0;approached[id]=0;counts[id]={};distance[id]=0.0;idle[id]=0.0;max_idle[id]=0.0
	for tick in 7200:
		w.advance(.25)
		for id in w.director.brains:
			var b:RefCounted=w.director.brains[id]
			distance[id]+=b.distance()*.25
			idle[id]=float(idle[id])+.25 if b.current.is_empty() and not w._routes.has(id) else 0.0
			max_idle[id]=maxf(float(max_idle[id]),float(idle[id]))
			if w.work.jobs.has(id) and w.director.moods.laboring(id):no_labor=false
		if tick%40==0:
			conserved=conserved and initial==w.storage.saved() and plots==w.farms.plots
			for id in w.director.brains:
				var b:RefCounted=w.director.brains[id]
				timeline.append({"actor":id,"at":tick*.25,"action":b.current.get("action",""),"reasons":b.current.get("reasons",[]),"distance":b.distance()})
		if tick%240==0:await process_frame
		if tick%2400==0:print("BRAIN_SIM_PROGRESS run=",index," seconds=",tick*.25)
	var trace_dir:String=w.director.brain_trace_directory
	for name in DirAccess.get_files_at(trace_dir):
		if not name.ends_with(".jsonl"):continue
		var raw_trace:String=FileAccess.get_file_as_string(trace_dir.path_join(name))
		var retained:=FileAccess.open(evidence.path_join("brain-trace-run"+str(index)+".jsonl"),FileAccess.WRITE);retained.store_string(raw_trace);retained.close()
		for line in raw_trace.split("\n",false):
			var row:Dictionary=JSON.parse_string(line)
			if row.get("event")=="interaction":
				interactions[row.actor]+=1
				var delivered_key:String=str(row.day)+":"+str(row.actor)+":"+str(row.zh)
				check(not delivered_lines.has(delivered_key),"no repeated delivered line per resident per day")
				delivered_lines[delivered_key]=true
				check(not str(row.get("scene","")).is_empty() and not row.get("reasons",[]).is_empty() and not str(row.get("proof","")).is_empty(),"every interaction has a real scene and reason")
				interaction_seq.append(row)
			if row.get("event")!="choice":continue
			counts[row.actor][row.choice]=int(counts[row.actor].get(row.choice,0))+1
			seq.append({"actor":row.actor,"at":row.at,"choice":row.choice,"reasons":row.reasons})
	for id in w.director.brains:
		var b:RefCounted=w.director.brains[id]
		check(int(interactions[id])>=5,"at least five delivered host interactions "+id)
		check(float(max_idle[id])<=15,"idle gap <=15 seconds "+id)
		check(counts[id].size()>=8,"at least eight distinct actions "+id)
		check(float(distance[id])/1800>=2 and float(distance[id])/1800<=8,"follow average 2..8 "+id)
		var ranking:Array=counts[id].keys();ranking.sort_custom(func(a,b):return counts[id][a]>counts[id][b])
		# Authored preference: lively enjoys hopping, twirling and chasing butterflies.
		var signatures:Array={"gentle":["flower_scent","sea_watch","cloud_watch"],"lively":["play_cute","spin","hop","butterfly"],"laborious":["sweep","wood_tidy","dust"],"quiet":["read","stars","play_lie"]}.get(b.tag(),[])
		check(ranking.slice(0,3).any(func(a):return a in signatures),"signature preference among top three "+id)
	for a in counts:
		for b in counts:
			if str(a)<str(b):check(counts[a]!=counts[b],"distinct pair distributions "+a+" / "+b)
	check(no_labor,"zero unsolicited labor")
	check(conserved,"original stock and unworked plots conserved at every sample")
	sequences.append([seq,interaction_seq])
	var report:Dictionary={"counts":counts,"host_interactions":interactions,"interaction_sequence":interaction_seq,"distance_mean":{},"idle_max":max_idle,"no_labor":no_labor,"conserved":conserved,"sequence":seq,"timeline":timeline}
	for id in distance:report.distance_mean[id]=float(distance[id])/1800
	var f:=FileAccess.open(evidence.path_join("30min-"+str(index)+".json"),FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t"));f.close()
	return report
func run()->void:
	base_directory=OS.get_environment("HABITAT_DATA_DIR")
	evidence=OS.get_environment("HABITAT_BRAIN_EVIDENCE")
	if evidence.is_empty():evidence=base_directory
	DirAccess.make_dir_recursive_absolute(evidence)
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	node_added.connect(func(node):
		if node.get_script()!=null and node.get_script().resource_path=="res://scripts/main.gd":node.set_process(false);node.dialogue_adapter_factory=func(_id,_scope):return Fake.new())
	await sample(1)
	game.queue_free();await process_frame
	await sample(2)
	check(sequences[0]==sequences[1],"same seed exact decision sequence twice")
	game.queue_free();await process_frame
	print("BRAIN_30MIN ",checks," failed=",failed);quit(1 if failed else 0)
