"""Decode every manifest variant and write numerical, not listening, evidence."""
import argparse
import json
import math
from pathlib import Path
import numpy as np
import soundfile as sf
from synthesize import ROOT,MANIFEST,hash_file


def db(value):return round(20*math.log10(max(value,1e-12)),3)


def inspect():
    data=json.loads(MANIFEST.read_text());rows=[];errors=[]
    for key,event in data['events'].items():
      for version,variant in event['variants'].items():
        path=ROOT/'godot'/variant['file'].removeprefix('res://');y,rate=sf.read(path,always_2d=True)
        peak=float(np.abs(y).max());rms=float(np.sqrt(np.mean(y*y)));active=np.flatnonzero(np.abs(y).max(axis=1)>1e-3)
        head=float(active[0]/rate) if len(active) else len(y)/rate
        tail=float((len(y)-active[-1]-1)/rate) if len(active) else len(y)/rate
        seam=float(np.abs(y[-1]-y[0]).max())
        row={'event':key,'variant':version,'file':str(path.relative_to(ROOT)),'sha256':hash_file(path),'seconds':round(len(y)/rate,4),'sample_rate':rate,'channels':y.shape[1],'peak_dbfs':db(peak),'rms_dbfs':db(rms),'clipped_samples':int(np.count_nonzero(np.abs(y)>=1)),'dc_mean':round(float(np.abs(y.mean(axis=0)).max()),7),'loop':event['loop'],'loop_seam_amplitude':round(seam,7),'loop_seam_dbfs':db(seam),'head_below_minus60_seconds':round(head,4),'tail_below_minus60_seconds':round(tail,4)}
        rows.append(row)
        if row['sha256']!=variant['sha256']:errors.append(key+': hash mismatch')
        if peak>10**(-1/20) or row['clipped_samples']:errors.append(key+': peak/clipping')
        if event['loop'] and seam>.03:errors.append(key+': loop discontinuity >0.03 amplitude')
        if not event['loop'] and (head>.05 or tail>.08):errors.append(key+': excess edge silence')
    report={'note':'Numeric checks only; RMS is unweighted dBFS, not perceptual LUFS. Loop seam measures last-to-first decoded sample; no click audibility claim. Intentional sparse bird calls are a 12s ambience bed.','files':rows,'errors':errors}
    out=ROOT/'production/evidence/overnight-1031/audio-qc.json';out.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    text=['# 声音数字自查','',report['note'],'','|ID/版本|秒|峰值 dBFS|RMS dBFS|削波|循环接缝幅度|头/尾静音秒|','|---|---:|---:|---:|---:|---:|---|']
    for r in rows:text.append(f'|{r["event"]}/{r["variant"]}|{r["seconds"]}|{r["peak_dbfs"]}|{r["rms_dbfs"]}|{r["clipped_samples"]}|{r["loop_seam_amplitude"] if r["loop"] else "—"}|{r["head_below_minus60_seconds"]}/{r["tail_below_minus60_seconds"]}|')
    text+=['','错误：'+('无' if not errors else '; '.join(errors))]
    out.with_suffix('.md').write_text('\n'.join(text)+'\n')
    print(len(rows),'files;',len(errors),'errors');print('\n'.join(errors))
    if errors:raise SystemExit(1)

if __name__=='__main__':inspect()
