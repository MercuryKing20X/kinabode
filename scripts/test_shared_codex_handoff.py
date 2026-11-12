#!/usr/bin/env python3
"""Explicit live experiment: migrate only a disposable Codex test thread.

Two completed model turns are intended: seed actual conversation history before
handoff, then verify recall and a workspace edit after handoff. Never resumes
CODEX_THREAD_ID, changes global configuration, or touches the player's save.
"""
import argparse
import json
import os
from pathlib import Path
import queue
import secrets
import signal
import subprocess
import tempfile
import threading
import time
from codex_unix_websocket import UnixWebSocket

CODEX = '/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex'


class Rpc:
    def __init__(self, command, cwd, handler=None, socket_path=None):
        self.socket = UnixWebSocket(socket_path) if socket_path else None
        self.process = None if self.socket else subprocess.Popen(command, cwd=cwd, stdin=subprocess.PIPE,
                                        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                        text=True, encoding='utf-8', bufsize=1,
                                        start_new_session=True)
        self.events = queue.Queue(); self.notifications = []; self.serial = 0
        self.handler = handler
        self.write_lock = threading.Lock()
        self.trace = []
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        try:
            if self.socket:
                while True: self._enqueue(self.socket.receive())
            for line in self.process.stdout:
                try: self._enqueue(json.loads(line))
                except ValueError: pass
        except (OSError, EOFError, ValueError) as error:
            self.events.put({'transport_error':str(error)})
        finally: self.events.put(None)

    def _enqueue(self, value):
        if 'method' in value: self.trace.append(value)
        if 'method' in value and 'id' in value:
            response = self.handler(value) if self.handler else {'error': {'code':-32601,'message':'No delegated approval or attestation'}}
            self.send({'id':value['id'], **response})
        self.events.put(value)

    def send(self, value):
        if self.socket:
            self.socket.send(value); return
        with self.write_lock:
            self.process.stdin.write(json.dumps(value, ensure_ascii=False)+'\n')
            self.process.stdin.flush()

    def receive(self, timeout):
        value = self.events.get(timeout=timeout)
        if value is None: raise RuntimeError('RPC process closed')
        return value

    def call(self, method, params=None, timeout=30):
        self.serial += 1; identifier = self.serial
        self.send({'id': identifier, 'method': method, 'params': params or {}})
        deadline = time.monotonic()+timeout
        while time.monotonic() < deadline:
            item = self.receive(max(.01, deadline-time.monotonic()))
            if item.get('id') == identifier and 'method' not in item:
                if 'error' in item: raise RuntimeError(method+': '+json.dumps(item['error']))
                return item['result']
            self.notifications.append(item)
        raise TimeoutError(method)

    def initialize(self):
        result = self.call('initialize', {'clientInfo': {'name':'youqi-handoff-test','version':'0.1'},
                                         'capabilities': {'experimentalApi':True}})
        self.send({'method':'initialized'})
        return result

    def wait_turn(self, thread_id, turn_id, timeout=120):
        deadline = time.monotonic()+timeout
        seen = []
        while time.monotonic() < deadline:
            item = self.notifications.pop(0) if self.notifications else self.receive(max(.01, deadline-time.monotonic()))
            seen.append(item)
            params = item.get('params', {})
            if item.get('method') == 'turn/completed' and params.get('threadId') == thread_id and params.get('turn',{}).get('id') == turn_id:
                if params['turn']['status'] != 'completed': raise RuntimeError('Turn failed: '+json.dumps(params['turn'].get('error')))
                return seen
        # A timeout is not permission to start another turn. Caller will stop its
        # exclusively-owned test process and leave the test marked incomplete.
        raise TimeoutError('turn/completed')

    def close(self):
        if self.socket:
            self.socket.close(); return
        if self.process.poll() is None:
            if self.process.stdin:
                try: self.process.stdin.close()
                except OSError: pass
            try: self.process.wait(timeout=4)
            except subprocess.TimeoutExpired:
                os.killpg(self.process.pid, signal.SIGTERM)
                try: self.process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    os.killpg(self.process.pid, signal.SIGKILL); self.process.wait(timeout=3)
        self.process.stdout.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--live', action='store_true')
    parser.add_argument('--output', required=True)
    parser.add_argument('--continue-from', help='Resume this failed disposable test after a transport-only failure, without repeating its completed seed turn')
    parser.add_argument('--restore-test-permissions', action='store_true', help='Explicitly restore the same workspace-write/never permissions used by this disposable seed thread')
    parser.add_argument('--continue-queued', action='store_true', help='Inspect and continue the already queued test message; never enqueue another copy')
    args = parser.parse_args()
    if not args.live or os.environ.get('HABITAT_LIVE_TEST') != '1':
        parser.error('Requires --live and HABITAT_LIVE_TEST=1; invokes at most two short model turns.')
    output = Path(args.output).resolve(); output.mkdir(parents=True, exist_ok=True)
    previous = json.loads(Path(args.continue_from).read_text()) if args.continue_from else None
    if previous and previous.get('ok'):
        raise RuntimeError('A passing live test must not be repeated without a new concern')
    workspace = Path(previous['workspace']) if previous else Path(tempfile.mkdtemp(prefix='habitat-live-test-handoff-'))
    if previous:
        workspace = Path(previous['workspace'])
        if 'habitat-live-test-handoff-' not in workspace.name or not previous.get('test_services_stopped'):
            raise RuntimeError('Cannot continue an active or non-disposable test')
        if previous['test_thread_id'] == os.environ.get('CODEX_THREAD_ID'): raise RuntimeError('Refusing current thread')
    socket_dir = Path(tempfile.mkdtemp(prefix='yq-socket-', dir='/tmp'))
    socket_path = socket_dir/'s.sock'
    fixture = 'FIXTURE-'+secrets.token_hex(6)
    if previous: fixture = (workspace/'fixture.txt').read_text().strip()
    else: (workspace/'fixture.txt').write_text(fixture+'\n')
    report = {'ok':False, 'live_test':True, 'workspace':str(workspace),
              'current_development_thread_untouched':True, 'checks':{}, 'model_turns_started':0}
    active = []; server = None; thread_id = None
    if previous:
        report = previous.copy(); report.pop('error',None)
        report['test_services_stopped'] = False
        thread_id = report['test_thread_id']

    def checkpoint(stage):
        report['stage'] = stage
        (output/'result.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
        print(stage, flush=True)

    def handle(value):
        if value.get('method') == 'item/tool/call' and value.get('params',{}).get('tool') == 'youqi_handoff_receipt':
            params = value['params']
            report['receipt'] = params.get('arguments', {})
            report['receipt_thread_id'] = params.get('threadId')
            checkpoint('received_preserved_dynamic_tool_call')
            return {'result': {'success':True, 'contentItems':[{'type':'inputText','text':'Receipt recorded. Finish with OK.'}]}}
        return {'error': {'code':-32601,'message':'Unsupported test-side request; do not grant additional permissions.'}}

    overrides = ['-c','features.plugins=false','-c','features.apps=false',
                 '-c','features.memories=false','-c','model_reasoning_effort="low"']
    try:
        if not previous:
            seed_experiment(workspace, overrides, report, checkpoint, active, handle)
        thread_id = report['test_thread_id']
        started = report.get('initial_settings',{})

        log = (output/'shared-server.log').open('w')
        server = subprocess.Popen([CODEX,*overrides,'app-server','--listen','unix://'+str(socket_path)],cwd=workspace,
                                  stdin=subprocess.DEVNULL,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
        report['shared_server_pid'] = server.pid
        deadline = time.monotonic()+10
        while not socket_path.exists() and server.poll() is None and time.monotonic()<deadline: time.sleep(.05)
        if not socket_path.exists(): raise RuntimeError('Shared public socket did not appear')
        second = Rpc(None,workspace,handle,socket_path); active.append(second)
        second.initialize()
        resume_params = {'threadId':thread_id,'excludeTurns':True}
        if args.restore_test_permissions:
            original = report.get('initial_settings', {})
            if original and (original['sandbox']['type'] != 'workspaceWrite' or original['approvalPolicy'] != 'never'):
                raise RuntimeError('Unexpected initial policy; refusing to replace it')
            resume_params.update(sandbox='workspace-write',approvalPolicy='never')
            report['explicit_original_test_permissions_restored'] = True
        resumed = second.call('thread/resume',resume_params)
        report['restored_settings'] = {key:resumed.get(key) for key in ('cwd','sandbox','approvalPolicy','model','modelProvider')}
        report['checks']['same_thread_id'] = resumed['thread']['id'] == thread_id
        for key in ('cwd','sandbox','approvalPolicy','model','modelProvider'):
            if key in started: report['checks']['preserved_'+key] = resumed.get(key) == started[key]
        # For a transport-only retry of the initial harness version, the exact
        # requested sandbox and working directory are still known independently.
        if not started:
            report['checks']['preserved_cwd'] = resumed.get('cwd') == str(workspace)
            report['checks']['preserved_sandbox'] = resumed.get('sandbox',{}).get('type') == 'workspaceWrite'
            report['checks']['preserved_approvalPolicy'] = resumed.get('approvalPolicy') == 'never'
        after = second.call('thread/turns/list',{'threadId':thread_id,'itemsView':'full','limit':5})
        report['checks']['preserved_turn_history'] = all(t in [turn['id'] for turn in after['data']] for t in report['before_turn_ids'])
        import re
        saved_marker = re.search(r'YOUQI-[0-9a-f]{12}',json.dumps(after))
        if not saved_marker: raise RuntimeError('Seed history is missing; refusing new inference')
        marker = saved_marker.group()
        checkpoint('resumed_on_public_shared_service')
        if not all(report['checks'].values()): raise RuntimeError('Configuration checks failed before inference; inspect restored_settings')

        third = Rpc(None,workspace,handle,socket_path); active.append(third)
        third.initialize()
        observed = third.call('thread/read',{'threadId':thread_id,'includeTurns':False})
        report['checks']['second_client_same_thread'] = observed['thread']['id'] == thread_id
        diagnostic = third.call('server/diagnostics')
        report['checks']['second_client_same_server'] = diagnostic['process']['id'] == server.pid
        if not args.continue_queued:
            queued = third.call('thread/queue/add',{'threadId':thread_id,'clientUserMessageId':secrets.token_hex(16),
                'input':[{'type':'text','text':'Now verify the earlier conversation marker from memory. Read fixture.txt, create result.txt with exactly the same contents using your ordinary file tools, then call youqi_handoff_receipt with the remembered marker and the file contents (trim whitespace). Finish with OK. Do not read or change anything outside this temporary workspace.'}]})
            report['queued_submission_id'] = queued['queuedSubmission']['id']
            checkpoint('second_client_queued_message')
        pending = third.call('thread/queue/list',{'threadId':thread_id})
        report['queue_state'] = pending
        status = third.call('thread/read',{'threadId':thread_id,'includeTurns':False})['thread']['status']
        report['before_start_status'] = status
        checkpoint('inspected_queue_before_start')
        if status.get('type') != 'active' and any(q.get('id') == report['queued_submission_id'] for q in pending['data']):
            try:
                third.call('thread/queue/start',{'threadId':thread_id,'queuedSubmissionId':report['queued_submission_id']})
            except RuntimeError as error:
                report['start_response_error'] = str(error)
                # Queue/start can race queue auto-start. Inspect; never re-enqueue.
        deadline = time.monotonic()+120
        turn_id = None
        prior_ids = {t['id'] for t in after['data']}
        completed = False
        while time.monotonic()<deadline:
            for client in (second,third):
                while client.notifications or not client.events.empty():
                    item = client.notifications.pop(0) if client.notifications else client.receive(.1)
                    params = item.get('params',{})
                    if params.get('threadId') != thread_id: continue
                    if item.get('method') == 'turn/started' and params['turn']['id'] not in prior_ids:
                        turn_id = params['turn']['id']
                    if item.get('method') == 'turn/completed' and params['turn']['id'] not in prior_ids:
                        turn_id = params['turn']['id']
                        if params['turn']['status'] != 'completed': raise RuntimeError('Actual turn/completed failed: '+json.dumps(params['turn']))
                        completed = True
            if completed: break
            time.sleep(.1)
        else: raise TimeoutError('Queued message did not complete; no automatic resend')
        receipt = report.get('receipt',{})
        report['checks']['recalled_pre_migration_marker'] = receipt.get('marker') == marker
        report['checks']['read_fixture'] = receipt.get('fixture') == fixture
        report['checks']['preserved_dynamic_tool'] = report.get('receipt_thread_id') == thread_id
        report['checks']['ordinary_file_edit'] = (workspace/'result.txt').exists() and (workspace/'result.txt').read_text() == fixture+'\n'
        final_history = third.call('thread/turns/list',{'threadId':thread_id,'itemsView':'summary','limit':5})
        report['model_turns_started'] = len(final_history['data'])
        report['checks']['second_client_sees_both_turns'] = turn_id in [t['id'] for t in final_history['data']] and all(t in [v['id'] for v in final_history['data']] for t in report['before_turn_ids'])
        report['final_turn_ids'] = [t['id'] for t in final_history['data']]
        report['ok'] = all(report['checks'].values())
        checkpoint('completed' if report['ok'] else 'verification_failed')
    except Exception as error:
        report['error'] = type(error).__name__+': '+str(error)
        checkpoint('failed_no_automatic_retry')
    finally:
        for index,client in enumerate(active):
            (output/('client-%s-events.json'%index)).write_text(json.dumps(client.trace,ensure_ascii=False,indent=2))
        for client in active:
            if report.get('ok') and thread_id and thread_id != os.environ.get('CODEX_THREAD_ID'):
                try: client.call('thread/archive',{'threadId':thread_id},timeout=5)
                except Exception: pass
                thread_id = None
            client.close()
        if server and server.poll() is None:
            os.killpg(server.pid,signal.SIGTERM)
            try: server.wait(timeout=4)
            except subprocess.TimeoutExpired:
                os.killpg(server.pid,signal.SIGKILL); server.wait(timeout=3)
        report['test_services_stopped'] = True
        if socket_path.exists(): socket_path.unlink()
        socket_dir.rmdir()
        (output/'result.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
    print(json.dumps(report,ensure_ascii=False,indent=2),flush=True)
    return 0 if report['ok'] else 1


def seed_experiment(workspace, overrides, report, checkpoint, active, handle):
        marker = 'YOUQI-'+secrets.token_hex(6)
        first = Rpc([CODEX,*overrides,'app-server','--listen','stdio://'],workspace,handle); active.append(first)
        first.initialize()
        started = first.call('thread/start', {
            'cwd':str(workspace), 'sandbox':'workspace-write', 'approvalPolicy':'never',
            'developerInstructions':'This is a bounded Youqi integration test in a disposable workspace. Access only this workspace. Do not use network, spawn agents, or read user credentials. Preserve conversation facts exactly. Use normal editing tools for the explicitly requested temporary file. Call youqi_handoff_receipt only when asked.',
            'dynamicTools':[{'name':'youqi_handoff_receipt','description':'Record the actual recalled marker and fixture contents in this integration test.',
                             'inputSchema':{'type':'object','properties':{'marker':{'type':'string'},'fixture':{'type':'string'}},'required':['marker','fixture'],'additionalProperties':False}}]})
        thread_id = started['thread']['id']
        if thread_id == os.environ.get('CODEX_THREAD_ID'): raise RuntimeError('Refusing current development thread')
        report['test_thread_id'] = thread_id
        report['initial_settings'] = {key:started.get(key) for key in ('cwd','sandbox','approvalPolicy','model','modelProvider')}
        report['source_server_pid'] = first.process.pid
        first.call('thread/name/set',{'threadId':thread_id,'name':'有栖共享服务交接验证（临时）'})
        checkpoint('created_disposable_test_thread')
        seed = first.call('turn/start', {'threadId':thread_id,'input':[{'type':'text','text':'Remember this test marker for later: '+marker+'. Reply only READY; do not use tools yet.'}],'effort':'low'})
        report['model_turns_started'] += 1
        first.wait_turn(thread_id,seed['turn']['id'])
        history_before = first.call('thread/turns/list',{'threadId':thread_id,'itemsView':'summary','limit':5})
        report['before_turn_ids'] = [t['id'] for t in history_before['data']]
        checkpoint('seed_turn_completed')
        first.close(); active.remove(first)
        report['checks']['source_process_stopped_before_resume'] = first.process.poll() is not None
        checkpoint('old_owner_stopped')


if __name__ == '__main__': raise SystemExit(main())
