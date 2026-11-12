from pathlib import Path
from PIL import Image
import json
ROOT=Path(__file__).resolve().parents[2];SRC=ROOT/'output/imagegen/playgrounds-20261024';OUT=ROOT/'godot/assets/playgrounds';OUT.mkdir(exist_ok=True)
image=Image.open(SRC/'structures-keyed.png').convert('RGBA')
for col,(key,name,behavior,slots,depth) in enumerate([('swing','双人秋千','swing',[[-1.25,0],[1.25,0]],5),('gazebo','茶歇凉亭','sit',[[-1.5,-.5],[1.5,-.5],[-1.5,1.3],[1.5,1.3]],6),('stage','林间舞台','dance',[[-1.5,-.5],[1.5,-.5],[-1.5,1.3],[1.5,1.3]],6)]):
 tile=image.crop((col*512,0,(col+1)*512,1024))
 tile.putdata([(0,0,0,0) if r>110 and b>90 and min(r,b)>g*1.4 else (r,g,b,a) for r,g,b,a in tile.getdata()]);tile=tile.crop(tile.getbbox())
 tile.thumbnail((248,248),Image.Resampling.NEAREST)
 canvas=Image.new('RGBA',(256,256));canvas.alpha_composite(tile,((256-tile.width)//2,252-tile.height))
 quant=canvas.convert('RGB').quantize(colors=191,method=Image.Quantize.MEDIANCUT);pal=quant.getpalette();palette=['#00000000']+['#%02x%02x%02xff'%tuple(pal[i:i+3]) for i in range(0,573,3)]
 pixels=[0 if canvas.getpixel((x,y))[3]<128 else quant.getpixel((x,y))+1 for y in range(256) for x in range(256)]
 config={'width':8,'depth':depth,'entry':[0,depth/2],'slots':slots,'obstacles':[[-4,-2,.65,3],[3.35,-2,.65,3]],'behavior':behavior,'seconds':30}
 if key=='swing':config['rigs']=[{'rect':[66,44,49,152],'pivot':[90,44],'seat':[90,183]},{'rect':[137,44,49,152],'pivot':[161,44],'seat':[161,183]}]
 art={'schema_version':1,'id':'play-'+key,'name':name,'kind':'facility','facility_type':'recreation','width':256,'height':256,'anchor':[128,208],'revision':1,'palette':palette,'recreation':config,'frames':{}}
 for frame in ['idle','active']:art['frames'][frame]=[{'id':'structure','name':'设施','visible':True,'pixels':pixels}]
 (ROOT/f'godot/content/works/play-{key}.json').write_text(json.dumps(art,ensure_ascii=False,separators=(',',':')))
 canvas.save(OUT/f'{key}.png')
print('Imported three editable leisure templates')
