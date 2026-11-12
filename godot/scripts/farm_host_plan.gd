extends RefCounted
## DIRECTION 214: pure host preview; confirmation retains the exact people and plots.
const Text=preload("res://scripts/localization.gd")
static func reason(f:RefCounted,id:String)->String:
	var w:RefCounted=f.world
	if not w.actors.has(id):return "unknown_resident"
	if w.resort!=null and w.resort.vacation(id):return w.resort.line()
	if w.actors[id].region_id!="home" or w.actors.human.region_id!="home":return "different_region"
	if id!="human" and w.hunger!=null and w.hunger.rank(id)>=2:return "very_hungry" if w.hunger.rank(id)>=3 else "hungry"
	if f.active(id) or w.work.jobs.has(id) or w.deliveries.active(id) or w.projects.active(id) or w.homestead.active(id):return "busy"
	if not str(w.actors[id].get("furniture_id","")).is_empty():return "hands_full"
	if w.gomoku.active(id) or w.shared_activity.contains(id) or w.activities.blocked(id,false):return "busy"
	if not w.fishing.held(id).is_empty():return "hands_full"
	return ""
static func reserved(f:RefCounted,pid:String,except_id:String="")->bool:
	for id in f.host_grants:
		if id!=except_id and f.active(id) and pid in f.host_grants[id].get("plot_ids",[]):return true
	return false
static func seal(f:RefCounted,p:Dictionary)->String:
	return (str(f.world.world_id)+JSON.stringify(p.get("request",{}))+JSON.stringify(p.get("rows",[]))).sha256_text()
static func preview(f:RefCounted,ids:Array,intent:String,fid:String,crop:String)->Dictionary:
	var request:Dictionary={"actor_ids":ids.duplicate(),"intent":intent,"farm_id":fid,"crop_id":crop}
	var rows:Array=[];var seen:Dictionary={};var budget:Dictionary=f.world.storage.saved().get("items",{}).duplicate(true)
	# Storage.saved is intentionally queried once; only own retained carry may supplement it.
	for id_value in ids:
		var id:String=str(id_value)
		if seen.has(id):continue
		seen[id]=true
		var why:String=reason(f,id)
		if intent not in ["plant","ready"]:why="invalid_farm_plan"
		rows.append({"actor_id":id,"farm_id":fid,"crop_id":crop if intent=="plant" else "","mode":intent,"plot_ids":[],"crop_by_plot":{},"seed_costs":{},"seeds":{},"missing":{},"eligible":false,"allowed":false,"reason":why})
	var used:Dictionary={};var assigned_farms:Dictionary={};var assigned_own:Dictionary={};var own:Dictionary={}
	for row in rows:
		if not row.reason.is_empty():continue
		var id:String=row.actor_id;own[id]=f.world.actors[id].carry.duplicate(true)
		var candidates:Array=[fid] if not fid.is_empty() else f.farms.keys()
		var human:Vector2=f.world.point(f.world.actors.human)
		candidates.sort_custom(func(a,b):
			if not f.farms.has(a):return false
			if not f.farms.has(b):return true
			var pa:Array=f.farms[a].meeting_at;var pb:Array=f.farms[b].meeting_at
			return human.distance_squared_to(Vector2(pa[0],pa[1]))<human.distance_squared_to(Vector2(pb[0],pb[1])))
		var best:String="";var unfunded:String=""
		for candidate in candidates:
			if not f.farms.has(candidate) or not f.ready(candidate):continue
			if intent=="plant" and crop!="mixed" and crop not in f.farms[candidate].crop_ids:continue
			var available:Array=f.farm_plots(candidate).filter(func(p):return not f.world.work.claims.has(p.id) and not reserved(f,p.id) and (f.stage(p) in ["empty","dry"] if intent=="plant" else f.stage(p)=="mature"))
			if available.is_empty():continue
			var capacity:int=available.size()
			if intent=="plant":
				var dry:int=available.filter(func(plot):return f.stage(plot)=="dry").size()
				var seeds:int=int(assigned_own.get(candidate,0))
				for c in (f.farms[candidate].crop_ids.filter(func(item):return item not in ["potato","corn"]) if crop=="mixed" else [crop]):
					seeds+=int(budget.get("seed."+str(c),0))+int(own[id].get("seed."+str(c),0))
				capacity=dry+mini(available.size()-dry,seeds)
			if int(assigned_farms.get(candidate,0))<capacity:best=candidate;break
			if capacity==0 and unfunded.is_empty():unfunded=candidate
		if best.is_empty():best=unfunded
		if best.is_empty():row.reason="no_work";continue
		row.farm_id=best;assigned_farms[best]=int(assigned_farms.get(best,0))+1
		if intent=="plant":
			for c in (f.farms[best].crop_ids.filter(func(item):return item not in ["potato","corn"]) if crop=="mixed" else [crop]):assigned_own[best]=int(assigned_own.get(best,0))+int(own[id].get("seed."+str(c),0))

	# Round robin gives each selected resident a distinct affordable plot before a second.
	var progress:bool=true
	while progress:
		progress=false
		for row in rows:
			if not row.reason.is_empty():continue
			var id:String=row.actor_id
			for p in f.farm_plots(row.farm_id):
				if used.has(p.id) or f.world.work.claims.has(p.id) or reserved(f,p.id):continue
				var stage:String=f.stage(p)
				if (intent=="plant" and stage not in ["empty","dry"]) or (intent=="ready" and stage!="mature"):continue
				var chosen:String=""
				if intent=="plant" and stage=="empty":
					var choices:Array=[crop] if crop!="mixed" else f.farms[row.farm_id].crop_ids.filter(func(c):return c not in ["potato","corn"])
					if crop=="mixed":
						var start:int=(int(str(p.id).get_slice(".plot.",1))-1)%choices.size()
						choices=choices.slice(start)+choices.slice(0,start)
					for c in choices:
						var key:String="seed."+str(c)
						if int(own[id].get(key,0))+int(budget.get(key,0))>0:chosen=c;break
					if chosen.is_empty():continue
					var seed:String="seed."+chosen
					if int(own[id].get(seed,0))>0:own[id][seed]-=1
					else:budget[seed]=int(budget.get(seed,0))-1
					row.seed_costs[seed]=int(row.seed_costs.get(seed,0))+1
				used[p.id]=true;row.plot_ids.append(p.id);row.crop_by_plot[p.id]=chosen;progress=true;break
	# Unfunded plots are also counted once across this group, never once per person.
	for row in rows:row.missing={}
	var counted:Dictionary=used.duplicate();progress=true
	while progress:
		progress=false
		for row in rows:
			if not row.reason.is_empty() or intent!="plant":continue
			for plot in f.farm_plots(row.farm_id):
				if counted.has(plot.id) or f.world.work.claims.has(plot.id) or reserved(f,plot.id) or f.stage(plot)!="empty":continue
				var c:String=crop
				if c=="mixed":
					var choices:Array=f.farms[row.farm_id].crop_ids.filter(func(item):return item not in ["potato","corn"])
					c=choices[(int(str(plot.id).get_slice(".plot.",1))-1)%choices.size()]
				var seed:String="seed."+c;row.missing[seed]=int(row.missing.get(seed,0))+1
				counted[plot.id]=true;progress=true;break
	for row in rows:
		row.eligible=not row.plot_ids.is_empty();row.allowed=row.eligible;row.seeds=row.seed_costs.duplicate(true)
		if not row.eligible and row.reason.is_empty():row.reason="no_seed" if not row.missing.is_empty() else "no_work"
	var result:Dictionary={"version":1,"request":request,"rows":rows};result.seal=seal(f,result)
	return result
