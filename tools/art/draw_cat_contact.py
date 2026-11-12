"""New contact poses, sourced only from idle frames plus newly painted arms.
Original character JSON is read only; no pickup/putdown frame is used.
"""
import json,struct,zlib,hashlib
from pathlib import Path
root=Path('godot/content/characters');out=Path('godot/assets/cat-contact');out.mkdir(exist_ok=True)
ids=['human-starter','white-haired-girl','blue-haired-girl','orange-haired-girl','black-scarf-girl']+json.load(open(root/'spare-catalog.json'))['character_ids']
manifest={}
for id in dict.fromkeys(ids):
 source=root/(id+'.json')
 x=json.load(open(source));w=x['width'];h=x['height'];pal=[bytes.fromhex(c.lstrip('#')) for c in x['palette']]
 if len(pal[0])==3:pal=[c+b'\xff' for c in pal]
 for direction in ['down','up','left','right']:
  layers=x['frames'][direction+'_0'];base=[b'\x00\x00\x00\x00']*(w*h)
  for layer in layers:
   if not layer.get('visible',True):continue
   for i,v in enumerate(layer['pixels']):
    if pal[v][3]:base[i]=pal[v]
  for action in ['hold','pet']:
   for column in range(2):
    pixels=base.copy();cx=w//2;cy=int(h*.58)+(h//8 if action=='pet' else 0);offset=-w//7 if direction=='left' else w//7 if direction=='right' else 0
    # Direction-specific arm arcs, shoulder to cradling or reaching hand.
    for side in [-1,1]:
     start=(cx+side*w//7+offset,cy);end=(cx+side*w//14+offset,cy+h//12+column);steps=max(1,int(((start[0]-end[0])**2+(start[1]-end[1])**2)**.5))
     for n in range(steps+1):
      px=round(start[0]+(end[0]-start[0])*n/steps);py=round(start[1]+(end[1]-start[1])*n/steps)
      for radius,color in [(2,bytes.fromhex('634b43ff')),(1,bytes.fromhex('f3c9a1ff'))]:
       for yy in range(max(0,py-radius),min(h,py+radius+1)):
        for xx in range(max(0,px-radius),min(w,px+radius+1)):pixels[yy*w+xx]=color
    def chunk(k,v):return struct.pack('>I',len(v))+k+v+struct.pack('>I',zlib.crc32(k+v)&0xffffffff)
    raw=b''.join(b'\0'+b''.join(pixels[y*w:(y+1)*w]) for y in range(h))
    name=f'{id}-{action}-{direction}-{column}.png';data=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>2I5B',w,h,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(raw))+chunk(b'IEND',b'');(out/name).write_bytes(data)
    manifest[name]={'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'source_frame':direction+'_0','method':'idle composite plus new painted contact arms','independent_full_body':False,'sha256':hashlib.sha256(data).hexdigest()}
(out/'provenance.json').write_text(json.dumps({'generator':'tools/art/draw_cat_contact.py','frames':manifest,'note':'All outfits use explicitly disclosed composite fallback; no pickup frames. Full independently redrawn bodies remain unavailable.'},indent=2))
print('contact frames',len(manifest))
