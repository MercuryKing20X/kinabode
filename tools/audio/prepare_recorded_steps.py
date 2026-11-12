"""Prepare explicitly licensed recordings previously downloaded as untrusted data."""
import json
from pathlib import Path
import numpy as np
import soundfile as sf
from process_v2 import ROOT, MANIFEST, OUT, digest, shape

RAW = ROOT / 'tmp/sound-v2-downloads/raw'
ARCHIVES = {
    'Fantozzi': ('Fantozzi-footsteps.7z', 'https://opengameart.org/content/fantozzis-footsteps-grasssand-stone', 'https://opengameart.org/sites/default/files/Fantozzi-footsteps.7z'),
    'TinyWorlds': ('TinyWorlds-DifferentSteps.zip', 'https://opengameart.org/content/different-steps-on-wood-stone-leaves-gravel-and-mud', 'https://opengameart.org/sites/default/files/%5Bkdd%5DDifferentSteps_0.zip'),
}
CHOICES = {
    'grass': [('TinyWorlds-leaves01.ogg','TinyWorlds-leaves02.ogg'),('TinyWorlds-leaves02.ogg','Fantozzi-SandL1.flac'),('Fantozzi-SandR2.flac','TinyWorlds-leaves01.ogg')],
    'sand': [(f'Fantozzi-SandL{i}.flac',f'Fantozzi-SandR{i}.flac') for i in range(1,4)],
    'stone': [(f'Fantozzi-StoneL{i}.flac',f'Fantozzi-StoneR{i}.flac') for i in range(1,4)],
    'wood': [('TinyWorlds-wood01.ogg','TinyWorlds-wood02.ogg'),('TinyWorlds-wood02.ogg','TinyWorlds-wood03.ogg'),('TinyWorlds-wood03.ogg','TinyWorlds-wood01.ogg')],
}


def main():
    data=json.loads(MANIFEST.read_text())
    OUT.mkdir(parents=True,exist_ok=True)
    for surface, groups in CHOICES.items():
        event='step.'+surface
        variants={}
        for version, inputs in zip('ABC',groups):
            takes=[]
            for n, filename in enumerate(inputs,1):
                raw=RAW/filename
                author=filename.split('-',1)[0]
                archive, page, url=ARCHIVES[author]
                source, rate=sf.read(raw,always_2d=True)
                mono=np.mean(source,axis=1)
                count=round(len(mono)*24000/rate)
                mono=np.interp(np.arange(count)*rate/24000,np.arange(len(mono)),mono)[:,None]
                fade=min(round(.008*24000),len(mono)//2)
                mono[:fade]*=np.linspace(0,1,fade)[:,None]
                mono[-fade:]*=np.linspace(1,0,fade)[:,None]
                processed, exponent=shape(mono,24000,-20,-4.6,False)
                dest=OUT/f'{event}-{version}-{n}.wav';sf.write(dest,processed,24000,subtype='PCM_16')
                actual,_=sf.read(dest,always_2d=True)
                rms=20*np.log10(max(float(np.sqrt(np.mean(actual*actual))),1e-12))
                peak=20*np.log10(max(float(np.max(np.abs(actual))),1e-12))
                sid=f'cc0.{surface}.{version}.{n}'
                data['sources'][sid]={'kind':'recording','script':'tools/audio/prepare_recorded_steps.py',
                    'parameters':{'author':author,'download_date':'2026-10-31','archive_url':url,
                        'archive_sha256':digest(ROOT/'tmp/sound-v2-downloads'/archive),'input_file':str(raw.relative_to(ROOT)),
                        'input_sha256':digest(raw),'sample_rate':24000,'lowpass_hz':4500,'compression_exponent':exponent,
                        'target_rms_dbfs':-20.0,'rms_dbfs':round(rms,6),'peak_dbfs':round(peak,6)},
                    'license':'CC0-1.0','url':page,'sha256':digest(dest)}
                takes.append({'file':'res://content/audio/sound-v2/'+dest.name,'sha256':digest(dest),'source_id':sid})
            variants[version]={**takes[0], 'takes':takes}
        data['events'][event]['variants']=variants
        data['events'][event]['selected']='A'
    MANIFEST.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
    print('Recorded candidates: 4 surfaces, 3 groups, 2 takes each')


if __name__=='__main__':main()