static func confirm(f:RefCounted,p:Dictionary,selected:Variant=null)->Dictionary:
	if p.get("version")!=1 or not p.get("rows") is Array or str(p.get("seal",""))!=seal(f,p):return {"ok":false,"error":"invalid_farm_plan","rows":[],"message":message("invalid_farm_plan")}
	var results:Array=[];var any_ok:bool=false;var remaining_shared:Dictionary=f.world.storage.saved().items.duplicate(true)
	for row in p.rows:
		var id:String=str(row.actor_id)
		if selected is Array and id not in selected:continue
		var why:String=reason(f,id)
		if not row.eligible:why=str(row.reason)
		if why.is_empty() and not f.ready(row.farm_id):why="no_work"
		var costs:Dictionary={}
		if why.is_empty():
			for pid in row.plot_ids:
				var plot:Dictionary=f.plots.get(pid,{})
				if plot.is_empty() or plot.farm_id!=row.farm_id or f.world.work.claims.has(pid) or reserved(f,pid):why="changed";break
				var stage:String=f.stage(plot)
				if (row.mode=="ready" and stage!="mature") or (row.mode=="plant" and stage not in ["empty","dry"]):why="changed";break
				if row.mode=="plant" and stage=="empty":
					var seed:String="seed."+str(row.crop_by_plot[pid]);costs[seed]=int(costs.get(seed,0))+1
			for seed in costs:
				if int(remaining_shared.get(seed,0))+int(f.world.actors[id].carry.get(seed,0))<int(costs[seed]):why="no_seed"
		var result:Dictionary={"actor_id":id,"farm_id":row.farm_id,"ok":false,"error":why,"message":message(why)}
		if why.is_empty():
			result=f.host_order(id,row.farm_id,row.crop_id,row.mode,row.plot_ids,row.crop_by_plot)
			result.actor_id=id;result.farm_id=row.farm_id
			if result.get("ok",false):
				for seed in costs:remaining_shared[seed]=int(remaining_shared.get(seed,0))-maxi(0,int(costs[seed])-int(f.world.actors[id].carry.get(seed,0)))
				var token:String=Crypto.new().generate_random_bytes(16).hex_encode();f.orders[id].host_order_id=token;result.order_id=token;any_ok=true
		results.append(result)
	return {"ok":any_ok,"rows":results,"message":"；".join(results.map(func(r):return Text.resident(f.world,r.actor_id)+"："+str(r.get("message",message(str(r.get("error","")))))))}
static func message(code:String)->String:
	return Text.text("farm.help."+(code if not code.is_empty() else "accepted"))
