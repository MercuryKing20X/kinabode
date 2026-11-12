import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import probe_codex_connection as probe

THREAD = '01a15cad-a6ec-7da2-8810-f64c34a67cbd'


class FakeClient:
    def __init__(self, pid=123, loaded=None, status='idle'):
        self.pid = pid; self.loaded = [THREAD] if loaded is None else loaded
        self.status = status; self.calls = []

    def send(self, value): self.calls.append(value['method'])

    def call(self, method, params=None):
        self.calls.append(method)
        if method == 'initialize': return {}
        if method == 'server/diagnostics': return {'process': {'id': self.pid}}
        if method == 'thread/loaded/list': return {'data': self.loaded, 'nextCursor': None}
        if method == 'thread/read': return {'thread': {'id': THREAD, 'status': {'type': self.status}}}
        raise AssertionError('Unexpected mutation: '+method)


class ConnectionProbeTests(unittest.TestCase):
    def test_missing_socket_never_starts_process(self):
        with tempfile.TemporaryDirectory(prefix='youqi-probe-test-') as d:
            with patch.object(probe, 'PublicConnection') as start:
                result = probe.probe(str(Path(d)/'missing.sock'), THREAD, 123)
                self.assertEqual(result['status'], 'no_public_socket')
                start.assert_not_called()

    def test_second_server_with_same_thread_not_original_owner(self):
        client = FakeClient(pid=456)
        self.assertEqual(probe.inspect_owner(client, THREAD, 123)['status'], 'different_server')
        self.assertNotIn('thread/read', client.calls)

    def test_saved_history_not_resumed(self):
        client = FakeClient(loaded=[])
        result = probe.inspect_owner(client, THREAD, 123)
        self.assertEqual(result['status'], 'thread_not_loaded')
        self.assertNotIn('thread/resume', client.calls)
        self.assertNotIn('thread/read', client.calls)

    def test_idle_and_busy_have_read_only_verification(self):
        for status in ('idle', 'active'):
            client = FakeClient(status=status)
            result = probe.inspect_owner(client, THREAD, 123)
            self.assertEqual(result['status'], 'owner_transport_ready')
            self.assertFalse(result['automatic_wakeup_verified'])
            self.assertFalse(result['inference_started'])
            self.assertFalse(set(client.calls)-probe.READ_METHODS-{'initialized'})

    def test_private_pipe_never_contacted(self):
        with patch.object(probe, 'PublicConnection') as start:
            with self.assertRaises(probe.ProbeError):
                probe.probe('/tmp/codex-app-tools/private.sock', THREAD, 123)
            start.assert_not_called()

    def test_probe_rejects_mutations(self):
        client = object.__new__(probe.PublicConnection)
        for method in ('thread/resume', 'thread/queue/add', 'turn/start', 'config/value/write'):
            with self.assertRaises(probe.ProbeError): client.call(method, {})


if __name__ == '__main__': unittest.main()
