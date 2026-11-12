"""Strict optional presentation-only gesture settings, matching ActorMotion."""
import json
import math
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
def number(value,low,high):return type(value) in (int,float) and math.isfinite(value) and low<=value<=high
def valid(v):
    if type(v) is not dict or set(v)!={'version','wave','stretch'} or not number(v['version'],1,1):return False
    w,s=v['wave'],v['stretch']
    if type(w) is not dict or set(w)!={'duration','bounce_pixels','lean'}:return False
    if type(s) is not dict or set(s)!={'duration','scale_x','scale_y'}:return False
    return number(w['duration'],.1,5) and number(w['bounce_pixels'],0,10) and number(w['lean'],0,.2) and number(s['duration'],.1,5) and number(s['scale_x'],.9,1) and number(s['scale_y'],1,1.2)
if __name__=='__main__':
    assert valid(json.loads((ROOT/'godot/content/gesture_motion.json').read_text()))
    print('Gesture motion settings validated')
