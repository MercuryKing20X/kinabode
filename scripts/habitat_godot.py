#!/usr/bin/env python3
"""Local validated game tools for Youqi. No inference or direct save edits."""
import argparse
import re
import json
import math
import os
from pathlib import Path
import sys
import time
import uuid

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"godot/bridge"))
from action_contract import SCHEMA as GAME_ACTION_SCHEMA, command as validate_game_action

DEFAULT_DATA = Path.home() / 'Library/Application Support/Godot/app_userdata/有栖'
QUERY_SCHEMA = {'type': 'object', 'properties': {
    'region_id': {'type': 'string'}, 'object_id': {'type': 'string'},
    'offset': {'type': 'integer', 'minimum': 0},
    'limit': {'type': 'integer', 'minimum': 1, 'maximum': 100},
    'revision': {'type': 'integer', 'minimum': 1}}, 'additionalProperties': False}
TOOL = {'name': 'observe_world', 'description': 'Read the running Youqi world as this connection’s resident. Read-only snapshot; regions, self, residents, zones and paginated objects. Continue pages using snapshot_revision as revision. No model is started. Use act for validated tasks; accepted is not complete.', 'inputSchema': QUERY_SCHEMA, 'annotations': {'readOnlyHint': True, 'idempotentHint': True, 'openWorldHint': False}}

ACTION_SCHEMA = {'type':'object','properties':{'intent':{'type':'string','enum':['move','stop','build_house','pause_project','resume_project','cancel_project','deliver_wood','chop','gather_wood','store','collect','build','forage','barbecue','turn_food','eat','cleanup','select_blueprint','enter','exit','furnish','place_furniture','pickup_furniture','rotate_furniture','sit','take','plant','water','harvest','manage_farm','farm_take','farm_store','farm_meal','decorate_farm','build_facility','use_facility','greet','come_near','dance','watch']},**{key:{'type':'string'} for key in ('farm_id','crop_id','mode','item_id')},'target_id':{'type':'string'},'project_id':{'type':'string'},'zone_id':{'type':'string'},'tree_count':{'type':'integer','minimum':1,'maximum':100},'recipe_id':{'type':'string','enum':['table','chair','chest','rug','lamp']},'facing':{'type':'string','enum':['up','down']},'blueprint_id':{'type':'string'},'region_id':{'type':'string'},'x':{'type':'number'},'y':{'type':'number'}},'required':['intent'],'additionalProperties':False}
TOOLS = [TOOL,
 {'name':'act','description':'Submit a task only as the connection resident. build_facility(target_id) builds using real stored wood; use_facility(target_id) reserves a leisure slot and plays for its configured duration. Assembly rejects actions until the host dismisses it. build_house completes the selected house through one persistent plan, gathering and delivering as needed; pause_project/resume_project/cancel_project use project_id. deliver_wood helps another builder with carried wood. gather_wood continuously harvests and hauls trees in one resource zone (optional target_id, zone_id, tree_count1–100); omit count to continue until stop/full/no targets. chop handles exactly one selected tree. build accepts partial deliveries and constructs only once the next stage is funded. Accepted is not completion. Do not retry an uncertain timeout; observe first.','inputSchema':ACTION_SCHEMA,'annotations':{'readOnlyHint':False,'idempotentHint':False,'openWorldHint':False}},
 {'name':'read_character','description':'Read your own editable artwork frame, palette and revision.','inputSchema':{'type':'object','properties':{'frame':{'type':'string'}},'additionalProperties':False},'annotations':{'readOnlyHint':True}},
 {'name':'edit_character','description':'Apply a limited pixel patch to your own artwork. Requires current revision; user can undo. Does not edit files or other residents.','inputSchema':{'type':'object','properties':{'base_revision':{'type':'integer'},'frame':{'type':'string'},'layer':{'type':'integer','minimum':0},'pixels':{'type':'array','maxItems':1024,'items':{'type':'object','properties':{'x':{'type':'integer'},'y':{'type':'integer'},'color':{'type':'string'}},'required':['x','y','color'],'additionalProperties':False}}},'required':['base_revision','frame','layer','pixels'],'additionalProperties':False},'annotations':{'readOnlyHint':False,'idempotentHint':False}}]

