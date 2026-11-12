"""Deterministic original dark-island Foley and warm beacon chord. No recordings."""
import hashlib
import json
from pathlib import Path
import numpy as np
import soundfile as sf
ROOT=Path(__file__).resolve().parents[2]
RATE=24000
SPECS={'torch.ignite':(.25,6101),'torch.plant':(.12,6102),'torch.lift':(.12,6103),'torch.warning':(.35,6104),'dark.kindling':(.50,6105),'dark.beacon':(1.2,6106)}
def render(name,seconds,seed):
 t=np.arange(round(seconds*RATE))/RATE
 rng=np.random.default_rng(seed);noise=rng.normal(0,1,len(t))
 freq=np.fft.rfftfreq(len(t),1/RATE)
 noise=np.fft.irfft(np.fft.rfft(noise)/np.sqrt(1+(freq/950)**6),n=len(t))
 progress=t/seconds
 if name=='dark.beacon':
  y=sum(np.sin(2*np.pi*f*t)+.06*np.sin(4*np.pi*f*t) for f in [196,246.94165,293.66477])/3
  y*=np.sin(np.pi*progress)**1.5
 elif name in ['torch.plant','torch.lift']:
  y=(noise*.65+np.sin(2*np.pi*(95 if name.endswith('plant') else 165)*t)*.2)*np.sin(np.pi*progress)**2.5
 elif name=='torch.warning':
  y=noise*(.22+.1*np.sin(2*np.pi*17*t))*(1-progress)*np.sin(np.pi*progress)
 else:
  y=noise*np.sin(np.pi*progress)**1.4+.08*np.sin(2*np.pi*110*t)*np.sin(np.pi*progress)**2
 y*=10**(-18/20)/max(1e-8,np.sqrt(np.mean(y*y)))
 limit=10**(-5/20);y=limit*np.tanh(y/limit)
 fade=min(len(y)//4,int(RATE*.006));ramp=np.sin(np.linspace(0,np.pi/2,fade))**2;y[:fade]*=ramp;y[-fade:]*=ramp[::-1]
 return y
if __name__=='__main__':
 manifest_path=ROOT/'godot/content/audio/sounds.json';d=json.loads(manifest_path.read_text());out=ROOT/'godot/content/audio/dark-island';out.mkdir(exist_ok=True)
 for name,(seconds,seed) in SPECS.items():
  file=out/(name+'.wav');sf.write(file,render(name,seconds,seed),RATE,subtype='PCM_16');pcm,_=sf.read(file);digest=hashlib.sha256(file.read_bytes()).hexdigest();source='dark1101.'+name
  imported=file.with_suffix(file.suffix+'.import')
  if imported.exists():imported.write_text(imported.read_text().replace('compress/mode=2','compress/mode=0'))
  d['sources'][source]={'kind':'synthesis','script':'tools/audio/dark_island_audio.py','parameters':{'algorithm':'filtered-noise-single-envelope' if name!='dark.beacon' else 'warm-major-triad-swell','sample_rate':RATE,'seconds':seconds,'seed':seed,'lowpass_hz':950,'rms_dbfs':round(float(20*np.log10(np.sqrt(np.mean(pcm*pcm)))),6),'peak_dbfs':round(float(20*np.log10(np.max(np.abs(pcm)))),6)},'license':'project-original','url':'','sha256':digest}
  d['events'][name]={'bus':'Effects','variants':{'A':{'file':'res://content/audio/dark-island/'+file.name,'sha256':digest,'source_id':source}},'selected':'A','volume_db':-3.0,'pitch_min':1.0,'pitch_max':1.0,'max_instances':1,'near_tiles':6.0,'far_tiles':22.0,'loop':False,'cooldown_seconds':.1}
 manifest_path.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
 print('Generated six original dark island events; no external calls.')
