"""Original paid outdoor templates assembled from original editable pixels."""
import json,copy
from pathlib import Path
root=Path(__file__).resolve().parents[2]
source=root/'godot/content/works'
def write(id,name,base,config):
    art=copy.deepcopy(json.loads((source/(base+'.json')).read_text()))
    art.update(id=id,name=name,kind='facility',facility_type='recreation',recreation=config)
    frames=art['frames']
    if 'down' in frames: art['frames']={'idle':frames['down'],'active':copy.deepcopy(frames['down'])}
    if 'mature' in frames: art['frames']={'idle':frames['mature'],'active':copy.deepcopy(frames['mature'])}
    art.pop('structure',None)
    art['provenance']={'source':base,'mode':'original pixel assembly; no image generation','script':'tools/outdoor/build_templates.py'}
    (source/(id+'.json')).write_text(json.dumps(art,separators=(',',':'),ensure_ascii=False)+'\n')
common={'width':3,'depth':3,'entry':[0,1.5],'slots':[[0,0]],'obstacles':[],'behavior':'sit','seconds':30}
write('outdoor-chair','庭院木椅','furniture-chair',common)
# Preserve original rug wood texture as a laid garden boardwalk; no free placement.
write('outdoor-path','花园木径','furniture-rug',dict(common,behavior='dance'))
path_file=source/'outdoor-path.json'
art=json.loads(path_file.read_text())
art.update(width=96,height=64,anchor=[48,56],palette=['#00000000','#584735ff','#866544ff','#a58356ff','#bc9a69ff','#ceac78ff'])
pixels=[0]*(96*64)
# Four staggered board planks, native pixels, same warm wood/upper-left light.
for y in range(8,56):
    row=(y-8)//12
    left=5+(row%2)*3;right=91-(row%2)*3
    for x in range(left,right):
        edge=(y-8)%12
        c=1 if edge==11 or x==right-1 else 5 if edge==0 or x==left else 3
        if edge not in [0,11] and ((x*7+y*13)%41==0 or (x+y//3)%59==0):c=2
        if edge not in [0,11] and (x*3+y*7)%67==0:c=4
        pixels[y*96+x]=c
for row in range(4):
    for x in [12,83]:
        pixels[(12+row*12)*96+x]=1
art['frames']={key:[{'id':'wood','name':'Wood boards','visible':True,'pixels':pixels}] for key in ['idle','active']}
art['provenance']['assembly']='native-pixel wooden garden planks; original warm wood palette'
path_file.write_text(json.dumps(art,separators=(',',':'),ensure_ascii=False)+'\n')
# Pots and daisies use the original authored crop pixels, paid as a recreation footprint.
write('outdoor-flowers','庭院花圃','crop-daisy',dict(common,behavior='dance'))
