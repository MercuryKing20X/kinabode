"""Offline replay only: full native instructions/tools plus 120 legal board prefixes."""
import json,math,sys
from pathlib import Path
from test_overnight_prompt import measure,ROOT

def tokens(text):
    ascii_count=sum(ord(c)<128 for c in text)
    return math.ceil(ascii_count/4+(len(text)-ascii_count)/1.5)

def generate(directory):
    base=json.loads((directory/'ai-context.json').read_text())
    black=base['chess']['black_id'];white=base['chess']['white_id']
    blacks=[];whites=[]
    for y in range(15):
        for x in range(15):(blacks if (x+2*y)%4<2 else whites).append([x,y])
    moves=[(blacks if i%2==0 else whites).pop(0) for i in range(225)]
    previous={black:0,white:0};rows=[]
    for index in range(120):
        context=json.loads(json.dumps(base));actor=black if index%2==0 else white
        context['resident_id']=actor;context['self']['id']=actor
        context['self']['name']=actor # Stable test identity, not provider or hardcoded engine roster.
        context['chess'].update(history=moves[:index],revision=index+3,turn_actor_id=actor,phase='playing',winning_line=[])
        context['chess']['ai'].update(tokens=index*100,unknown_tokens=0,reserved_tokens=12000)
        # Hypothetical fake-adapter remarks consistent with each offline prefix.
        context['match_dialogue']=[{'actor_id':black if n%2==0 else white,'text':'我把棋子落在这里。','source':'model','hand':n+1} for n in range(max(0,index-3),index)]
        board=[0]*225
        for n,(x,y) in enumerate(moves[:index]):board[y*15+x]=1+n%2
        context['chess']['board']=board
        encoded=json.dumps(context,ensure_ascii=False,separators=(',',':'))
        if len(encoded.encode())>4096:raise ValueError('context exceeds4KB')
        stats=measure(context)
        row={'step':index+1,'resident_id':actor,'context_bytes':len(encoded.encode()),**stats}
        row['estimated_with_retained_match_history']=stats['estimated_tokens_per_turn']+previous[actor]
        rows.append(row)
        # Explicit history assumption, not a provider bill or claim of played120 moves.
        receipt={'event_context':context,'game_action':{'action':'gomoku_move','arguments':dict(site_id=context['chess']['site_id'],match_id=context['chess']['id'],revision=index+3,x=moves[index][0],y=moves[index][1],speech='我把棋子落在这里。')},'result':{'ok':True,'status':'completed','revision':index+4},'assistant':'这一手完成，等下一手。'}
        previous[actor]+=tokens(json.dumps(receipt,ensure_ascii=False,separators=(',',':')))
    result={'real_model_calls':0,'steps':120,'moves_are':'Offline legal replay prefixes of the existing full-board draw test; not a claim that models played120 turns.','method':'Full INSTRUCTIONS + actual driver developerInstructions + unchanged native tools + actual v2 tools + current input. ASCII/4 + non-ASCII/1.5 +64 protocol +256 output.','existing_thread_history':'NOT INCLUDED: conversations preceding this match, hidden reasoning, caching/compaction and actual provider tokenizer.','retained_history_assumption':'Each player retains its own preceding game-event context/tool call/receipt/short response, uncached; estimate, not measured usage.','estimated_isolated_turn_total':sum(row['estimated_tokens_per_turn'] for row in rows),'estimated_retained_match_history_total':sum(row['estimated_with_retained_match_history'] for row in rows),'estimated_mean_isolated_turn':math.ceil(sum(row['estimated_tokens_per_turn'] for row in rows)/120),'maximum_context_bytes':max(row['context_bytes'] for row in rows),'per_confirmation_budget':json.loads((ROOT/'godot/content/gomoku-match.json').read_text()),'rounds':rows}
    (directory/'model-vs-model-120-estimate.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k!='rounds'},ensure_ascii=False,indent=2))
if __name__=='__main__':generate(ROOT/'production/evidence/gomoku-companion-2026-10-27')
