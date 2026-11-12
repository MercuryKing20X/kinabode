"""Extract approved generated raster sheets; no scene or sprite drawing is synthesized here."""
from pathlib import Path
import json
from PIL import Image, ImageOps, ImageEnhance
ROOT=Path(__file__).resolve().parents[1]
SRC=ROOT/'output/imagegen/island-slice-20261022'
OUT=ROOT/'godot/assets/island';OUT.mkdir(parents=True,exist_ok=True)

def key(image):
    image=image.convert('RGBA')
    pixels=image.load()
    for y in range(image.height):
        for x in range(image.width):
            r,g,b,a=pixels[x,y]
            if r>125 and b>125 and min(r,b)>g*1.45 and g<145: pixels[x,y]=(0,0,0,0)
    return image

def fit(image,size,foot,scale=None):
    box=image.getbbox()
    if box is None:raise ValueError('Empty extracted asset')
    image=image.crop(box)
    factor=scale or min((size[0]-8)/image.width,(size[1]-12)/image.height)
    image=image.resize((max(1,round(image.width*factor)),max(1,round(image.height*factor))),Image.Resampling.NEAREST)
    frame=Image.new('RGBA',size)
    frame.alpha_composite(image,(round(foot[0]-image.width/2),round(foot[1]-image.height)))
    return frame

props=key(Image.open(SRC/'props.png'))
boxes=[(0,0,452,660),(452,0,800,660),(800,0,1165,660),(1165,0,1536,660),(0,680,384,1024),(384,680,768,1024),(768,680,1152,1024),(1152,680,1536,1024)]
names=['oak','oak_small','birch','fir','chest','stump','bush','rock']
for i,(name,box) in enumerate(zip(names,boxes)):
    size=(256,320) if i<4 else (128,112)
    if name=='chest':size=(96,80)
    fit(props.crop(box),size,(size[0]/2,size[1]-8)).save(OUT/(name+'.png'))
# Repeated terrain uses mirrored edge matching, removing hard seams without inventing art.
terrain=Image.open(SRC/'terrain.png').convert('RGB')
for name,(x,y) in zip(['grass','sand','water','soil'],[(0,0),(512,0),(0,512),(512,512)]):
    tile=terrain.crop((x,y,x+512,y+512)).resize((256,256),Image.Resampling.LANCZOS)
    canvas=Image.new('RGB',(512,512));canvas.paste(tile,(0,0));canvas.paste(ImageOps.mirror(tile),(256,0));canvas.paste(ImageOps.flip(tile),(0,256));canvas.paste(ImageOps.flip(ImageOps.mirror(tile)),(256,256))
    if name=='grass':
        canvas=ImageEnhance.Color(canvas).enhance(.68)
        canvas=ImageEnhance.Contrast(canvas).enhance(.6)
    canvas.save(OUT/(name+'.png'))

house=key(Image.open(SRC/'house.png'))
for i in range(6):
    tile=house.crop(((i%3)*512,(i//3)*512,(i%3+1)*512,(i//3+1)*512))
    fit(tile,(400,420),(200,408),scale=.82).save(OUT/f'house_{i}.png')

sheet=key(Image.open(SRC/'characters.png'))
for who,first_col in [('white-haired-girl',0),('human-starter',3)]:
    palette=['#00000000'];lookup={palette[0]:0};frames={}
    for row,direction in enumerate(['down','left','right','up']):
        for frame in range(3):
            source_row=1 if who=='white-haired-girl' and direction=='right' else row
            tile=sheet.crop(((first_col+frame)*256,source_row*256,(first_col+frame+1)*256,(source_row+1)*256))
            if who=='white-haired-girl' and direction=='right':tile=ImageOps.mirror(tile)
            tile=fit(tile,(96,128),(48,120),scale=.5)
            # Indexed source remains fully editable: all frames use this same artwork format.
            quantized=tile.quantize(colors=96,method=Image.Quantize.FASTOCTREE).convert('RGBA')
            data=[]
            for rgba in quantized.getdata():
                value='#%02x%02x%02x%02x'%rgba if rgba[3]>0 else '#00000000'
                if value not in lookup:lookup[value]=len(palette);palette.append(value)
                data.append(lookup[value])
            frames[f'{direction}_{frame}']=[{'id':'paint','name':'原画','visible':True,'pixels':data}]
    artwork={'schema_version':1,'id':who,'name':'白发少女' if who=='white-haired-girl' else '人类主角','revision':1,'width':96,'height':128,'anchor':[48,120],'palette':palette,'frames':frames,'source':'Generated character sheet; keyed, cropped, foot-aligned. Right girl frames mirrored from left to correct generation direction.','license':'Publication license not selected'}
    (ROOT/'godot/content/characters'/f'{who}.json').write_text(json.dumps(artwork,ensure_ascii=False,separators=(',',':'))+'\n')
    preview=Image.new('RGBA',(96*3,128*4))
    for i,(name,layers) in enumerate(frames.items()):
        im=Image.new('RGBA',(96,128));im.putdata([tuple(bytes.fromhex(palette[p][1:])) for p in layers[0]['pixels']]);preview.alpha_composite(im,((i%3)*96,(i//3)*128))
    preview.save(OUT/(who+'-preview.png'))
print('Imported 8 props, 4 seamless terrain textures, 6 building stages and 2 editable 12-frame character artworks.')
if (SRC/'details-v2.png').exists():
    details=key(Image.open(SRC/'details-v2.png'))
    names=['fence_h','fence_v','gate','grass_clump','flowers','barrel','logs','axe']
    sizes=[(150,100),(90,160),(140,110),(100,80),(100,65),(96,100),(70,55),(64,64)]
    for i,(name,size) in enumerate(zip(names,sizes)):
        tile=details.crop(((i%4)*384,(i//4)*512,(i%4+1)*384,(i//4+1)*512))
        fit(tile,size,(size[0]/2,size[1]-4)).save(OUT/(name+'.png'))
    print('Imported fence, gate, foliage, barrel, logs, and axe.')
