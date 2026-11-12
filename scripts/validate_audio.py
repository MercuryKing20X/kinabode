"""Strict validation of optional presentation audio data; never reads player data."""
import json, math, re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
BUSES={'Music','Ambience','Effects','Voices'}
MUSIC_SCENES=('day','dusk','night','rain','fireside','moon')
def number(v,lo,hi): return type(v) in (int,float) and math.isfinite(v) and lo<=v<=hi
def sha256(v): return type(v) is str and len(v)==64 and all(c in "0123456789abcdef" for c in v)
def exact(d,keys): return type(d) is dict and set(d)==set(keys)
def voice(v):
    return exact(v,['event','pitch','max_blips']) and v['event'] in ['voice.soft','voice.bright','voice.crisp','voice.low'] and number(v['pitch'],.5,2) and number(v['max_blips'],1,1)
def music_slots(v):
    if not exact(v,['version','slots']) or not number(v['version'],1,1) or not exact(v['slots'],MUSIC_SCENES):return False
    for scene in MUSIC_SCENES:
        names=v['slots'][scene]
        if type(names) is not list or len(names)>16:return False
        if any(type(name) is not str or len(name)>180 or not name.startswith(scene+'-') or '/' in name or '\\' in name or '..' in name or Path(name).suffix.lower() not in ['.wav','.mp3','.ogg','.flac','.m4a'] for name in names):return False
    return True
def tuning(v):
    required={'version','default_enabled','default_mute_unfocused','default_master','bus_levels','duck_db','duck_release_seconds','crossfade_seconds','step_walk_tiles','step_run_tiles','step_global_gap_seconds','hunger_intervals_seconds','voice_default','global_oneshot_limit','environment_refresh_seconds','run_step_gain','main_waves_gain','moon_waves_gain'}
    if type(v) is not dict or not required <= set(v) or not set(v) <= required | {'nature','wind','targets_dbfs','speech_gap_seconds','speech_max_blips','speech_near_tiles'}: return False
    if 'nature' in v:
        nature=v['nature']
        if not exact(nature,['bird_interval_min','bird_interval_max']) or not number(nature['bird_interval_min'],30,300) or not number(nature['bird_interval_max'],nature['bird_interval_min'],300): return False
    if 'wind' in v:
        wind=v['wind']
        if not exact(wind, {'home_base','home_peak','interval_min','interval_max','duration_min','duration_max'}): return False
        if any(not number(wind[k],0,1) for k in ['home_base','home_peak']): return False
        if any(not number(wind[k],1,120) for k in ['interval_min','interval_max','duration_min','duration_max']): return False
    if any(k in v and not number(v[k],1,60) for k in ['speech_gap_seconds','speech_max_blips','speech_near_tiles']):return False
    if 'speech_max_blips' in v and v['speech_max_blips']!=1:return False
    if 'targets_dbfs' in v:
        t=v['targets_dbfs']
        if not exact(t,['voice','ui','ambience','music','duck_floor','peak_max']):return False
        if any(type(t[k]) is not list or len(t[k])!=2 or not number(t[k][0],-120,0) or not number(t[k][1],t[k][0],0) for k in ['voice','ui','ambience','music']):return False
        if not number(t['duck_floor'],-120,0) or not number(t['peak_max'],-60,0):return False
    if v['version']!=1 or type(v['default_enabled']) is not bool or type(v['default_mute_unfocused']) is not bool or not number(v['default_master'],0,1) or not exact(v['bus_levels'],BUSES) or not all(number(x,0,1) for x in v['bus_levels'].values()) or not voice(v['voice_default']): return False
    if not all(number(v[k],.02,20) for k in ['duck_release_seconds','crossfade_seconds','step_walk_tiles','step_run_tiles','step_global_gap_seconds']): return False
    if not all(number(v[k],.05,2) for k in ['environment_refresh_seconds','run_step_gain','main_waves_gain','moon_waves_gain']): return False
    if not number(v['duck_db'],-18,0) or not number(v['global_oneshot_limit'],1,32) or v['global_oneshot_limit']!=int(v['global_oneshot_limit']): return False
    a=v['hunger_intervals_seconds'];return type(a) is list and len(a)==3 and all(number(x,10,600) for x in a) and a[0]>=a[1]>=a[2]
