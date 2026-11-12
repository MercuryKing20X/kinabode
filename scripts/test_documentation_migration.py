# -*- coding: utf-8 -*-
"""Check lossless rule relocation, scope and player/developer documentation boundaries."""
import hashlib,json,re,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'production/evidence/2026-10-27-polish'

class DocumentationMigration(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mapping=json.loads((OUT/'documentation-map.json').read_text())
        cls.before=(OUT/'before/AGENTS.md').read_text()
    def test_every_original_rule_paragraph_is_relocated_verbatim(self):
        self.assertEqual(hashlib.sha256(self.before.encode()).hexdigest(),self.mapping['source_sha256'])
        fragments=[]
        for entry in self.mapping['entries']:
            text=(ROOT/entry['target']).read_text()
            self.assertIn('<a id="'+entry['anchor']+'"></a>',text)
            self.assertIn(entry['source_text'],text)
            self.assertEqual(hashlib.sha256(entry['source_text'].encode()).hexdigest(),entry['source_sha256'])
            fragments.append(entry['source_text'])
        bodies=re.split(r'^## .+\n',self.before,flags=re.M)[1:]
        for body in bodies:
            for paragraph in body.strip().split('\n\n'):
                if paragraph.strip():self.assertTrue(any(paragraph.strip() in part for part in fragments),paragraph[:80])
    def test_agents_halved_and_topic_links_exist(self):
        text=(ROOT/'AGENTS.md').read_text()
        snapshot=(OUT/'final-AGENTS.md').read_text()
        self.assertLessEqual(len(snapshot.encode()),len(self.before.encode())//2)
        self.assertLessEqual(len(snapshot),len(self.before)//2)
        for path in set(re.findall(r'docs/[A-Za-z0-9_/-]+\.md',text)):self.assertTrue((ROOT/path).exists(),path)
        for key in ['CARRY_LIMIT20','schema7','generation','cancelId','120s','0.4.0','runtime_supported']:
            # Stop quiet time is written as quiet120s in the consolidated resident rule.
            self.assertIn(key,text)
    def test_only_three_full_handoff_records_and_older_text_archived(self):
        before=(OUT/'before/docs--SESSION_HANDOFF.md').read_text();new=(ROOT/'docs/SESSION_HANDOFF.md').read_text();archive=(ROOT/'docs/DEVELOPMENT_LOG.md').read_text()
        old_heads=list(re.finditer(r'^## .+\n',before,re.M))
        # The next-stage plan and recent summary are not full historical records.
        full_heads=[line for line in re.findall(r'^## .+\n',new,re.M)
                    if not line.startswith(('## 下一阶段：', '## 已完成：月牙岛', '## 本轮：AI 娘备用外观', '## 本轮：衣柜、主角外观保护'))]
        self.assertEqual(len(full_heads),3)
        for index in range(2):self.assertIn(before[old_heads[index].start():old_heads[index+1].start()].strip(),new+archive)
        self.assertIn(before[old_heads[2].start():],archive)
    def test_readme_is_player_facing_and_dev_material_retained(self):
        readme=(ROOT/'README.md').read_text();guide=(ROOT/'docs/DEVELOPMENT_GUIDE.md').read_text()
        for item in ['岛上手册','钓鱼','做饭','赠予','像素工坊']:self.assertIn(item,readme)
        self.assertNotIn('scripts/test-godot.sh',readme)
        self.assertIn('scripts/test-godot.sh',guide)
        self.assertIn('habitat_godot.py observe',guide)
        self.assertIn('DYNAMIC_TOOLS',(ROOT/'docs/AUTONOMY.md').read_text())

if __name__=='__main__':unittest.main()
