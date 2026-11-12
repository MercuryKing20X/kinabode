from pathlib import Path
from PIL import Image,ImageDraw
import sys
p=Path(sys.argv[1])
for actor in ['companion-2','codex','npc.mira','npc.nora']:
 frames=[]
 for i in range(60):
  out=Image.new('RGB',(640,360),'#eee4ca')
  for n,mode in enumerate(['walk','run']):
   im=Image.open(p/f'{actor}-{mode}-{i:02}.png').convert('RGB').crop((320,70,640,390));out.paste(im,(n*320,30))
  d=ImageDraw.Draw(out);d.text((12,8),'WALK / original',fill='black');d.text((332,8),'RUN / distance phase',fill='black');frames.append(out)
 frames[0].save(p/f'{actor}-side-compare.gif',save_all=True,append_images=frames[1:],duration=50,loop=0,optimize=False)
