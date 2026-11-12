"""Opt-in real-driver instrumentation for the isolated 2026-10-27 validation."""
import json,os,sys,time
from pathlib import Path
import companion

def clean(value):
    if isinstance(value,dict):return {k:('<redacted turn token>' if k in ('turn_token','action_turn_token') else clean(v)) for k,v in value.items()}
    if isinstance(value,list):return [clean(v) for v in value]
    return value

def record(kind,value):
    path=os.environ.get('HABITAT_LIVE_TRACE_PATH')
    if path:
        with open(path,'a',encoding='utf-8') as stream:stream.write(json.dumps({'at':time.time(),'kind':kind,'data':clean(value)},ensure_ascii=False)+'\n')

Base=companion.Companion
class Probe(Base):
    def request(self,method,params):
        if method=='turn/start':record('turn_start',{'turn_key':self.turn_key,'turn_kind':self.turn_kind,'params':params})
        return super().request(method,params)
    def server_request(self,message):
        if message.get('method')=='item/tool/call':record('native_tool_call',dict(message,turn_key=self.turn_key,turn_kind=self.turn_kind))
        return super().server_request(message)
    def server(self,message):
        item=message.get('params',{}).get('item',{})
        if item.get('type') in ('mcpToolCall','dynamicToolCall'):record('model_tool_item',dict(message,turn_key=self.turn_key,turn_kind=self.turn_kind))
        return super().server(message)
    def respond_tool(self,key,result,success):
        record('tool_result',{'request_id':key,'result':result,'success':success,'turn_key':self.turn_key,'turn_kind':self.turn_kind})
        return super().respond_tool(key,result,success)

if __name__=='__main__':
    if os.environ.get('HABITAT_LIVE_TEST')!='1' or 'habitat-live-test-' not in os.environ.get('HABITAT_DATA_DIR',''):raise SystemExit('Isolated explicit live opt-in required')
    companion.Companion=Probe
    sys.exit(companion.main())
