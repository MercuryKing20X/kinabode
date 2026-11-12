"""Deterministic additive layout upgrade; existing IDs/positions never move."""
from pathlib import Path
import json, math, random
ROOT=Path(__file__).resolve().parents[1];path=ROOT/'godot/content/packs/core.json'
p=json.loads(path.read_text());home=p['regions'][0]
if home.get('content_version',1)<2:
    home['legacy_land']=home['land']
    home['land']=[[round(48+(x-48)*2.35,3) if x>48 else x, round(40+(y-40)*2.1,3) if y>40 else y] for x,y in home['land']]
    home['size']=[160,128];home['content_version']=2;p['version']=2
    for z in home['zones']:
        if z['id']=='home.shore':z.update(name='家园南庭',purpose='scenery',planned_actions=[])
        if z['id']=='home.meadow':z['rect']=[13,34,14.6,20]
    for id,name,purpose,rect,actions in [
        ('home.north_grove','北部松林','resources',[92,20,38,23],['chop']),
        ('home.east_grove','东部阔叶林','resources',[99,46,29,27],['chop']),
        ('home.storage','林间仓储','storage',[85,50,12,13],['store']),
        ('home.second_court','南部宅地','housing',[56,77,26,19],['build']),
        ('home.east_orchard','东部果园预留地','orchard',[86,83,16,12],['plant_tree']),
        ('home.pond','林间池塘','scenery',[104,76,18,10],[]),
        ('home.south_beach','南部沙岸','shore',[51,100,20,8],[]),
        ('home.lookout','北坡花径','scenery',[45,12,22,10],[])]:
        home['zones'].append(dict(id=id,name=name,purpose=purpose,rect=rect,planned_actions=actions))
    rng=random.Random(34)
    candidates=[(x,y,'home.north_grove') for x in range(95,130,5) for y in range(24,43,5)]+[(x,y,'home.east_grove') for x in range(102,128,5) for y in range(48,73,5)]
    for i,(x,y,zone) in enumerate(candidates):
        home['objects'].append(dict(id=f'home.tree.{101+i:02d}',kind='tree',zone_id=zone,position=[round(x+rng.uniform(-.6,.6),2),round(y+rng.uniform(-.6,.6),2)],name='松林木' if zone.endswith('north_grove') else '阔叶树',status='mature',wood_yield=8,health=6,introduced_in=2))
    home['objects'].append(dict(id='home.chest.02',kind='chest',zone_id='home.storage',position=[90,56],name='林间木箱',items={},capacity=160,introduced_in=2))
    home['objects'].append(dict(id='home.house.02',kind='construction_site',zone_id='home.second_court',position=[68,84],name='南庭小屋',status='planned',footprint=[8,7],stage='foundation',delivered={},required={'wood':12},stage_index=0,invested=0,introduced_in=2))
roads=[
 ([[38,42],[38,45],[43,45],[51,45],[59,44],[63,42]],1.05),
 ([[45,45],[48,51],[48,61],[43,68],[41,74]],.9),
 ([[48,56.5],[44,56.5],[43.3,56.5]],.65),
 ([[38,45],[30,45],[24,47]],.8),
 ([[51,45],[54,30],[52,24],[55,19]],.8),
 ([[59,44],[85,44],[94,43],[106,38],[115,32]],1.0),
 ([[85,44],[90,48],[90,56],[95,60],[111,61]],.95),
 ([[48,61],[52,68],[54,74],[68,75],[80,76],[92,78],[103,89],[114,94]],1.1),
 ([[68,75],[70,96],[67,108]],1.05),
 ([[68,89],[70,92]],.85),
 ([[92,78],[94,87],[94,92]],.65)]
home['layout']={'roads':[{'points':pts,'width':width} for pts,width in roads],
 'garden':{'soil_rect':[30.3,50.6,12.4,8.8],'bed_size':[2.4,1.8],'fences':[[[29,49.6],[44.3,49.6]],[[29,62],[44.3,62]],[[29,49.6],[29,62]],[[44.3,49.6],[44.3,54.2]],[[44.3,58],[44.3,62]]],'gate':[44.3,56.5],'apron_rect':[29.6,50.1,14.1,10.8]},
 'ponds':[{'center':[113,81],'radius':[7,3.4]}],
 'landmarks':[{'name':'家园','position':[38,43]},{'name':'菜园','position':[44.3,56]},{'name':'烧烤草地','position':[24,47]},{'name':'林间木箱','position':[90,58]},{'name':'南庭宅地','position':[68,90]},{'name':'池塘','position':[113,87]},{'name':'沙岸','position':[67,108]}]}
# Keep walking corridors free of newly introduced trees.
def segment_distance(point,a,b):
    dx,dy=b[0]-a[0],b[1]-a[1];t=max(0,min(1,((point[0]-a[0])*dx+(point[1]-a[1])*dy)/(dx*dx+dy*dy)))
    return math.hypot(point[0]-a[0]-t*dx,point[1]-a[1]-t*dy)
home['objects']=[o for o in home['objects'] if not (o.get('introduced_in')==2 and o['kind']=='tree' and any(segment_distance(o['position'],a,b)<width+1.3 for pts,width in roads for a,b in zip(pts,pts[1:])))]
path.write_text(json.dumps(p,ensure_ascii=False,indent=2)+'\n')
print('home',home['size'],'zones',len(home['zones']),'objects',len(home['objects']),'trees',sum(o['kind']=='tree' for o in home['objects']))
