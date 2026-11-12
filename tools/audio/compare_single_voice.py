"""Re-run the same seeded fireside mouse flow with retained/new audio in private worlds.

Only audio code/content is replaced for the before run. WAV mixes are reconstructed
from actual native_start events, clip PCM, pitch and gain (Dummy driver); they are
not microphone recordings. All temporary project/data/output paths contain youqi-test-.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--before-ref', default='bc75715')
args = parser.parse_args()
BASE = args.before_ref
OUT = Path(tempfile.mkdtemp(prefix='youqi-test-voice-compare-'))
REPORT = ROOT/'production/evidence/2026-11-01-黑暗岛/audio'
REPORT.mkdir(parents=True, exist_ok=True)

source = (ROOT/'godot/tests/test_speech_quiet_input.gd').read_text()
source = source.replace('new("res://content/home-v3/world.json");w.residents.provision(w);', 'new("res://content/home-v3/world.json")\n\tif not w.error.is_empty():push_error(w.error);quit(1);return\n\tw.residents.provision(w);')
source = source.replace('var trace_start:int=audio.trace.size()', 'var trace_start:int=audio.trace.size();audio.trace_path=OS.get_environment("HABITAT_PLAYTEST_CAPTURE").path_join("native.jsonl");var audio_start:float=audio.clock')
source = source.replace('g._process(.05);g.view._process(.05)\n\t\tfor id in g.view.speech_by_actor:', 'g._process(.05);g.view._process(.05);await process_frame\n\t\tfor id in g.view.speech_by_actor:')
source = source.replace('"at_seconds":i*.05', '"at_seconds":i*.05,"audio_time":audio.clock')
source = source.replace('"seconds":60,"new_scheduled_blips"', '"seconds":60,"audio_start":audio_start,"new_scheduled_blips"')

for mode in ['before','after']:
    task=OUT/mode;task.mkdir();project=task/'godot';project.mkdir()
    replacements={'scripts/game_audio.gd','scripts/game_audio_observer.gd','content/audio/runtime.json','content/audio/sounds.json',*[str(p.relative_to(ROOT/'godot')) for p in (ROOT/'godot/content/intelligence/traits').glob('*.json') if '"voice"' in p.read_text()]}
    def copy_dir(rel):
        dest=project/rel;dest.mkdir(exist_ok=True)
        for e in (ROOT/'godot'/rel).iterdir():
            r=str(Path(rel)/e.name)
            if mode=='before' and r in replacements:
                (project/r).write_bytes(subprocess.check_output(['git','show',BASE+':godot/'+r],cwd=ROOT))
            elif mode=='before' and any(x.startswith(r+'/') for x in replacements):copy_dir(r)
            else:(project/r).symlink_to(e,target_is_directory=e.is_dir())
    for e in (ROOT/'godot').iterdir():
        if e.name=='project.godot':continue
        if mode=='before' and e.name in ['scripts','content']:copy_dir(e.name)
        else:(project/e.name).symlink_to(e,target_is_directory=e.is_dir())
    config=(ROOT/'godot/project.godot').read_text().replace('[application]','[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="'+OUT.name+'-'+mode+'"');(project/'project.godot').write_text(config)
    (task/'capture.gd').write_text(source)
    data=task/'data';data.mkdir();capture=task/'capture';capture.mkdir()
    env=dict(os.environ,HABITAT_DATA_DIR=str(data),HABITAT_OPENING='legacy',HABITAT_PLAYTEST_CAPTURE=str(capture))
    r=subprocess.run(['/Applications/Godot.app/Contents/MacOS/Godot','--audio-driver','Dummy','--log-file',str(task/'engine.log'),'--path',str(project),'--script',str(task/'capture.gd')],cwd=ROOT,env=env,capture_output=True,text=True,timeout=180)
    (task/'run.log').write_text(r.stdout+r.stderr);print(mode,r.returncode,(r.stdout+r.stderr)[-1600:],flush=True)
    shutil.rmtree(Path.home()/'Library/Application Support'/(OUT.name+'-'+mode),ignore_errors=True)
    if r.returncode:continue
    import numpy as np
    import soundfile as sf
    RATE=24000;mix=np.zeros(RATE*61,dtype=np.float64)
    manifest=json.loads((project/'content/audio/sounds.json').read_text())
    record=json.loads((capture/'speech-60s.json').read_text());events=[json.loads(line) for line in (capture/'native.jsonl').read_text().splitlines()]
    native=[e for e in events if e['action']=='native_start' and e['event'].startswith('voice.')]
    scheduled=[e for e in events if e['action']=='scheduled' and e['event'].startswith('voice.')]
    record['native_voice_events']=native;record['scheduled_voice_events']=scheduled
    record['mix_kind']='PCM reconstruction from actual native_start, pitch, gain; Dummy driver, not microphone recording'
    for e in native:
        clip=manifest['events'][e['event']]['variants'][e['variant']]
        pcm,rate=sf.read(project/clip['file'].removeprefix('res://'))
        if pcm.ndim>1:pcm=pcm.mean(axis=1)
        positions=np.arange(0,len(pcm),e['pitch']*rate/RATE)
        samples=np.interp(positions,np.arange(len(pcm)),pcm)*10**(e['gain_db']/20)
        at=round((e['time']-record['audio_start'])*RATE)
        if at<0:samples=samples[-at:];at=0
        n=min(len(samples),len(mix)-at)
        if n>0:mix[at:at+n]+=samples[:n]
    sf.write(task/'dialogue-mix.wav',mix,RATE,subtype='PCM_16')
    for i,b in enumerate(record['bubbles']):
        later=[x['audio_time'] for x in record['bubbles'][i+1:] if x['actor']==b['actor']]
        end=min(b['audio_time']+6,min(later,default=1e12))
        b['actual_scheduled_blips']=sum(e['actor']==b['actor'] and b['audio_time']-.051<=e['time']<end for e in scheduled)
        b['actual_native_blips']=sum(e['actor']==b['actor'] and b['audio_time']-.051<=e['time']<end for e in native)
    (task/'comparison.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
    (REPORT/(mode+'.json')).write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
summary={'before_ref':BASE,'output':str(OUT),'driver':'Dummy','same_sequence':False}
if all((OUT/m/'comparison.json').exists() for m in ['before','after']):
    a,b=[json.loads((OUT/m/'comparison.json').read_text()) for m in ['before','after']]
    key=lambda r:[(x['actor'],x['text'],x['at_seconds']) for x in r['bubbles']]
    summary.update(same_sequence=key(a)==key(b),before_native=len(a['native_voice_events']),after_native=len(b['native_voice_events']))
(REPORT/'comparison.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(summary,ensure_ascii=False),flush=True)
