import io
import json
import os
from pathlib import Path
import sys
import subprocess
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'godot/bridge'))
import openai_companion as api

class OpenAITest(unittest.TestCase):
 def test_chat_and_planning(self):
  seen=[]
  def stub(request,timeout):
   seen.append(json.loads(request.data))
   return io.StringIO(json.dumps({'choices':[{'message':{'content':'{"speech":"hi","intents":[],"memory":[]}'}}],'usage':{'prompt_tokens':100,'completion_tokens':10,'prompt_tokens_details':{'cached_tokens':20}}}))
  with patch.dict(os.environ,{'HABITAT_OPENAI_KEY':'stub-not-a-secret'}):
   for message,model in [({'text':'hi','world':{'intent_card':{}}},'gpt-6.1-terra'),({'kind':'autonomy_event','world':{}},'gpt-6.1-terra')]:
    raw,usage=api.complete(message,'persona',opener=stub)
    self.assertEqual(api.parse_reply(raw)['speech'],'hi');self.assertEqual(usage['total_tokens'],110);self.assertIsNone(usage['estimated_usd'])
    self.assertEqual(seen[-1]['model'],model);self.assertEqual(seen[-1]['messages'][0]['role'],'system');self.assertIn('persona',seen[-1]['messages'][0]['content']);self.assertEqual(len(seen[-1]['messages']),2)
 def test_stream_speech_before_intents_and_usage(self):
  class Stream(io.BytesIO):
   headers={'Content-Type':'text/event-stream'}
  raw=json.dumps({'speech':'你好呀','intents':[]},ensure_ascii=False)
  events=[{'choices':[{'delta':{'content':part}}]} for part in [raw[:14],raw[14:18],raw[18:]]]
  events.append({'choices':[],'usage':{'prompt_tokens':100,'completion_tokens':10}})
  data=''.join('data: '+json.dumps(e,ensure_ascii=False)+'\n\n' for e in events)+'data: [DONE]\n\n'
  seen=[]
  with patch.dict(os.environ,{'HABITAT_OPENAI_KEY':'stub'}):
   result,usage=api.complete({'text':'hi'},'persona',opener=lambda *a,**k:Stream(data.encode()),on_speech=seen.append)
  self.assertTrue(seen);self.assertEqual(seen[-1],'你好呀');self.assertEqual(api.parse_reply(result)['intents'],[])
  self.assertEqual(usage['total_tokens'],110);self.assertIsNotNone(usage['first_token_ms'])
 def test_endpoint_and_error_reason(self):
  import urllib.error
  with patch.dict(os.environ,{'HABITAT_OPENAI_BASE_URL':'https://api.example.invalid/v1'}):
   self.assertEqual(api.endpoint(),'https://api.example.invalid/v1')
  for base in ['http://example.com','https://key@example.com','https://example.com/?key=secret']:
   with patch.dict(os.environ,{'HABITAT_OPENAI_BASE_URL':base}):
    with self.assertRaises(ValueError):api.endpoint()
  for status,body,expected in [(403,b'error code: 1010','1010'),(401,b'invalid key','401'),(429,b'insufficient_quota','余额')]:
   error=urllib.error.HTTPError('https://example.com',status,'',{},io.BytesIO(body))
   self.assertIn(expected,api.error_message(error))
 def test_invalid_intents(self):
  for value in ['{}','{"speech":"ok","intents":[1]}','{"speech":"ok","memory":false}']:
   with self.assertRaises(ValueError):api.parse_reply(value)
 def test_missing_key_isolated(self):
  with patch.dict(os.environ,{'HABITAT_OPENAI_KEY':'','HABITAT_DATA_DIR':'/tmp/youqi-stub'}),patch('subprocess.run') as run:
   with self.assertRaisesRegex(ValueError,'missing_key'):api.complete({},'')
   run.assert_not_called()
 def test_context_reject_before_network(self):
  with patch.dict(os.environ,{'HABITAT_OPENAI_KEY':'stub'}):
   with self.assertRaisesRegex(ValueError,'context_too_large'):api.complete({'world':{'x':'a'*49000}},'')
class ProtocolTest(unittest.TestCase):
 def test_ten_real_helper_turns(self):
  code="""
import io,json,sys
import openai_companion as api
def stub(request,timeout):
 body=json.loads(request.data)
 assert body['messages'][0]['role']=='system'
 return io.StringIO(json.dumps({'choices':[{'message':{'content':json.dumps({'speech':'hello','intents':[],'memory':[]})}}],'usage':{'prompt_tokens':100,'completion_tokens':10}}))
api.complete.__defaults__=('gpt-6.1-terra','gpt-6.1-terra',stub,None)
api.main()
"""
  with tempfile.TemporaryDirectory(prefix='youqi-gpt-protocol-') as folder:
   env=dict(os.environ,HABITAT_DATA_DIR=folder,HABITAT_OPENAI_KEY='stub',PYTHONPATH=str(Path(api.__file__).parent))
   child=subprocess.Popen([sys.executable,'-u','-c',code,'--data-dir',folder],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,env=env)
   try:
    self.assertEqual(json.loads(child.stdout.readline())['state'],'ready')
    usage=0
    for i in range(10):
     key='test-'+str(i)
     child.stdin.write(json.dumps({'kind':'chat','text':'hello','world':{},'turn_key':key})+'\n');child.stdin.flush()
     kinds=[]
     for _ in range(4):
      event=json.loads(child.stdout.readline());self.assertEqual(event['turn_key'],key);kinds.append(event['kind'])
      if event['kind']=='usage':usage+=event['total_tokens']
     self.assertEqual(kinds,['state','usage','intent_result','state'])
    self.assertEqual(usage,1100)
    child.stdin.write('{"kind":"shutdown"}\n');child.stdin.flush();self.assertEqual(child.wait(timeout=5),0)
   finally:
    if child.poll() is None:child.terminate();child.wait(timeout=5)
    child.stdin.close();child.stdout.close();child.stderr.close()

if __name__=='__main__':unittest.main()
