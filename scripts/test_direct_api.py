"""Offline loopback server; no credentials or model process needed."""
import json,os,subprocess,sys,threading,time,socket
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from pathlib import Path
requests=[]
class QuietHTTPServer(ThreadingHTTPServer):
 def handle_error(self,*args):pass
class Server(BaseHTTPRequestHandler):
 protocol_version="HTTP/1.1"
 def log_message(self,*args): pass
 def do_GET(self):
  assert self.path=='/v1/models'
  self.send_response(200);self.send_header('Content-Length','11');self.end_headers();self.wfile.write(b'{"data":[]}')
 def do_POST(self):
  assert self.path=='/v1/chat/completions'
  body=self.rfile.read(int(self.headers['Content-Length']));p=json.loads(body);requests.append(p)
  assert self.headers['Authorization']=='Bearer stub-only-key'
  assert 'stub-only-key' not in body.decode()
  assert set(p)=={'model','messages','stream','stream_options','max_tokens'}
  assert len(p['messages'])==2
  assert json.loads(p['messages'][1]['content'])['card']['memory']['about_you'][0]['text']=='我喜欢下雨'
  if p['model']=='disconnect':
   self.close_connection=True;self.connection.shutdown(socket.SHUT_RDWR);self.connection.close();return
  if p['model']=='auth':
   self.send_response(401);self.send_header('Content-Length','34');self.end_headers();self.wfile.write(b'stub-only-key must not be forwarded');return
  if p['model']=='timeout':time.sleep(.5)
  self.send_response(200);self.send_header('Transfer-Encoding','chunked');self.send_header('Content-Type','application/json' if p['model'] in ('plain','leak') else 'text/event-stream');self.end_headers()
  def write(data):
   self.wfile.write(("%x\r\n"%len(data)).encode()+data+b"\r\n");self.wfile.flush()
  try:
   if p['model'] in ('plain','leak'):write(json.dumps({'choices':[{'message':{'content':json.dumps({'speech':('stub-only-key' if p['model']=='leak' else '我去看看。'),'intents':[]})}}],'usage':{'prompt_tokens':20,'completion_tokens':10,'total_tokens':30}}).encode());self.wfile.write(b'0\r\n\r\n');return
   raw=json.dumps({'speech':'你好呀，雨停了，我们去看看柚柚。','intents':[]},ensure_ascii=False)
   for part in [raw[:20],raw[20:]]:
    event=('data: '+json.dumps({'choices':[{'delta':{'content':part}}]},ensure_ascii=False)+'\n\n').encode()
    for i in range(0,len(event),7):write(event[i:i+7])
    time.sleep(.05)
   write(b'data: {"choices":[],"usage":{"prompt_tokens":20,"completion_tokens":10,"total_tokens":30}}\n\ndata: [DONE]\n\n');self.wfile.write(b'0\r\n\r\n')
  except (BrokenPipeError,ConnectionResetError):pass
server=QuietHTTPServer(('127.0.0.1',0),Server);threading.Thread(target=server.serve_forever,daemon=True).start()
env=dict(os.environ,HABITAT_STUB_BASE=f'http://127.0.0.1:{server.server_port}/v1',HABITAT_OPENAI_KEY='',HABITAT_OPENAI_BASE_URL='')
result=subprocess.run([sys.executable,'scripts/portable_godot_checks.py','--script','test_direct_api.gd'],env=env)
server.shutdown()
# Compare exactly the same minimal game card and persona, using an offline opener.
sys.path.insert(0,str(Path('godot/bridge').resolve()))
import openai_companion,io
old_bytes=[]
class Response(io.BytesIO):headers={}
def opener(req,**kwargs):
 old_bytes.append(len(req.data))
 return Response(json.dumps({'choices':[{'message':{'content':'{\"speech\":\"ok\",\"intents\":[]}'}}],'usage':{'prompt_tokens':1,'completion_tokens':1}}).encode())
os.environ['HABITAT_OPENAI_KEY']='stub-only-key'
openai_companion.complete({'text':'你好','world':{'intent_card':{'self':{'id':'codex'},'memory':{'about_you':[{'id':'quote-1','text':'我喜欢下雨'}]}}}},'小白，温柔。',opener=opener)
print('REQUEST_BYTES_SAME_FIXTURE old_bridge='+str(old_bytes[0])+' native='+str(len(json.dumps(requests[0],ensure_ascii=False,separators=(',',':')).encode())))

assert all(p['messages']==requests[0]['messages'] for p in requests[:-1]), 'provider switch changed resident card'
print('STUB_REQUESTS',len(requests),'KEY_SAFE',all('stub-only-key' not in json.dumps(p) for p in requests))
sys.exit(result.returncode)
