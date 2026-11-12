#!/usr/bin/env python3
"""Check literal res:// references against exact on-disk filename case.

Dynamic prefixes and test-created resources are reported separately as missing;
only proven case mismatches fail this check. No files are changed.
"""
import argparse
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--json', type=Path)
a = p.parse_args()
project = ROOT / 'godot'
mismatches, missing = [], []
checked = 0
for source in sorted(project.rglob('*')):
    if '.godot' in source.parts or source.suffix not in {'.gd', '.tscn', '.tres', '.godot', '.json'}:
        continue
    for match in re.finditer(r"""["'](?:res://([^"'\n]+)|((?:assets|content|fonts|scenes|scripts)/[^"'\n]+\.(?:png|jpg|webp|ogg|wav|mp3|ttf|otf|json|gd|tscn|tres)))["']""", source.read_text(errors='replace')):
        relative = match.group(1) or match.group(2)
        if any(c in relative for c in ('%', '+', '{', '\\')) or relative.endswith('/'):
            continue
        current, corrected = project, []
        for part in relative.split('/'):
            if not current.is_dir():
                break
            names = {child.name: child for child in current.iterdir()}
            if part in names:
                current = names[part]
            else:
                same = [name for name in names if name.casefold() == part.casefold()]
                if len(same) != 1:
                    break
                current = names[same[0]]
            corrected.append(current.name)
        else:
            checked += 1
            actual = '/'.join(corrected)
            if relative != actual:
                mismatches.append({'source': str(source.relative_to(ROOT)), 'literal': relative, 'actual': actual})
            continue
        missing.append({'source': str(source.relative_to(ROOT)), 'literal': relative})
result = {'checked': checked, 'case_mismatches': mismatches, 'unresolved_literals': missing}
if a.json:
    a.json.parent.mkdir(parents=True, exist_ok=True)
    a.json.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(result, ensure_ascii=False, indent=2))
raise SystemExit(bool(mismatches))
