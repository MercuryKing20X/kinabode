"""Original deterministic palette sheet, standard-library PNG; no downloaded/model assets."""
import json,struct,zlib,os
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def png(path,w,h,pixels):
 def chunk(k,v):return struct.pack('>I',len(v))+k+v+struct.pack('>I',zlib.crc32(k+v)&0xffffffff)
 raw=b''.join(b'\0'+bytes(pixels[y*w*4:(y+1)*w*4]) for y in range(h))
 path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(raw,9))+chunk(b'IEND',b''))
def generate():
 style=json.loads((ROOT/'godot/content/island-v3-style.json').read_text())
 palette=style['palette'];assert len(palette)==48
 w,h=560,424;bg=bytes.fromhex('101C23')+b'\xff';pixels=bytearray(bg*(w*h))
 for i,entry in enumerate(palette):
  x=12+i%8*68;y=12+i//8*68;color=bytes.fromhex(entry['hex'][1:])+b'\xff'
  for py in range(y,y+60):
   for px in range(x,x+60):pixels[(py*w+px)*4:(py*w+px)*4+4]=color
 png(Path(os.environ.get('HABITAT_PALETTE_OUTPUT',str(ROOT/'production/evidence/island-v3-stage1/palette-48.png'))),w,h,pixels)
if __name__=='__main__':generate()
