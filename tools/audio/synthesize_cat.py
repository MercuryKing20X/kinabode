import math,wave,struct,json,hashlib
from pathlib import Path
out=Path('godot/content/audio/cat');out.mkdir(exist_ok=True)
p=Path('godot/content/audio/sounds.json');catalog=json.loads(p.read_text())
for name,seconds in [('meow',.48),('purr',.8)]:
 rate=24000;v=[]
 for n in range(int(rate*seconds)):
  t=n/rate;env=math.sin(math.pi*t/seconds)**2
  if name=='meow':value=.12*env*(math.sin(2*math.pi*(420*t+90*t*t))+.2*math.sin(2*math.pi*840*t))
  else:value=.09*env*math.sin(2*math.pi*96*t)*(1+.45*math.sin(2*math.pi*24*t))
  v.append(int(value*32767))
 f=out/(name+'.wav')
 with wave.open(str(f),'wb') as wav:wav.setparams((1,2,rate,0,'NONE','not compressed'));wav.writeframes(struct.pack('<'+'h'*len(v),*v))
 sha=hashlib.sha256(f.read_bytes()).hexdigest();source='original.cat.'+name
 catalog['sources'][source]={'kind':'synthesis','script':'tools/audio/synthesize_cat.py','parameters':{'algorithm':'soft-cat-original-v1','sample_rate':rate,'seconds':seconds},'license':'project-original','url':'','sha256':sha}
 template=catalog['events']['voice.bright'].copy();template.update(bus='Effects',variants={'A':{'file':'res://content/audio/cat/'+name+'.wav','sha256':sha,'source_id':source}},selected='A',volume_db=-15,pitch_min=1.,pitch_max=1.,max_instances=1,near_tiles=2.,far_tiles=12.,cooldown_seconds=8.,loop=False)
 catalog['events']['cat.'+name]=template
p.write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n')
