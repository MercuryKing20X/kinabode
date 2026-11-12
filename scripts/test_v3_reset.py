"""Actual Main startup/reset/reload with disposable files. No models or screenshot shortcuts."""
import hashlib,json,os,subprocess,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];ENGINE=os.environ.get('HABITAT_GODOT',str(ROOT/'scripts/isolated_godot.py'))
class Reset(unittest.TestCase):
 def test_actual_cli_reset_preserves_identity_and_templates(self):
  with tempfile.TemporaryDirectory(prefix='youqi-test-v3-reset-') as folder:
   directory=Path(folder);env=dict(os.environ,HABITAT_DATA_DIR=folder,HABITAT_LIVE_TEST='0')
   def run(args,expected=0):
    result=subprocess.run([ENGINE,'--headless','--path',str(ROOT/'godot'),*args],env=env,capture_output=True,text=True,timeout=45)
    self.assertEqual(result.returncode,expected,result.stdout+result.stderr)
    if expected==0:self.assertNotIn('SCRIPT ERROR:',result.stdout+result.stderr)
    return result
   run(['--script','tests/seed_legacy_identity.gd'])
   old=(directory/'island-v2.json').read_bytes();sentinel=directory/'editable-template-sentinel.json';sentinel.write_text('preserved editable source\n')
   run(['--quit-after','4','--','--opening=showcase','--fresh-world'])
   archives=list(directory.glob('island-v2.json.before-farms-*'));self.assertEqual(len(archives),1);self.assertEqual(archives[0].read_bytes(),old)
   new=json.loads((directory/'island-v2.json').read_text());self.assertEqual(new['template_id'],'home-v3');self.assertEqual(new['opening_id'],'showcase')
   self.assertEqual(new['actors']['human']['name'],'留住的名字');self.assertTrue(new['actors']['human']['custom_appearance']);self.assertEqual(new['actors']['codex']['controller'],'local')
   self.assertFalse(new['actors']['human']['carry']);self.assertEqual(new['storage']['items'],json.loads((ROOT/'godot/content/openings/showcase.json').read_text())['storage']);self.assertEqual(new['storage']['items']['wood'],24);self.assertEqual(new['storage']['items']['mushroom'],12);self.assertFalse(any(o['kind']=='chest' for o in new['objects'].values()));self.assertEqual(sentinel.read_text(),'preserved editable source\n')
   initial_memories=new['shared_memories'];run(['--quit-after','4','--','--opening=showcase'])
   loaded=json.loads((directory/'island-v2.json').read_text());self.assertEqual(loaded['shared_memories'],initial_memories);self.assertEqual(loaded['interior']['furniture'],new['interior']['furniture'])  # Reload preserves every authored main-island and vacation-room instance.
   before=(directory/'island-v2.json').read_bytes();run(['--quit-after','4','--','--opening=legacy'],expected=1)
   self.assertEqual((directory/'island-v2.json').read_bytes(),before);self.assertTrue(list(directory.glob('island-v2.json.wrong-template-*')))
if __name__=='__main__':unittest.main()
