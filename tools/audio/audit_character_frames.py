"""Contact sheet of existing character frames; candidates still need visual review."""
from collections import deque
from hashlib import sha256
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'production/evidence/sound-v2'
IDS=['human-starter','white-haired-girl','blue-haired-girl','orange-haired-girl','black-scarf-girl','ai-gpt','ai-deepseek','ai-claude','ai-glm','ai-gemini','ai-grok','ai-qwen','ai-kimi']
COLS=10
CELL_W,CELL_H=102,150

def color(value):
    s=value.removeprefix('#')
    if len(s) in (3,4):s=''.join(c*2 for c in s)
    if len(s)==6:s+='ff'
    return tuple(int(s[i:i+2],16) for i in (0,2,4,6))

def components(mask):
    height,width=mask.shape;seen=np.zeros_like(mask,dtype=bool);found=[]
    for y,x in np.argwhere(mask):
        y=int(y);x=int(x)
        if seen[y,x]:continue
        seen[y,x]=True;q=deque([(y,x)]);xs=[];ys=[]
        while q:
            cy,cx=q.popleft();xs.append(cx);ys.append(cy)
            for dy in (-1,0,1):
                for dx in (-1,0,1):
                    ny,nx=cy+dy,cx+dx
                    if 0<=ny<height and 0<=nx<width and mask[ny,nx] and not seen[ny,nx]:
                        seen[ny,nx]=True;q.append((ny,nx))
        found.append({'pixels':len(xs),'box':[min(xs),min(ys),max(xs)+1,max(ys)+1]})
    return sorted(found,key=lambda part:part['pixels'],reverse=True)

def main():
    works=[]
    for id in IDS:
        path=ROOT/'godot/content/characters'/f'{id}.json';raw=path.read_bytes();art=json.loads(raw)
        works.append((id,art,sha256(raw).hexdigest()))
    height=sum(26+math.ceil(len(art['frames'])/COLS)*CELL_H for _,art,_ in works)
    sheet=Image.new('RGB',(COLS*CELL_W,height),'#f4f6f5');draw=ImageDraw.Draw(sheet)
    font_path=ROOT/'godot/assets/fonts/NotoSansSC.ttf'
    font=ImageFont.truetype(str(font_path),9);heading=ImageFont.truetype(str(font_path),14)
    y=0;records=[];total=0
    for id,art,digest in works:
        draw.rectangle((0,y,COLS*CELL_W,y+24),fill='#d8e8e3');draw.text((5,y+3),id,font=heading,fill='#233936');y+=26
        palette=np.array([color(c) for c in art['palette']],dtype=np.uint8)
        for index,(name,layers) in enumerate(art['frames'].items()):
            assert len(layers)==1 and layers[0]['visible']
            pixels=palette[np.array(layers[0]['pixels'],dtype=np.int32)].reshape(art['height'],art['width'],4)
            image=Image.fromarray(pixels,'RGBA');parts=components(pixels[:,:,3]>0)
            suspects=[]
            if parts:
                largest=parts[0]['box']
                for part in parts[1:]:
                    x0,y0,x1,y1=part['box'];gap=max(largest[0]-x1,x0-largest[2],largest[1]-y1,y0-largest[3],0)
                    if part['pixels']>=6 and gap>=2:suspects.append(part)
            x=(index%COLS)*CELL_W;top=y+(index//COLS)*CELL_H
            sheet.paste(image,(x+3,top+2),image)
            if suspects:draw.rectangle((x,top,x+99,top+130),outline='#c66a48',width=2)
            state=art.get('frame_status',{}).get('frames',{}).get(name,'unspecified')
            label=('? ' if suspects else '')+name
            size=9
            while draw.textlength(label,font=font)>CELL_W-3 and size>6:
                size-=1;font=ImageFont.truetype(str(font_path),size)
            draw.text((x+2,top+130),label,font=font,fill='#6f352a' if suspects else '#31403d')
            font=ImageFont.truetype(str(font_path),9)
            records.append({'id':id,'frame':name,'state':state,'source_sha256':digest,'separate_components':suspects})
            total+=1
        y+=math.ceil(len(art['frames'])/COLS)*CELL_H
    OUT.mkdir(parents=True,exist_ok=True)
    sheet.save(OUT/'all-action-frames.png',optimize=True)
    preview_ids=['ai-gpt','ai-deepseek','ai-claude','ai-glm']
    selected=Image.new('RGB',(4*300,4*420),'#f4f6f5');labels=ImageDraw.Draw(selected)
    lookup={id:art for id,art,_ in works}
    for row,id in enumerate(preview_ids):
        art=lookup[id];palette=np.array([color(c) for c in art['palette']],dtype=np.uint8)
        for col,direction in enumerate(['down','left','right','up']):
            frame='pickup_'+direction;pixels=palette[np.array(art['frames'][frame][0]['pixels'],dtype=np.int32)].reshape(art['height'],art['width'],4)
            picture=Image.fromarray(pixels,'RGBA').resize((art['width']*3,art['height']*3),Image.Resampling.NEAREST)
            x,y=col*300,row*420;selected.paste(picture,(x+6,y+25),picture);labels.text((x+6,y+4),id+' · '+frame,font=heading,fill='#233936')
    selected.save(OUT/'pickup-four-appearances.png',optimize=True)
    flagged=[r for r in records if r['separate_components']]
    candidates=Image.new('RGB',(3*300,math.ceil(len(flagged)/3)*420),'#f4f6f5')
    labels=ImageDraw.Draw(candidates)
    for index,record in enumerate(flagged):
        art=lookup[record['id']];palette=np.array([color(c) for c in art['palette']],dtype=np.uint8)
        pixels=palette[np.array(art['frames'][record['frame']][0]['pixels'],dtype=np.int32)].reshape(art['height'],art['width'],4)
        picture=Image.fromarray(pixels,'RGBA').resize((art['width']*3,art['height']*3),Image.Resampling.NEAREST)
        x,y=(index%3)*300,(index//3)*420
        candidates.paste(picture,(x+6,y+25),picture)
        labels.text((x+6,y+4),record['id']+' '+record['frame'],font=font,fill='#233936')
    candidates.save(OUT/'component-candidates.png',optimize=True)
    summary={'frames':total,'characters':len(works),'sheet':'all-action-frames.png','pickup_sheet':'pickup-four-appearances.png',
             'method':'Existing single-layer original palette pixels; orange outline marks separated >=6-pixel components with >=2-pixel bounding-box gap. Candidates may be accessories, not automatic anatomical verdicts.',
             'source_sha256':{id:digest for id,_,digest in works},'frames_data':records}
    (OUT/'frame-audit.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
    print('Frame audit',total,'frames;',sum(bool(r['separate_components']) for r in records),'candidates')

if __name__=='__main__':main()
