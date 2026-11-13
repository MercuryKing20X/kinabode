#!/usr/bin/env python3
"""Export licensed, offline-playable desktop bundles using installed Godot templates."""
import argparse, hashlib, json, os, shutil, subprocess, tempfile, zipfile
from pathlib import Path
from godot_runtime import godot_executable
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--platform', choices=['all','Windows','macOS','Linux'], default='all')
p.add_argument('--output',type=Path,default=ROOT/'build')
a=p.parse_args();out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)
version='0.6.1'
readme='''有栖 / Kinabode v0.6.1

打开 / Open
Windows: 双击 Kinabode.exe。SmartScreen: 更多信息 → 仍要运行。
Windows: Double-click Kinabode.exe. SmartScreen: More info → Run anyway.
macOS: 解压后右键 Kinabode.app → 打开（未公证，ad-hoc签名）。
macOS: Extract, then right-click Kinabode.app → Open (ad-hoc signed, not notarized).
Linux: 双击 Kinabode.x86_64；必要时 chmod +x Kinabode.x86_64。
Linux: Double-click Kinabode.x86_64; if needed, chmod +x Kinabode.x86_64.

不接 AI 也能完整游玩；本地玩法不需要 Python。
The full game works offline without AI or Python.
可选 AI 需要 Python 3、自己的密钥，费用自理；连接页有说明。
Optional AI needs Python 3 and your own credentials, billed to you.

存档 / Saves (same application name 有栖 as the development version)
macOS: ~/Library/Application Support/Godot/app_userdata/有栖/
Windows: %APPDATA%/Godot/app_userdata/有栖/
Linux: ~/.local/share/godot/app_userdata/有栖/
若设置 HABITAT_DATA_DIR，则沿用其指定目录。不会重置旧进度。
HABITAT_DATA_DIR overrides the save location. Existing progress is preserved.

https://github.com/shuixingking/kinabode
抖音 / Douyin: MercuryFantasy
See LICENSE, CREDITS.md and font licenses.
'''
# These exact canonical documents are read through FileAccess inside the PCK.
for name in ['about.md','about.en.md']:
 dest=ROOT/'godot/content/about'/name;dest.parent.mkdir(exist_ok=True);shutil.copy2(ROOT/'docs'/name,dest)
records=[]
for preset,slug,exe in [('Windows','windows','Kinabode.exe'),('macOS','macos','Kinabode.zip'),('Linux','linux','Kinabode.x86_64')]:
 if a.platform not in ['all',preset]:continue
 folder=out/slug
 if folder.exists():shutil.rmtree(folder)
 folder.mkdir()
 command=[godot_executable(),'--headless','--audio-driver','Dummy','--rendering-method','gl_compatibility','--rendering-driver','opengl3','--path',str(ROOT/'godot'),'--export-release',preset,str(folder/exe)]
 subprocess.run(command,check=True)
 if preset=='macOS':
  with zipfile.ZipFile(folder/exe) as z:
   for item in z.infolist():
    target=folder/item.filename
    if item.is_dir():target.mkdir(parents=True,exist_ok=True);continue
    target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(z.read(item));mode=item.external_attr>>16
    if mode:target.chmod(mode)
  (folder/exe).unlink()
  apps=list(folder.glob('*.app'))
  if len(apps)!=1:raise RuntimeError('Expected one macOS app')
  app=apps[0]
  if app.name!='Kinabode.app':app.rename(folder/'Kinabode.app')
  subprocess.run(['codesign','--force','--deep','--sign','-',str(folder/'Kinabode.app')],check=True)
 elif preset=='Linux':(folder/exe).chmod(0o755)
 for name in ['LICENSE','CREDITS.md']:shutil.copy2(ROOT/name,folder/name)
 for source in (ROOT/'godot/assets/fonts').glob('*OFL*'):shutil.copy2(source,folder/source.name)
 (folder/'README.txt').write_text(readme,encoding='utf-8')
 archive=out/f'Kinabode-v{version}-{slug}.zip'
 with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
  for file in sorted(folder.rglob('*')):
   if file.is_file():z.write(file,file.relative_to(folder))
 records.append({'platform':preset,'file':archive.name,'bytes':archive.stat().st_size,'sha256':hashlib.sha256(archive.read_bytes()).hexdigest()})
(out/'packages.json').write_text(json.dumps(records,indent=2)+'\n');print(json.dumps(records,indent=2))
