#!/usr/bin/env python3
"""Real temporary Godot and external MCP; no actual model calls."""
import json,os,subprocess,tempfile,time,unittest
from pathlib import Path
from habitat_godot import Reader
ROOT=Path(__file__).resolve().parents[1]
ENGINE=os.environ.get('HABITAT_GODOT',str(ROOT/'scripts/isolated_godot.py'))
class ChessAdapter(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.temp=tempfile.TemporaryDirectory(prefix='youqi-test-chess-api-');cls.log=open(Path(cls.temp.name)/'engine.log','w+')
  cls.process=subprocess.Popen([ENGINE,'--headless','--path',str(ROOT/'godot'),'--script','tests/gomoku_adapter_host.gd'],env=dict(os.environ,HABITAT_DATA_DIR=cls.temp.name),stdout=cls.log,stderr=cls.log)
  cls.addClassCleanup(cls.cleanup);cls.reader=Reader(cls.temp.name,timeout=3)
  deadline=time.monotonic()+15
  while time.monotonic()<deadline:
   if cls.process.poll() is not None:cls.log.seek(0);raise RuntimeError(cls.log.read()[-4000:])
   try:
    packet=cls.reader.request('dialogue_poll',{}).get('pending',{})
    if packet:cls.packet=packet;break
   except Exception:pass
   time.sleep(.05)
  else:cls.log.seek(0);raise RuntimeError(cls.log.read()[-4000:])
 @classmethod
 def cleanup(cls):
  cls.process.terminate()
  try:cls.process.wait(timeout=5)
  except subprocess.TimeoutExpired:cls.process.kill();cls.process.wait(timeout=5)
  cls.log.close();cls.temp.cleanup()
 def call(self,action,args,identity):
  result=self.reader.handle({'id':9,'method':'tools/call','params':{'name':'game_action','arguments':{'action':action,'arguments':args,'dialogue':identity}}})
  return json.loads(result['result']['content'][0]['text'])
 def test_bound_turn_and_stale_rejection(self):
  identity={k:self.packet[k] for k in ('world_id','resident_id','scope','session','generation','request_id')}
  game=self.reader.observe()['gomoku']['own_matches'][0]
  self.assertEqual(game['turn_actor_id'],'codex');self.assertEqual(game['history'],[])
  args={'site_id':'play.gomoku','match_id':game['id'],'revision':game['revision'],'x':7,'y':7}
  self.assertTrue(self.call('gomoku_move',args,identity)['ok'])
  self.assertFalse(self.call('gomoku_move',args,identity)['ok'])
  board=self.call('gomoku_read',{'site_id':'play.gomoku'},identity)['match']
  self.assertEqual(board['history'],[[7,7]]);self.assertEqual(board['turn_actor_id'],'human')
  self.assertFalse(self.call('gomoku_move',dict(args,revision=board['revision'],x=8),identity)['ok'])
  self.assertFalse(self.call('gomoku_move',dict(args,actor_id='human'),identity)['ok'])
  self.assertFalse(self.call('gomoku_leave',{'site_id':'play.gomoku','match_id':game['id'],'revision':board['revision']},dict(identity,scope='group'))['ok'])
  self.assertTrue(self.call('gomoku_leave',{'site_id':'play.gomoku','match_id':game['id'],'revision':board['revision']},identity)['ok'])
  observed=self.reader.observe();self.assertEqual(observed['gomoku']['own_matches'][0]['phase'],'paused');self.assertEqual(observed['self']['job'],{})
  args={'site_id':'play.gomoku','match_id':game['id'],'revision':observed['gomoku']['own_matches'][0]['revision']}
  self.assertTrue(self.call('gomoku_resign',args,identity)['ok'])
  memories=self.reader.handle({'id':10,'method':'tools/call','params':{'name':'read_memories','arguments':{'kind':'gomoku_match'}}})
  self.assertEqual(json.loads(memories['result']['content'][0]['text'])['total'],1)
if __name__=='__main__':unittest.main()
