"""Make comparison loops from unscaled, real Godot viewport crops."""
from pathlib import Path
from PIL import Image,ImageDraw
import sys
p=Path(sys.argv[1])
def compare(target,left,right,label_left,label_right):
 frames=[]
 for i in range(60):
  canvas=Image.new('RGB',(640,370),'#eee4ca')
  for x,mode in [(0,left),(320,right)]:canvas.paste(Image.open(p/f'human-{mode}-{i:02}.png').convert('RGB').crop((320,80,640,420)),(x,30))
  d=ImageDraw.Draw(canvas);d.text((12,8),label_left,fill='black');d.text((332,8),label_right,fill='black');frames.append(canvas)
 frames[0].save(p/target,save_all=True,append_images=frames[1:],duration=50,loop=0,optimize=False)
compare('human-side-walk-run.gif','walk','run','WALK','RUN / human v3')
compare('human-program-before-after.gif','run-before','run','RUN / previous','RUN / human v3')
frames=[]
for i in range(60):
 im=Image.open(p/f'five-run-{i:02}.png').convert('RGB').crop((0,175,960,455));frames.append(im)
frames[0].save(p/'five-personalities-run.gif',save_all=True,append_images=frames[1:],duration=50,loop=0,optimize=False)
