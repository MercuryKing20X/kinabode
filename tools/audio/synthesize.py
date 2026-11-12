"""Deterministic original audio; no recordings, network, or model.

Run with numpy installed. --stage samples|effects|ambience generates only that
stage, preserving other manifest entries. Every variation has its exact seed
and synthesis parameters in sounds.json. No file in assets/audio is modified.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import wave
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'godot/content/audio/generated'
MANIFEST = ROOT / 'godot/content/audio/sounds.json'
RATE = 24000
SAMPLE_IDS = ['voice.bright', 'hunger.hungry', 'ambience.fire', 'ui.click']
EFFECT_IDS = ['voice.soft','voice.crisp','voice.low','hunger.mild','hunger.very_hungry','meal.satisfied','tree.hit','wood.fall','fire.ignite','fire.refuel','meal.bite','meal.chew','fishing.cast','fishing.water','fishing.bite','fishing.reel','fish.flap','fish.stock','fish.release','ui.open','ui.close','ui.fish_card','ui.invite','work.pickup','work.deposit','gomoku.stone']
AMBIENCE_IDS = ['ambience.waves','ambience.wind','ambience.birds','ambience.insects','ambience.rain','ambience.sizzle','step.grass','step.sand','step.wood','step.stone']


def hash_file(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def periodic_noise(rng, n, cutoff, slope=2):
    noise = rng.normal(0, 1, n)
    freq = np.fft.rfftfreq(n, 1/RATE)
    filtered = np.fft.irfft(np.fft.rfft(noise)/(1+(freq/cutoff)**slope), n)
    filtered -= filtered.mean()
    return filtered/max(float(np.std(filtered)), 1e-8)


def env(t, attack=.008, decay=.10):
    return np.minimum(1,t/attack)*np.exp(-t/decay)*np.minimum(1,(t[-1]-t)/.012)


def parameters(key, version):
    v = 'ABC'.index(version)
    family = key.split('.')[0]
    seconds = 12.0 if family=='ambience' else .09
    frequency = 360.0
    if key.startswith('voice.'):
        frequency = {'bright':690.,'soft':425.,'crisp':510.,'low':235.}[key.split('.')[1]]
        seconds = {'bright':.065,'soft':.105,'crisp':.075,'low':.145}[key.split('.')[1]]
    elif family=='hunger':
        seconds={'mild':.65,'hungry':1.05,'very_hungry':1.45}[key.split('.')[1]]
        frequency={'mild':115.,'hungry':95.,'very_hungry':75.}[key.split('.')[1]]
    elif key=='meal.satisfied': seconds,frequency=.38,390.
    elif family=='step': seconds,frequency=.14,{'grass':160.,'sand':120.,'wood':210.,'stone':340.}[key.split('.')[1]]
    elif key=='wood.fall': seconds,frequency=.65,95.
    elif key=='tree.hit': seconds,frequency=.17,170.
    elif key.startswith('fire.'): seconds,frequency=.70,180.
    elif key.startswith('fishing.') or key.startswith('fish.'): seconds,frequency=.42,320.
    elif key in ('meal.bite','meal.chew'): seconds,frequency=.18,140.
    elif family=='ui': seconds,frequency=.095,640.
    if key=='fishing.bite':seconds,frequency=.24,760.
    return {'algorithm':'pastoral-sfx-v1','sample_rate':RATE,'seconds':seconds,'frequency':frequency*(.94+v*.06),'variant_index':v,'rms_target':.065 if key.startswith('step.') else .14,'seed':int.from_bytes(hashlib.sha256((key+':'+version+':1031').encode()).digest()[:8],'big')}


def synth(key,p):
    n=round(p['seconds']*RATE);t=np.arange(n)/RATE
    rng=np.random.default_rng(p['seed']);f=p['frequency'];v=p['variant_index']
    if key.startswith('voice.'):
        # Rounded vowel-like hum: fundamental + quiet harmonics, no square wave.
        phase=2*np.pi*f*(t+.0018*np.sin(2*np.pi*6*t))
        y=(np.sin(phase)+.20*np.sin(2*phase)+.09*np.sin(3*phase))*np.sin(np.pi*np.arange(n)/(n-1))**1.5
    elif key.startswith('hunger.'):
        # Low, damped bubbles with uneven rounded pitch; no speech event added.
        phase=2*np.pi*(f*t+9*np.sin(2*np.pi*2*t)/(2*np.pi*2))
        pulses=(.3+.7*np.sin(np.pi*t/p['seconds'])**2)*(.25+.75*np.sin(2*np.pi*(2.5+v*.4)*t)**2)
        y=(.75*np.sin(phase)+.25*periodic_noise(rng,n,220))*pulses
        y*=np.minimum(1,t/.03)*np.minimum(1,(p['seconds']-t)/.05)
    elif key=='meal.satisfied':
        y=(np.sin(2*np.pi*(f*t+65*t*t))+.15*np.sin(2*np.pi*2*f*t))*env(t,.025,.18)
    elif key.startswith('ambience.'):
        period=t/p['seconds'];base=periodic_noise(rng,n,{'ambience.wind':150,'ambience.waves':700,'ambience.rain':1800,'ambience.fire':900,'ambience.sizzle':2400,'ambience.birds':1200,'ambience.insects':3200}[key])
        if key=='ambience.wind': y=base*(.55+.25*np.cos(2*np.pi*period)+.12*np.sin(6*np.pi*period))
        elif key=='ambience.waves': y=base*(.22+.78*(.5-.5*np.cos(4*np.pi*period))**2)
        elif key in ('ambience.fire','ambience.sizzle'):
            y=base*.1
            for _ in range(35 if key.endswith('fire') else 160):
                start=rng.integers(0,n);length=round(RATE*rng.uniform(.008,.045));idx=(start+np.arange(length))%n
                crackle=rng.normal(size=length)*np.exp(-np.arange(length)/(length*.18))
                y[idx]+=crackle*rng.uniform(.12,.4)
        elif key=='ambience.rain': y=base*(.8+.08*np.sin(2*np.pi*period))
        elif key=='ambience.birds':
            y=np.zeros(n)
            for start in (-.1,2.1,5.5,8.2,10.2):
                a=round(start*RATE);m=round(.32*RATE);q=np.arange(m)/RATE
                y[(a+np.arange(m))%n]+=(np.sin(2*np.pi*(1600*q+320*q*q))+.15*np.sin(2*np.pi*2400*q))*np.sin(np.pi*np.arange(m)/(m-1))**3
        else:
            y=(np.sin(2*np.pi*2400*t)+.2*np.sin(2*np.pi*3100*t))*(.35+.25*np.sin(2*np.pi*7*t))*(.7+.3*np.cos(2*np.pi*period))
        # All loop sources are periodic; correct residual endpoint in last 8 ms.
        m=192;y[-m:]-=np.linspace(0,y[-1]-y[0],m)
    else:
        noise=periodic_noise(rng,n,{'step.grass':1000,'step.sand':1800,'step.wood':750,'step.stone':1600}.get(key,1100))
        if key.startswith('step.'):
            y=(.30*np.sin(2*np.pi*f*t)+.70*noise)*env(t,.004,.025)
        elif key=='fishing.bite':
            q=np.maximum(0,t-.105)
            y=(np.sin(2*np.pi*(f*t-340*t*t))*env(t,.005,.035)+.8*np.sin(2*np.pi*(f*1.15*q-300*q*q))*env(q,.005,.035)*(t>=.105))
        elif key in ('fishing.water','fish.stock','fish.release','fish.flap'):
            y=(.65*noise+.25*np.sin(2*np.pi*(f*t-160*t*t)))*env(t,.007,.11)
        elif key in ('fishing.cast','fishing.reel'):
            y=noise*(.5+.5*np.sin(2*np.pi*35*t))*env(t,.03,.14)
        elif key.startswith('fire.'):
            y=(noise+.08*np.sin(2*np.pi*f*t))*env(t,.015,.16)
        elif key in ('tree.hit','wood.fall','meal.bite','meal.chew','work.pickup','work.deposit'):
            y=(.55*np.sin(2*np.pi*(f*t-30*t*t))+.45*noise)*env(t,.003,p['seconds']*.21)
        else:
            direction=-1 if key=='ui.close' else 1
            y=(np.sin(2*np.pi*(f*t+direction*400*t*t))+.12*np.sin(2*np.pi*1.5*f*t))*env(t,.004,.026)
    return y


def event_spec(key):
    loop=key.startswith('ambience.')
    bus='Ambience' if loop else 'Voices' if key.startswith(('voice.','hunger.')) or key=='meal.satisfied' else 'Effects'
    volume=-19 if loop else -12 if key.startswith(('voice.','ui.')) else -14
    if key.startswith('hunger.'):volume={'hunger.mild':-22,'hunger.hungry':-18,'hunger.very_hungry':-15}[key]
    return {'bus':bus,'variants':{},'selected':'A','volume_db':volume,'pitch_min':1.0 if loop else .97,'pitch_max':1.0 if loop else 1.03,'max_instances':2 if loop or key.startswith('hunger.') else 3,'near_tiles':2.0,'far_tiles':24.0 if loop else 18.0,'loop':loop,'cooldown_seconds':.08 if key.startswith('voice.') else .12}


def write_wave(path,y,target_rms=.14):
    # Short cues have an identical family RMS target and a -3dB peak ceiling.
    y=np.asarray(y,dtype=np.float64);y-=y.mean()
    rms=float(np.sqrt(np.mean(y*y)));peak=float(np.max(np.abs(y)))
    y*=min(target_rms/max(rms,1e-12),10**(-3/20)/max(peak,1e-12))
    pcm=np.rint(y*32767).astype('<i2')
    with wave.open(str(path),'wb') as w:w.setparams((1,2,RATE,0,'NONE','not compressed'));w.writeframes(pcm.tobytes())


def generate(stage):
    manifest=json.loads(MANIFEST.read_text());OUT.mkdir(parents=True,exist_ok=True)
    keys={'samples':SAMPLE_IDS,'effects':EFFECT_IDS,'ambience':AMBIENCE_IDS}[stage]
    for key in keys:
        event=dict(manifest['events'].get(key,event_spec(key)));event['variants']={}
        for variant in ('ABC' if key in SAMPLE_IDS else 'A'):
            p=parameters(key,variant);path=OUT/f'{key}-{variant}.wav';write_wave(path,synth(key,p),p['rms_target'])
            source_id=f'synth.{key}.{variant}'
            event['variants'][variant]={'file':f'res://content/audio/generated/{path.name}','sha256':hash_file(path),'source_id':source_id}
            manifest['sources'][source_id]={'kind':'synthesis','script':'tools/audio/synthesize.py','parameters':p,'license':'project-original','url':'','sha256':hash_file(path)}
        manifest['events'][key]=event
    MANIFEST.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    from audition import build
    build()
    print(f'{stage}: {len(keys)} events')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--stage',choices=['samples','effects','ambience'],required=True);generate(parser.parse_args().stage)
