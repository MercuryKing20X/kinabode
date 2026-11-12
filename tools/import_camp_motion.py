from pathlib import Path
from PIL import Image, ImageOps
import json
ROOT=Path(__file__).resolve().parents[1]
SRC=ROOT/'output/imagegen/camp-life-20261023'
sheet=Image.open(SRC/'seating-cutouts.png').convert('RGBA')
pixels=sheet.load()
for y in range(sheet.height):
    for x in range(sheet.width):
        r,g,b,a=pixels[x,y]
        if r>125 and b>125 and min(r,b)>g*1.45 and g<145: pixels[x,y]=(0,0,0,0)
sheet=sheet.quantize(colors=128,method=Image.Quantize.FASTOCTREE).convert('RGBA')
preview=Image.new('RGBA',(96*6,128*2))
for row,identity in enumerate(['white-haired-girl','human-starter']):
    path=ROOT/'godot/content/characters'/f'{identity}.json';art=json.loads(path.read_text());lookup={c:i for i,c in enumerate(art['palette'])}
    for col,name in enumerate(['sitting_down','seated_idle','seated_bite','seated_left','seated_right','standing_up']):
        # Farmer's left-looking source turned forward; use a mirrored right pose.
        source_col=4 if row==1 and col==3 else col
        tile=sheet.crop((source_col*256,row*512,(source_col+1)*256,(row+1)*512))
        if row==1 and col==3: tile=ImageOps.mirror(tile)
        tile=tile.crop(tile.getbbox());scale=.35 if name in ['sitting_down','standing_up'] else .34
        tile=tile.resize((round(tile.width*scale),round(tile.height*scale)),Image.Resampling.NEAREST)
        canvas=Image.new('RGBA',(96,128));canvas.alpha_composite(tile,((96-tile.width)//2,120-tile.height))
        values=[]
        for rgba in canvas.getdata():
            c='#%02x%02x%02x%02x'%rgba if rgba[3] else '#00000000'
            if c not in lookup:lookup[c]=len(art['palette']);art['palette'].append(c)
            values.append(lookup[c])
        art['frames'][name]=[{'id':'paint','name':'营地动作','visible':True,'pixels':values}]
        preview.alpha_composite(canvas,(col*96,row*128))
    art['frames']['rest_empty'] = art['frames']['standing_up']
    assert len(art['palette'])<=4096 and len(art['frames'])<=80
    path.write_text(json.dumps(art,ensure_ascii=False,separators=(',',':'))+'\n')
    print(identity,len(art['frames']),'frames')
preview.save(SRC/'imported.png')
