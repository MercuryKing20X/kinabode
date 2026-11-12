from pathlib import Path
from PIL import Image,ImageDraw
import sys
p=Path(sys.argv[1])
for actor in ['human','companion-2','npc.nora']:
 for left,name in [('walk','walk-run'),('fallback','old-new')]:
  frames=[]
  for i in range(60):
   out=Image.new('RGB',(640,370),'#eee4ca')
   for x,mode in [(0,left),(320,'run')]:out.paste(Image.open(p/f'{actor}-{mode}-{i:02}.png').convert('RGB').crop((320,80,640,420)),(x,30))
   d=ImageDraw.Draw(out);d.text((12,8),'WALK' if left=='walk' else 'OLD FALLBACK',fill='black');d.text((332,8),'NEW RUN / independent atlas',fill='black');frames.append(out)
  frames[0].save(p/f'{actor}-{name}.gif',save_all=True,append_images=frames[1:],duration=50,loop=0,optimize=False)