def manifest(v):
    if not exact(v,['version','events','sources']) or v['version']!=1 or type(v['events']) is not dict or type(v['sources']) is not dict or len(v['events'])>128:return False
    for s in v['sources'].values():
        if not exact(s,['kind','script','parameters','license','url','sha256']) or s['kind'] not in ['synthesis','soundfont','recording','licensed_music'] or type(s['script']) is not str or type(s['parameters']) is not dict or type(s['license']) is not str or not s['license'] or type(s['url']) is not str or not sha256(s['sha256']):return False
        p=s['parameters']
        if ('rms_dbfs' in p)!=('peak_dbfs' in p):return False
        if 'rms_dbfs' in p and (not number(p['rms_dbfs'],-120,0) or not number(p['peak_dbfs'],p['rms_dbfs'],0)):return False
        if s['kind']=='licensed_music':
            if not exact(p,['file','title','author','license','url','sha256','rms_dbfs','peak_dbfs']) or s['license'] not in ['CC0-1.0','CC-BY-4.0'] or type(p['author']) is not str or not p['author'] or type(p['title']) is not str or not s['url'].startswith('https://') or p['license']!=s['license'] or p['url']!=s['url'] or p['sha256']!=s['sha256']:return False
        if s['kind']=='recording':
            if not exact(p,['author','download_date','archive_url','archive_sha256','input_file','input_sha256','sample_rate','lowpass_hz','compression_exponent','target_rms_dbfs','rms_dbfs','peak_dbfs']):return False
            if s['license']!='CC0-1.0' or not s['url'].startswith('https://') or type(p['author']) is not str or not p['author'] or type(p['download_date']) is not str or not re.fullmatch(r'[0-9]{4}-[0-9]{2}-[0-9]{2}',p['download_date']) or type(p['archive_url']) is not str or not p['archive_url'].startswith('https://') or not sha256(p['archive_sha256']) or not sha256(p['input_sha256']):return False
            if type(p['input_file']) is not str or not p['input_file'].startswith('tmp/sound-v2-downloads/raw/') or '..' in p['input_file'] or p['sample_rate']!=24000 or not number(p['lowpass_hz'],100,12000) or not number(p['compression_exponent'],.2,1) or not number(p['target_rms_dbfs'],-120,0):return False
    for id,e in v['events'].items():
        required={'bus','variants','selected','volume_db','pitch_min','pitch_max','max_instances','near_tiles','far_tiles','loop','cooldown_seconds'}
        if type(id) is not str or not id or type(e) is not dict or not required<=set(e) or not set(e)<=required|{'selection_key'}:return False
        if e['bus'] not in BUSES or type(e['loop']) is not bool or type(e['variants']) is not dict or not 1<=len(e['variants'])<=3 or type(e['selected']) is not str or e['selected'] not in e['variants']:return False
        if not number(e['volume_db'],-60,0) or not number(e['pitch_min'],.5,2) or not number(e['pitch_max'],e['pitch_min'],2) or not number(e['max_instances'],1,8) or e['max_instances']!=int(e['max_instances']) or not number(e['near_tiles'],0,64) or not number(e['far_tiles'],e['near_tiles']+.01,128) or not number(e['cooldown_seconds'],0,600):return False
        def valid_clip(clip):
            return exact(clip,['file','sha256','source_id']) and type(clip['file']) is str and clip['file'].startswith('res://content/audio/') and '..' not in clip['file'] and Path(clip['file']).suffix in ['.wav','.ogg'] and sha256(clip['sha256']) and type(clip['source_id']) is str and clip['source_id'] in v['sources']
        for key,clip in e['variants'].items():
            if key not in ['A','B','C'] or type(clip) is not dict or not {'file','sha256','source_id'}<=set(clip) or not set(clip)<={'file','sha256','source_id','takes'}:return False
            first={k:clip[k] for k in ['file','sha256','source_id']}
            if not valid_clip(first):return False
            if 'takes' in clip:
                takes=clip['takes']
                if type(takes) is not list or not 2<=len(takes)<=3 or takes[0]!=first or not all(valid_clip(t) for t in takes) or len({t['sha256'] for t in takes})!=len(takes):return False
    for id,e in v['events'].items():
        if 'selection_key' not in e:continue
        key=e['selection_key']
        if e['bus']!='Music' or type(key) is not str or key==id or key not in v['events']:return False
        selector=v['events'][key]
        if selector['bus']!='Music' or 'selection_key' in selector or not set(selector['variants'])<=set(e['variants']):return False
    return True
if __name__=='__main__':
    assert manifest(json.loads((ROOT/'godot/content/audio/sounds.json').read_text())), 'invalid sounds manifest'
    assert tuning(json.loads((ROOT/'godot/content/audio/runtime.json').read_text())), 'invalid audio tuning'
    print('Strict audio manifest/runtime validation passed')
