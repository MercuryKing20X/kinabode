"""Copy complete approved house masters and lossless cutouts; never synthesize house geometry."""
from pathlib import Path
import copy,json,hashlib,colorsys
from PIL import Image,ImageOps,ImageDraw
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'godot/content/house-retrofits';ART=ROOT/'production/art/island-v3-houses'
def read(n):return json.loads((ROOT/'godot/content/works'/f'{n}.json').read_text())
def raster(a,frame='stage_4'):
 im=Image.new('RGBA',(a['width'],a['height']))
 for layer in a['frames'][frame]:
  if not layer['visible']:continue
  q=Image.new('RGBA',im.size);q.putdata([tuple(bytes.fromhex(a['palette'][int(i)][1:])) for i in layer['pixels']]);im.alpha_composite(q)
 return im
masters={n:read(n) for n in ['cottage','cottage-blue','cottage-large']}
# Rectangles and optional cut selections refer only to existing master pixels.
parts={
 'roof-segment':('cottage',[75,76,40,34],None),
 'wall-segment':('cottage',[34,141,14,38],None),
 'window':('cottage',[48,143,37,42],None),
 'narrow-window':('cottage-blue',[177,141,27,40],None),
 'door':('cottage',[139,160,32,60],None),
 'porch-landing':('cottage-large',[134,216,57,30],None),
 'chimney':('cottage-large',[151,29,34,45],[(3,8),(14,1),(30,7),(33,37),(23,44),(5,38)]),
 'steps':('cottage',[138,223,53,23],None),
 'flower-box':('cottage',[175,181,34,46],[(7,10),(16,1),(27,5),(33,17),(28,38),(19,45),(9,43),(3,28),(1,17)]),
 'eaves':('cottage',[66,141,62,33],None),
 'attic-window':('cottage-blue',[134,105,35,38],None),
}
cutouts={};manifest={'source_hashes':{},'parts':{},'houses':{},'no_new_drawing':True}
for n,a in masters.items():
 manifest['source_hashes'][n]=hashlib.sha256((ROOT/'godot/content/works'/f'{n}.json').read_bytes()).hexdigest()
 raster(a).save(ART/f'master-{n}.png')
def encode(im,palette):
 lookup={v:i for i,v in enumerate(palette)};pixels=[]
 for rgba in im.getdata():
  c='#%02x%02x%02x%02x'%rgba if rgba[3] else '#00000000'
  if c not in lookup:lookup[c]=len(palette);palette.append(c)
  pixels.append(lookup[c])
 return {'id':'pixels','name':'原作品像素分片','visible':True,'pixels':pixels}
def save(a,path):path.write_text(json.dumps(a,ensure_ascii=False,separators=(',',':'))+'\n')
for key,(parent,box,selection) in parts.items():
 im=raster(masters[parent]).crop((box[0],box[1],box[0]+box[2],box[1]+box[3]))
 if selection:
  # This is a cut selection, not painting or generating any pixel colors.
  mask=Image.new('L',im.size);ImageDraw.Draw(mask).polygon(selection,fill=255)
  alpha=im.getchannel('A');import PIL.ImageChops
  im.putalpha(PIL.ImageChops.multiply(alpha,mask))
 cutouts[key]=im;palette=['#00000000'];layer=encode(im,palette)
 a={'schema_version':1,'id':'retrofit-part-'+key,'name':key,'kind':'facility','facility_type':'furniture','revision':1,'width':im.width,'height':im.height,'anchor':[im.width//2,im.height], 'palette':palette,'frames':{'down':[layer],'up':[copy.deepcopy(layer)]},'provenance':{'parent':parent,'frame':'stage_4','rect':box,'cut_selection':selection}}
 save(a,OUT/'parts'/f'{key}.json');im.save(ART/f'part-{key}.png');manifest['parts'][key]=a['provenance']
plans={
 'human':{'parent':'cottage-large','parts':[('chimney',[111,38])],'fallback':'原大屋与小屋图像相同；保留原门阶作为门廊落脚台，不虚构带顶门廊。第二烟囱为原件完整裁切。'},
 'gentle':{'parent':'cottage','parts':[('flower-box',[48,181])],'fallback':'花箱实际来自原有花盆组合，保留原盆形；花架放院子，不改屋体。'},
 'curious':{'parent':'cottage-blue','parts':[],'fallback':'蓝屋已有阁楼窗，保留原位置，不额外切开屋顶插新窗。望远镜放院子。'},
 'lively':{'parent':'cottage','mirror':True,'parts':[],'fallback':'保留母版原有宽侧窗；加宽拼接会破坏窗框与透视，因此不硬拼。风铃晾衣绳放院子。'},
 'quiet':{'parent':'cottage-blue','dark_wood':True,'parts':[],'fallback':'侧面窄窗移到正面透视不一致，因此保留原窗。仅木梁/门原木色内调深，院子配长椅。'},
}
allowed=set(c for a in masters.values() for c in a['palette'] if c[-2:]!='00')
wood_candidates=[]
for c in sorted(allowed):
 r,g,b,alpha=bytes.fromhex(c[1:]);h,s,v=colorsys.rgb_to_hsv(r/255,g/255,b/255)
 if .025<h<.14 and s>.25:wood_candidates.append((r,g,b,alpha))
for key,plan in plans.items():
 a=copy.deepcopy(masters[plan['parent']]);a.update(id='retrofit-house-'+key,name='母版改装·'+key,revision=1,art_scale=1,provenance=plan)
 a['openings']={'windows':[[48,143,37,42],[177,141,27,40],[134,105,35,38]]}
 if plan.get('mirror'):a['openings']['windows']=[[240-x-w,y,w,h] for x,y,w,h in a['openings']['windows']]
 recolors={};actual=[]
 for frame in a['frames']:
  im=raster(masters[plan['parent']],frame)
  if plan.get('mirror'):im=ImageOps.mirror(im)
  if plan.get('dark_wood'):
   px=im.load()
   for y in range(132,im.height):
    for x in range(im.width):
     c=px[x,y];r,g,b,alpha=c;h,s,v=colorsys.rgb_to_hsv(r/255,g/255,b/255)
     if alpha and .025<h<.14 and s>.35 and r>g*1.22:
      if c not in recolors:recolors[c]=min(wood_candidates,key=lambda q:sum((q[i]-c[i]*.80)**2 for i in range(3)))
      px[x,y]=recolors[c]
  layers=[dict(encode(im,a['palette']),id='master',name='完整母版（镜像/原木调深仅按标记）')]
  if frame=='stage_4':
   for part,at in plan['parts']:
    overlay=Image.new('RGBA',im.size);overlay.paste(cutouts[part],tuple(at));layers.append(dict(encode(overlay,a['palette']),id='part-'+part,name='原件·'+part));actual.append(part)
  a['frames'][frame]=layers
 a['provenance']['used_parts']=actual;a['provenance']['recolors']={str(c):q for c,q in recolors.items()}
 assert all(c in allowed or c[-2:]=='00' for c in a['palette'])
 save(a,OUT/'houses'/f'{key}.json');raster(a).save(ART/f'house-{key}.png');manifest['houses'][key]=a['provenance']
(OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
print('Copied 11 lossless parts and five full-master derivatives; original sources unchanged.')
