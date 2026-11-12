#!/usr/bin/env python3
"""Game-owned shared Unix server for an explicitly labelled test companion.

Same validated game tools as Companion; never resumes the developer desktop
thread. Public socket permits another client to inspect this same live session.
"""
import argparse
import fcntl
import json
import os
from pathlib import Path
import queue
import re
import subprocess
import sys
import tempfile
import threading
import time

from companion import Companion, DYNAMIC_TOOLS, compact, find_codex, runtime_config, MAX_LINE_BYTES
from codex_unix_websocket import UnixWebSocket

OWNER = 'youqi-shared-test-v1'


class SharedCompanion(Companion):
    def __init__(self, directory, emit, send, endpoint=None, now=time.monotonic):
        super().__init__(directory, emit, send, now)
        self.thread_id = None
        self.state_path = self.directory/'shared-test-thread.json'
        self.endpoint = endpoint or {}
        self.binding_error = None
        self.completed_turns = set()
        self.turns_started = 0
        self.turns_completed = 0
        self.messages_submitted = 0
        self.completing = False
        self.named = False
        if self.state_path.exists():
            try:
                data = json.loads(self.state_path.read_text())
                value = data['threadId']
                if data.get('owner') != OWNER or not isinstance(value,str) or not re.fullmatch(r'[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}',value):
                    raise ValueError('invalid owned test session')
                if value == os.environ.get('CODEX_THREAD_ID'): raise ValueError('developer thread cannot be used as test companion')
                self.thread_id = value
            except (OSError,ValueError,KeyError,TypeError) as error: self.binding_error = str(error)

    def start(self):
        if self.binding_error:
            self.error('测试会话记录无效，已保留原件；不会另开会话冒充连接。')
            self.closed = True; return
        super().start()

    def state(self, state, message='', **extra):
        if state == 'ready': extra['turnComplete'] = self.completing
        super().state(state,message,**extra)

    def error(self, message):
        super().error(message)
        # Keep no uncertain model running behind a UI that now allows retry.
        self.closed = True

    def thread_params(self):
        result = super().thread_params()
        result['developerInstructions'] += '\n这是有栖共享服务测试伙伴的独立会话，不是玩家当前开发窗口中的Codex；不要声称拥有那段开发对话的记忆。用简短中文自然回答。'
        return result

    def save_thread(self):
        self.directory.mkdir(parents=True,exist_ok=True)
        temporary = self.state_path.with_suffix('.tmp')
        temporary.write_text(compact({'owner':OWNER,'threadId':self.thread_id}),encoding='utf-8')
        temporary.replace(self.state_path)
        self.save_status()

    def save_status(self):
        temporary = self.directory/'shared-status.tmp'
        temporary.write_text(compact({**self.endpoint,'threadId':self.thread_id,'owner':OWNER,
            'active':self.active,'turns_started':self.turns_started,'turns_completed':self.turns_completed,
            'messages_submitted':self.messages_submitted,'updated':time.time()}),encoding='utf-8')
        temporary.replace(self.directory/'shared-status.json')

    def request(self, method, params, label=None):
        if method == 'turn/start':
            self.messages_submitted += 1
            self.save_status()
        return super().request(method,params,label)

    def client(self, message):
        if isinstance(message,dict) and message.get('kind') == 'chat' and isinstance(message.get('world'),dict):
            world = message['world']
            resident = world.get('self',{})
            summary = {key:world[key] for key in ('world_id','self_actor_id','selected_object_id','snapshot_revision','dialogue') if key in world}
            summary['self'] = {key:resident[key] for key in ('id','name','appearance_id','region_id','position','job','project','farm_order','control') if key in resident}
            summary['self']['project'] = {key:resident.get('project',{}).get(key) for key in ('id','status')}
            summary['self']['farm_order'] = {key:resident.get('farm_order',{}).get(key) for key in ('farm_id','status')}
            message = dict(message,world=summary)
        super().client(message)

    def server(self, message):
        if self.pending_rpc.get(message.get('id')) == 'thread/name/set':
            # Naming is cosmetic and may race initial session persistence.
            self.pending_rpc.pop(message['id'],None)
            return
        # Failure to resume must never silently make a different model session.
        if message.get('id') in self.pending_rpc and 'error' in message:
            if self.pending_rpc[message['id']] == 'thread/resume':
                self.error('共享测试会话恢复失败，已保留记录，请检查后再连接。')
                self.state('error','会话没有恢复；未创建替代会话。')
                self.closed = True; return
        method = message.get('method')
        params = message.get('params',{})
        if method == 'turn/started':
            identifier = params.get('turn',{}).get('id')
            if params.get('threadId') != self.thread_id or not self.active or identifier in self.completed_turns:
                return
            self.turns_started += 1
        if method == 'turn/completed':
            identifier = params.get('turn',{}).get('id')
            if params.get('threadId') != self.thread_id or not self.active or identifier in self.completed_turns or (self.turn_id and self.turn_id != identifier):
                return
            self.completed_turns.add(identifier)
            self.turns_completed += 1
        creating = self.pending_rpc.get(message.get('id')) == 'thread/start' and 'result' in message
        self.completing = method == 'turn/completed'
        try: super().server(message)
        finally: self.completing = False
        if method == 'turn/completed' and self.thread_id and not self.named:
            self.named = True
            self.request('thread/name/set',{'threadId':self.thread_id,'name':'有栖 · 自动对话测试伙伴'})
        if method in ('turn/started','turn/completed') or creating: self.save_status()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data-dir',required=True)
    parser.add_argument('--codex')
    args = parser.parse_args(argv)
    directory = Path(args.data_dir).resolve(); directory.mkdir(parents=True,exist_ok=True)
    lock = (directory/'shared-owner.lock').open('a')
    output_lock = threading.Lock()
    def emit(value):
        with output_lock: print(compact(value),flush=True)
    try: fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
    except BlockingIOError:
        emit({'kind':'error','message':'同一个测试伙伴已有连接，未启动第二个服务。'}); return 1
    process = None; socket = None; client = None
    events = queue.Queue()
    socket_directory = Path(tempfile.mkdtemp(prefix='youqi-shared-',dir='/tmp'))
    socket_path = socket_directory/'app.sock'
    try:
        command = [find_codex(args.codex),'app-server','--listen','unix://'+str(socket_path)]
        for key,value in runtime_config().items(): command += ['-c',key+'='+compact(value)]
        # Child belongs to the file transport's exclusively-owned process group.
        process = subprocess.Popen(command,cwd=directory,stdin=subprocess.DEVNULL,
                                   stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        deadline = time.monotonic()+15
        while not socket_path.exists():
            if process.poll() is not None or time.monotonic()>=deadline: raise RuntimeError('共享服务未能启动。')
            time.sleep(.05)
        socket = UnixWebSocket(socket_path)
        def read_server():
            try:
                while True: events.put(('server',socket.receive()))
            except (OSError,EOFError,ValueError): events.put(('closed','server'))
        def read_client():
            try:
                while True:
                    line = sys.stdin.readline(MAX_LINE_BYTES+1)
                    if not line: break
                    if len(line.encode('utf-8'))>MAX_LINE_BYTES: raise ValueError('消息过大。')
                    events.put(('client',json.loads(line)))
            except (OSError,ValueError): pass
            finally: events.put(('closed','client'))
        threading.Thread(target=read_server,daemon=True).start()
        threading.Thread(target=read_client,daemon=True).start()
        client = SharedCompanion(directory,emit,socket.send,{'socket':str(socket_path),'server_pid':process.pid})
        client.start()
        while not client.closed:
            try: source,message = events.get(timeout=.2)
            except queue.Empty: client.tick(); continue
            if source == 'server': client.server(message)
            elif source == 'client': client.client(message)
            else:
                if message == 'server': client.error('共享服务已断开；未自动重发消息。')
                break
            client.tick()
    except (OSError,ValueError,RuntimeError,TypeError) as error:
        emit({'kind':'error','message':'自动对话连接失败：'+str(error)[:500]})
    finally:
        if socket:
            if client:
                try: client.cancel('连接关闭。')
                except OSError: pass
            socket.close()
        if process and process.poll() is None:
            process.terminate()
            try: process.wait(timeout=3)
            except subprocess.TimeoutExpired: process.kill(); process.wait(timeout=3)
        (directory/'shared-status.json').unlink(missing_ok=True)
        socket_path.unlink(missing_ok=True)
        socket_directory.rmdir()
        lock.close()
    return 0


if __name__ == '__main__': raise SystemExit(main())
