"""Compare CoreAudio native-start estimates with the configured target bands."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'production/evidence/sound-v2'
probe = json.loads((OUT/'core-events-probe.json').read_text())
limits = json.loads((ROOT/'godot/content/audio/runtime.json').read_text())['targets_dbfs']
critical = {'fire.ignite', 'fishing.bite', 'fish.release', 'meal.satisfied'}
rows = []
for event in probe['native_starts']:
    name = event['event']
    category = 'voice' if name.startswith('voice.') or name in critical else ('ambience' if name.startswith('ambience.') else 'ui')
    target = limits[category]
    rms = event['effective_db']
    peak = event['peak_dbfs']
    rows.append({'event': name, 'gain_db': event['gain_db'], 'effective_db': rms, 'peak_dbfs': peak,
                 'target_dbfs': target, 'in_target': target[0] <= rms <= target[1], 'peak_ok': peak <= limits['peak_max']})
summary = {'method': 'Programmatic CoreAudio native starts at unity bus/master and full event gain; derived from source WAV metadata, not loopback.',
           'driver_pass': probe['pass'], 'events': len(rows), 'out_of_target': sum(not r['in_target'] for r in rows),
           'peak_failures': sum(not r['peak_ok'] for r in rows), 'rows': rows}
(OUT/'core-events-loudness.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2)+'\n')
lines=['# CoreAudio 原生派发：事件数字估算', '', '由程序触发，每条音量为完整事件增益且主音量及分类音量为 100%。数值是源 WAV 的测量值加播放增益，不是声卡回录、引擎解码后波形或多声混合结果。', '', '| 事件 | 增益 dB | 有效 RMS dBFS | 峰值 dBFS | 目标 dBFS | 结果 |', '|---|---:|---:|---:|---|---|']
lines.extend(f"| {r['event']} | {r['gain_db']:.2f} | {r['effective_db']:.2f} | {r['peak_dbfs']:.2f} | {r['target_dbfs'][0]} 至 {r['target_dbfs'][1]} | {'通过' if r['in_target'] and r['peak_ok'] else '未通过'} |" for r in rows)
lines.extend(['',f"共 {len(rows)} 个事件；目标外 {summary['out_of_target']}，单条峰值超限 {summary['peak_failures']}。距离、淡入淡出、用户音量、遮挡和混音会改变实际播放。",''])
(OUT/'core-events-loudness.md').write_text('\n'.join(lines))
print(json.dumps({k:v for k,v in summary.items() if k!='rows'},ensure_ascii=False,indent=2))
if not summary['driver_pass'] or summary['out_of_target'] or summary['peak_failures']:raise SystemExit(1)
