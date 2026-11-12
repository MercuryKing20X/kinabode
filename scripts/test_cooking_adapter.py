#!/usr/bin/env python3
"""Real temporary Godot + v2 external adapter; no inference or player data."""
import json,os,subprocess,tempfile,time,unittest
from pathlib import Path
from habitat_godot import Reader
ROOT=Path(__file__).resolve().parents[1]
ENGINE=os.environ.get('HABITAT_GODOT',str(ROOT/'scripts/isolated_godot.py'))
class CookingAdapter(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.temp=tempfile.TemporaryDirectory(prefix='youqi-test-cooking-api-');cls.log=open(Path(cls.temp.name)/'engine.log','w+')
  cls.process=subprocess.Popen([ENGINE,'--headless','--path',str(ROOT/'godot'),'--script','tests/cooking_adapter_host.gd'],env=dict(os.environ,HABITAT_DATA_DIR=cls.temp.name),stdout=cls.log,stderr=cls.log)
  cls.addClassCleanup(cls.cleanup);cls.reader=Reader(cls.temp.name,timeout=3)
  deadline=time.monotonic()+20
  while time.monotonic()<deadline:
   if cls.process.poll() is not None:cls.log.seek(0);raise RuntimeError(cls.log.read()[-5000:])
   try:
    packet=cls.reader.request('dialogue_poll',{}).get('pending',{})
    if packet:cls.packet=packet;break
   except Exception:pass
   time.sleep(.05)
  else:cls.log.seek(0);raise RuntimeError(cls.log.read()[-5000:])
 @classmethod
 def cleanup(cls):
  cls.process.terminate()
  try:cls.process.wait(timeout=5)
  except subprocess.TimeoutExpired:cls.process.kill();cls.process.wait(timeout=5)
  cls.log.close();cls.temp.cleanup()
 def call(self,action,args,identity):
  response=self.reader.handle({'id':9,'method':'tools/call','params':{'name':'game_action','arguments':{'action':action,'arguments':args,'dialogue':identity}}})
  return json.loads(response['result']['content'][0]['text'])
 def test_removed_cooking_rejects_without_side_effects_and_binding_stays_strict(self):
  identity={k:self.packet[k] for k in ('world_id','resident_id','scope','session','generation','request_id')}
  before=self.reader.observe();host=next(r for r in before['residents'] if r['id']=='human')['position']
  for action,args in [('cook_read',{}),('cook',{'recipe_id':'turnip-soup'}),('cook',{'recipe_id':'blueberry-jam'}),('cook',{'recipe_id':'grilled-fish','fish_id':'missing'})]:
   self.assertFalse(self.call(action,args,identity)['ok'])
  self.assertFalse(self.call('cook',{'recipe_id':'turnip-soup'},dict(identity,resident_id='human'))['ok'])
  self.assertFalse(self.call('cook',{'recipe_id':'turnip-soup','actor_id':'human'},identity)['ok'])
  self.assertFalse(self.call('cook',{'recipe_id':'turnip-soup'},dict(identity,scope='group'))['ok'])
  self.assertFalse(self.call('cook',{'recipe_id':'turnip-soup'},dict(identity,request_id='stale'))['ok'])
  self.assertFalse(self.call('cook',{'recipe_id':'turnip-soup'},dict(identity,generation=identity['generation']+1))['ok'])
  # Existing unchanged v2 read operation proves exact-session binding remains active.
  self.assertTrue(self.call('journal_read',{},identity)['ok'])
  self.assertFalse(self.call('journal_read',{},dict(identity,request_id='stale'))['ok'])
  after=self.reader.observe()
  self.assertEqual(next(r for r in after['residents'] if r['id']=='human')['position'],host)
  self.assertEqual(after['self']['job'],{})
  self.assertNotIn('cooking',after)
  self.assertEqual(after['shared_life'],before['shared_life'])
if __name__=='__main__':unittest.main()
