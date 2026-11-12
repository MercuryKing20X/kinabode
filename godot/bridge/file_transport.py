#!/usr/bin/env python3
"""Godot 与真实 Codex helper 的独立文件传输进程；不运行模型循环。"""
import argparse
import json
import os
from pathlib import Path
import queue
import signal
import subprocess
import sys
import threading
import time
import uuid

MAX_BYTES = 2 * 1024 * 1024
SENSITIVE = {"action", "observe", "read_work", "edit_work", "question", "assistant", "thinking"}


def encode(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False)


def atomic_json(path, value):
    temporary = path.with_name(path.name + "." + uuid.uuid4().hex + ".tmp")
    try:
        with temporary.open("x", encoding="utf-8") as stream:
            stream.write(encode(value)); stream.flush(); os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        try: temporary.unlink()
        except OSError: pass


def parent_alive(pid):
    try: os.kill(pid, 0); return True
    except ProcessLookupError: return False
    except PermissionError: return True


class FileTransport:
    def __init__(self, directory, nonce, send, emit=None, now=time.monotonic):
        self.directory = Path(directory)
        self.nonce = nonce
        self.send = send
        self.observe = emit
        self.now = now
        self.generation = 0
        self.sequence = 0
        self.active = False
        self.cancelling = False
        self.cancel_id = None
        self.pending = {}
        self.closed = False
        self.last_client_heartbeat = now()
        self.seen_request_ids = set()
        for name in ("inbox", "processing", "outbox"):
            (self.directory / name).mkdir(parents=True, exist_ok=True)

    def publish(self, event, generation=None):
        self.sequence += 1
        envelope = {"session": self.nonce, "generation": self.generation if generation is None else generation,
                    "sequence": self.sequence, "event": event}
        atomic_json(self.directory / "outbox" / ("%010d.json" % self.sequence), envelope)
        if self.observe: self.observe(envelope)

    def reject(self, message):
        self.publish({"kind": "error", "message": message})

    def client(self, envelope):
        if not isinstance(envelope, dict) or envelope.get("session") != self.nonce:
            return
        if type(envelope.get("generation")) is not int or not isinstance(envelope.get("id"), str):
            self.reject("传输请求格式不正确。"); return
        request_id = envelope["id"]
        if request_id in self.seen_request_ids:
            return
        self.seen_request_ids.add(request_id)
        if len(self.seen_request_ids) > 4096:
            self.reject("本次连接请求过多，请重新连接。"); self.closed = True; return
        message = envelope.get("message", {})
        if not isinstance(message, dict):
            self.reject("传输消息无效。"); return
        kind = message.get("kind")
        generation = envelope["generation"]
        if kind in ("cancel", "shutdown"):
            if generation <= self.generation:
                return
            self.generation = generation
            self.cancelling = True
            self.cancel_id = uuid.uuid4().hex
            self.pending.clear()
            self.publish({"kind": "state", "state": "cancelling", "message": "正在停止回应…"})
            self.send({"kind": "cancel" if kind == "cancel" else "shutdown", "cancelId": self.cancel_id})
            if kind == "shutdown": self.closed = True
            return
        if kind in ("chat", "autonomy_event"):
            if generation <= self.generation or self.active or self.cancelling:
                self.reject("上一轮回应尚未结束，请稍后再发送。"); return
            self.generation = generation
            self.active = True
            self.send(message)
            return
        if kind == "tool_result":
            if generation != self.generation or self.cancelling or message.get("id") not in self.pending:
                self.reject("这个问题或动作已过期，回复未执行。"); return
            self.pending.pop(message["id"], None)
            self.send(message)
            return
        self.reject("不支持的游戏传输消息。")

    def helper(self, event):
        if not isinstance(event, dict) or not isinstance(event.get("kind"), str):
            self.reject("Codex 返回了无效消息。"); return
        kind = event["kind"]
        if self.cancelling and kind in SENSITIVE:
            return
        if kind == "error" and event.get("code")=="autonomy_unsupported":
            self.active=False;self.pending.clear()
        if kind == "state":
            state = event.get("state")
            if self.cancelling:
                # A ready message may already be queued before cancel reached the helper.
                # Only this cancellation's acknowledgement or process closure is a barrier.
                if state != "disconnected" and not (state == "cancelled" and event.get("cancelId") == self.cancel_id):
                    return
                self.cancelling = False
                self.active = False
                self.publish({"kind": "state", "state": "cancelled", "message": "已停止回应。"})
                return
            if state in ("ready", "cancelled", "error", "disconnected"):
                self.active = False
                self.pending.clear()
            elif state in ("thinking", "acting", "waiting"):
                self.active = True
        if kind in ("action", "observe", "read_work", "edit_work", "question"):
            request_id = event.get("id")
            if not self.active or not isinstance(request_id, str):
                return
            self.pending[request_id] = self.generation
        self.publish(event)

    def drain(self):
        for path in sorted((self.directory / "inbox").glob("*.json"))[:32]:
            claimed = self.directory / "processing" / path.name
            try:
                os.rename(path, claimed)
            except OSError:
                continue
            try:
                if claimed.stat().st_size > MAX_BYTES:
                    raise ValueError("请求太大")
                envelope = json.loads(claimed.read_text(encoding="utf-8"))
                self.client(envelope)
            except (OSError, ValueError, TypeError) as error:
                self.reject("游戏请求无法读取：" + str(error)[:200])
            finally:
                try: claimed.unlink()
                except OSError: pass


