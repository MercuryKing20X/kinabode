extends RefCounted
## Derives plantable state from existing, validated built-site identities only.
## No costs, seeds, routes, placement authority or independent saved geometry.
const PREFIX="farm.bed."
static func definitions(world:RefCounted,sites:Dictionary)->Array:
	if not world.locations.v3():return []
	var result:Array=[]
	var home:Dictionary=world.locations.read("homestead").site
	var r:Array=home.rect
	result.append(make("farm.bed.homestead",str(home.name),r,[float(r[0])+1.7,float(r[1])+float(r[3])-1.2],[2,1],[3.2,0],home.entry,str(home.id),"homestead"))
	for site in sites.values():
		if site.get("template_id")!="outdoor-flowers":continue
		var at:Array=site.position
		result.append(make(PREFIX+str(site.id),str(site.name),[float(at[0])-1.5,float(at[1])-1.5,3,3],at,[1,1],[0,0],[at[0],float(at[1])+2],str(site.id),"leisure"))
	return result
static func make(id:String,label:String,rect:Array,first:Array,grid:Array,spacing:Array,entry:Array,source:String,kind:String)->Dictionary:
	var definition:Dictionary={"id":id,"name":label,"manager_id":"","zone_id":"home.garden","rect":rect.map(func(n):return float(n)),"crop_ids":["turnip","tomato","pumpkin","daisy","blueberry","potato","corn"],"grid":grid.map(func(n):return float(n)),"first":first.map(func(n):return float(n)),"spacing":spacing.map(func(n):return float(n)),"seed_at":entry.map(func(n):return float(n)),"harvest_at":entry.map(func(n):return float(n)),"meeting_at":entry.map(func(n):return float(n)),"road":[],"bed_size":[2.6,2.2],"raised_bed":true,"source_site_id":source,"source_kind":kind,"flowers":0,"harvested":0}
	return JSON.parse_string(JSON.stringify(definition))