import copy
for original,name in [('read_character','read_work'),('edit_character','edit_work')]:
    tool=copy.deepcopy(next(t for t in TOOLS if t['name']==original))
    tool['name']=name
    tool['description']='Read or apply versioned pixel changes to a shared cottage, cottage-blue, cottage-large, or camp-grill artwork. Structural cost is engine-calculated; existing buildings pin their old version.'
    tool['inputSchema']['properties']['artwork_id']={'type':'string','enum':['cottage','cottage-large','cottage-blue','camp-grill','furniture-table','furniture-chair','furniture-chest','furniture-rug','furniture-lamp','crop-turnip','crop-tomato','crop-pumpkin','crop-daisy','crop-blueberry','crop-apple']}
    tool['inputSchema']['properties']['artwork_id'].pop('enum',None)
    tool['inputSchema'].setdefault('required',[]).append('artwork_id')
    if name=='read_work':
        for key in ['x','y','revision']: tool['inputSchema']['properties'][key]={'type':'integer','minimum':0}
    if name=='edit_work':
        tool['inputSchema']['properties']['structure']={'type':'object','properties':{key:{'type':'integer'} for key in ['width','depth','floors','porch']},'required':['width','depth','floors','porch'],'additionalProperties':False}
        tool['inputSchema']['properties']['recreation']={'type':'object','description':'Complete validated facility config: width, depth, behavior(swing/sit/dance), seconds, entry[x,y], slots[[x,y]], obstacles[[x,y,w,h]], optional swing rigs.'}
        tool['inputSchema']['required']=['artwork_id','base_revision']
    TOOLS.append(tool)

MEMORY_QUERY_SCHEMA = {'type':'object','properties':{
    'kind':{'type':'string','enum':['meal','sat_together','house_completed','shared_barbecue','fishing_catch','gomoku_match','proposal_decision','promise_result','gift','relationship_stage','wish_completed']},
    **{key:{'type':'string','minLength':1,'maxLength':128} for key in ('with_resident','region_id','memory_id','revision')},
    'after':{'type':'number','minimum':0},'before':{'type':'number','minimum':0},
    'offset':{'type':'integer','minimum':0,'maximum':10000},
    'limit':{'type':'integer','minimum':1,'maximum':50}},'additionalProperties':False}
TOOLS.append({'name':'read_memories','description':'Read committed game memories involving this bound resident. Filter kind, with_resident, region_id, inclusive Unix after/before or exact memory_id. Offset pages require returned memory revision; world movement does not invalidate it. A meal credits only eater_id; overlapped_with does not prove others finished eating. No inference or writes.','inputSchema':MEMORY_QUERY_SCHEMA,'annotations':{'readOnlyHint':True,'idempotentHint':True,'openWorldHint':False}})

def validate_memory_query(query):
    if not isinstance(query,dict) or set(query)-set(MEMORY_QUERY_SCHEMA['properties']):
        raise BridgeError('invalid_memory_query')
    for key in ('kind','with_resident','region_id','memory_id','revision'):
        if key in query and (not isinstance(query[key],str) or not 0<len(query[key])<=128):
            raise BridgeError('invalid_memory_query')
    if 'kind' in query and query['kind'] not in MEMORY_QUERY_SCHEMA['properties']['kind']['enum']:
        raise BridgeError('invalid_memory_query')
    for key,low,high in [('offset',0,10000),('limit',1,50)]:
        if key in query and (type(query[key]) is not int or not low<=query[key]<=high):
            raise BridgeError('invalid_memory_query')
    for key in ('after','before'):
        if key in query:
            try:
                valid=type(query[key]) in (int,float) and math.isfinite(query[key]) and query[key]>=0
            except (OverflowError,ValueError,TypeError):
                valid=False
            if not valid: raise BridgeError('invalid_memory_query')
    if 'after' in query and 'before' in query and query['after']>query['before']:
        raise BridgeError('invalid_memory_query')

MAP_QUERY_SCHEMA={'type':'object','properties':{'region_id':{'type':'string','minLength':1,'maxLength':128},'offset':{'type':'integer','minimum':0,'maximum':10000},'limit':{'type':'integer','minimum':1,'maximum':100},'revision':{'type':'string','minLength':1,'maxLength':128}},'additionalProperties':False}
TOOLS.append({'name':'read_map','description':'Read the registered archipelago and island detail as the bound resident. No movement, inference, content import or travel. Omit region_id for a paginated island list; detail includes outline, zones, pack version and availability. Continue offset pages with returned map revision, which stays stable during resident movement.','inputSchema':MAP_QUERY_SCHEMA,'annotations':{'readOnlyHint':True,'idempotentHint':True,'openWorldHint':False}})

