"""Rebuild offline estimates from full native instructions + real context + tools."""
import json,sys,math
from pathlib import Path
from test_overnight_prompt import ROOT,measure

def generate():
    context=json.loads((ROOT/'production/evidence/overnight-2026-10-27/prompt-context.json').read_text())
    stats=measure(context)
    escaped=json.dumps(json.dumps(context,ensure_ascii=False,separators=(',',':')),ensure_ascii=False,separators=(',',':'))
    ascii_ctx=sum(ord(c)<128 for c in escaped)
    path=ROOT/'godot/content/autonomy.json';config=json.loads(path.read_text())
    config['failure_limit']=3
    config['estimate']={'base_ascii':stats['ascii_characters']-ascii_ctx,'base_non_ascii':stats['non_ascii_characters']-(len(escaped)-ascii_ctx),'ascii_per_token':4,'non_ascii_per_token':1.5,'protocol_tokens':64,'output_tokens':256,'reference_tokens_per_turn':stats['estimated_tokens_per_turn']}
    path.write_text(json.dumps(config,ensure_ascii=False,indent=2)+'\n')
    simpath=ROOT/'production/evidence/autonomy/ultra-30min.json';sim=json.loads(simpath.read_text())
    contexts_path=ROOT/'production/evidence/overnight-2026-10-27/stage0-ultra-contexts.json'
    if contexts_path.exists():
        run=json.loads(contexts_path.read_text());turns=[measure(item) for item in run['contexts']]
        sim.update(seconds=run['seconds'],advance_frames=run['advance_frames'],wake_count=run['wake_count'],turn_estimates=turns,estimated_tokens_per_turn=math.ceil(sum(t['estimated_tokens_per_turn'] for t in turns)/len(turns)),estimated_total_tokens=sum(t['estimated_tokens_per_turn'] for t in turns),reference_prompt_tokens=stats['estimated_tokens_per_turn'],prompt_measurement=stats)
    else:sim.update(reference_prompt_tokens=stats['estimated_tokens_per_turn'],prompt_measurement=stats)
    simpath.write_text(json.dumps(sim,ensure_ascii=False,indent=2)+'\n')
    (ROOT/'production/evidence/overnight-2026-10-27/prompt-estimate.json').write_text(json.dumps(stats,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(stats,ensure_ascii=False))
if __name__=='__main__':generate()
