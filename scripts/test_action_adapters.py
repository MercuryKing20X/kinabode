#!/usr/bin/env python3
"""Provider-neutral, native-session MCP, and cancellation contract tests; no inference."""
import concurrent.futures,importlib.util,json,sys,tempfile,time,unittest,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'godot/bridge'))
from companion import Companion,VERSION,DYNAMIC_TOOLS
from action_contract import command
from model_actions_mcp import exchange,tools
from habitat_godot import Reader
class Adapters(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory(prefix='youqi-test-adapter-');self.addCleanup(self.temp.cleanup)
  self.events=[];self.calls=[];self.client=Companion(self.temp.name,self.events.append,self.calls.append)
  self.client.thread_id='11111111-1111-1111-1111-111111111111';self.client.ready=True
 def start(self):self.client.client({'kind':'chat','text':'在海边钓一条鱼','world':{'self_actor_id':'test.resident','self':{}}})
 def submit(self,tool,args,token=None):
  key=uuid.uuid4().hex
  payload={'id':key,'tool':tool,'expires':time.time()+15,'arguments':dict(args,turn_token=self.client.action_token if token is None else token)}
  (self.client.actions_dir/'inbox'/(key+'.json')).write_text(json.dumps(payload))
  self.client.tick();return key
 def response(self,key):return json.loads((self.client.actions_dir/'outbox'/(key+'.json')).read_text())
 def test_legacy_session_keeps_identity_and_dynamic_tools(self):
  self.client.save_thread();original=json.loads(self.client.state_path.read_text());self.client.open_thread()
  call=self.calls[-1];self.assertEqual(call['method'],'thread/resume');self.assertEqual(call['params']['threadId'],original['threadId'])
  self.assertNotIn('dynamicTools',call['params']);self.assertEqual(original['version'],VERSION)
  self.assertNotIn('white-haired',call['params']['baseInstructions']);self.assertIn('game_actions/game_action',call['params']['baseInstructions'])
  config=call['params']['config']['mcp_servers.youqi_actions'];self.assertTrue(config['enabled']);self.assertTrue(config['args'][0].endswith('model_actions_mcp.py'))
  self.assertNotIn('fish',next(t for t in DYNAMIC_TOOLS if t['name']=='habitat_request')['inputSchema']['properties']['intent']['enum'])
 def test_resume_error_replaces_owned_session_without_disconnect(self):
  self.client.save_thread();old=self.client.state_path.read_text();self.client.open_thread();call=self.calls[-1]
  self.client.server({'id':call['id'],'error':{'message':'resume failed'}})
  # DIRECTION 2026-11-09: 会话恢复失败不再关闭连接，改为自动开新会话并用记忆卡片接上。
  self.assertFalse(self.client.closed);self.assertEqual(self.client.state_path.read_text(),old)
  self.assertEqual(self.calls[-1]['method'],'thread/start')
  self.assertEqual(self.events[-1]['kind'],'session_recovery')
 def test_native_mcp_actual_mailbox_roundtrip(self):
  self.start();token=self.client.action_token
  with concurrent.futures.ThreadPoolExecutor() as pool:
   future=pool.submit(exchange,self.client.actions_dir,'game_action',{'action':'fish','arguments':{},'turn_token':token})
   deadline=time.monotonic()+3
   while not list((self.client.actions_dir/'inbox').glob('*.json')) and time.monotonic()<deadline:time.sleep(.005)
   self.client.tick();event=next(e for e in self.events if e.get('kind')=='action')
   self.assertEqual(event['command'],{'intent':'fish'})
   self.client.client({'kind':'tool_result','id':event['id'],'result':{'ok':True,'status':'accepted','job_id':'genuine-job'}})
   result=future.result(timeout=3);self.assertEqual(result['status'],'accepted');self.assertEqual(result['action_turn_token'],token)
  key=self.submit('game_action',{'action':'move','arguments':{'x':5,'y':6}})
  self.assertFalse(self.response(key)['ok'])
 def test_cancel_blocks_old_and_cross_turn_tokens(self):
  self.start();old=self.client.action_token;count=len(self.events)
  self.client.cancel('stop');key=self.submit('game_action',{'action':'fish'},old)
  self.assertEqual(self.response(key)['error'],'stale_action_turn')
  self.assertFalse(any(e.get('kind')=='action' for e in self.events[count:]))
  self.client.server({'method':'turn/completed','params':{'turn':{}}});self.start()
  key=self.submit('game_action',{'action':'fish'},old);self.assertEqual(self.response(key)['error'],'stale_action_turn')
 def test_no_model_wakeup_from_idle_mailbox(self):
  before=list(self.calls);key=self.submit('game_actions',{},'old-token');self.assertEqual(self.response(key)['error'],'stale_action_turn');self.assertEqual(self.calls,before)
 def test_actor_override_and_unknown_fields_reject(self):
  self.start()
  for args in [{'action':'fish','arguments':{'actor_id':'human'}},{'action':'move','arguments':{'x':True,'y':5}},{'action':'fish','arguments':{'target_id':'fishery'}},{'action':'gesture','arguments':{'gesture':'execute'}},{'action':'exec','arguments':{}}]:
   with self.assertRaises(ValueError):command(args)
   key=self.submit('game_action',args);self.assertFalse(self.response(key)['ok'])
 def test_external_and_native_use_same_action_contract(self):
  class External(Reader):
   def request(self,operation,query=None):return {'ok':True,'operation':operation,'command':query,'self_actor_id':'external.model'}
  reader=External(self.temp.name)
  value={'action':'stock_fish','arguments':{'fish_id':'fish-x','pen_id':'pen-x'}}
  result=reader.handle({'id':1,'method':'tools/call','params':{'name':'game_action','arguments':value}})
  payload=json.loads(result['result']['content'][0]['text']);self.assertEqual(payload['command'],command(value));self.assertEqual(payload['self_actor_id'],'external.model')
  self.assertIn('turn_token',tools()[1]['inputSchema']['required'])
 def test_chess_exact_integer_contract(self):
  args={'site_id':'play.gomoku','match_id':'match-x','revision':4,'x':7,'y':7}
  self.assertEqual(command({'action':'gomoku_move','arguments':args}),dict(args,intent='gomoku_move'))
  for patch in [{'revision':True},{'x':.5},{'y':15},{'x':float('nan')},{'actor_id':'human'}]:
   with self.assertRaises(ValueError):command({'action':'gomoku_move','arguments':dict(args,**patch)})
  with self.assertRaises(ValueError):command({'action':'gomoku_move','arguments':{'site_id':'play.gomoku'}})
 def test_removed_cooking_contract_and_native_turn_barrier(self):
  for action,args in [('cook_read',{}),('cook',{'recipe_id':'turnip-soup'}),('cook',{'recipe_id':'grilled-fish','fish_id':'real-fish'}),('cook',{'recipe_id':'turnip-soup','actor_id':'human'}),('cook',{'recipe_id':'turnip-soup','portions':8})]:
   with self.assertRaises(ValueError):command({'action':action,'arguments':args})
  self.start();token=self.client.action_token
  for action in ['cook','cook_read']:
   key=self.submit('game_action',{'action':action,'arguments':{'recipe_id':'turnip-soup'} if action=='cook' else {}})
   self.assertFalse(self.response(key)['ok'])
  self.assertFalse(any(e.get('kind')=='action' for e in self.events))
  # Preserve original native accepted/busy/cancel/stale barriers on a supported action.
  key=self.submit('game_action',{'action':'homestead_start','arguments':{'site_id':'site-real'}})
  event=next(e for e in self.events if e.get('kind')=='action')
  self.assertEqual(event['command'],{'intent':'homestead_start','site_id':'site-real'})
  self.client.client({'kind':'tool_result','id':event['id'],'result':{'ok':True,'status':'accepted','job_id':'real-job'}})
  self.assertTrue(self.response(key)['ok'])
  blocked=self.submit('game_action',{'action':'homestead_build','arguments':{'plan_id':'other-plan'}})
  self.assertFalse(self.response(blocked)['ok'])
  self.client.cancel('stop');stale=self.submit('game_action',{'action':'journal_read'},token)
  self.assertEqual(self.response(stale)['error'],'stale_action_turn')
 def test_journal_optional_pagination_and_native_binding(self):
  self.assertEqual(command({'action':'journal_read'}),{'intent':'journal_read'})
  args={'species_id':'bean','status':'caught','offset':16,'limit':8,'revision':'a'*64}
  self.assertEqual(command({'action':'journal_read','arguments':args}),dict(args,intent='journal_read'))
  for patch in ({'actor_id':'human'},{'offset':True},{'limit':33},{'revision':1},{'status':'seen'},{'offset':.2}):
   with self.assertRaises(ValueError):command({'action':'journal_read','arguments':patch})
  self.start();key=self.submit('game_action',{'action':'journal_read','arguments':{'limit':8}})
  event=next(e for e in self.events if e.get('kind')=='action')
  self.assertEqual(event['command'],{'intent':'journal_read','limit':8})
  self.client.client({'kind':'tool_result','id':event['id'],'result':{'ok':True,'entries':[],'total':128}})
  self.assertTrue(self.response(key)['ok']);self.assertFalse(self.client.accepted_job)
  old=self.client.action_token;self.client.cancel('stop');stale=self.submit('game_action',{'action':'journal_read'},old)
  self.assertEqual(self.response(stale)['error'],'stale_action_turn')
 def test_native_chess_move_is_not_replacement_labor(self):
  self.start();self.client.accepted_job='existing'
  key=self.submit('game_action',{'action':'gomoku_move','arguments':{'site_id':'play.gomoku','match_id':'match-x','revision':4,'x':7,'y':7}})
  event=next(e for e in self.events if e.get('kind')=='action')
  self.assertEqual(event['command']['intent'],'gomoku_move')
  self.client.client({'kind':'tool_result','id':event['id'],'result':{'ok':True,'status':'completed','revision':5}})
  self.assertEqual(self.response(key)['revision'],5)
if __name__=='__main__':unittest.main()
