"""List user-provided music without modifying the user's directory."""
import argparse
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
DIRECTORY=ROOT/'production/audio/user-music'
SLOTS=ROOT/'godot/content/audio/music-slots.json'
SCENES=('day','dusk','night','rain','fireside','moon')
EXTENSIONS={'.wav','.mp3','.ogg','.flac','.m4a'}

def scan(directory=DIRECTORY):
    result={name:[] for name in SCENES};unrecognized=[]
    for path in sorted(directory.iterdir()):
        if path.is_symlink() or not path.is_file() or path.suffix.lower() not in EXTENSIONS:continue
        if '..' in path.name or len(path.name)>180:unrecognized.append(path.name);continue
        scene=next((name for name in SCENES if path.name.startswith(name+'-')),None)
        if scene is None:unrecognized.append(path.name)
        else:result[scene].append(path.name)
    if any(len(files)>16 for files in result.values()):raise ValueError('每个场景最多登记16个文件')
    return {'version':1,'slots':result},unrecognized

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--write',action='store_true');args=parser.parse_args()
    result,unknown=scan()
    if args.write:SLOTS.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'catalog':result,'unrecognized':unknown,'imported':False,'note':'扫描不转码或接入；放入文件后还需完成音乐处理和授权核验。'},ensure_ascii=False,indent=2))

if __name__=='__main__':main()
