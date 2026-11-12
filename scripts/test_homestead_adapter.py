#!/usr/bin/env python3
"""Real temporary engine + v2 binding/cancellation; client is a test, never a model."""
import json,math,os,subprocess,tempfile,time,unittest
from pathlib import Path
from habitat_godot import Reader
from action_contract import command
ROOT=Path(__file__).resolve().parents[1]
ENGINE=os.environ.get('HABITAT_GODOT',str(ROOT/'scripts/isolated_godot.py'))
class HomesteadContract(unittest.TestCase):
 def test_strict_v2_arguments(self):
  self.assertEqual(command({'action':'homestead_read'})['intent'],'homestead_read')
  self.assertEqual(command({'action':'homestead_start','arguments':{'site_id':'point','wood_limit':5,'crop_limit':3}})['wood_limit'],5)
  for value in (True,-1,1.5,float('nan'),float('inf'),1001):
   with self.subTest(value=value),self.assertRaises(ValueError):command({'action':'homestead_start','arguments':{'site_id':'point','wood_limit':value}})
  for payload in ({'actor_id':'human','site_id':'point'},{'site_id':'point','fish_id':'fake'},{'plan_id':'other'}):
   with self.assertRaises(ValueError):command({'action':'homestead_start','arguments':payload})
class HomesteadAdapter(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.temp=tempfile.TemporaryDirectory(prefix='youqi-test-homestead-api-');cls.log=open(Path(cls.temp.name)/'engine.log','w+')
  cls.process=subprocess.Popen([ENGINE,'--headless','--path',str(ROOT/'godot'),'--script','tests/homestead_adapter_host.gd'],env=dict(os.environ,HABITAT_DATA_DIR=cls.temp.name),stdout=cls.log,stderr=cls.log)
  cls.addClassCleanup(cls.cleanup);cls.reader=Reader(cls.temp.name,timeout=3)
  deadline=time.monotonic()+25
  while time.monotonic()<deadline:
   if cls.process.poll() is not None:cls.log.seek(0);raise RuntimeError(cls.log.read()[-5000:])
   try:
    packet=cls.reader.request('dialogue_poll',{}).get('pending',{})
    if packet:cls.packet=packet;return
   except Exception:pass
   time.sleep(.05)
  cls.log.seek(0);raise RuntimeError(cls.log.read()[-5000:])
 @classmethod
 def cleanup(cls):
  cls.process.terminate()
  try:cls.process.wait(timeout=5)
  except subprocess.TimeoutExpired:cls.process.kill();cls.process.wait(timeout=5)
  cls.log.close();cls.temp.cleanup()
 def call(self,action,args,identity):
  response=self.reader.handle({'id':1,'method':'tools/call','params':{'name':'game_action','arguments':{'action':action,'arguments':args,'dialogue':identity}}})
  return json.loads(response['result']['content'][0]['text'])
 def wait(self,predicate):
  deadline=time.monotonic()+25
  while time.monotonic()<deadline:
   snapshot=self.reader.observe()
   if predicate(snapshot):return snapshot
   time.sleep(.05)
  self.fail('engine job timed out: '+str(snapshot.get('homestead')))
 def test_actual_bound_delivery_and_unlock(self):
  identity={k:self.packet[k] for k in ('world_id','resident_id','scope','session','generation','request_id')}
  detail=self.call('homestead_read',{},identity);self.assertTrue(detail['ok']);point=detail['homestead']['site']['id']
  self.assertFalse(self.call('cook',{'recipe_id':'blueberry-jam'},identity)['ok'])
  self.assertFalse(self.call('homestead_start',{'site_id':point},dict(identity,resident_id='human'))['ok'])
  self.assertFalse(self.call('homestead_start',{'site_id':point,'actor_id':'human'},identity)['ok'])
  self.assertFalse(self.call('homestead_start',{'site_id':point},dict(identity,scope='group'))['ok'])
  before=next(r for r in self.reader.observe()['residents'] if r['id']=='human')['position']
  started=self.call('homestead_start',{'site_id':point,'wood_limit':5,'crop_limit':3},identity);self.assertTrue(started['ok']);plan=started['plan_id']
  first=self.wait(lambda s:s['homestead']['plan'].get('status')=='paused')
  self.assertEqual(first['homestead']['delivered'],{'wood':5,'turnip':3});self.assertEqual(first['homestead']['progress'],0)
  self.assertFalse(self.call('homestead_resume',{'plan_id':'stale-plan'},identity)['ok'])
  self.assertTrue(self.call('homestead_resume',{'plan_id':plan},identity)['ok'])
  ready=self.wait(lambda s:s['homestead']['state']=='ready' and not s['self']['job'])
  self.assertEqual(ready['homestead']['delivered'],{'wood':24,'turnip':6,'pumpkin':4});self.assertFalse(ready['homestead']['unlock_recipe']['unlocked'])
  self.assertTrue(self.call('homestead_build',{'plan_id':plan},identity)['ok'])
  finished=self.wait(lambda s:s['homestead']['state']=='completed')
  self.assertEqual(next(r for r in finished['residents'] if r['id']=='human')['position'],before)
  self.assertTrue(finished['homestead']['unlock_recipe']['unlocked'])
  self.assertFalse(self.call('cook_read',{},identity)['ok'])
  self.assertFalse(self.call('cook',{'recipe_id':'blueberry-jam'},identity)['ok'])
  self.assertFalse(self.call('homestead_build',{'plan_id':plan},identity)['ok'])
  self.assertFalse(self.call('homestead_read',{},dict(identity,request_id='stale'))['ok'])
  self.assertFalse(self.call('homestead_read',{},dict(identity,generation=identity['generation']+1))['ok'])
if __name__=='__main__':unittest.main()
