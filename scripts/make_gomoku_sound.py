#!/usr/bin/env python3
"""Original short board/stone tap, synthesized offline without external samples."""
from pathlib import Path
import math,random,struct,wave
def main():
    rng=random.Random(109);rate=22050;samples=[]
    for i in range(int(rate*.12)):
        t=i/rate
        tone=math.sin(2*math.pi*820*t)*math.exp(-t*85)*.22
        tap=rng.uniform(-1,1)*math.exp(-t*180)*.26
        samples.append(struct.pack('<h',int((tone+tap)*32767)))
    path=Path(__file__).resolve().parents[1]/'godot/assets/audio/gomoku_stone.wav'
    with wave.open(str(path),'wb') as file:
        file.setparams((1,2,rate,0,'NONE','not compressed'));file.writeframes(b''.join(samples))
if __name__=='__main__':main()