def validate_map_query(query):
    if not isinstance(query,dict) or set(query)-set(MAP_QUERY_SCHEMA['properties']):raise BridgeError('invalid_map_query')
    for key in ('region_id','revision'):
        if key in query and (not isinstance(query[key],str) or not 1<=len(query[key])<=128):raise BridgeError('invalid_map_query')
    for key,minimum,maximum in [('offset',0,10000),('limit',1,100)]:
        if key in query and (type(query[key]) is not int or not minimum<=query[key]<=maximum):raise BridgeError('invalid_map_query')

FISH_ACTION_SCHEMA={'type':'object','properties':{'intent':{'type':'string','enum':['fish','stock_fish','release_fish']},'target_id':{'type':'string'},'fish_id':{'type':'string'},'pen_id':{'type':'string'}},'required':['intent'],'additionalProperties':False}
TOOLS.append({'name':'fish_action','description':'Bound-resident fishing action. fish() starts one engine catch at the current natural coast; accepted is not caught. Read observe_world.fishing for real spots, pending fish and fisheries. stock_fish(fish_id,pen_id) directly places your pending catch without movement. release_fish(fish_id) releases your actual fish. No actor override, model polling, free fish or ordinary item transfer.','inputSchema':FISH_ACTION_SCHEMA,'annotations':{'readOnlyHint':False,'idempotentHint':False,'openWorldHint':False}})
def validate_fish_action(args):
    if not isinstance(args,dict) or args.get('intent') not in ('fish','stock_fish','release_fish'):raise BridgeError('invalid_fish_action')
    keys={'fish':{'intent'},'stock_fish':{'intent','fish_id','pen_id'},'release_fish':{'intent','fish_id'}}[args['intent']]
    if set(args)!=keys or any(not isinstance(v,str) or not 1<=len(v)<=128 for v in args.values()):raise BridgeError('invalid_fish_action')

TOOLS.extend([
 {'name':'game_actions','description':'Discover current validated action categories, arguments, availability and identity. Provider-neutral v2; read-only.','inputSchema':{'type':'object','properties':{},'additionalProperties':False},'annotations':{'readOnlyHint':True}},
 {'name':'game_action','description':'Execute a discovered action as this bound resident. fish casts at current natural coast; inland only prompts. Movement can carry your held catch. Engine validates all rules. Accepted is not completed; no automatic polling or uncertain write retries.','inputSchema':dict(GAME_ACTION_SCHEMA,properties=dict(GAME_ACTION_SCHEMA['properties'],dialogue={'type':'object','description':'Exact current identity fields from dialogue_poll.pending; required in external conversation mode.'})),'annotations':{'readOnlyHint':False,'idempotentHint':False}},
 {'name':'dialogue_poll','description':'Read your external-MCP game conversation mailbox and exact scope/session/generation/request identity. No inference or automatic replies.','inputSchema':{'type':'object','properties':{'scope':{'type':'string','enum':['direct','group']}},'additionalProperties':False},'annotations':{'readOnlyHint':True}},
 {'name':'dialogue_reply','description':'Return an actual external AI event using exact identity from dialogue_poll.pending. event kinds assistant/question/action/complete; never fabricate another resident or treat waiting as consent.','inputSchema':{'type':'object','properties':{**{key:{'type':'string'} for key in ('world_id','resident_id','scope','session','request_id','event_id')},'generation':{'type':'integer'},'event':{'type':'object'}},'required':['world_id','resident_id','scope','session','request_id','event_id','generation','event'],'additionalProperties':False},'annotations':{'readOnlyHint':False,'idempotentHint':False}}
])

def persona_card(resident,language='zh',data_dir=None):
    base=Path(__file__).resolve().parents[1]/'godot/content/personas'
    language='en' if language.startswith('en') else 'zh'
    if resident not in ('codex','companion-2','npc.mira','npc.nora'):raise ValueError('unknown_persona')
    cards=[json.loads((base/(name+'.'+language+'.json')).read_text()) for name in ('world',resident)]
    text='\n\n'.join(section for card in cards for section in card['sections'])
    # Godot ConfigFile strings use JSON-compatible quoted escaping.
    directory=Path(data_dir or os.environ.get('HABITAT_DATA_DIR') or DEFAULT_DATA)
    try:
        section=''
        for line in (directory/'persona-overrides.cfg').read_text().splitlines():
            line=line.strip()
            if line.startswith('[') and line.endswith(']'):section=line[1:-1]
            elif section==language and '=' in line:
                key,value=line.split('=',1)
                if key.strip()==resident:
                    override=json.loads(value.strip())
                    if isinstance(override,str):text=override
    except (OSError,ValueError):pass
    return {'persona_id':resident,'language':language,'text':text}
