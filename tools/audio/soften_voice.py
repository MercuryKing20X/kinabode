"""Reproducible 1031 voice treatment, exclusively from retained v2 originals."""
import hashlib,json
from pathlib import Path
import numpy as np
import soundfile as sf
ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 p=ROOT/'godot/content/audio/sounds.json';d=json.loads(p.read_text());out=ROOT/'godot/content/audio/voice-soft-1031';out.mkdir(exist_ok=True)
 for key,e in d['events'].items():
  if not key.startswith('voice.'):continue
  e['volume_db']=-5.0
  for version,clip in e['variants'].items():
   old=ROOT/'godot/content/audio/sound-v2'/f'{key}-{version}.wav';x,sr=sf.read(old,always_2d=True)
   freq=np.fft.rfftfreq(len(x),1/sr);gain=1/np.sqrt(1+(freq/2400)**6)
   y=np.fft.irfft(np.fft.rfft(x,axis=0)*gain[:,None],n=len(x),axis=0)
   n=min(len(y)//2,int(sr*.025));y[:n]*=(np.sin(np.linspace(0,np.pi/2,n))**2)[:,None]
   y=np.sign(y)*np.abs(y)**.65;y*=10**(-12/20)/max(float(np.sqrt(np.mean(y*y))),1e-12)
   y=np.clip(y,-10**(-3/20),10**(-3/20));dest=out/old.name;sf.write(dest,y,sr,subtype='PCM_16')
   actual,_=sf.read(dest,always_2d=True);rms=20*np.log10(np.sqrt(np.mean(actual*actual)));peak=20*np.log10(np.max(np.abs(actual)))
   source='soft1031.'+key+'.'+version;d['sources'][source]={'kind':'synthesis','script':'tools/audio/soften_voice.py','parameters':{'input_file':str(old.relative_to(ROOT)),'input_sha256':sha(old),'lowpass_hz':2400,'attack_seconds':.025,'compression_exponent':.65,'target_rms_dbfs':-12,'rms_dbfs':round(float(rms),6),'peak_dbfs':round(float(peak),6)},'license':'project-original','url':'','sha256':sha(dest)}
   clip.update(file='res://content/audio/voice-soft-1031/'+dest.name,sha256=sha(dest),source_id=source)
   assert -18<=rms-5<=-14,(key,rms)
 p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
if __name__=='__main__':main()
