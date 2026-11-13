extends RefCounted
## Seeded original stonework, composed with the game's existing flower sprites.
static var cached:Texture2D
static var soil_cached:Texture2D
static func texture(planted:bool=true)->Texture2D:
	if planted and cached!=null:return cached
	if not planted and soil_cached!=null:return soil_cached
	var image:=Image.create(224,128,false,Image.FORMAT_RGBA8)
	var rng:=RandomNumberGenerator.new();rng.seed=11042026
	for y in range(14,118):
		for x in range(8,216):
			var radius:float=pow((x-112.0)/102,2)+pow((y-62.0)/48,2)
			if radius>1.12:continue
			if radius<.67:
				var grain:float=rng.randf_range(-.035,.035)
				image.set_pixel(x,y,Color(.31+grain,.245+grain,.16+grain));continue
			var row:int=(y-14)/11;var bx:int=(x+row%2*9)/19
			var seam:bool=(y-14)%11==0 or (x+row%2*9)%19==0
			var shade:float=float((bx*7+row*11)%9)*.009+rng.randf_range(-.025,.025)
			var c:=Color(.52+shade,.50+shade,.40+shade)
			if seam:c=Color("68634d")
			elif (y-14)%11<3:c=Color(.70+shade,.68+shade,.54+shade)
			elif (y-14)%11>8:c=Color(.42+shade,.43+shade,.34+shade)
			if radius>.95 and y>66:c=c.darkened(.13)
			image.set_pixel(x,y,c)
	if planted:
		var flowers:=preload("res://scripts/bundled_image.gd").read("res://assets/island/flowers.png")
		flowers.resize(46,46,Image.INTERPOLATE_NEAREST)
		for at in [Vector2i(26,30),Vector2i(62,19),Vector2i(99,26),Vector2i(139,22),Vector2i(54,53),Vector2i(95,56),Vector2i(134,50)]:
			image.blend_rect(flowers,Rect2i(0,0,46,46),at)
	if not planted:
		soil_cached=ImageTexture.create_from_image(image);return soil_cached
	cached=ImageTexture.create_from_image(image);return cached