TOOLS.append({'name':'habitat_persona','description':'Read your fixed island persona and world. Use this voice for every reply; outside memories are not island facts. Same editable persona as built-in AI.','inputSchema':{'type':'object','properties':{'language':{'type':'string','enum':['zh','en']}},'additionalProperties':False},'annotations':{'readOnlyHint':True}})

class BridgeError(Exception):
    pass

class Reader:
    def __init__(self, data_dir=None, resident='codex', timeout=5, expected_world=None):
        self.directory = Path(data_dir or os.environ.get('HABITAT_DATA_DIR') or DEFAULT_DATA) / 'read-api'
        self.resident = resident
        self.persona_language='zh'
        try:
            language_file=(self.directory.parent/'language.cfg').read_text()
            if re.search(r'language\s*=\s*"en"',language_file):self.persona_language='en'
        except OSError:pass
        self.timeout = timeout
        self.expected_world=expected_world
        if not isinstance(timeout, (int, float)) or not math.isfinite(timeout) or timeout <= 0:
            raise ValueError('invalid timeout')

    def observe(self, query=None):
        query = {} if query is None else query
        if not isinstance(query, dict) or set(query) - set(QUERY_SCHEMA['properties']):
            raise BridgeError('invalid_query')
        for key in ('offset', 'limit', 'revision'):
            if key in query and type(query[key]) is not int:
                raise BridgeError('invalid_query')
        for key in ('region_id', 'object_id'):
            if key in query and not isinstance(query[key], str):
                raise BridgeError('invalid_query')
        return self.request("observe", query)

    def request(self, operation, query=None):
        if operation == 'read_map': validate_map_query({} if query is None else query)
        if operation == 'read_memories': validate_memory_query({} if query is None else query)
        if operation not in ("observe", "read_actions", "dialogue_poll", "dialogue_reply", "read_map", "read_memories", "act", "read_character", "edit_character", "read_work", "edit_work", "read_conversation", "reply_conversation") or (query is not None and not isinstance(query, dict)):
            raise BridgeError("invalid_request")
        query = query or {}
        try:
            status = json.loads((self.directory / 'heartbeat.json').read_text())
            if self.expected_world and status.get('world_id')!=self.expected_world:raise BridgeError('world_binding_changed')
            age = time.time() - status['updated']
            if not math.isfinite(age) or age < -5 or age > 5:
                raise ValueError()
            token = json.loads((self.directory / 'connections.json').read_text())[self.resident]
        except (OSError, ValueError, KeyError, TypeError):
            raise BridgeError('game_unavailable_or_resident_not_provisioned') from None
        request_id = uuid.uuid4().hex
        request = {'operation': operation, 'request_id': request_id, 'session': status['session'], 'token': token,
                   'expires': time.time() + self.timeout, 'query': query}
        pending = self.directory / 'inbox' / (request_id + '.json')
        temp = pending.with_suffix('.tmp')
        response = self.directory / 'outbox' / pending.name
        try:
            temp.write_text(json.dumps(request, ensure_ascii=False, allow_nan=False))
            temp.chmod(0o600)
            temp.replace(pending)
            deadline = time.monotonic() + self.timeout
            while time.monotonic() < deadline:
                if response.exists():
                    value = json.loads(response.read_text())
                    return value
                time.sleep(0.025)
            raise BridgeError('read_timeout' if operation in ('observe','read_actions','dialogue_poll','read_map','read_memories','read_character','read_conversation') else 'action_timeout_observe_before_retry')
        except OSError as error:
            raise BridgeError('transport_unavailable') from error
        finally:
            for path in (temp, pending, response):
                path.unlink(missing_ok=True)

    def handle(self, message):
        request_id = message.get('id')
        method = message.get('method')
        if request_id is None:
            return None
        if method == 'initialize':
            requested = message.get('params', {}).get('protocolVersion', '2024-11-05')
            result = {'protocolVersion': requested, 'capabilities': {'tools': {'listChanged': False}},
                      'serverInfo': {'name': 'youqi-world-reader', 'version': '0.1.0'},
                      'instructions': persona_card(self.resident,self.persona_language,self.directory.parent)['text']}
        elif method == 'ping':
            result = {}
        elif method == 'tools/list':
            result = {'tools': TOOLS}
        elif method == 'tools/call':
            params = message.get('params', {})
            try:
                name = params.get('name')
                args = params.get('arguments', {})
                if name == 'habitat_persona':
                    if not isinstance(args,dict) or set(args)-{'language'} or args.get('language','zh') not in ('zh','en'):raise BridgeError('invalid_persona_query')
                    value=dict(ok=True,**persona_card(self.resident,args.get('language',self.persona_language),self.directory.parent))
                elif name == 'observe_world':
                    value = self.observe(args)
                    if value.get('ok',False):value['persona']=persona_card(self.resident,self.persona_language,self.directory.parent)
                elif name == 'game_actions':
                    if args!={}:raise BridgeError('invalid_action_query')
                    value=self.request('read_actions',{})
                elif name == 'game_action':
                    try:command=validate_game_action({k:v for k,v in args.items() if k!='dialogue'})
                    except (ValueError,TypeError,AttributeError):raise BridgeError('invalid_game_action')
                    if 'dialogue' in args:
                        identity=args['dialogue']
                        if not isinstance(identity,dict) or set(identity)!={'world_id','resident_id','scope','session','generation','request_id'}:raise BridgeError('invalid_dialogue_identity')
                        result=self.request('dialogue_reply',dict(identity,event_id=uuid.uuid4().hex,event={'kind':'action','command':command}))
                        value=result.get('result',{}) if result.get('ok') else result
                    else:value=self.request('act',command)
                elif name in ('dialogue_poll','dialogue_reply'):
                    if not isinstance(args,dict):raise BridgeError('invalid_dialogue_query')
                    if name=='dialogue_poll' and (set(args)-{'scope'} or args.get('scope','direct') not in ('direct','group')):raise BridgeError('invalid_dialogue_query')
                    if name=='dialogue_reply':
                        required={'world_id','resident_id','scope','session','generation','request_id','event_id','event'}
                        if set(args)!=required or type(args['generation']) is not int or not isinstance(args['event'],dict):raise BridgeError('invalid_dialogue_reply')
                    value=self.request(name,args)
                elif name == 'fish_action':
                    validate_fish_action(args)
                    value = self.request('act',args)
                elif name == 'read_map':
                    validate_map_query(args)
                    value = self.request(name,args)
                elif name == 'read_memories':
                    validate_memory_query(args)
                    value = self.request(name,args)
                elif name in ('act','read_character','edit_character','read_work','edit_work'):
                    value = self.request(name, args)
                else:
                    value = {'ok':False,'error':'unsupported_tool'}
            except BridgeError as error:
                value = {'ok':False,'error':str(error)}
            result = {'content': [{'type': 'text', 'text': json.dumps(value, ensure_ascii=False)}], 'isError': not value.get('ok', False)}
        else:
            return {'jsonrpc': '2.0', 'id': request_id, 'error': {'code': -32601, 'message': 'Method not found'}}
        return {'jsonrpc': '2.0', 'id': request_id, 'result': result}

