extends RefCounted
## Development telemetry only. Reads live choices; never commands actors.
var stats:Dictionary={}
var timeline:Array=[]
var elapsed:=0.0
var next_sample:=0.0
var step:=0.0
func sample(w:RefCounted,delta:float)->void:
	elapsed+=delta
	for id in w.director.brains:
		var b:RefCounted=w.director.brains[id]
		if not stats.has(id):stats[id]={'seconds':{},'phases':{},'ranks':{},'distance_sum':0.0,'idle':0.0,'max_idle':0.0,'host_replies':0,'interactions':0,'banter':0,'cooperation':0}
		var s:Dictionary=stats[id];var action:String=str(b.current.get('action','idle'))
		s.seconds[action]=float(s.seconds.get(action,0))+delta
		var phase:String=w.days.phase().id
		if not s.phases.has(phase):s.phases[phase]={}
		s.phases[phase][action]=float(s.phases[phase].get(action,0))+delta
		var rank:String=str(w.hunger.rank(id))
		if not s.ranks.has(rank):s.ranks[rank]={'seconds':0.0,'food':0.0}
		s.ranks[rank].seconds+=delta
		if action=='food':s.ranks[rank].food+=delta
		s.distance_sum+=b.distance()*delta
		s.idle=float(s.idle)+delta if b.current.is_empty() and not w._routes.has(id) and not w.work.jobs.has(id) else 0.0
		s.max_idle=maxf(float(s.max_idle),float(s.idle))
	if elapsed<next_sample:return
	next_sample=elapsed+float(w.director.brains.values()[0].config.developer_report.sample_seconds)
	for id in w.director.brains:
		var b:RefCounted=w.director.brains[id]
		timeline.append({'actor':id,'at':elapsed,'day':w.days.day(),'phase':w.days.phase().id,'weather':w.weather.current().id,'hunger_rank':w.hunger.rank(id),'action':b.current.get('action','idle'),'reasons':b.current.get('reasons',[]),'distance':b.distance()})
func top(values:Dictionary,limit:int=5)->Array:
	var keys:Array=values.keys();keys.sort_custom(func(a,b):return values[a]>values[b] if values[a]!=values[b] else str(a)<str(b))
	return keys.slice(0,limit).map(func(key):return {'action':key,'seconds':values[key],'share':float(values[key])/maxf(.001,values.values().reduce(func(a,b):return float(a)+float(b),0.0))})
func finish(w:RefCounted,output:String)->Dictionary:
	for id in stats:
		for key in ["interactions","host_replies","banter","cooperation"]:stats[id][key]=0
	var trace:Array=[]
	for file in DirAccess.get_files_at(w.director.brain_trace_directory):
		if not file.ends_with('.jsonl'):continue
		for line in FileAccess.get_file_as_string(w.director.brain_trace_directory.path_join(file)).split('\n',false):
			var entry:Variant=JSON.parse_string(line)
			if entry is Dictionary:trace.append(entry)
	for row in trace:
		if not stats.has(row.get('actor','')):continue
		var s:Dictionary=stats[row.actor]
		if row.get('event')=='interaction':s.interactions+=1
		if row.get('event')=='host_reply':s.host_replies+=1
		if row.get('event')=='social_episode' and row.get('outcome')=='completed':s['banter' if row.kind=='banter' else 'cooperation']+=1
	var result:Dictionary={'version':1,'seconds':elapsed,'seed':w.director.brains.values()[0].config.developer_report.seed,'actors':stats.duplicate(true),'timeline':timeline.duplicate(true),'trace':trace,'world_day':w.days.day(),'weather':w.weather.current().id}
	for id in result.actors:
		var s:Dictionary=result.actors[id];s.distance_mean=float(s.distance_sum)/maxf(.001,elapsed);s.top_five=top(s.seconds)
		s.phase_top={}
		for phase in s.phases:s.phase_top[phase]=top(s.phases[phase],3)
	DirAccess.make_dir_recursive_absolute(output)
	var file:=FileAccess.open(output.path_join('report.json'),FileAccess.WRITE);file.store_string(JSON.stringify(result,'\t'));file.close()
	var svg:String='<svg xmlns="http://www.w3.org/2000/svg" width="1400" height="550" viewBox="0 0 1400 550"><rect width="1400" height="550" fill="#f3f0df"/><g font-family="sans-serif" fill="#253a34"><text x="20" y="30" font-size="22">Resident brain — '+str(int(elapsed))+' seconds</text>'
	var ids:Array=stats.keys();ids.sort()
	for index in ids.size():
		var id:String=ids[index];var y:int=75+index*65
		svg+='<text x="15" y="'+str(y+24)+'" font-size="15">'+id+'</text>'
		for row in timeline:
			if row.actor!=id:continue
			var hue:int=posmod(str(row.action).hash(),360)
			var x:float=165+float(row.at)/maxf(1,elapsed)*1200
			svg+='<rect x="'+str(x)+'" y="'+str(y)+'" width="'+str(maxf(1,1200*float(w.director.brains.values()[0].config.developer_report.sample_seconds)/maxf(1,elapsed)))+'" height="32" fill="hsl('+str(hue)+',45%,58%)"><title>'+str(row.action)+' — '+str(row.phase)+' — '+', '.join(row.reasons)+'</title></rect>'
	for phase in w.days.config.phases:
		var x:float=165+float(phase.start)*1500/maxf(1,elapsed)*1200
		svg+='<text x="'+str(x)+'" y="365" font-size="14">'+str(phase.id)+'</text>'
	var totals:Dictionary={}
	for id in stats:
		for action in stats[id].seconds:totals[action]=float(totals.get(action,0))+float(stats[id].seconds[action])
	var legend:Array=top(totals,16)
	for index in legend.size():
		var action:String=legend[index].action;var x:int=20+(index%4)*345;var y:int=405+int(index/4)*31
		svg+='<rect x="'+str(x)+'" y="'+str(y)+'" width="14" height="14" fill="hsl('+str(posmod(action.hash(),360))+',45%,58%)"/><text x="'+str(x+21)+'" y="'+str(y+12)+'" font-size="12">'+w.director.brains.values()[0].action_name(action,'en').xml_escape()+'</text>'
	svg+='</g></svg>'
	file=FileAccess.open(output.path_join('timeline.svg'),FileAccess.WRITE);file.store_string(svg);file.close()
	return result
