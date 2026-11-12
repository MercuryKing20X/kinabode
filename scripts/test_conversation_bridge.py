import os
import unittest
from unittest.mock import patch

import conversation_bridge as bridge

THREAD = '01a15cad-a6ec-7da2-8810-f64c34a67cbd'


class FakeReader:
    def __init__(self):
        self.calls = []
        self.request_data = dict(thread_id=THREAD, request_id='one', session='session',
                                 generation=1, world_id='world', resident_id='codex', text='你好')
        self.failure = None

    def request(self, operation, query):
        self.calls.append((operation, query))
        if operation == 'read_conversation':
            return {'ok': True, 'request': self.request_data}
        if self.failure: raise self.failure
        return {'ok': True, 'receipt': {'status': 'displayed'}}


class ConversationBridgeTests(unittest.TestCase):
    def test_current_thread_required(self):
        with patch.dict(os.environ, {'CODEX_THREAD_ID': ''}):
            with self.assertRaises(bridge.BridgeError): bridge.current_thread()
        with patch.dict(os.environ, {'CODEX_THREAD_ID': THREAD}):
            self.assertEqual(bridge.current_thread(), THREAD)

    def test_reply_copies_only_routing_identity(self):
        reader = FakeReader()
        result = bridge.reply(reader, THREAD, 'one', '你好，我收到啦。')
        self.assertTrue(result['ok'])
        self.assertEqual(reader.calls[0], ('read_conversation', {'thread_id': THREAD}))
        sent = reader.calls[1][1]
        self.assertEqual(sent['text'], '你好，我收到啦。')
        self.assertEqual(sent['generation'], 1)
        self.assertEqual(set(sent), {'thread_id','request_id','session','generation','world_id','resident_id','text'})

    def test_cancelled_or_replaced_message_never_sent(self):
        reader = FakeReader()
        result = bridge.reply(reader, THREAD, 'old', '不要显示')
        self.assertFalse(result['ok'])
        self.assertEqual(len(reader.calls), 1)

    def test_uncertain_timeout_never_retried(self):
        reader = FakeReader()
        reader.failure = bridge.BridgeError('action_timeout_observe_before_retry')
        with self.assertRaises(bridge.BridgeError): bridge.reply(reader, THREAD, 'one', '回复')
        self.assertEqual(sum(op == 'reply_conversation' for op, _ in reader.calls), 1)

    def test_reply_validation_precedes_transport(self):
        reader = FakeReader()
        for value in ('', ' ', 'a' * 8001):
            with self.assertRaises(bridge.BridgeError): bridge.reply(reader, THREAD, 'one', value)
        self.assertFalse(reader.calls)


if __name__ == '__main__': unittest.main()
