"""Measure every active take at unity gain; do not touch historical evidence."""
import hashlib
import json
import math
from pathlib import Path

import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'production/evidence/sound-v2'
catalog = json.loads((ROOT / 'godot/content/audio/sounds.json').read_text())
runtime = json.loads((ROOT / 'godot/content/audio/runtime.json').read_text())
critical = {'fire.ignite', 'fishing.bite', 'fish.release', 'meal.satisfied'}
rows = []
for event_id, event in catalog['events'].items():
    category = 'voice' if event_id.startswith('voice.') or event_id in critical else ('ambience' if event['bus'] == 'Ambience' else 'ui')
    target = runtime['targets_dbfs'][category]
    for variant, clip in event['variants'].items():
        for index, take in enumerate(clip.get('takes', [clip])):
            path = ROOT / 'godot' / take['file'].removeprefix('res://')
            raw = path.read_bytes()
            data, sample_rate = sf.read(path, dtype='float64', always_2d=True)
            rms = 20 * math.log10(max(float(np.sqrt(np.mean(data * data))), 1e-12))
            peak = 20 * math.log10(max(float(np.max(np.abs(data))), 1e-12))
            gain = float(event['volume_db'])
            run_peak = peak + gain + (20 * math.log10(runtime['run_step_gain']) if event_id.startswith('step.') else 0)
            source = catalog['sources'][take['source_id']]['parameters']
            rows.append({'event': event_id, 'variant': variant, 'take': index, 'file': take['file'],
                         'sha256_ok': hashlib.sha256(raw).hexdigest() == take['sha256'], 'sample_rate': sample_rate,
                         'rms_dbfs': round(rms + gain, 3), 'peak_dbfs': round(peak + gain, 3),
                         'max_run_peak_dbfs': round(run_peak, 3), 'target_dbfs': target,
                         'in_target': target[0] <= rms + gain <= target[1],
                         'peak_ok': run_peak <= runtime['targets_dbfs']['peak_max'],
                         'metadata_ok': abs(rms-source['rms_dbfs']) < .01 and abs(peak-source['peak_dbfs']) < .01,
                         'clipped_samples': int(np.count_nonzero(np.abs(data) >= 1.0)),
                         'loop_edge_difference': round(float(np.max(np.abs(data[0]-data[-1]))), 6) if event['loop'] else None})
summary = {'method': 'Digital RMS and peak per file at unity master/bus and full event gain; not system output or summed mix.',
           'takes': len(rows), 'out_of_target': sum(not r['in_target'] for r in rows),
           'peak_failures': sum(not r['peak_ok'] for r in rows), 'metadata_failures': sum(not r['metadata_ok'] for r in rows),
           'hash_failures': sum(not r['sha256_ok'] for r in rows), 'clipped_samples': sum(r['clipped_samples'] for r in rows),
           'rows': rows}
OUT.mkdir(parents=True, exist_ok=True)
(OUT/'loudness.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2)+'\n')
lines=['# 数字素材响度', '', '每条为素材经事件增益后的数字 RMS 与峰值，主音量及分类音量为 100%，不是声卡回录或多声叠加峰值。距离、淡入淡出、静音和用户设置会改变实际电平。', '', '| 事件 | 版本/录音 | RMS dBFS | 峰值 dBFS | 目标 dBFS |', '|---|---|---:|---:|---|']
lines.extend(f"| {r['event']} | {r['variant']}/{r['take']+1} | {r['rms_dbfs']:.2f} | {r['peak_dbfs']:.2f} | {r['target_dbfs'][0]} 至 {r['target_dbfs'][1]} |" for r in rows)
lines.extend(['', f"共 {len(rows)} 条；目标外 {summary['out_of_target']}，峰值超限 {summary['peak_failures']}，哈希错误 {summary['hash_failures']}，削波样本 {summary['clipped_samples']}。跑步脚步峰值按 {runtime['run_step_gain']} 倍增益另外核查。", ''])
(OUT/'loudness.md').write_text('\n'.join(lines))
print(json.dumps({k:v for k,v in summary.items() if k!='rows'}, ensure_ascii=False, indent=2))
if any(summary[k] for k in ('out_of_target','peak_failures','metadata_failures','hash_failures','clipped_samples')):
    raise SystemExit(1)