def main(argv=None):
    parser = argparse.ArgumentParser(description="栖居 Godot 文件传输")
    parser.add_argument("--session-dir", required=True)
    parser.add_argument("--data-dir", required=True)
    parser.add_argument("--nonce", required=True)
    parser.add_argument("--parent-pid", type=int, required=True)
    parser.add_argument("--helper", default=str(Path(__file__).with_name("companion.py")))
    parser.add_argument("--codex")
    args = parser.parse_args(argv)
    session = Path(args.session_dir).resolve()
    session.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(session, 0o700)
    command = [sys.executable, "-u", args.helper, "--data-dir", str(Path(args.data_dir).resolve())]
    if args.codex: command += ["--codex", args.codex]
    # One process group belongs exclusively to this game's helper and app-server.
    child = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, text=True, encoding="utf-8", bufsize=1,
                             start_new_session=True)
    events = queue.Queue()
    stopping = threading.Event()

    def stop_signal(_sig, _frame): stopping.set()
    signal.signal(signal.SIGTERM, stop_signal)
    signal.signal(signal.SIGINT, stop_signal)

    def send(message):
        child.stdin.write(encode(message) + "\n"); child.stdin.flush()

    def read(stream, stderr=False):
        try:
            while True:
                line = stream.readline(MAX_BYTES + 1)
                if not line: break
                if stderr: continue
                if len(line.encode("utf-8")) > MAX_BYTES:
                    events.put({"kind": "error", "message": "Codex 消息过大。"}); break
                try: events.put(json.loads(line))
                except ValueError: events.put({"kind": "error", "message": "Codex 消息格式无效。"})
        finally:
            if not stderr: events.put(None)

    threading.Thread(target=read, args=(child.stdout,), daemon=True).start()
    threading.Thread(target=read, args=(child.stderr, True), daemon=True).start()
    bridge = FileTransport(session, args.nonce, send)
    def heartbeat_worker():
        while not stopping.is_set():
            atomic_json(session / "bridge-heartbeat.json", {"pid": os.getpid(), "childPid": child.pid, "updated": time.time(), "session": args.nonce})
            stopping.wait(1)
    heartbeat_thread = threading.Thread(target=heartbeat_worker, daemon=True)
    heartbeat_thread.start()
    try:
        while not bridge.closed and not stopping.is_set():
            if not parent_alive(args.parent_pid): break
            heartbeat = session / "client-heartbeat.json"
            try:
                if time.time() - heartbeat.stat().st_mtime > 60: break
            except FileNotFoundError:
                if time.monotonic() - bridge.last_client_heartbeat > 60: break
            bridge.drain()
            while True:
                try: event = events.get_nowait()
                except queue.Empty: break
                if event is None:
                    bridge.publish({"kind": "state", "state": "disconnected", "message": "Codex 连接已结束。"})
                    bridge.closed = True; break
                bridge.helper(event)
            stopping.wait(0.05)
    except (BrokenPipeError, OSError) as error:
        bridge.reject("Codex 传输中断：" + str(error)[:200])
    finally:
        stopping.set()
        heartbeat_thread.join(timeout=2)
        try: send({"kind": "shutdown"})
        except (OSError, BrokenPipeError): pass
        try: child.wait(timeout=3)
        except subprocess.TimeoutExpired:
            try: os.killpg(child.pid, signal.SIGTERM)
            except ProcessLookupError: pass
            try: child.wait(timeout=2)
            except subprocess.TimeoutExpired:
                try: os.killpg(child.pid, signal.SIGKILL)
                except ProcessLookupError: pass
                child.wait(timeout=2)
        for stream in (child.stdin, child.stdout, child.stderr):
            try: stream.close()
            except OSError: pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
