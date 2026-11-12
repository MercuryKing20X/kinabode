"""Reproducible soft nature derivatives. No normalization after filtering.
Run with numpy available; original sources remain unchanged.
"""
import hashlib,json,wave
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[2]
manifest=ROOT/'godot/content/audio/sounds.json'
data=json.loads(manifest.read_text())
for event,cutoff,attenuation in [('ambience.birds',1800,-8),('ambience.insects',1400,-14)]:
    source=ROOT/'godot/content/audio/sound-v2'/f'{event}-A.wav'
    with wave.open(str(source),'rb') as f:
        rate=f.getframerate();channels=f.getnchannels();assert f.getsampwidth()==2
        samples=np.frombuffer(f.readframes(f.getnframes()),dtype='<i2').astype(float).reshape(-1,channels)/32768
    if event=='ambience.birds':
        # One complete chirp from the original five-chirp loop, with quiet lead/tail.
        samples=samples[round(1.95*rate):round(2.60*rate)]
    spectrum=np.fft.rfft(samples,axis=0);freq=np.fft.rfftfreq(len(samples),1/rate)
    samples=np.fft.irfft(spectrum/(1+(freq/cutoff)**4)[:,None],n=len(samples),axis=0)
    samples*=10**(attenuation/20)
    if event=='ambience.birds':
        fade=min(round(.06*rate),len(samples)//2);envelope=np.ones(len(samples));envelope[:fade]=np.linspace(0,1,fade);envelope[-fade:]=np.linspace(1,0,fade);samples*=envelope[:,None]
    else:
        # A periodic FFT filter preserves the original seamless loop.
        assert len(samples)>rate
    output=ROOT/'godot/content/audio/quiet-nature'/f'{event}-A.wav'
    with wave.open(str(output),'wb') as f:
        f.setnchannels(channels);f.setsampwidth(2);f.setframerate(rate);f.writeframes(np.round(np.clip(samples,-1,1)*32767).astype('<i2').tobytes())
    digest=hashlib.sha256(output.read_bytes()).hexdigest();sid=f'quietnature.{event}.A'
    rms=20*np.log10(max(1e-12,float(np.sqrt(np.mean(samples**2)))));peak=20*np.log10(max(1e-12,float(np.max(abs(samples)))))
    data['sources'][sid]={'kind':'synthesis','script':'tools/audio/soften_nature.py','parameters':{'input_file':str(source.relative_to(ROOT)),'input_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'input_source_id':f'v2.{event}.A','lowpass_hz':cutoff,'attenuation_db':attenuation,'rms_dbfs':round(rms,6),'peak_dbfs':round(peak,6),'single_chirp':event=='ambience.birds'},'license':'project-original','url':'','sha256':digest}
    data['events'][event]['variants']['A']={'file':'res://'+str(output.relative_to(ROOT/'godot')),'sha256':digest,'source_id':sid}
    if event=='ambience.birds':data['events'][event].update(loop=False,max_instances=1,cooldown_seconds=30.0)
    print(event,'seconds',len(samples)/rate,'rms_dbfs',round(rms,2),'peak_dbfs',round(peak,2))
manifest.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
