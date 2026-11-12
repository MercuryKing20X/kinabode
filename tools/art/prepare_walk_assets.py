"""Non-destructive pixel cleanup of authorized walk sheets; originals never written."""
from pathlib import Path
import json,hashlib,math
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[2];SRC=ROOT/'production/art/actions-redraw-20261105';OUT=ROOT/'godot/content/walk-animations';OUT.mkdir(exist_ok=True)
manifest={'version':1,'columns':6,'works':{}}
for id,base in json.loads((ROOT/'godot/content/run-animations/manifest.json').read_text())['works'].items():
 path=SRC/(id+'-walk-raw.png')
 if not path.exists():continue
 work=json.loads((ROOT/'godot/content/characters'/(id+'.json')).read_text());pal=work['palette']
 colors=np.array([list(bytes.fromhex(c.lstrip('#')))[:3] for c in pal],dtype=np.int32)
 original=work['frames']['down_0'][0]['pixels'];a=np.array(original).reshape(128,96);ys,xs=np.where(a!=0);height=ys.max()-ys.min()+1
 source=Image.open(path).convert('RGBA');atlas=Image.new('RGBA',(576,512));feet=[]
 for row in range(4):
  rowfeet=[]
  for col in range(6):
   # Right mirrors the reviewed left so GLM cannot silently reverse direction.
   sr=1 if row==2 else row
   tile=source.crop((col*source.width//6,sr*source.height//4,(col+1)*source.width//6,(sr+1)*source.height//4))
   ar=np.array(tile);ar[:,:,3]=np.where(ar[:,:,3]>=128,255,0)
   tile=Image.fromarray(ar);box=tile.getbbox()
   if box is None:raise ValueError(id)
   tile=tile.crop(box);tile=tile.resize((max(1,round(tile.width*height/tile.height)),height),Image.Resampling.NEAREST)
   if row==2:tile=tile.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
   # Quantize every opaque pixel to the original work palette, no antialiasing.
   ar=np.array(tile);rgb=ar[:,:,:3].astype(np.int32);flat=rgb.reshape(-1,3);out=[]
   for start in range(0,len(flat),256):
    chunk=flat[start:start+256];nearest=((chunk[:,None,:]-colors[None,:,:])**2).sum(2).argmin(1);out.extend(colors[nearest])
   ar[:,:,:3]=np.array(out,dtype=np.uint8).reshape(rgb.shape)
   tile=Image.fromarray(ar)
   # Pixel cleanup: stagger the lower silhouette and sway the far/near arm
   # in opposition, with zero resampling of the locked head.
   im=Image.new('RGBA',tile.size)
   h=tile.height;w=tile.width;swing=[3,1,-2,-3,-1,2][col]
   for y in range(h):
    shift=0
    if y>h*.72:shift=round(swing*(y/h-.72)/.28)
    im.alpha_composite(tile.crop((0,y,w,y+1)),(shift,y))
   tile=im
   x=(96-tile.width)//2;bob=[0,1,0,0,1,0][col];y=120-tile.height+bob
   atlas.alpha_composite(tile,(col*96+x,row*128+y))
   ys2,xs2=np.where(np.array(tile)[:,:,3]>0);bottom=int(ys2.max());footx=int(np.median(xs2[ys2>=bottom-1]))
   rowfeet.append({'pixel':[x+footx,y+bottom],'airborne':False})
  feet.append(rowfeet)
 atlas.save(OUT/(id+'.png'))
 entry={k:base[k] for k in ['base_frame_sha256','base_palette_sha256']};entry.update(status='independent',asset=id+'.png',feet=feet,source_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),source=str(path.relative_to(ROOT)),provenance='Authorized generated walking source; original-palette nearest-neighbor pixel cleanup; opposite leg silhouette offsets; right mirrored from left. No original work overwritten.')
 manifest['works'][id]=entry
 review=Image.new('RGBA',(576,512),'#59635b');review.alpha_composite(atlas);review.convert('RGB').save(SRC/(id+'-review.png'))
(OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
print('walk sheets',len(manifest['works']))
