import ast
import json
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]/'godot/content/characters'

def bias(art, frame, annotation):
    width=art['width'];lo,hi=annotation['head_y'];palette=art['palette']
    pixels=art['frames'][frame][0]['pixels']
    body=[];face=[]
    for i,index in enumerate(pixels):
        if not index or not lo<=i//width<hi:continue
        x=i%width;body.append(x)
        r,g,b=bytes.fromhex(palette[index][1:7])
        selected=(index==annotation['palette_index']) if annotation['face_rule']=='palette' else (r>170 and g>110 and b>90 and r-g>=12 and abs(g-b)<=55)
        if selected:face.append(x)
    if len(face)<5 or not body:raise ValueError('missing annotated facial pixels')
    return sum(face)/len(face)-sum(body)/len(body)

class Directions(unittest.TestCase):
    def test_glm_import_uses_reviewed_source_orientation(self):
        # Both keyed source sheets have two right-facing side rows. Their
        # left-facing output must explicitly mirror a reviewed right-facing row.
        base=Path(__file__).resolve().parents[1]/'production/art/ai-girls-studies'
        for filename, name in [('import_studies.py','SOURCE_ROWS'),('import_actions_v2.py','ACTION_SOURCE_ROWS')]:
            tree=ast.parse((base/filename).read_text())
            value=next(ast.literal_eval(node.value) for node in tree.body if isinstance(node,ast.Assign) and any(isinstance(target,ast.Name) and target.id==name for target in node.targets))
            self.assertEqual(value['glm']['left'],(1,True))
            self.assertEqual(value['glm']['right'],(1,False))

    def test_all_authored_characters(self):
        annotations=json.loads((ROOT/'direction_annotations.json').read_text())['works']
        works=[]
        for path in ROOT.glob('*.json'):
            if path.name.endswith('.provenance.json') or path.name in ['spare-catalog.json','direction_annotations.json','glm_legacy_direction_hashes.json']:continue
            art=json.loads(path.read_text())
            if art.get('kind','character')!='character' or 'frames' not in art:continue
            works.append(art)
        self.assertGreaterEqual(len(works),13)
        self.assertEqual({art['id'] for art in works},set(annotations),'new works require reviewed face annotation')
        for art in works:
            ann=annotations[art['id']]
            with self.subTest(character=art['id']):
                self.assertEqual((ann['left'],ann['right']),('left','right'))
                left=bias(art,'left_0',ann);right=bias(art,'right_0',ann)
                self.assertLess(left,-0.2,'left face centroid must lie left of head')
                self.assertGreater(right,0.2,'right face centroid must lie right of head')
                self.assertGreater(right-left,1.0,'reversing the frames must fail')
                self.assertFalse(right < -0.2 and left > 0.2,'the same detector rejects swapped sides')

    def test_glm_original_swapped_pair_is_detected(self):
        art=json.loads((ROOT/'ai-glm.json').read_text())
        ann=json.loads((ROOT/'direction_annotations.json').read_text())['works']['ai-glm']
        art['frames']['left_0'],art['frames']['right_0']=art['frames']['right_0'],art['frames']['left_0']
        self.assertGreater(bias(art,'left_0',ann),0)
        self.assertLess(bias(art,'right_0',ann),0)

if __name__=='__main__':unittest.main()
