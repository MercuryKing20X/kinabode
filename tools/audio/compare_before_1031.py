"""Run retained 82ef116 audio in a temporary isolated project, through input UI."""
import os,subprocess,tempfile,pathlib,json
root=pathlib.Path(__file__).resolve().parents[2];out=root/'production/evidence/playtest-fix-1031/audio/before';out.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='youqi-test-audio-before-') as tmp:
 t=pathlib.Path(tmp);project=t/'godot';project.mkdir()
 for entry in (root/'godot').iterdir():
  if entry.name in ['project.godot','scripts','content']:continue
  (project/entry.name).symlink_to(entry,target_is_directory=entry.is_dir())
 cfg=(root/'godot/project.godot').read_text().replace('[application]','[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="'+t.name+'"');(project/'project.godot').write_text(cfg)
 replacements={'scripts/game_audio.gd','scripts/game_audio_observer.gd','content/audio/runtime.json','content/audio/sounds.json'}
 def copy_dir(rel):
  dest=project/rel;dest.mkdir(exist_ok=True)
  for entry in (root/'godot'/rel).iterdir():
   r=str(pathlib.Path(rel)/entry.name)
   if r in replacements:
    (project/r).write_bytes(subprocess.check_output(['git','show','82ef116:godot/'+r],cwd=root))
   elif any(x.startswith(r+'/') for x in replacements):copy_dir(r)
   else:(project/r).symlink_to(entry,target_is_directory=entry.is_dir())
 copy_dir('scripts');copy_dir('content')
 env=dict(os.environ,HABITAT_DATA_DIR=str(t/'data'),HABITAT_OPENING='legacy',HABITAT_PLAYTEST_CAPTURE=str(out))
 (t/'data').mkdir()
 p=subprocess.run(['/Applications/Godot.app/Contents/MacOS/Godot','--audio-driver','Dummy','--log-file',str(t/'engine.log'),'--path',str(project),'--script','tests/test_speech_quiet_input.gd'],env=env,cwd=root,capture_output=True,text=True,timeout=90)
 (out/'run.log').write_text(p.stdout+p.stderr);print(p.returncode,p.stdout[-1000:],p.stderr[-500:])
 import shutil
 shutil.rmtree(pathlib.Path.home()/'Library/Application Support'/t.name,ignore_errors=True)
 if p.returncode:raise SystemExit(p.returncode)
