extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
# All motion here is presentation only. Slots and walking remain in WorldState.
var bases: Dictionary={}
func angle(view: Node,site: Dictionary,index: int,active: bool) -> float:
	return sin(view.clock*2.3+float(index)*.8)*(0.12 if active else .015)
func rect(view: Node,site: Dictionary) -> Rect2:
	var art: Dictionary=view.world.leisure.art(site)
	if art.is_empty():return Rect2()
	return Rect2(view.screen(view.world.point(site))-Vector2(art.anchor[0],art.anchor[1])*view.zoom,Vector2(art.width,art.height)*view.zoom)
func draw(view: Node,site: Dictionary) -> void:
	if not site.complete and view.world.resort!=null and view.world.resort.retired(site):return
	if view.world.standard.sites.has(site.id) and site.complete:return
	var art: Dictionary=view.world.leisure.art(site)
	if art.is_empty():return
	var p: Vector2=view.screen(view.world.point(site))
	if not site.complete:
		if view.world.standard.active():
			quiet_marker(view,site,p)
			return
		var config: Dictionary=art.recreation
		var area:=Rect2(p-Vector2(config.width,config.depth)*16*view.zoom,Vector2(config.width,config.depth)*32*view.zoom)
		view.draw_rect(area,Color("a58b6470"));view.draw_rect(area,Color("d8bc8d"),false,2*view.zoom)
		view.draw_string(view.font,p+Vector2(-55,0),LocalText.content(site.name),HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("fff4db"))
		view.draw_string(view.font,p+Vector2(-50,22),LocalText.text("ui.leisure_renderer.wood_s_s")%[site.invested,view.world.leisure.cost(site)],HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("fff4db"))
		return
	if site.template_id=="outdoor-flowers" and view.world.locations.v3():
		var at:Vector2=view.world.point(site)
		var box:=Rect2(at-Vector2(1.5,1.5),Vector2(3,3))
		view._surface(preload("res://scripts/home_layout.gd").rectangle(box,.2),view.textures.get("slab",view.textures.soil),Color("9d947c"))
		view._surface(preload("res://scripts/home_layout.gd").rectangle(box.grow(-.25),.15),view.textures.soil,Color("a1835c"))
		return
	var frame: String="idle"
	var active: Dictionary={}
	for job in view.world.work.jobs.values():
		if job.get("target_id")==site.id and job.get("step")=="using":active[job.get("slot",-1)]=true;frame="active"
	var texture: Texture2D=view.library.frozen_texture(art,frame)
	var target:=rect(view,site)
	var rigs: Array=art.recreation.get("rigs",[])
	if rigs.is_empty():
		view.draw_texture_rect(texture,target,false)
		if art.recreation.get("game")=="gomoku":chessboard(view,site,target)
		return
	var key: String="%s:%s:%s"%[art.id,art.revision,frame]
	if not bases.has(key):
		var source: Image=view.library.render(art,frame)
		for rig in rigs:source.fill_rect(Rect2i(rig.rect[0],rig.rect[1],rig.rect[2],rig.rect[3]),Color.TRANSPARENT)
		bases[key]=ImageTexture.create_from_image(source)
	view.draw_texture_rect(bases[key],target,false)
	for i in range(rigs.size()):
		var rig: Dictionary=rigs[i];var region:=Rect2(rig.rect[0],rig.rect[1],rig.rect[2],rig.rect[3]);var pivot:=Vector2(rig.pivot[0],rig.pivot[1])
		view.draw_set_transform(target.position+pivot*view.zoom,angle(view,site,i,active.has(i)))
		view.draw_texture_rect_region(texture,Rect2((region.position-pivot)*view.zoom,region.size*view.zoom),region)
		view.draw_set_transform(Vector2.ZERO)
func detailed(view:Node,site:Dictionary)->bool:
	if view.world.standard.sites.has(site.id) and view.world.standard.ready(view.world.standard.sites[site.id].target):return false
	return view.hover_id==site.id or (view.world.actors.human.region_id==site.region_id and view.world.point(view.world.actors.human).distance_to(view.world.point(site))<=6)
