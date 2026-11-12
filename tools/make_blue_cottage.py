"""Editable roof recolor of our existing cottage; no new external assets."""
from pathlib import Path
import json,colorsys
ROOT=Path(__file__).resolve().parents[1];path=ROOT/'godot/content/works/cottage.json';art=json.loads(path.read_text())
art['id']='cottage-blue';art['name']='海蓝小屋';lookup={color:i for i,color in enumerate(art['palette'])}
for frame in ['stage_3','stage_4']:
    for layer in art['frames'][frame]:
        for i,index in enumerate(layer['pixels']):
            if i//art['width']>170:continue
            r,g,b,a=bytes.fromhex(art['palette'][index][1:]);h,s,v=colorsys.rgb_to_hsv(r/255,g/255,b/255)
            if a and .015<h<.10 and s>.55 and r>g*1.28 and g>b*1.25:
                rr,gg,bb=colorsys.hsv_to_rgb(.57,max(.55,s*.9),v*.75)
                color='#%02x%02x%02x%02x'%(round(rr*255),round(gg*255),round(bb*255),a)
                if color not in lookup:lookup[color]=len(art['palette']);art['palette'].append(color)
                layer['pixels'][i]=lookup[color]
(ROOT/'godot/content/works/cottage-blue.json').write_text(json.dumps(art,ensure_ascii=False,separators=(',',':'))+'\n')
