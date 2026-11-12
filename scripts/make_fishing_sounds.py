#!/usr/bin/env python3
"""Original deterministic water/drop cues; no samples, network or model calls."""
import math, random, struct, wave
from pathlib import Path

def main():
    output=Path(__file__).resolve().parents[1]/'godot/assets/audio'
    for name,duration in [('fish_splash',.48),('fish_bite',.27)]:
        rng=random.Random(108);rate=22050;samples=[];filtered=0.0
        for i in range(int(rate*duration)):
            t=i/rate;filtered=filtered*.83+rng.uniform(-1,1)*.17
            if name=='fish_splash':
                envelope=math.exp(-t*9)*min(1,t*80)
                value=filtered*envelope*.65+math.sin(2*math.pi*(610*t-380*t*t))*math.exp(-t*18)*.17
            else:
                phase=max(0,t-.12);value=(math.sin(2*math.pi*(970*t-900*t*t))*math.exp(-t*30)+math.sin(2*math.pi*(1240*phase-1100*phase*phase))*math.exp(-phase*35)*(t>.12))*.17
            samples.append(struct.pack('<h',int(max(-1,min(1,value))*32767)))
        with wave.open(str(output/(name+'.wav')),'wb') as file:
            file.setparams((1,2,rate,0,'NONE','not compressed'));file.writeframes(b''.join(samples))
if __name__=='__main__':main()
