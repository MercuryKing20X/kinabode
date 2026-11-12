"""Build the local audition table from the same manifest used by Godot."""
import html
import json
import os
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / 'godot/content/audio/sounds.json'
OUTPUT = ROOT / 'production/audio/audition.html'
SAMPLES = ['voice.bright', 'hunger.hungry', 'ambience.fire', 'music.sample30', 'ui.click']


def build():
    data = json.loads(MANIFEST.read_text())
    music=ROOT/'godot/content/audio/user-music.json'
    if music.exists():
        for scene,track in json.loads(music.read_text())['tracks'].items():
            key='music.'+scene
            data['sources'][key]={'kind':'licensed_music','script':'tools/audio/prepare_user_music.py','parameters':track,'license':track['license'],'url':track['url'],'sha256':track['sha256']}
            data['events'][key]={'bus':'Music','variants':{'A':{'file':track['file'],'sha256':track['sha256'],'source_id':key}},'selected':'A','volume_db':-6}
    sources_path=ROOT/'godot/content/audio/SOURCES.md'
    prefix=sources_path.read_text().split('<!-- GENERATED FILE SOURCES -->')[0]
    lines=['<!-- GENERATED FILE SOURCES -->','', '## 当前运行时逐文件来源（自动生成）','', '精确处理参数、原始文件哈希和来源信息在清单 sources.parameters。TimGM6mb 音乐仅作历史参考，当前运行时不引用。','', '|ID/版本|来源/脚本|作者|授权|来源|文件 SHA256|','|---|---|---|---|---|---|']
    for key,event in data['events'].items():
        for version,variant in event['variants'].items():
            for number,take in enumerate(variant.get('takes',[variant]),1):
                source=data['sources'][take['source_id']]
                author=source['parameters'].get('author','本项目')
                url=source['url'] or '本项目原创'
                lines.append(f'|{key}/{version}/{number}|{source["script"]} · {take["source_id"]}|{author}|{source["license"]}|{url}|`{take["sha256"]}`|')
    sources_path.write_text(prefix+'\n'.join(lines)+'\n')
    def row(key):
        event = data['events'][key]
        selection_key=event.get('selection_key',key)
        selected=data['events'][selection_key]['selected']
        link_note=f' · 版本跟随 {selection_key}' if selection_key!=key else ''
        cells = []
        for version, variant in event['variants'].items():
            current = ' · 当前' if selected == version else ''
            sounds=[]
            for number,take in enumerate(variant.get('takes',[variant]),1):
                path = ROOT / 'godot' / take['file'].removeprefix('res://')
                media = path if event['bus']=='Music' else OUTPUT.parent / 'audition-media' / path.name
                media.parent.mkdir(parents=True,exist_ok=True)
                if path.suffix.lower() == '.wav':

                    if path != media:shutil.copyfile(path, media)
                else:
                    raise ValueError('试听台需要浏览器通用 WAV 副本: '+str(path))
                url = os.path.relpath(media, OUTPUT.parent)
                source=data['sources'][take['source_id']]
                credit=source['parameters'].get('author','本项目')+' · '+source['license']
                sounds.append(f'<small>{number} · {html.escape(credit)}</small><audio controls preload="metadata" src="{html.escape(url)}"></audio><small class="status">正在读取音频…</small><a href="{html.escape(url)}" target="_blank">直接打开音频</a>')
            cells.append(f'<td><b>{html.escape(version+current)}</b><br>'+''.join(sounds)+'</td>')
        return f'<tr><th>{html.escape(key)}<small>{event["bus"]} · {event["volume_db"]} dB{html.escape(link_note)}</small></th>'+''.join(cells)+'</tr>'
    body = '<h1>有栖 · 声音试听台</h1><p>先调低系统音量，一次试听一个。修改 sounds.json 的 selected 可选 A/B/C，再运行本脚本更新页面。草地候选使用树叶与沙地录音近似。</p><h2>小样</h2><table>'
    body += ''.join(row(key) for key in SAMPLES if key in data['events'])+'</table>'
    body += '<h2>说话声：旧版 / 一泡一声 A·B·C（均含运行时 -5dB）</h2><table>'
    for key,event in data['events'].items():
        if not key.startswith('voice.'):continue
        body += '<tr><th>'+html.escape(key)+'</th>'
        for label,folder,version,gain in [('旧（每泡最多三声）','voice-deep-1101','A',10**(-5/20)),('新A · 最软（默认）','voice-single-1101','A',10**(-5/20)),('新B · 轻啵','voice-single-1101','B',10**(-5/20)),('新C · 轻拨','voice-single-1101','C',10**(-5/20))]:
            src=ROOT/'godot/content/audio'/folder/(key+'-'+version+'.wav')
            dst=OUTPUT.parent/'audition-media'/(label+'-'+src.name)
            if gain==1:shutil.copyfile(src,dst)
            else:
                import wave,array
                with wave.open(str(src),'rb') as w:params=w.getparams();samples=array.array('h',w.readframes(w.getnframes()))
                samples=array.array('h',(round(v*gain) for v in samples))
                with wave.open(str(dst),'wb') as w:w.setparams(params);w.writeframes(samples.tobytes())
            body += '<td>'+label+'<audio controls src="'+html.escape(os.path.relpath(dst,OUTPUT.parent))+'"></audio><small class="status"></small></td>'
        body += '</tr>'
    body += '</table>'
    for bus in ('Voices', 'Effects', 'Ambience', 'Music'):
        body += f'<h2>{bus}</h2><table>'+''.join(row(key) for key,event in data['events'].items() if event['bus']==bus)+'</table>'
    if not any(event['bus']=='Music' for event in data['events'].values()):
        slot_path=ROOT/'godot/content/audio/music-slots.json'
        slots=json.loads(slot_path.read_text())['slots'] if slot_path.exists() else {}
        labels={'day':'白天','dusk':'黄昏','night':'夜晚','rain':'雨天','fireside':'围炉','moon':'月牙岛'}
        body += '<ul>'+''.join('<li>'+label+'：'+('待处理 '+html.escape('、'.join(slots.get(key,[]))) if slots.get(key) else '还未放入')+'</li>' for key,label in labels.items())+'</ul>'
    if music.exists():
        body += '<h2>音乐来源 / Music sources</h2><ul>'
        for scene,track in json.loads(music.read_text())['tracks'].items():
            body += '<li>'+html.escape(scene+' · '+track['title']+' · '+track['author']+' · '+track['license'])+' <a href="'+html.escape(track['url'])+'">Source</a></li>'
        body += '</ul>'
    OUTPUT.parent.mkdir(parents=True,exist_ok=True)
    OUTPUT.write_text('<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>有栖声音试听台</title><style>body{font:16px system-ui;max-width:1280px;margin:32px auto;background:#fcf6e8;color:#514536}h1,h2{color:#86633d}table{width:100%;border-collapse:collapse}td,th{padding:12px;text-align:left;border-bottom:1px solid #dfd4bf}small{display:block;font-weight:400}audio{max-width:260px}</style>'+body+'''<script>
for(const a of document.querySelectorAll('audio')){
  const status=a.nextElementSibling;
  const ready=()=>{status.textContent='可播放 · '+a.duration.toFixed(3)+' 秒'};
  a.addEventListener('loadedmetadata',ready);
  if(a.readyState>=1)ready();
  a.addEventListener('error',()=>{status.textContent='加载失败，请点击下方“直接打开音频”，或用本机试听网页打开。'});
}
document.addEventListener('play',e=>{for(const a of document.querySelectorAll('audio'))if(a!==e.target)a.pause()},true)
</script></html>''')
    print(OUTPUT)

if __name__ == '__main__':
    build()
