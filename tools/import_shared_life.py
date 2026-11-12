from pathlib import Path
from PIL import Image,ImageOps
import json
ROOT=Path(__file__).resolve().parents[1]
SRC=ROOT/'output/imagegen/shared-life-20261023'
OUT=ROOT/'godot/assets/island'
WORKS=ROOT/'godot/content/works';WORKS.mkdir(parents=True,exist_ok=True)
def key(image):
 image=image.convert('RGBA');p=image.load()
 for y in range(image.height):
  for x in range(image.width):
   r,g,b,a=p[x,y]
   if r>125 and b>125 and min(r,b)>g*1.45 and g<145:p[x,y]=(0,0,0,0)
 return image
def fit(image,size,scale=None):
 box=image.getbbox()
 if not box:raise ValueError('empty asset')
 image=image.crop(box)
 scale=scale or min((size[0]-8)/image.width,(size[1]-12)/image.height)
 image=image.resize((round(image.width*scale),round(image.height*scale)),Image.Resampling.NEAREST)
 canvas=Image.new('RGBA',size);canvas.alpha_composite(image,(round((size[0]-image.width)/2),size[1]-8-image.height));return canvas
def frame(art,key,image):
 image=image.quantize(colors=128,method=Image.Quantize.FASTOCTREE).convert('RGBA')
 lookup={c:i for i,c in enumerate(art['palette'])};pixels=[]
 for rgba in image.getdata():
  c='#%02x%02x%02x%02x'%rgba if rgba[3] else '#00000000'
  if c not in lookup:lookup[c]=len(art['palette']);art['palette'].append(c)
  pixels.append(lookup[c])
 art['frames'][key]=[{'id':'paint','name':'原画','visible':True,'pixels':pixels}]
def new(id,kind,size):return {'schema_version':1,'id':id,'kind':kind,'revision':1,'width':size[0],'height':size[1],'anchor':[size[0]//2,size[1]-8],'palette':['#00000000'],'frames':{}}
def save(art,path):path.write_text(json.dumps(art,ensure_ascii=False,separators=(',',':'))+'\n')
for id,structure in [('cottage',{'width':8,'depth':7,'floors':1,'porch':0}),('cottage-large',{'width':10,'depth':8,'floors':2,'porch':1})]:
 art=new(id,'building',(240,252));art['name']='林间小屋' if id=='cottage' else '带廊大屋';art['structure']=structure
 for i in range(5):frame(art,f'stage_{i}',Image.open(OUT/f'house_{i}.png').resize((240,252),Image.Resampling.NEAREST))
 save(art,WORKS/(id+'.json'))
sheet=key(Image.open(SRC/'actions.png'))
for row,id in enumerate(['white-haired-girl','human-starter']):
 path=ROOT/'godot/content/characters'/f'{id}.json';art=json.loads(path.read_text())
 for col,name in enumerate(['lighting_0','lighting_1','grilling_0','grilling_1','eating_0','eating_1']):
  tile=sheet.crop((col*256,row*512,(col+1)*256,(row+1)*512))
  # Match standing head/body scale; sitting and crouching remain shorter.
  frame(art,name,fit(tile,(96,128),.36))
 save(art,path)
if (SRC/'barbecue-cutouts.png').exists():
 sheet=key(Image.open(SRC/'barbecue-cutouts.png'));art=new('camp-grill','facility',(192,176));art['name']='野外烧烤'
 for i,name in enumerate(['cold','lit','cooking','embers']):frame(art,name,fit(sheet.crop((i*384,0,(i+1)*384,512)),(192,176)))
 save(art,WORKS/'camp-grill.json')
 for i,name in enumerate(['stool','mushrooms','meal','picnic']):fit(sheet.crop((i*384,512,(i+1)*384,1024)),(100,100)).save(OUT/(name+'.png'))
print('Shared editable building works and real barbecue action frames imported.')
