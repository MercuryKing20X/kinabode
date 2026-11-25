extends RefCounted

const MARKS={
	"heart":[".##.##.","#######","#######",".#####.","..###..","...#..."],
	"sweat":["...#...","..##...","..###..",".#####.",".##.##.","..###.."],
	"anger":["##...##","..#.#..","##...##","..#.#..","##...##"],
	"note":["...###.","...#..#","...#...","...#...",".###...",".###..."],
	"quiet":[".......",".......","##.##.#","##.##.#"],
	"alert":["..###..","..###..","...#...","...#...",".......","...#..."],
	"question":["..###..",".#...#.","....#..","...#...",".......","...#..."],
	"sleep":["....###",".....#.","....###","###....",".#.....","###...."],
	"spark":["...#...","...#...","..###..","#######","..###..","...#...","...#..."],
	"rain":["...##..",".#####.","#######","#######",".......","..#..#.",".#..#.."],
}
const MOODS={"joy":"note","tired":"sleep","missing":"heart","curious":"question","hurt":"rain","safe":"heart"}
const INKS={"heart":"d84c70","anger":"a94658","sweat":"4393bd","rain":"627da1","spark":"ae7429","note":"6b538d"}
static var textures:Dictionary={}

static func texture(mark:String)->Texture2D:
	if textures.has(mark):return textures[mark]
	var img:=Image.create_empty(15,15,false,Image.FORMAT_RGBA8)
	for y in range(15):
		for x in range(15):
			var r:float=Vector2(x-7,y-7).length_squared()
			if r<=49:img.set_pixel(x,y,Color("453849") if r>35 else Color("fff9ed"))
	img.set_pixel(3,4,Color.WHITE);img.set_pixel(4,3,Color.WHITE);img.set_pixel(5,3,Color.WHITE)
	var mask:Array=MARKS.get(mark,MARKS.quiet)
	var ink:=Color(str(INKS.get(mark,"55455e")))
	for y in mask.size():
		for x in mask[y].length():
			if mask[y][x]=="#":img.set_pixel(x+4,y+7-int(mask.size()/2.0),ink)
	textures[mark]=ImageTexture.create_from_image(img)
	return textures[mark]

static func paint(canvas:CanvasItem,at:Vector2,mark:String,size:float,age:float,duration:float)->void:
	if age<0 or age>=duration:return
	var scale:float=lerpf(.6,1.1,clampf(age/.14,0,1)) if age<.14 else lerpf(1.1,1,clampf((age-.14)/.16,0,1))
	var width:float=size*scale
	canvas.draw_texture_rect(texture(mark),Rect2(at-Vector2.ONE*width*.5,Vector2.ONE*width),false,Color(1,1,1,clampf((duration-age)/.4,0,1)))
