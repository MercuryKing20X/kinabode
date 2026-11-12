"""Original deterministic hand-pixel kitten, no image model or reused resident art."""
from pathlib import Path
import struct,zlib,json
out=Path('godot/assets/cat');out.mkdir(exist_ok=True)
colors=['00000000','66452fff','df8a43ff','f3b55eff','ffe4b2ff','f7f0ddff','443a32ff']
names=['walk','run','sit','sleep','stretch','lick','butterfly','rub','belly','held','pet','jump']
frames={}
for a,name in enumerate(names):
 for d in ['down','left','right','up']:
  for t in range(2):
   p=[[0]*24 for _ in range(24)]
   def rect(x,y,w,h,c):
    for yy in range(max(0,y),min(24,y+h)):
     for xx in range(max(0,x),min(24,x+w)):p[yy][xx]=c
   low=name in ['sleep','belly'];y=12 if low else 8
   rect(6,y+5,12,7,1);rect(7,y+5,10,6,2);rect(7,y+5,7,3,3)
   rect(5,y,12,9,1);rect(6,y+1,10,7,3);rect(5,y-2,3,4,1);rect(14,y-2,3,4,1);rect(6,y-1,1,3,2);rect(15,y-1,1,3,2)
   if d!='up':
    rect(8,y+4,1,1 if name in ['sleep','pet'] else 2,6);rect(13,y+4,1,1 if name in ['sleep','pet'] else 2,6);rect(10,y+6,2,1,1);rect(8,y+6,2,2,4);rect(12,y+6,2,2,4)
   rect(9,y+1,1,2,2);rect(12,y+1,1,2,2)
   rect(17,y+7,4,3,2);rect(20,y+5-t,2,4,5)
   if not low:
    rect(7,y+11,3,2+(t if name in ['walk','run'] else 0),1);rect(14,y+11,3,2+((1-t) if name in ['walk','run'] else 0),1)
   if d=='left':p=[row[::-1] for row in p]
   raw=b''.join(b'\0'+b''.join(bytes.fromhex(colors[c]) for c in row) for row in p)
   def chunk(k,v):return struct.pack('>I',len(v))+k+v+struct.pack('>I',zlib.crc32(k+v)&0xffffffff)
   file=f'{name}_{d}_{t}.png';(out/file).write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>2I5B',24,24,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(raw))+chunk(b'IEND',b''));frames[file]={'original_hand_pixel':True,'size':[24,24]}
(out/'provenance.json').write_text(json.dumps({'author':'Codex original hand pixel','generator':'tools/art/draw_kitten.py','palette':colors,'light':'upper-left','frames':frames},indent=2))
