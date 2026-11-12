"""Offline fixed persona parity and no-inference handshake regressions."""
import json,sys,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path[:0]=[str(ROOT/'godot/bridge'),str(ROOT/'scripts')]
from intent_companion import Companion
from habitat_godot import persona_card,Reader
class Tests(unittest.TestCase):
 def test_same_fixed_persona_and_no_turn(self):
  for resident in ('codex','companion-2','npc.mira','npc.nora'):
   for language in ('zh','en'):
    card=persona_card(resident,language)
    with tempfile.TemporaryDirectory(prefix='youqi-persona-') as d:
     Path(d,'persona.json').write_text(json.dumps(card))
     rpc=[];events=[];c=Companion(d,events.append,rpc.append)
     c.start()
     for label,result in [('initialize',{}),('account/read',{'requiresOpenaiAuth':True,'account':{'type':'chatgpt'}}),('config/read',{'config':{}}),('thread/start',{'thread':{'id':'stub-thread'},'model':'stub'})]:
      request=rpc[-1];self.assertEqual(request['method'],label)
      if label=='thread/start':
       self.assertIn(card['text'],request['params']['baseInstructions'])
       self.assertEqual(request['params']['baseInstructions'].count(card['text']),1)
      c.server({'id':request['id'],'result':result})
     self.assertTrue(c.ready);self.assertFalse(any(x.get('method')=='turn/start' for x in rpc))
 def test_mcp_initial_persona(self):
  with tempfile.TemporaryDirectory(prefix='youqi-persona-') as d:
   reader=Reader(d,'codex')
   self.assertEqual(reader.handle({'id':1,'method':'initialize'})['result']['instructions'],persona_card('codex')['text'])
   result=reader.handle({'id':2,'method':'tools/call','params':{'name':'habitat_persona','arguments':{'language':'en'}}})
   self.assertEqual(json.loads(result['result']['content'][0]['text'])['text'],persona_card('codex','en')['text'])
 def test_saved_override_isolated(self):
  with tempfile.TemporaryDirectory(prefix='youqi-persona-') as d:
   Path(d,'persona-overrides.cfg').write_text('[zh]\ncodex='+json.dumps('玩家保存的人设\n第二行',ensure_ascii=False)+'\n')
   reader=Reader(d,'codex')
   self.assertEqual(reader.handle({'id':1,'method':'initialize'})['result']['instructions'],'玩家保存的人设\n第二行')
   self.assertEqual(persona_card('codex','zh',d)['text'],'玩家保存的人设\n第二行')
   self.assertEqual(persona_card('codex','en',d),persona_card('codex','en'))
 def test_rotation_limits_and_reset(self):
  for rounds,tokens in [(6,0),(1,20001)]:
   with tempfile.TemporaryDirectory(prefix='youqi-rotation-') as d:
    rpc=[];c=Companion(d,lambda e:None,rpc.append)
    c.ready=True;c.thread_id='owned';c.rounds=rounds;c.turn_usage={'input_tokens':tokens}
    c.client({'kind':'chat','turn_key':'bound-turn','world':{'intent_card':{}}})
    self.assertEqual(rpc[-1]['method'],'thread/start')
    self.assertIsNotNone(c.queued_chat)
    self.assertEqual(c.rounds,0)
    self.assertEqual(c.turn_usage,{})
 def test_full_world_and_character(self):
  text=persona_card('codex')['text']
  for fact in ('蜂蜜蓝莓烤苹果','蓝莓果酱','只有一起烤东西吃才会饱','岛外记忆不能当成岛上发生过的事','不替其他伙伴说话','工作累了吗'):
   self.assertIn(fact,text)
  self.assertIn('harvest stew',persona_card('npc.mira','en')['text'])
if __name__=='__main__':unittest.main()
