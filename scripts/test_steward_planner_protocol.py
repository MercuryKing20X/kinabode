"""Steward's exact transport envelopes, offline. No bridge/model process is started."""
import json, sys, tempfile
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'godot/bridge'))
from intent_companion import Companion

def run():
 with tempfile.TemporaryDirectory(prefix='youqi-steward-protocol-') as directory:
  calls=[];events=[]
  c=Companion(directory,events.append,calls.append)
  c.persona='温柔，喜欢和大家商量。'
  card={'steward_request':{'reply_format':'speech/preference/reason; no actions'},'candidates':[{'id':'food:single:mushroom','text':'烤蘑菇'},{'id':'game:eagle','text':'老鹰捉小鸡'}]}
  message={'kind':'chat','text':'Choose one candidate.','world':{'intent_card':card},'level':'ultra','turn_key':'test-steward'}
  c.ready=True;c.thread_id='private-chat';c.rounds=80
  c.client(message)
  thread=calls[-1];assert thread['method']=='thread/start' and 'threadId' not in thread['params']
  assert 'move anyone' in thread['params']['baseInstructions']
  c.ready=True;c.thread_id='planner-stub'
  c.client(c.queued_chat)
  turn=calls[-1];assert turn['method']=='turn/start' and turn['params']['effort']=='low'
  profile=next(e for e in events if e['kind']=='steward_input_profile')
  envelope={'thread':c.thread_params(),'turn':turn['params'],'tools':[]}
  exact=len(json.dumps(envelope,ensure_ascii=False,separators=(',',':')).encode())
  assert profile['complete_request_utf8_bytes']==exact and exact<=5000
  oversized=json.loads(json.dumps(message))
  oversized['level']='low'
  oversized['world']['intent_card']['memory_sources']=[{'text':'近况'*3000}]
  c.active=False;c.ready=True
  c.client(oversized)
  if calls[-1]['method']=='thread/start':
   c.ready=True;c.thread_id='oversize-stub';c.client(c.queued_chat)
  assert calls[-1]['method']=='turn/start'
  assert [e for e in events if e['kind']=='steward_input_profile'][-1]['complete_request_utf8_bytes']<=4600
  c.emit_event({'kind':'assistant','text':'{"speech":"我想烤蘑菇。","preference":"food:single:mushroom","reason":"材料够","intents":[],"memory":[]}'})
  assert events[-1]['kind']=='intent_result' and events[-1]['preference']=='food:single:mushroom'
  c.save_thread();assert not c.state_path.exists()
  print(json.dumps({'complete_request_utf8_bytes':exact,'token_upper_bound':exact,'effort':turn['params']['effort'],'fresh_thread':True,'private_binding_unchanged':True},ensure_ascii=False))
def openai_run():
 import os,io
 import openai_companion as bridge
 with tempfile.TemporaryDirectory(prefix='youqi-steward-http-stub-') as directory:
  os.environ['HABITAT_DATA_DIR']=directory
  os.environ['HABITAT_OPENAI_KEY']='offline-placeholder'
  sent=[]
  class Response(io.StringIO):
   headers={'Content-Type':'application/json'}
  def opener(request,timeout):
   sent.append(json.loads(request.data))
   return Response(json.dumps({'choices':[{'message':{'content':'{"speech":"好呀","preference":"game:eagle","intents":[],"memory":[]}'}}],'usage':{'prompt_tokens':0,'completion_tokens':0}}))
  message={'kind':'chat','level':'ultra','text':'Choose a candidate.','world':{'intent_card':{'steward_request':{},'candidates':[{'id':'game:eagle','text':'老鹰捉小鸡'}]}}}
  message['world']['intent_card']['steward_request']={'reply_format':'speech/preference/reason'}
  raw,_=bridge.complete(message,'温柔的总管',chat='stub-chat',thinking='stub-deep',opener=opener)
  assert sent[0]['model']=='stub-chat' and sent[0]['reasoning_effort']=='low'
  exact=len(json.dumps(sent[0],ensure_ascii=False,separators=(',',':')).encode())
  assert exact<=5000 and bridge.parse_reply(raw)['preference']=='game:eagle'
  print(json.dumps({'openai_complete_request_utf8_bytes':exact,'token_upper_bound':exact,'effort':'low','real_http_requests':0}))
if __name__=='__main__':run();openai_run()
