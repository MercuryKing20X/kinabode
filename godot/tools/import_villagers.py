"""Import three authored, distinct resident sheets into the pixel workshop. No API calls."""
from pathlib import Path
from PIL import Image
import json
ROOT=Path(__file__).resolve().parents[2]
SRC=ROOT/'output/imagegen/village-residents-20261024'
OUT=ROOT/'godot/assets/residents';OUT.mkdir(exist_ok=True)
for color,work_id,name in [('blue','blue-haired-girl','阿澄 · 蓝发蓝裙'),('orange','orange-haired-girl','米拉 · 橙发橙裙'),('black','black-scarf-girl','诺拉 · 黑衣红围巾')]:
 source=Image.open(SRC/('orange-keyed.png' if color=='orange' else f'{color}.png')).convert('RGBA')
 cells=[]
 for row in range(4):
  rowcells=[]
  for col in range(6):
   tile=source.crop((col*source.width//6,row*source.height//4,(col+1)*source.width//6,(row+1)*source.height//4))
   tile.putdata([(0,0,0,0) if r>100 and b>90 and min(r,b)>g*1.55 else (r,g,b,a) for r,g,b,a in tile.getdata()])
   rowcells.append(tile.crop(tile.getbbox()))
  cells.append(rowcells)
 # Correct generated left/right pose inconsistencies using the matching opposite pose.
 for col in [0,1,2]: cells[2][col]=cells[1][col].transpose(Image.Transpose.FLIP_LEFT_RIGHT)
 for col in [3,4]: cells[1][col]=cells[2][col].transpose(Image.Transpose.FLIP_LEFT_RIGHT)
 # The generator included stumps in blue/orange strike poses; remove the right-side
 # brown ground prop at source resolution, retaining the axe and clothes.
 if color in ('blue','orange'):
  for row in [0,1,2,3]:
   tile=cells[row][4]; pixels=tile.load()
   for y in range(tile.height):
    for x in range(tile.width):
     r,g,b,a=pixels[x,y]
     on_prop_side=x<tile.width*.42 if row==1 else x>tile.width*.56
     if on_prop_side and y>tile.height*.70 and r>g*1.08 and g>b*1.15 and r<210: pixels[x,y]=(0,0,0,0)
 # Common scale, common ground contact; keep directions and all outfit parts intact.
 scale=min(88/max(c.width for row in cells for c in row),112/max(c.height for row in cells for c in row))
 frames={}
 for row,direction in enumerate(['down','left','right','up']):
  for col,key in enumerate([direction+'_0',direction+'_1',direction+'_2','chop_'+direction+'_0','chop_'+direction+'_1','carry_'+direction]):
   tile=cells[row][col];tile=tile.resize((round(tile.width*scale),round(tile.height*scale)),Image.Resampling.NEAREST)
   canvas=Image.new('RGBA',(96,128));canvas.alpha_composite(tile,((96-tile.width)//2,120-tile.height));frames[key]=canvas
  frames['chop_'+direction+'_2']=frames['chop_'+direction+'_0'].copy()
  frames['carry_'+direction+'_0']=frames['carry_'+direction].copy()
  frames['carry_'+direction+'_1']=frames['carry_'+direction].copy()
  frames['pickup_'+direction]=frames[direction+'_0'].copy()
 strip=Image.new('RGBA',(96*len(frames),128))
 for i,canvas in enumerate(frames.values()):strip.alpha_composite(canvas,(i*96,0))
 quant=strip.convert('RGB').quantize(colors=191,method=Image.Quantize.MEDIANCUT)
 rgb=quant.getpalette();palette=['#00000000']+['#%02x%02x%02xff'%tuple(rgb[i:i+3]) for i in range(0,573,3)]
 work={'schema_version':1,'id':work_id,'name':name,'kind':'character','width':96,'height':128,'anchor':[48,120],'revision':1,'palette':palette,'frames':{}}
 preview=Image.new('RGBA',(96*6,128*4))
 for n,(key,canvas) in enumerate(frames.items()):
  pixels=[0 if canvas.getpixel((x,y))[3]<128 else quant.getpixel((n*96+x,y))+1 for y in range(128) for x in range(96)]
  work['frames'][key]=[{'name':'人物','visible':True,'pixels':pixels}]
  render=Image.new('RGBA',(96,128));render.putdata([tuple(bytes.fromhex(palette[i][1:])) for i in pixels]);render.save(OUT/f'{color}-{key}.png')
  if key in ['down_0','left_0','right_0','up_0']:
   preview.alpha_composite(render,(['down_0','left_0','right_0','up_0'].index(key)*96,0))
 preview.crop((0,0,384,128)).resize((768,256),Image.Resampling.NEAREST).save(SRC/f'{color}-imported.png')
 (ROOT/f'godot/content/characters/{work_id}.json').write_text(json.dumps(work,ensure_ascii=False,separators=(',',':')))
 print('Imported',name,len(frames),'frames')