def main():
    parser = argparse.ArgumentParser(description='有栖世界读取：无模型调用')
    parser.add_argument('--data-dir')
    parser.add_argument('--world',help='Expected world ID from the host connection configuration')
    parser.add_argument('--resident', default='codex', help='Host-selected resident; must already exist in the running game')
    parser.add_argument('operation', choices=['observe', 'read_actions', 'dialogue_poll', 'dialogue_reply', 'read_map', 'read_memories', 'mcp', 'act', 'read_character', 'edit_character', 'read_work', 'edit_work'])
    parser.add_argument('--json', dest='payload', help='JSON action or artwork arguments')
    parser.add_argument('--region')
    parser.add_argument('--object', dest='object_id')
    parser.add_argument('--limit', type=int)
    parser.add_argument('--offset', type=int)
    parser.add_argument('--revision', type=int)
    args = parser.parse_args()
    reader = Reader(args.data_dir, args.resident,expected_world=args.world)
    if args.operation == 'mcp':
        for line in sys.stdin:
            try:
                message = json.loads(line)
                if not isinstance(message, dict): raise ValueError()
                result = reader.handle(message)
            except (ValueError, TypeError, AttributeError):
                result = {'jsonrpc': '2.0', 'id': None, 'error': {'code': -32700, 'message': 'Invalid JSON-RPC message'}}
            if result is not None:
                print(json.dumps(result, ensure_ascii=False), flush=True)
        return 0
    query = {key: value for key, value in {'region_id': args.region, 'object_id': args.object_id, 'limit': args.limit, 'offset': args.offset, 'revision': args.revision}.items() if value is not None}
    try:
        result = reader.observe(query) if args.operation == "observe" else reader.request(args.operation, json.loads(args.payload or "{}"))
    except BridgeError as error:
        result = {'ok': False, 'error': str(error)}
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result.get('ok') else 1

if __name__ == '__main__':
    raise SystemExit(main())
