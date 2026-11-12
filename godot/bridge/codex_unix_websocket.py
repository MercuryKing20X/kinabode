"""Bounded text WebSocket transport over an explicit local AF_UNIX socket.

Public Codex --listen unix:// uses an HTTP Upgrade handshake, not raw JSONL.
No authentication substitution, daemon startup or non-local networking.
"""
import base64
import hashlib
import json
import secrets
import socket
import struct
import threading

MAX_BYTES = 8 * 1024 * 1024


class UnixWebSocket:
    def __init__(self, path, timeout=10):
        self.socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.lock = threading.Lock()
        self.socket.settimeout(timeout)
        self.buffer = bytearray()
        try:
            self.socket.connect(str(path))
            key = base64.b64encode(secrets.token_bytes(16)).decode()
            request = ('GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\n'
                       'Connection: Upgrade\r\nSec-WebSocket-Key: '+key+
                       '\r\nSec-WebSocket-Version: 13\r\n\r\n')
            self.socket.sendall(request.encode())
            while b'\r\n\r\n' not in self.buffer:
                block = self.socket.recv(4096)
                if not block: raise ConnectionError('Socket closed during WebSocket upgrade')
                self.buffer.extend(block)
                if len(self.buffer) > 16384: raise ValueError('Upgrade header too large')
            header, tail = self.buffer.split(b'\r\n\r\n', 1)
            self.buffer = bytearray(tail)
            lines = header.decode('ascii').split('\r\n')
            headers = {k.lower().strip(): v.strip() for k,v in (line.split(':',1) for line in lines[1:])}
            expected = base64.b64encode(hashlib.sha1((key+'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest()).decode()
            if lines[0].split()[1] != '101' or headers.get('sec-websocket-accept') != expected:
                raise ConnectionError('Public endpoint rejected WebSocket handshake')
            if headers.get('upgrade','').lower() != 'websocket': raise ConnectionError('Invalid upgrade response')
            self.socket.settimeout(None)
        except Exception:
            self.socket.close(); raise

    def _read(self, size):
        while len(self.buffer) < size:
            block = self.socket.recv(min(65536, size-len(self.buffer)))
            if not block: raise EOFError('Public WebSocket closed')
            self.buffer.extend(block)
        result = bytes(self.buffer[:size]); del self.buffer[:size]
        return result

    def _send(self, opcode, payload):
        if len(payload) > MAX_BYTES: raise ValueError('Message too large')
        prefix = bytes([0x80 | opcode])
        if len(payload) < 126: prefix += bytes([0x80 | len(payload)])
        elif len(payload) < 65536: prefix += bytes([0x80 | 126])+struct.pack('!H',len(payload))
        else: prefix += bytes([0x80 | 127])+struct.pack('!Q',len(payload))
        mask = secrets.token_bytes(4)
        encoded = bytes(value ^ mask[i % 4] for i,value in enumerate(payload))
        with self.lock: self.socket.sendall(prefix+mask+encoded)

    def send(self, value):
        self._send(1, json.dumps(value,ensure_ascii=False).encode('utf-8'))

    def receive(self):
        message = bytearray(); started = False
        while True:
            first, second = self._read(2)
            opcode = first & 15; final = bool(first & 0x80)
            if first & 0x70 or second & 0x80: raise ValueError('Invalid server frame flags')
            size = second & 127
            if size == 126: size = struct.unpack('!H',self._read(2))[0]
            elif size == 127: size = struct.unpack('!Q',self._read(8))[0]
            if size > MAX_BYTES or len(message)+size > MAX_BYTES: raise ValueError('Message too large')
            if opcode >= 8 and (size > 125 or not final): raise ValueError('Invalid control frame')
            payload = self._read(size)
            if opcode == 8: raise EOFError('Public WebSocket closed')
            if opcode == 9: self._send(10,payload); continue
            if opcode == 10: continue
            if opcode not in (0,1) or (opcode == 0) != started: raise ValueError('Unexpected frame sequence')
            started = True; message.extend(payload)
            if final: return json.loads(message.decode('utf-8'))

    def close(self):
        try: self._send(8,struct.pack('!H',1000))
        except OSError: pass
        try: self.socket.shutdown(socket.SHUT_RDWR)
        except OSError: pass
        self.socket.close()
