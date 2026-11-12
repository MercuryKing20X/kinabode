"""Offline life JSON protocol checks; no HTTP, credentials, processes or player data."""
import json
import sys
import tempfile
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'godot/bridge'))
from intent_companion import Companion, life_fields
from openai_companion import parse_reply


class LifeProtocol(unittest.TestCase):
    def reply(self):
        return dict(speech='', intents=[], memory=[], observe='I see the sky.',
                    feel=dict(text='Curious.', source_ids=['real-observation']),
                    want='Stay nearby.', act=[], reflect='A quiet moment.')

    def test_same_fields_survive_both_provider_parsers(self):
        value = self.reply()
        parsed = parse_reply(json.dumps(value))
        self.assertEqual(parsed['feel'], value['feel'])
        self.assertEqual(parsed['act'], parsed['intents'])
        with tempfile.TemporaryDirectory(prefix='youqi-life-json-') as directory:
            events = []
            bridge = Companion(directory, events.append, lambda _: None)
            bridge.emit_event(dict(kind='assistant', text=json.dumps(value)))
            self.assertEqual(events[-1]['kind'], 'intent_result')
            self.assertEqual(events[-1]['reflect'], value['reflect'])

    def test_illegal_act_cannot_hide_behind_legal_intents(self):
        value = self.reply()
        value['act'] = [dict(action='fish')]
        with self.assertRaises(ValueError):
            parse_reply(json.dumps(value))

    def test_oversized_or_wrong_shape_fields_reject(self):
        for update in [dict(observe='x' * 1201), dict(feel=[]),
                       dict(life_wishes=[{}] * 4), dict(life_day=dict(dream=[]))]:
            value = self.reply()
            value.update(update)
            with self.assertRaises(ValueError):
                life_fields(value)

    def test_optional_life_keeps_ordinary_dialogue_unchanged(self):
        value = dict(speech='Hello.', intents=[], memory=[])
        self.assertEqual(life_fields(value), {})
        self.assertNotIn('feel', parse_reply(json.dumps(value)))


if __name__ == '__main__':
    unittest.main()
