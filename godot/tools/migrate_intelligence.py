"""One-shot authored content migration; never reads player data."""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
CONTENT=ROOT/'godot/content'; DEST=CONTENT/'intelligence'
def save(path,data):
 path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
old=json.loads((CONTENT/'personalities.json').read_text())
people=json.loads((CONTENT/'residents.json').read_text())['residents']
meta={k:v for k,v in old.items() if k!='traits'};meta['profiles']={}
for tag,profile in old['traits'].items():
 refs=[]
 for context,lines in profile['lines'].items():
  uid=f'{tag}-{context}';refs.append(uid);save(DEST/'units/speech'/f'{uid}.json',dict(id=uid,context=context,lines=lines,autonomy_output=False))
 meta['profiles'][tag]={k:v for k,v in profile.items() if k!='lines'};meta['profiles'][tag]['speech_units']=refs
 save(DEST/'traits'/f'{tag}.json',dict(id=tag,name=profile['name'],description='从原性格逐字迁移。',speech_units=refs,behavior_units=[],speech_multiplier=profile.get('idle_speech_scale',1),hunger_multiplier=dict(gentle=1,curious=1,lively=1.2,quiet=.9)[tag],activation=None,weights=profile['weights'],wish_weights=profile['wish_weights'],schedule_weights=profile['schedule_weights']))
for action in ['nearby','wander','rest','facility','garden','watch','stretch','look','flower_gift']:
 save(DEST/'units/behavior'/f'idle-{action.replace("_","-")}.json',dict(id=f'idle-{action.replace("_","-")}',action=action,conditions={},cooldown_seconds=0,requires_target=action in ['facility','garden','rest','flower_gift']))
for path in (DEST/'traits').glob('*.json'):
 d=json.loads(path.read_text())
 if d['id'] in old['traits']:d['behavior_units']=['idle-'+k.replace('_','-') for k in old['traits'][d['id']]['weights']];save(path,d)
# New packages remain inactive during the equivalence migration.
extra={'laborious':('爱劳动','lively',None,1.0),'serious':('严肃','quiet',{'interaction_age_at_least':1200},.85),'clingy':('黏人','gentle',{'player_idle':True},1.0),'slow-warm':('慢热','quiet',{'relationship_below':'familiar'},1.0),'introvert':('内敛','quiet',{'nearby_count_at_least':3},.9),'night-owl':('夜猫子','quiet',{'phases':['night']},.9),'curious-context':('好奇','curious',{'player_actions':['fish','forage']},1.0),'glutton-minor':('吃货副','gentle',{'hunger_at_least':'hungry'},1.8)}
for tag,(name,base,activation,mult) in extra.items():
 d=json.loads((DEST/'traits'/f'{base}.json').read_text());d.update(id=tag,name=name,description='本轮情境性格包。',activation=activation,hunger_multiplier=mult);save(DEST/'traits'/f'{tag}.json',d)
# Existing glutton demo becomes the real context package; author only new lines.
save(DEST/'units/speech/glutton-hungry.json',dict(id='glutton-hungry',context='hungry',lines=['有点想吃热乎乎的东西了。','肚子好像在提醒我啦。','等开饭的时候，我就在旁边。','闻到饭香就想过去看看。'],autonomy_output=False))
g=json.loads((DEST/'traits/gentle.json').read_text());g.update(id='glutton',name='吃货',description='饿时更惦记真实的饭。',activation={'hunger_at_least':'hungry'},hunger_multiplier=1.8,speech_units=['glutton-hungry'],weights={'facility':1.4,'nearby':1.5});save(DEST/'traits/glutton.json',g)
rows={'codex':('white','智能小白','gentle',['curious-context','slow-warm']),'companion-2':('blue','智能小蓝','lively',['glutton','clingy']),'npc.mira':('orange','智能小橙','laborious',['serious','glutton-minor']),'npc.nora':('black','智能阿黑','quiet',['introvert','night-owl'])}
bindings={}
for person in people:
 if person['id'] not in rows:continue
 short,name,main,contexts=rows[person['id']];pid='resident-'+short
 preset=dict(id=pid,name=name,main_trait=main,context_traits=contexts,speech_style='根据真实状态，简短自然地说话。',mode='model' if person.get('controller')=='model' else 'local')
 if preset['mode']=='model':preset['autonomy_level']='low'
 save(DEST/'presets'/f'{pid}.json',preset)
 bindings[person['id']]={'preset_id':pid,'legacy_tag':person['preferences']['personality'],'preferences':person['preferences'],'hunger_enabled':True}
save(DEST/'legacy-profiles.json',meta)
save(DEST/'bindings.json',{'version':1,'residents':bindings})
save(DEST/'runtime.json',{'version':1,'phase':2,'activation_limit':2,'exit_cooldown':60,'priority':['glutton','glutton-minor','clingy','serious'],'reactions':{**{k:v['action'] for k,v in old['traits'].items()},**{k:old['traits'][v[1]]['action'] for k,v in extra.items()},'glutton':'watch'}})
