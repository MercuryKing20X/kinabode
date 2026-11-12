"""Process licensed originals, preserving them; no synthesis or network access.
Run with the project's audio-env Python (numpy) and ffmpeg.
"""
import hashlib,json,pathlib,subprocess,tempfile
import numpy as np
ROOT=pathlib.Path(__file__).resolve().parents[2]
FF=ROOT/'tmp/audio-env/bin/ffmpeg'
rows=json.loads((ROOT/'production/audio/user-music/catalog.json').read_text())
tracks={};quality={}
out=ROOT/'godot/content/audio/user-music';out.mkdir(exist_ok=True)
for row in rows:
 scene=row['scene'];raw=ROOT/f'production/audio/user-music/originals/{scene}.mp3'
 if not raw.exists():continue
 with tempfile.TemporaryDirectory(prefix='youqi-music-') as tmp:
  pcm=pathlib.Path(tmp)/'in.f32'
  subprocess.run([str(FF),'-v','error','-i',str(raw),'-af','loudnorm=I=-18:TP=-5:LRA=8','-ar','24000','-ac','2','-f','f32le',str(pcm)],check=True)
  a=np.fromfile(pcm,dtype='<f4').reshape(-1,2)
  # Whole original retained; overlap tail and head to make a smooth repeating bed.
  n=min(24000*4,len(a)//4);w=np.linspace(0,1,n)[:,None]
  cross=a[-n:]*(1-w)+a[:n]*w
  a=np.concatenate([cross,a[n:-n]])
  # Boundary between last middle sample and original tail is continuous.
  # A 20ms cosine endpoint guard removes quantization/DC discontinuities.
  guard=min(480,len(a)//8);fade=(.5-.5*np.cos(np.linspace(0,np.pi,guard)))[:,None]
  a[:guard]*=fade;a[-guard:]*=fade[::-1]
  path=out/f'{scene}.wav'
  pcm.write_bytes(a.astype('<f4').tobytes())
  subprocess.run([str(FF),'-v','error','-y','-f','f32le','-ar','24000','-ac','2','-i',str(pcm),'-c:a','pcm_s16le',str(path)],check=True)
  sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
  quality[scene]={'boundary_jump':float(np.max(np.abs(a[0]-a[-1]))),'peak_dbfs':float(20*np.log10(max(1e-8,np.max(np.abs(a))))),'rms_dbfs':float(20*np.log10(max(1e-8,np.sqrt(np.mean(a*a))))),'seconds':len(a)/24000,'original_sha256':sha(raw),'sha256':sha(path)}
  analysis=subprocess.run([str(FF),'-hide_banner','-i',str(path),'-af','loudnorm=I=-18:TP=-3:LRA=8:print_format=json','-f','null','-'],capture_output=True,text=True,check=True).stderr
  measured=json.JSONDecoder().raw_decode(analysis[analysis.rfind('{'):])[0]
  assert quality[scene]['boundary_jump']<=1/32768, 'nonzero seam'
  quality[scene]['integrated_lufs']=float(measured['input_i']);quality[scene]['true_peak_dbtp']=float(measured['input_tp'])
  assert quality[scene]['true_peak_dbtp']<=-2.9, 'true peak exceeds ceiling'
  tracks[scene]={'file':'res://content/audio/user-music/'+path.name,'title':row['title'],'author':'Kevin MacLeod','license':'CC-BY-4.0','url':'https://incompetech.com/music/royalty-free/index.html?isrc='+row['isrc'],'sha256':sha(path),'rms_dbfs':quality[scene]['rms_dbfs'],'peak_dbfs':quality[scene]['peak_dbfs']}
(ROOT/'godot/content/audio/user-music.json').write_text(json.dumps({'version':1,'tracks':tracks},indent=2)+'\n')
(ROOT/'production/audio/user-music/quality.json').write_text(json.dumps(quality,indent=2)+'\n')
print('processed',len(tracks))
lines=['# 首批音乐与授权（2026-11-05）','','作者均为 Kevin MacLeod；授权 CC BY 4.0，允许商用、修改，须署名并链接授权、注明修改。','授权原文：https://creativecommons.org/licenses/by/4.0/ 。官方曲目页底部明确标注 By Attribution 4.0。','建议游戏署名：Music by Kevin MacLeod (incompetech.com), licensed under CC BY 4.0. Edited for looping and loudness.','','|场景|曲名|官方来源|状态/原文件SHA256|','|---|---|---|---|']
for row in rows:
 scene=row['scene'];url='https://incompetech.com/music/royalty-free/index.html?isrc='+row['isrc']
 status=quality.get(scene,{}).get('original_sha256','下载失败/未完整收到；候选，不接入')
 lines.append(f"|{scene}|{row['title']}|{url}|{status}|")
lines+=['','已下载原文件在 originals/，日期2026-11-05；运行时24kHz双声道16位PCM在 godot/content/audio/user-music/。','处理：FFmpeg loudnorm目标-18 LUFS、-5dBTP（为24kHz重采样留余量），最终测量峰值须≤-2.9dBTP，4秒尾首交叠循环、20ms余弦接缝护边；quality.json记录实际RMS/峰值/边界跳变，不冒充听感验收。','换曲可替换 originals/ 对应场景文件后重新运行 tools/audio/prepare_user_music.py，或修改 user-music.json 的文件与哈希。授权必须自行确认。','本轮不使用合成音乐或旧TimGM音乐；未下载成功的场景保持静音。']
(ROOT/'production/audio/user-music/SOURCES.md').write_text('\n'.join(lines)+'\n')