func quiet_marker(view:Node,site:Dictionary,p:Vector2)->void:
	# Small stakes, rope and plaque; no filled footprint or distant cost overlay.
	for x in [-25,25]:
		view.draw_rect(Rect2(p+Vector2(x-2,-18)*view.zoom,Vector2(5,22)*view.zoom),Color("816044"))
		view.draw_rect(Rect2(p+Vector2(x-1,-19)*view.zoom,Vector2(3,3)*view.zoom),Color("c5a875"))
	view.draw_polyline(PackedVector2Array([p+Vector2(-23,-13)*view.zoom,p+Vector2(0,-9)*view.zoom,p+Vector2(25,-13)*view.zoom]),Color("c6b48d"),maxf(1,view.zoom))
	var size:int=11 if view.zoom>=1 else 8
	var text_size:Vector2=view.font.get_string_size(LocalText.content(site.name),HORIZONTAL_ALIGNMENT_LEFT,-1,size)
	view.draw_rect(Rect2(p+Vector2(-text_size.x/2-4,3),Vector2(text_size.x+8,size+6)),Color("735941"))
	view.draw_string(view.font,p+Vector2(-text_size.x/2,size+4),LocalText.content(site.name),HORIZONTAL_ALIGNMENT_LEFT,-1,size,Color("eee1bf"))
	if detailed(view,site):
		var text:String=LocalText.text("ui.leisure_renderer.wood_s_s_deliver_build")%[site.invested,view.world.leisure.cost(site)]
		view.draw_style_box(_hint_box(),Rect2(p+Vector2(-115,-58),Vector2(230,29)))
		view.draw_string(view.font,p+Vector2(-107,-37),text,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("fff4db"))
func _hint_box()->StyleBoxFlat:
	var box:=StyleBoxFlat.new();box.bg_color=Color("30483cec");return box
func actor_offset(view: Node,actor: Dictionary) -> Vector2:
	if actor.activity!="swinging":return Vector2.ZERO
	var job: Dictionary=view.world.work.jobs.get(actor.id,{})
	var site: Dictionary=view.world.leisure.sites.get(job.get("target_id",""),{})
	if site.is_empty():return Vector2.ZERO
	var art: Dictionary=view.world.leisure.art(site);var rigs: Array=art.recreation.get("rigs",[]);var index:=int(job.get("slot",0))
	if index>=rigs.size():return Vector2(0,-absf(sin(view.clock*2.3))*6)
	var rig: Dictionary=rigs[index];var a:=angle(view,site,index,true)
	var pivot:=Vector2(rig.pivot[0],rig.pivot[1]);var seat:=Vector2(rig.seat[0],rig.seat[1]);var slot: Array=art.recreation.slots[index]
	return pivot+(seat-pivot).rotated(a)-Vector2(art.anchor[0],art.anchor[1])-Vector2(slot[0],slot[1])*32

func chessboard(view: Node,site: Dictionary,target: Rect2) -> void:
	var art: Dictionary=view.world.leisure.art(site)
	var authored: Array=art.recreation.get("board_rect",[art.width*.23,art.height*.32,art.width*.54,art.height*.23])
	var rect: Rect2=Rect2(target.position+Vector2(authored[0],authored[1])*view.zoom,Vector2(authored[2],authored[3])*view.zoom)
	view.draw_rect(rect.grow(3*view.zoom),Color("dfc18d"))
	for index in range(15):
		var ratio: float=index/14.0
		view.draw_line(rect.position+Vector2(rect.size.x*ratio,0),rect.position+Vector2(rect.size.x*ratio,rect.size.y),Color("88704b"),maxf(.5,view.zoom))
		view.draw_line(rect.position+Vector2(0,rect.size.y*ratio),rect.position+Vector2(rect.size.x,rect.size.y*ratio),Color("88704b"),maxf(.5,view.zoom))
	var history: Array=view.world.gomoku.sessions.get(site.id,{}).get("history",[])
	for index in range(history.size()):
		var p: Array=history[index]
		view.draw_circle(rect.position+Vector2(p[0]/14.0*rect.size.x,p[1]/14.0*rect.size.y),maxf(1.2,2*view.zoom),Color("263f43") if index%2==0 else Color("fff4de"))
func chess_gesture(view: Node,actor: Dictionary) -> void:
	var job: Dictionary=view.world.work.jobs.get(actor.id,{})
	if job.get("intent")!="play_gomoku" or job.get("step")!="using":return
	for effect in view.effects:
		if effect.kind!="gomoku_stone" or effect.actor_id!=actor.id:continue
		var age: float=clampf((view.clock-effect.started)/.8,0,1)
		var point: Vector2=view.screen(view.world.point(actor))
		var side: float=1 if actor.facing=="right" else -1
		var texture: Texture2D=view.fishing_renderer._grip_texture(view,actor)
		view.draw_set_transform(point+Vector2(side*(18+sin(age*PI)*12),-40)*view.zoom,side*.6)
		view.draw_texture_rect(texture,Rect2(Vector2(-4,-8)*view.zoom,Vector2(8,17)*view.zoom),false)
		view.draw_circle(Vector2(0,-8)*view.zoom,3*view.zoom,Color("cfaa76"))
		view.draw_set_transform(Vector2.ZERO)
