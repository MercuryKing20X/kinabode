extends RefCounted

# Front: left/right eye and mouth. Profiles contain only the visible eye.
const POINTS={
	"white-haired-girl":{"down":[[37,62],[56,62],[47,73]],"left":[[29,62],[26,72]],"right":[[66,62],[69,72]]},
	"blue-haired-girl":{"down":[[37,50],[57,50],[47,61]],"left":[[33,47],[29,59]],"right":[[62,47],[66,59]]},
	"black-scarf-girl":{"down":[[34,51],[53,50],[44,61]],"left":[[31,49],[27,59]],"right":[[64,49],[68,59]]},
	"orange-haired-girl":{"down":[[36,50],[56,50],[47,61]],"left":[[32,49],[30,61]],"right":[[63,49],[65,61]]},
	"orange-sunflower-girl":{"down":[[37,34],[57,34],[47,43]],"left":[[32,34],[29,45]],"right":[[63,34],[66,45]]},
}
var cache:Dictionary={}

func draw(view:Node2D,library:RefCounted,art:Dictionary,dir:String,expression:String)->void:
	var id:String=art.id
	if expression.is_empty() or not POINTS.get(id,{}).has(dir):return
	if not cache.has(id):
		var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/characters/"+id+".json"))
		cache[id]=source
	var key:String=id+":"+str(art.revision)+":"+dir+":"+expression
	if not cache.has(key):
		var source:Dictionary=cache[id]
		var frame:=dir+"_0"
		if art.frames.get(frame)!=source.frames.get(frame) or art.palette!=source.palette or art.anchor!=source.anchor or art.width!=source.width or art.height!=source.height:return
		var image:=Image.create_empty(art.width,art.height,false,Image.FORMAT_RGBA8)
		var points:Array=POINTS[id][dir]
		for i in points.size()-1:
			var x:int=points[i][0];var y:int=points[i][1]
			if expression in ["blink","pat"]:
				var base:Image=library.render(art,frame)
				var skin:Color=base.get_pixel(x,y+7)
				if skin.a>0:
					image.fill_rect(Rect2i(x-3,y-2,7,7),skin)
					image.fill_rect(Rect2i(x-2,y+2,5,1),Color("503448"))
					image.set_pixel(x+(2 if i==0 else -2),y+1,Color("503448"))
			if expression in ["blush","pat"]:
				for n in 3:image.fill_rect(Rect2i(x-3+n*2,y+6-n%2,1,2),Color("#dc7386bb"))
			if expression=="tear":
				image.fill_rect(Rect2i(x,y+4,2,6),Color("#8acde8dd"))
			if expression=="anger":
				for n in 5:image.set_pixel(x-2+n,y-4+(n/2 if i==0 else (4-n)/2),Color("593343"))
		if expression=="mouth":
			var m:Array=points[-1]
			image.fill_rect(Rect2i(m[0]-2,m[1]-1,5,3),Color("733d46"))
			image.fill_rect(Rect2i(m[0]-1,m[1]+1,3,1),Color("df8886"))
		cache[key]=ImageTexture.create_from_image(image)
	view.draw_texture_rect(cache[key],Rect2(-Vector2(art.anchor[0],art.anchor[1])*view.zoom,Vector2(art.width,art.height)*view.zoom),false)
