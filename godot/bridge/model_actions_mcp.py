#!/usr/bin/env python3
"""Native-session MCP extension; every call passes through its owning turn bridge."""
import argparse,json,os,re,sys,time,uuid
from pathlib import Path
from action_contract import SCHEMA

def tools():
    from copy import deepcopy
    schema=deepcopy(SCHEMA);schema['properties']['turn_token']={'type':'string'};schema['required'].append('turn_token')
    return [{'name':'game_actions','description':'Discover live game actions. Use action_turn_token from this turn snapshot. Read-only; identity is bound to this resident and scope.','inputSchema':{'type':'object','properties':{'turn_token':{'type':'string'}},'required':['turn_token'],'additionalProperties':False}},
            {'name':'game_action','description':'Execute a discovered game action as your bound resident. fish casts at the current natural coast, never walks to a fishery; inland rejects. move can carry the actual held catch; stock_fish directly places it. island_propose suggests only an existing template in your own territory; reason must exactly match an offered true memory summary. It creates a host confirmation card, never starts work. Engine checks permissions/jobs. Accepted is not complete; no polling or retry of uncertain writes.','inputSchema':schema}]

def exchange(directory,name,args):
    key=uuid.uuid4().hex;inbox=directory/'inbox';outbox=directory/'outbox';path=inbox/(key+'.json');reply=outbox/path.name
    if not inbox.is_dir():return {'ok':False,'error':'game_model_bridge_unavailable'}
    payload={'id':key,'tool':name,'arguments':args,'expires':time.time()+18}
    temp=path.with_suffix('.tmp')
    try:
        temp.write_text(json.dumps(payload,allow_nan=False));temp.chmod(0o600);temp.replace(path)
        deadline=time.monotonic()+20
        while time.monotonic()<deadline:
            if reply.exists():return json.loads(reply.read_text())
            time.sleep(.025)
        return {'ok':False,'error':'action_timeout_observe_before_retry' if name=='game_action' else 'read_timeout'}
    finally:
        for item in (temp,path,reply):item.unlink(missing_ok=True)

def handle(message,directory):
    if 'id' not in message:return None
    method=message.get('method');params=message.get('params',{});request_id=message['id']
    if method=='initialize':result={'protocolVersion':params.get('protocolVersion','2024-11-05'),'capabilities':{'tools':{}},'serverInfo':{'name':'youqi-native-actions','version':'2'}}
    elif method=='ping':result={}
    elif method=='tools/list':result={'tools':tools()}
    elif method=='tools/call':
        if params.get('name') not in ('game_actions','game_action') or not isinstance(params.get('arguments',{}),dict):value={'ok':False,'error':'invalid_action_tool'}
        else:value=exchange(directory,params['name'],params.get('arguments',{}))
        result={'content':[{'type':'text','text':json.dumps(value,ensure_ascii=False)}],'isError':not value.get('ok',False)}
    else:return {'jsonrpc':'2.0','id':request_id,'error':{'code':-32601,'message':'Method not found'}}
    return {'jsonrpc':'2.0','id':request_id,'result':result}
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--directory',required=True);args=parser.parse_args()
    for line in sys.stdin:
        try:
            value=json.loads(line);response=handle(value,Path(args.directory))
        except (ValueError,TypeError,AttributeError,OSError):response={'jsonrpc':'2.0','id':None,'error':{'code':-32700,'message':'Invalid request'}}
        if response is not None:print(json.dumps(response,ensure_ascii=False),flush=True)
