#!/usr/bin/env python3
"""Decode authored ASCII pixels into the bundled editable work; never player data."""
from pathlib import Path
import json
ROOT=Path(__file__).resolve().parents[1]
def main():
    rows=(ROOT/'production/art/gomoku/table-source.txt').read_text().splitlines()
    assert len(rows)==40 and all(len(row)==48 for row in rows)
    keys='.otbdgh';pixels=[]
    for row in rows:
        line=[keys.index(c) for c in row for _ in range(3)]
        for _ in range(3):pixels.extend(line)
    path=ROOT/'godot/content/works/play-gomoku.json';work=json.loads(path.read_text())
    work['width']=144;work['height']=120;work['anchor']=[72,90]
    for frame in work['frames'].values():frame[0]['pixels']=pixels
    path.write_text(json.dumps(work,ensure_ascii=False,separators=(',',':'))+'\n')
if __name__=='__main__':main()
