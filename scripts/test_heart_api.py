"""Native loopback-only heart protocol including a real 90-second response."""
import json,os,subprocess,sys,threading,time,socket
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
requests=[]
class Server(BaseHTTPRequestHandler):
 protocol_version="HTTP/1.1"
 def log_message(self,*args):pass
 def do_POST(self):
  p=json.loads(self.rfile.read(int(self.headers['Content-Length'])));requests.append(p)
  assert self.headers['Authorization']=='Bearer stub-heart-key'
  model=p['model'];card=json.loads(p['messages'][1]['content'])['card']['heart_request']
  if model=='disconnect':self.connection.shutdown(socket.SHUT_RDWR);self.connection.close();return
  if model=='slow':time.sleep(90)
  ready=[v['activity'] for v in card['available'] if v['ready']]
  activity='daydream' if 'daydream' in ready else ready[0]
  result={'activity':('invented_free_money' if model=='outside' else activity),'minutes':1,'reason':'I want a quiet look at the island.','say':'A little quiet by the sea.','mood':{'joy':5}}
  raw='broken json' if model=='bad' else json.dumps(result)
  data=json.dumps({'choices':[{'message':{'content':raw}}],'usage':{'prompt_tokens':500,'completion_tokens':50,'total_tokens':550}}).encode()
  self.send_response(200);self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)
server=ThreadingHTTPServer(('127.0.0.1',0),Server);threading.Thread(target=server.serve_forever,daemon=True).start()
env=dict(os.environ,HABITAT_STUB_BASE=f'http://127.0.0.1:{server.server_port}/v1',HABITAT_OPENAI_KEY='',HABITAT_OPENAI_BASE_URL='')
result=subprocess.run([sys.executable,'scripts/portable_godot_checks.py','--script','test_heart_api.gd'],env=env)
server.shutdown()
print('HEART_REQUESTS',len(requests),'MAX_REQUEST_UTF8',max([len(json.dumps(p,ensure_ascii=False).encode()) for p in requests],default=0))
sys.exit(result.returncode)
