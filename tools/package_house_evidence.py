from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[1];source=ROOT/'tmp/house-stages';out=ROOT/'production/evidence'
canvas=Image.new('RGB',(960,788),'#243e35');draw=ImageDraw.Draw(canvas)
font=ImageFont.truetype(str(ROOT/'godot/assets/fonts/NotoSansSC.ttf'),18)
for i,title in enumerate(['选定宅地','地基','框架','墙面','屋顶','完成与院落']):
    image=Image.open(source/f'stage-{i}.png').convert('RGB').crop((420,100,800,530)).resize((320,362),Image.Resampling.LANCZOS)
    x=(i%3)*320;y=(i//3)*394
    canvas.paste(image,(x,y));draw.text((x+14,y+367),title,font=font,fill='#fff1d1')
canvas.save(out/'home-stages.png')
print('Actual construction viewport contact sheet packaged.')
