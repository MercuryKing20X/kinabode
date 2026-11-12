"""Provider-neutral actions. Only the engine grants capability or commits work."""
import math
VERSION=2
ACTIONS={'fish':set(),'stock_fish':{'fish_id','pen_id'},'release_fish':{'fish_id'},'move':{'region_id','x','y'},'stop':set(),'gesture':{'gesture'}}
ACTIONS.update(gomoku_read={'site_id'},gomoku_join={'site_id','match_id','revision'},gomoku_move={'site_id','match_id','revision','x','y','speech'},gomoku_leave={'site_id','match_id','revision'},gomoku_resign={'site_id','match_id','revision'})
ACTIONS.update(give={'receiver_id','item_id','quantity'})
ACTIONS.update(promise={'action_type','target_id','day','phase','valid_seconds'},promise_cancel={'promise_id'})
ACTIONS.update(resident_plan={'steps'})
ACTIONS.update(island_propose={'template_id','x','y','name','reason'})
ACTIONS.update(propose={'text','activity','target_id','ttl_seconds'})
ACTIONS.update(journal_read={'species_id','color_id','size_id','status','offset','limit','revision'})
ACTIONS.update(homestead_read=set(),homestead_start={'site_id','wood_limit','crop_limit'},homestead_resume={'plan_id','wood_limit','crop_limit'},homestead_build={'plan_id'},homestead_cancel={'plan_id'})
ACTIONS.update(invite_barbecue=set(),start_project=set(),open_chess=set())
ACTIONS.update(plant={'target_id','crop_id'},harvest={'target_id'},water={'target_id'},chop={'target_id'},gather={'target_id'},follow=set(),unfollow=set(),go_to={'region_id','x','y'},gather_at={'region_id','x','y'},hand_over=set(),query_state=set())
DELEGATABLE={'plant','harvest','water','chop','gather','fish','follow','unfollow','go_to','gather_at','hand_over','invite_barbecue','start_project','open_chess','stop','query_state'}
for name in DELEGATABLE:ACTIONS[name].add('actor_ids')
SCHEMA={'type':'object','properties':{'action':{'type':'string','enum':list(ACTIONS)},'arguments':{'type':'object'}},'required':['action'],'additionalProperties':False}
def validate_intention(step, nested=False):
    allowed={'action','text','target_id','item_id','crop_id','x','y','region_id','guest_ids','replace','actor_ids','assignments'}
    kinds={'assemble','fish','light','roast','invite','plant','harvest','water','chop','gather','build','chess','go_to','wander','sit','lounge','pool','swing','hold_cat','pet_cat','stars','home','follow','unfollow','hand_over','stop'}
    if not isinstance(step,dict) or set(step)-allowed or step.get('action') not in kinds:raise ValueError('invalid_intention')
    for field,value in step.items():
        if field in ('guest_ids','actor_ids'):
            if not isinstance(value,list) or not 1<=len(value)<=32 or any(not isinstance(v,str) or v=='human' or not v or len(v)>128 for v in value) or len(set(value))!=len(value):raise ValueError('invalid_participant')
        elif field=='assignments':
            if nested or not isinstance(value,list) or not 1<=len(value)<=4:raise ValueError('invalid_assignments')
            for assignment in value:validate_intention(assignment,True)
        elif field in ('x','y'):
            if type(value) not in (int,float) or not math.isfinite(value):raise ValueError('invalid_coordinates')
        elif field=='replace':
            if type(value) is not bool:raise ValueError('invalid_intention')
        elif not isinstance(value,str) or len(value)>400:raise ValueError('invalid_intention')
def command(value):
    if not isinstance(value,dict) or set(value)-{'action','arguments'} or not isinstance(value.get('action'),str) or value['action'] not in ACTIONS:raise ValueError('invalid_game_action')
    action=value['action'];args=value.get('arguments',{})
    if not isinstance(args,dict) or set(args)-ACTIONS[action]:raise ValueError('invalid_action_arguments')
    required=set() if action=='journal_read' else ACTIONS[action]-({'region_id'} if action in ('move','go_to','gather_at') else set())
    if action in ('homestead_start','homestead_resume'):required-= {'wood_limit','crop_limit'}
    if action=='gomoku_move':required.discard('speech')
    if action=='propose':required.discard('ttl_seconds')
    if action=='promise':required.discard('valid_seconds')
    required.discard('actor_ids')
    if 'actor_ids' in args:required=set()
    if required-set(args):raise ValueError('missing_action_arguments')
    for key,item in args.items():
        if action=='resident_plan' and key=='steps':
            if not isinstance(item,list) or not 1<=len(item)<=5:raise ValueError('invalid_intent_count')
            for step in item:validate_intention(step)
        elif key=='actor_ids':
            if not isinstance(item,list) or not 1<=len(item)<=32 or any(not isinstance(v,str) or not v or len(v)>128 or v=='human' for v in item) or len(set(item))!=len(item):raise ValueError('invalid_actor_ids')
        elif action=='island_propose' and key in ('name','reason'):
            if not isinstance(item,str) or not item.strip() or len(item)>(40 if key=='name' else 128) or '\n' in item or '\r' in item:raise ValueError('invalid_island_text')
        elif action=='gomoku_move' and key=='speech':
            if not isinstance(item,str) or len(item)>30 or '\n' in item or '\r' in item:raise ValueError('invalid_chess_speech')
        elif action=='give' and key=='quantity':
            if type(item) not in (int,float) or not math.isfinite(item) or item!=int(item) or item<1:raise ValueError('invalid_gift_quantity')
        elif action=='promise' and key in ('day','valid_seconds'):
            if type(item) not in (int,float) or not math.isfinite(item) or item!=int(item) or not 1<=item<1000000:raise ValueError('invalid_promise_date')
        elif action=='propose' and key=='ttl_seconds':
            if type(item) not in (int,float) or not math.isfinite(item) or item!=int(item) or not 1<=item<=600:raise ValueError('invalid_proposal_expiry')
        elif action.startswith('homestead_') and key in ('wood_limit','crop_limit'):
            if type(item) not in (int,float) or not math.isfinite(item) or item!=int(item) or not 0<=item<=1000:raise ValueError('invalid_material_limit')
        elif action=='journal_read' and key in ('offset','limit'):
            if type(item) not in (int,float) or not math.isfinite(item) or item!=int(item) or not (0<=item<=4096 if key=='offset' else 1<=item<=32):raise ValueError('invalid_journal_page')
        elif action=='journal_read' and key=='revision':
            if not isinstance(item,str) or len(item)!=64 or any(c not in '0123456789abcdef' for c in item):raise ValueError('invalid_journal_revision')
        elif key=='revision' or (action=='gomoku_move' and key in ('x','y')):
            if type(item) not in (int,float) or not math.isfinite(item) or item!=int(item) or not (1<=item<=1000000 if key=='revision' else 0<=item<=14):raise ValueError('invalid_chess_turn')
        elif key in ('x','y'):
            if type(item) not in (int,float) or not math.isfinite(item):raise ValueError('invalid_coordinates')
        elif not isinstance(item,str) or not 1<=len(item)<=128:raise ValueError('invalid_action_arguments')
    if action=='gesture' and args.get('gesture') not in ('wave','stretch'):raise ValueError('invalid_gesture')
    if action=='journal_read' and args.get('status','all') not in ('all','caught'):raise ValueError('invalid_journal_filter')
    return dict(args,intent={'go_to':'move'}.get(action,action))
