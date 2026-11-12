"""Reproducible pixel cleanup of new generated architecture and full-body contact sheets."""
from pathlib import Path
from PIL import Image,ImageDraw
import json,hashlib
from collections import deque
ROOT=Path(__file__).resolve().parents[2];SRC=ROOT/'production/art/houses-redraw-20261104'
HOUSES=ROOT/'godot/assets/houses-redraw';CONTACT=ROOT/'godot/assets/cat-contact-redraw'
HOUSES.mkdir(exist_ok=True);CONTACT.mkdir(exist_ok=True)
ids=['human-starter','white-haired-girl','blue-haired-girl','orange-haired-girl','black-scarf-girl']
names=['human','white','blue','orange','black']
def solid(im):
 im=im.convert('RGBA');im.putalpha(im.getchannel('A').point(lambda x:255 if x>=160 else 0));return im
# One shared limited palette for all five homes, never smooth runtime filtering.
thumbs=[]
for name in names:
 im=solid(Image.open(SRC/(name+'-raw.png')));im=im.crop(im.getbbox());im.thumbnail((232,244),Image.Resampling.NEAREST);thumbs.append(im)
palette_sheet=Image.new('RGB',(240*5,252),(103,112,76))
for i,im in enumerate(thumbs):palette_sheet.paste(im,(i*240,0),im)
palette=palette_sheet.quantize(colors=128,method=Image.Quantize.MEDIANCUT)
manifest={'model':'gpt-image-2.5-flare','endpoint':'configured image service (private endpoint omitted)','light':'upper-left','method':'new full architecture; alpha threshold160, native pixel sampling, shared128-color palette, explicit night light retouch','houses':{},'contact':{}}
# Window locations manually selected against each new sprite (native pixels).
windows={'human':[(99,98,11,17),(140,170,9,15),(115,181,8,12)],'white':[(111,79,12,16),(81,141,10,18),(169,150,10,15)],'blue':[(105,132,12,19),(151,129,9,14),(83,81,13,11)],'orange':[(97,96,12,18),(144,130,10,18),(160,176,8,13)],'black':[(122,133,11,16),(158,159,12,14),(109,91,11,12)]}
for name,im in zip(names,thumbs):
 canvas=Image.new('RGBA',(240,252));canvas.alpha_composite(im,((240-im.width)//2,244-im.height))
 alpha=canvas.getchannel('A');canvas=canvas.convert('RGB').quantize(palette=palette,dither=Image.Dither.NONE).convert('RGBA');canvas.putalpha(alpha)
 canvas.save(HOUSES/(name+'-day.png'))
 night=canvas.copy();px=night.load()
 for y in range(252):
  for x in range(240):
   r,g,b,a=px[x,y];px[x,y]=(round(r*.66),round(g*.71),round(b*.86),a)
 draw=ImageDraw.Draw(night)
 for x,y,w,h in windows[name]:
  # Retouch only existing opaque pixels; never paint outside the building.
  for yy in range(y,y+h):
   for xx in range(x,x+w):
    r,g,b,a=canvas.getpixel((xx,yy))
    if a and r>g*1.10 and g>b*1.25:
     nr,ng,nb,_=night.getpixel((xx,yy));draw.point((xx,yy),fill=(min(255,nr+48),min(255,ng+36),min(255,nb+8),255))
 night.save(HOUSES/(name+'-night.png'))
 manifest['houses'][name]={'raw_sha256':hashlib.sha256((SRC/(name+'-raw.png')).read_bytes()).hexdigest(),'native_size':[240,252],'night_window_retouch':windows[name]}
for id in ids:
 source=SRC/(id+'-contact-raw.png');sheet=solid(Image.open(source));cw=sheet.width//4;ch=sheet.height//4
 cells=[[sheet.crop((c*cw,r*ch,(c+1)*cw,(r+1)*ch)) for c in range(4)] for r in range(4)]
 # Some deployments bake a neutral transparency checkerboard. Remove only
 # edge-connected neutral background; enclosed hair/clothes stay untouched.
 for row in cells:
  for cell in row:
   pix=cell.load();seen=set();queue=deque([(x,0) for x in range(cw)]+[(x,ch-1) for x in range(cw)]+[(0,y) for y in range(ch)]+[(cw-1,y) for y in range(ch)])
   while queue:
    x,y=queue.popleft()
    if (x,y) in seen or x<0 or y<0 or x>=cw or y>=ch:continue
    seen.add((x,y));r,g,b,a=pix[x,y]
    if a==0 or (max(r,g,b)-min(r,g,b)<22 and min(r,g,b)>165):
     pix[x,y]=(0,0,0,0);queue.extend([(x-1,y),(x+1,y),(x,y-1),(x,y+1)])

 heights=[im.getbbox()[3]-im.getbbox()[1] for im in cells[0] if im.getbbox()]
 scale=118/max(heights)
 for col,direction in enumerate(['down','up','left','right']):
  for row in range(4):
   cell=cells[row][col];box=cell.getbbox()
   if box is None:raise RuntimeError('empty authored sheet cell '+id)
   body=cell.crop(box);body=body.resize((max(1,round(body.width*scale)),max(1,round(body.height*scale))),Image.Resampling.NEAREST)
   canvas=Image.new('RGBA',(96,128));canvas.alpha_composite(body,((96-body.width)//2,124-body.height))
   alpha=canvas.getchannel('A');canvas=canvas.convert('RGB').quantize(colors=96,method=Image.Quantize.MEDIANCUT,dither=Image.Dither.NONE).convert('RGBA');canvas.putalpha(alpha)
   action='hold' if row<3 else 'pet';phase=row if row<3 else 0
   name=f'{id}-{action}-{direction}-{phase}.png';canvas.save(CONTACT/name)
   if row==3:
    # Second crouch contact is a held full-body pose, not an idle/arm composite.
    canvas.save(CONTACT/f'{id}-pet-{direction}-1.png')
   manifest['contact'][name]={'raw_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'grid_cell':[col,row],'source':'new generated full body with manual grid/foot alignment and pixel cleanup','independent_full_body':True,'base_idle_pixels_copied':False,'native_size':[96,128]}
(HOUSES/'provenance.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2));(CONTACT/'provenance.json').write_text(json.dumps({'frames':manifest['contact'],'fallback_outfits':json.loads((ROOT/'godot/content/characters/spare-catalog.json').read_text())['character_ids'],'note':'Five defaults use new complete full-body drawings; remaining eight keep explicitly disclosed previous composites.'},ensure_ascii=False,indent=2))
print('prepared new houses and full-body default contact poses')
