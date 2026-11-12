"""Import the reviewed original room and furniture sheet, preserving editable layers."""
from pathlib import Path
import json
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'output/imagegen/interior-20261023'
sheet=Image.open(SOURCE/'furniture-v2.png').convert('RGBA')
OUT=ROOT/'godot/assets/interior';OUT.mkdir(exist_ok=True)
room=Image.open(SOURCE/'room.png').convert('RGBA').resize((768,512),Image.Resampling.NEAREST)
# Flood only the exterior green backdrop; window curtains are enclosed and retained.
from collections import deque
queue=deque([(x,y) for x in range(room.width) for y in (0,room.height-1)]+[(x,y) for y in range(room.height) for x in (0,room.width-1)])
visited=set()
while queue:
 x,y=queue.popleft()
 if (x,y) in visited or not (0<=x<room.width and 0<=y<room.height): continue
 visited.add((x,y));r,g,b,a=room.getpixel((x,y))
 if r<110 and g>r*1.35 and b>r*.7 and not (38 <= x <= 730 and 435 <= y <= 463):
  room.putpixel((x,y),(0,0,0,0));queue.extend(((x-1,y),(x+1,y),(x,y-1),(x,y+1)))
room.save(OUT/'room.png')
def cut(col,row,size):
 im=sheet.crop((col*512,row*512,(col+1)*512,(row+1)*512))
 im.putdata([(0,0,0,0) if r>140 and b>130 and g<r*.64 and g<b*.68 else (r,g,b,a) for r,g,b,a in im.getdata()])
 im=im.crop(im.getbbox());im.thumbnail((size[0]-8,size[1]-8),Image.Resampling.NEAREST)
 canvas=Image.new('RGBA',size);canvas.alpha_composite(im,((size[0]-im.width)//2,size[1]-4-im.height))
 return canvas
for recipe,name,col,row,size in [('table','橡木桌',0,0,(112,112)),('chair','软垫木椅',1,0,(80,112)),('chest','储物箱',2,0,(112,96)),('lamp','暖光木灯',0,1,(80,144)),('rug','木编地垫',1,1,(128,80))]:
 frames={'down':cut(col,row,size)}
 frames['up']=cut(2,1,size) if recipe=='chair' else frames['down'].copy()
 palette=['#00000000']; lookup={(0,0,0,0):0}; layers={}
 for direction,im in frames.items():
  # Quantize RGB and preserve binary alpha, sharing one indexed palette across frames.
  quant=im.convert('RGB').quantize(colors=192).convert('RGB'); pixels=[]
  for rgb,rgba in zip(quant.getdata(),im.getdata()):
   color=(*rgb,255) if rgba[3]>128 else (0,0,0,0)
   if color not in lookup: lookup[color]=len(palette);palette.append('#'+''.join(f'{v:02x}' for v in color))
   pixels.append(lookup[color])
  layers[direction]=[{'name':'家具','visible':True,'pixels':pixels}]
  im.save(OUT/f'{recipe}-{direction}.png')
 artwork={'schema_version':1,'id':f'furniture-{recipe}','name':name,'kind':'facility','facility_type':'furniture','width':size[0],'height':size[1],'anchor':[size[0]//2,size[1]-10 if recipe!='rug' else size[1]//2],'revision':1,'palette':palette,'frames':layers}
 (ROOT/f'godot/content/works/furniture-{recipe}.json').write_text(json.dumps(artwork,ensure_ascii=False,separators=(',',':')))
print('Imported 5 editable furniture works, 10 frame images and the empty room shell.')
