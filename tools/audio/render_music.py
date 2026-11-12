"""Render the checked-in original score with local FluidSynth + licensed SF2.

No download, credentials, runtime network, or third-party scripts. The caller
provides --soundfont and tools; binaries/SF2 stay outside version control.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import wave
import numpy as np
from synthesize import ROOT, OUT, MANIFEST, hash_file

RATE=24000
SCORE=Path(__file__).with_name('score.json')
SOUNDFONT_URL='https://mirrors.tuna.tsinghua.edu.cn/debian/pool/main/t/timgm6mb-soundfont/timgm6mb-soundfont_1.3-5_all.deb'
LICENSE_URL='https://sources.debian.org/src/timgm6mb-soundfont/1.3-5/debian/copyright/'


def vlq(value):
    result=[value&127];value>>=7
    while value:result.insert(0,(value&127)|128);value>>=7
    return bytes(result)


def midi(score,settings,loops,box_only=False,sample=False,variant=0):
    bpm=settings['bpm'];bars=score['melody_bars'][:8] if sample else score['melody_bars']
    beats=len(bars)*4*(1 if sample else settings['repeats']);events=[]
    events.append((0,b'\xff\x51\x03'+int(60000000/bpm).to_bytes(3,'big')))
    events += [(0,bytes([0xc0,10])),(0,bytes([0xc1,24]))]
    for loop in range(loops):
      for repeat in range(1 if sample else settings['repeats']):
       for bar,notes in enumerate(bars):
        offset=loop*beats+repeat*len(bars)*4+bar*4
        for start,pitch,duration in notes:
            # B lifts the final phrase; C has a softer response octave.
            velocity=settings['melody_velocity']-(4 if variant==2 else 0)
            on=round((offset+start)*480);off=round((offset+start+duration*.9)*480)
            events += [(on,bytes([0x90,pitch,velocity])),(off,bytes([0x80,pitch,0]))]
            if variant==1 and duration>=1.5:
                events += [(on+120,bytes([0x90,pitch-12,max(20,velocity-17)])),(off,bytes([0x80,pitch-12,0]))]
        if not box_only and settings['guitar_velocity']:
            chord=score['harmony'][bar]
            pattern=[0,2,1,3,1,2,1,3] if variant!=2 else [0,1,2,3,0,2,1,2]
            for i,index in enumerate(pattern):
                on=round((offset+i*.5)*480);off=on+190
                events += [(on,bytes([0x91,chord[index],settings['guitar_velocity']])),(off,bytes([0x81,chord[index],0]))]
    end=round(beats*loops*480);events.append((end,b'\xff\x2f\x00'));events.sort(key=lambda x:x[0])
    track=bytearray();last=0
    for tick,data in events:track.extend(vlq(tick-last));track.extend(data);last=tick
    return b'MThd'+struct.pack('>IHHH',6,0,1,480)+b'MTrk'+struct.pack('>I',len(track))+track,beats*60/bpm


def render(args):
    score=json.loads(SCORE.read_text());sf=Path(args.soundfont).resolve()
    if not sf.is_file():raise SystemExit('SF2 missing; no automatic download')
    sfhash=hash_file(sf)
    manifest=json.loads(MANIFEST.read_text());OUT.mkdir(parents=True,exist_ok=True)
    names=['sample30'] if args.samples else list(score['tracks'])
    for name in names:
      event={'bus':'Music','variants':{},'selected':'A','volume_db':-23 if name not in ('moon','night') else -25,'pitch_min':1.0,'pitch_max':1.0,'max_instances':1,'near_tiles':2.0,'far_tiles':128.0,'loop':True,'cooldown_seconds':0.0}
      event=dict(manifest['events'].get(f'music.{name}',event));event['variants']={}
      if name!='sample30':event['selection_key']='music.sample30'
      for version in 'ABC':
        sample=name=='sample30';settings={'bpm':64,'melody_velocity':50,'guitar_velocity':36,'repeats':1} if sample else score['tracks'][name]
        raw,seconds=midi(score,settings,3,args.musicbox_only,sample,'ABC'.index(version))
        with tempfile.TemporaryDirectory(prefix='youxi-music-') as work:
            work=Path(work);mid=work/'score.mid';wav=work/'render.wav';mid.write_bytes(raw)
            subprocess.run([args.fluidsynth,'-ni','-g','.55','-R','0','-C','0','-r',str(RATE),'-F',str(wav),str(sf),str(mid)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
            with wave.open(str(wav)) as w:
                if w.getsampwidth()!=2 or w.getframerate()!=RATE:raise ValueError('unexpected FluidSynth format')
                channels=w.getnchannels();y=np.frombuffer(w.readframes(w.getnframes()),'<i2').reshape(-1,channels).astype(float)/32768
            # Middle loop preserves note release tails inherited from prior loop.
            frames=round(seconds*RATE);y=y[frames:frames*2];y-=y.mean(axis=0)
            y*=min(.105/max(np.sqrt(np.mean(y*y)),1e-12),10**(-3/20)/max(abs(y).max(),1e-12))
            # Codec-safe zero-crossing join. 8ms cosine ramps retain the release
            # tail while forcing both edge amplitudes to zero before Vorbis.
            # This avoids extrapolation differences at the OGG boundary.
            seam=round(.008*RATE);ramp=(.5-.5*np.cos(np.linspace(0,np.pi,seam)))[:,None]
            y[:seam]*=ramp;y[-seam:]*=ramp[::-1]
            with wave.open(str(wav),'wb') as w:w.setparams((channels,2,RATE,0,'NONE','not compressed'));w.writeframes(np.rint(y*32767).astype('<i2').tobytes())
            dest=OUT/f'music.{name}-{version}.ogg'
            subprocess.run([args.ffmpeg,'-v','error','-y','-i',str(wav),'-c:a','libvorbis','-q:a','5','-map_metadata','-1','-fflags','+bitexact',str(dest)],check=True)
        source_id=f'sf2.music.{name}.{version}'
        manifest['sources'][source_id]={'kind':'soundfont','script':'tools/audio/render_music.py','parameters':{'score':'tools/audio/score.json','score_sha256':hash_file(SCORE),'soundfont':'TimGM6mb.sf2','author':'Tim Brechbill; David Bolton','soundfont_sha256':sfhash,'download_date':'2026-10-31','license_url':LICENSE_URL,'programs':[10] if args.musicbox_only or settings['guitar_velocity']==0 else [10,24],'settings':settings,'variant':version,'rate':RATE,'seconds':seconds,'musicbox_only':args.musicbox_only,'fluid_version':subprocess.check_output([args.fluidsynth,'--version'],text=True).splitlines()[0]},'license':'GPL-2.0 (soundfont and conservatively licensed rendered recording); original composition project-original','url':SOUNDFONT_URL,'sha256':hash_file(dest)}
        event['variants'][version]={'file':f'res://content/audio/generated/{dest.name}','sha256':hash_file(dest),'source_id':source_id}
        print(dest.name,round(seconds,3),'seconds')
      manifest['events'][f'music.{name}']=event
    MANIFEST.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    from audition import build
    build()

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--soundfont',required=True);p.add_argument('--fluidsynth',default=shutil.which('fluidsynth') or 'fluidsynth');p.add_argument('--ffmpeg',default=shutil.which('ffmpeg') or 'ffmpeg');p.add_argument('--samples',action='store_true');p.add_argument('--musicbox-only',action='store_true');render(p.parse_args())
