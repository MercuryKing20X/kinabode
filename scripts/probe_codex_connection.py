#!/usr/bin/env python3
"""Read-only check for the *existing owner's* public Codex Unix transport.

Never starts a daemon, resumes a thread, queues input or changes configuration.
Finding stored history on a different server does not qualify as a connection.
"""
import argparse
import json
import os
from pathlib import Path
import queue
import re
import stat
import threading
import time
from codex_unix_websocket import UnixWebSocket

READ_METHODS = {'initialize', 'server/diagnostics', 'thread/loaded/list', 'thread/read'}


class ProbeError(Exception):
    pass


class PublicConnection:
    def __init__(self, socket_path):
        self.socket = UnixWebSocket(socket_path)
        self.lines = queue.Queue()
        self.serial = 0
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        try:
            while True:
                self.lines.put(json.dumps(self.socket.receive()))
        except (OSError, EOFError, ValueError) as error:
            self.lines.put(ProbeError(str(error)))
        finally:
            self.lines.put(ProbeError('public_connection_closed'))

    def send(self, value):
        self.socket.send(value)

    def call(self, method, params=None):
        if method not in READ_METHODS: raise ProbeError('probe_is_read_only')
        self.serial += 1
        self.send({'id': self.serial, 'method': method, 'params': params or {}})
        deadline = time.monotonic() + 5
        for _ in range(500):
            remaining = deadline - time.monotonic()
            if remaining <= 0: break
            try: line = self.lines.get(timeout=remaining)
            except queue.Empty: break
            if isinstance(line, Exception): raise line
            item = json.loads(line)
            if item.get('method') and 'id' in item:
                # No upstream attestation, approvals or verification impersonation.
                self.send({'id': item['id'], 'error': {'code': -32601, 'message': 'Read-only diagnostic client'}})
            if item.get('id') != self.serial or item.get('method'): continue
            if 'error' in item: raise ProbeError('public_rpc_rejected:' + str(item['error'].get('code')))
            return item['result']
        raise ProbeError('public_rpc_timeout')

    def close(self):
        self.socket.close()


def inspect_owner(client, thread_id, expected_pid):
    client.call('initialize', {'clientInfo': {'name': 'youqi-read-only-probe', 'version': '0.1.0'},
                               'capabilities': {'experimentalApi': True}})
    client.send({'method': 'initialized'})
    diagnostic = client.call('server/diagnostics')
    actual_pid = diagnostic.get('process', {}).get('id')
    result = {'public_transport_connected': True, 'server_pid': actual_pid,
              'expected_server_pid': expected_pid, 'thread_loaded': False,
              'automatic_wakeup_verified': False, 'inference_started': False}
    if actual_pid != expected_pid:
        return dict(result, status='different_server', reason='A second server is not the original live conversation owner.')
    cursor = None
    for _ in range(20):
        page = client.call('thread/loaded/list', {'limit': 100, 'cursor': cursor})
        if thread_id in page.get('data', []):
            result['thread_loaded'] = True
            thread = client.call('thread/read', {'threadId': thread_id, 'includeTurns': False})['thread']
            if thread.get('id') != thread_id: raise ProbeError('thread_identity_mismatch')
            return dict(result, status='owner_transport_ready', thread_status=thread.get('status'),
                        reason='Read-only ownership verified; actual send/receive and wake-up still need an authorized test.')
        cursor = page.get('nextCursor')
        if not cursor:
            return dict(result, status='thread_not_loaded', reason='No resume or implicit takeover was attempted.')
    return dict(result, status='inventory_limit', reason='Bounded inventory exhausted; no takeover attempted.')


def probe(socket_path, thread_id, expected_pid):
    if not re.fullmatch(r'[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}', thread_id):
        raise ProbeError('invalid_thread_id')
    if expected_pid <= 0: raise ProbeError('expected_original_server_pid_required')
    path = Path(socket_path).expanduser()
    if not path.is_absolute(): raise ProbeError('absolute_public_socket_path_required')
    if 'codex-app-tools' in str(path) or path.parent.name == 'ipc':
        raise ProbeError('private_desktop_pipe_not_supported')
    try: mode = path.stat().st_mode
    except FileNotFoundError:
        return {'status': 'no_public_socket', 'public_transport_connected': False,
                'automatic_wakeup_verified': False, 'inference_started': False,
                'socket': str(path), 'expected_server_pid': expected_pid,
                'reason': 'Original desktop runtime has no public shared endpoint at this path.'}
    if not stat.S_ISSOCK(mode): raise ProbeError('not_a_socket')
    client = PublicConnection(path)
    try: return dict(inspect_owner(client, thread_id, expected_pid), socket=str(path))
    finally: client.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--socket', default=str(Path(os.environ.get('CODEX_HOME') or Path.home()/'.codex')/'app-server-control/app-server-control.sock'))
    parser.add_argument('--thread', default=os.environ.get('CODEX_THREAD_ID', ''))
    parser.add_argument('--owner-pid', required=True, type=int)
    args = parser.parse_args()
    try: result = probe(args.socket, args.thread, args.owner_pid)
    except (ProbeError, OSError, ValueError, KeyError) as error:
        result = {'status': 'probe_failed', 'automatic_wakeup_verified': False, 'error': str(error)}
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result['status'] == 'owner_transport_ready' else 2


if __name__ == '__main__': raise SystemExit(main())
