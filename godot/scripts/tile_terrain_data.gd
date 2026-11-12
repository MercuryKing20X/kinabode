class_name TileTerrainData
extends RefCounted
## Independent authored terrain data. No routes, actors, inventory or clocks.
const MATERIALS=["deep_water","shallow_water","sand","grass","soil","stone"]
var width:=0
var height:=0
var revision:=0
var error:=""
var _cells:Array=[]
func rect_valid(v:Variant,w:int,h:int)->bool:
	return v is Array and v.size()==4 and v.all(func(n):return (n is int or n is float) and is_finite(n) and n==floor(n)) and v[0]>=0 and v[1]>=0 and v[2]>0 and v[3]>0 and v[0]+v[2]<=w and v[1]+v[3]<=h
func load_data(data:Dictionary)->bool:
	if data.get("version")!=1 or not data.get("size") is Array or data.size.size()!=2:error="invalid terrain header";return false
	for n in data.size:
		if not (n is int or n is float) or not is_finite(n) or n!=floor(n) or n<1 or n>256:error="invalid terrain size";return false
	var w:=int(data.size[0]);var h:=int(data.size[1])
	if data.get("default_material") not in MATERIALS:error="invalid terrain material";return false
	for group in ["patches","plateaus","stairs"]:
		if not data.get(group) is Array or data[group].size()>512:error="invalid terrain group";return false
		for entry in data[group]:
			if not entry is Dictionary or not rect_valid(entry.get("rect"),w,h):error="invalid terrain rectangle";return false
			if group=="patches" and entry.get("material") not in MATERIALS:error="invalid patch material";return false
			if group=="plateaus" and (not entry.get("half_levels") is float and not entry.get("half_levels") is int or float(entry.half_levels)!=floor(float(entry.half_levels)) or entry.half_levels<0 or entry.half_levels>8):error="invalid height";return false
	var next:Array=[]
	for i in range(w*h):next.append({"material":data.default_material,"height":0,"stairs":false})
	for group in ["patches","plateaus","stairs"]:
		for entry in data[group]:
			for y in range(int(entry.rect[1]),int(entry.rect[1]+entry.rect[3])):
				for x in range(int(entry.rect[0]),int(entry.rect[0]+entry.rect[2])):
					var cell:Dictionary=next[y*w+x]
					if group=="patches":cell.material=entry.material
					elif group=="plateaus":cell.height=int(entry.half_levels)
					else:cell.stairs=true;cell.material="stone"
	width=w;height=h;_cells=next;revision+=1;error="";return true
func inside(at:Vector2i)->bool:return at.x>=0 and at.y>=0 and at.x<width and at.y<height
func cell(at:Vector2i)->Dictionary:return _cells[at.y*width+at.x].duplicate(true) if inside(at) else {}
func set_cell(at:Vector2i,value:Dictionary)->bool:
	if not inside(at) or value.size()!=3 or value.get("material") not in MATERIALS or not value.get("stairs") is bool:return false
	if not (value.get("height") is int or value.get("height") is float) or not is_finite(value.height) or value.height!=floor(value.height) or value.height<0 or value.height>8:return false
	if value.stairs and value.material in ["deep_water","shallow_water"]:return false
	if _cells[at.y*width+at.x]==value:return true
	_cells[at.y*width+at.x]=value.duplicate(true);revision+=1;return true
func cliff(at:Vector2i)->bool:
	var own:=cell(at)
	if own.is_empty() or own.stairs:return false
	var above:=cell(at+Vector2i.UP)
	return not above.is_empty() and int(above.height)>int(own.height)
func walkable(at:Vector2i)->bool:
	var own:=cell(at)
	return not own.is_empty() and own.material not in ["deep_water","shallow_water"] and not cliff(at)
func can_step(a:Vector2i,b:Vector2i)->bool:
	if not walkable(a) or not walkable(b) or absi(a.x-b.x)+absi(a.y-b.y)!=1:return false
	var from:=cell(a);var to:=cell(b);var difference:=absi(int(from.height)-int(to.height))
	return difference==0 or difference==1 and (from.stairs or to.stairs)
func edge_mask(at:Vector2i)->int:
	var own:=cell(at);var mask:=0
	if own.is_empty():return 0
	var offsets:=[Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]
	for i in range(4):
		var other:=cell(at+offsets[i])
		if not other.is_empty() and other.material!=own.material:mask|=1<<i
	return mask
