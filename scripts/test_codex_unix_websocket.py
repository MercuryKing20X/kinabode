import base64
import hashlib
import json
from pathlib import Path
import socket
import struct
import tempfile
import threading
import unittest

from codex_unix_websocket import UnixWebSocket, MAX_BYTES
from probe_codex_connection import probe

THREAD = '01a15cad-a6ec-7da2-8810-f64c34a67cbd'


def read_exact(connection, size):
    result = b''
    while len(result) < size:
        value = connection.recv(size-len(result))
        if not value: raise EOFError()
        result += value
    return result


def client_frame(connection):
    first, second = read_exact(connection, 2)
    if not second & 128: raise AssertionError('Client did not mask its frame')
    size = second & 127
    if size == 126: size = struct.unpack('!H',read_exact(connection,2))[0]
    elif size == 127: size = struct.unpack('!Q',read_exact(connection,8))[0]
    mask = read_exact(connection,4); data = read_exact(connection,size)
    return first & 15, bytes(v ^ mask[i % 4] for i,v in enumerate(data))


def server_frame(data, opcode=1, final=True):
    head = bytes([(128 if final else 0) | opcode])
    if len(data)<126: return head+bytes([len(data)])+data
    if len(data)<65536:return head+b'\x7e'+struct.pack('!H',len(data))+data
    return head+b'\x7f'+struct.pack('!Q',len(data))+data


class FakeServer:
    def __init__(self, callback, valid_handshake=True):
        self.directory = tempfile.TemporaryDirectory(prefix='yq-ws-',dir='/tmp')
        self.path = Path(self.directory.name)/'public.sock'
        self.listener = socket.socket(socket.AF_UNIX,socket.SOCK_STREAM)
        self.listener.bind(str(self.path)); self.listener.listen(1)
        self.errors = []; self.calls = []
        def run():
            try:
                connection, _ = self.listener.accept()
                with connection:
                    connection.settimeout(3)
                    header = b''
                    while b'\r\n\r\n' not in header: header += connection.recv(4096)
                    key = next(line.split(b':',1)[1].strip() for line in header.split(b'\r\n') if line.lower().startswith(b'sec-websocket-key:'))
                    accept = base64.b64encode(hashlib.sha1(key+b'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest()) if valid_handshake else b'invalid'
                    connection.sendall(b'HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nUpgrade: websocket\r\nSec-WebSocket-Accept: '+accept+b'\r\n\r\n')
                    if valid_handshake: callback(connection,self)
            except Exception as error: self.errors.append(error)
        self.thread = threading.Thread(target=run,daemon=True); self.thread.start()

    def close(self):
        self.thread.join(4); self.listener.close(); self.directory.cleanup()
        if self.thread.is_alive(): raise AssertionError('Server did not stop')
        if self.errors: raise self.errors[0]


class UnixWebSocketTests(unittest.TestCase):
    def test_masked_json_and_fragmented_reply_with_ping(self):
        def respond(connection,server):
            opcode,data = client_frame(connection)
            self.assertEqual(opcode,1); self.assertEqual(json.loads(data)['text'],'有栖'*100)
            encoded = json.dumps({'ok':True,'text':'收到了'},ensure_ascii=False).encode()
            connection.sendall(server_frame(encoded[:8],final=False)+server_frame(b'ping',opcode=9)+server_frame(encoded[8:],opcode=0))
            self.assertEqual(client_frame(connection),(10,b'ping'))
        server = FakeServer(respond)
        try:
            client = UnixWebSocket(server.path); client.send({'text':'有栖'*100})
            self.assertEqual(client.receive(),{'ok':True,'text':'收到了'}); client.close()
        finally: server.close()

    def test_rejected_handshake(self):
        server = FakeServer(lambda *args: None,False)
        try:
            with self.assertRaises(ConnectionError):UnixWebSocket(server.path)
        finally:server.close()

    def test_oversized_server_frame_rejected_before_payload(self):
        server = FakeServer(lambda connection,_:connection.sendall(b'\x81\x7f'+struct.pack('!Q',MAX_BYTES+1)))
        try:
            client = UnixWebSocket(server.path)
            with self.assertRaises(ValueError):client.receive()
            client.close()
        finally:server.close()

    def test_close_frame_is_not_a_reply(self):
        server = FakeServer(lambda connection,_:connection.sendall(server_frame(b'',opcode=8)))
        try:
            client = UnixWebSocket(server.path)
            with self.assertRaises(EOFError):client.receive()
            client.close()
        finally:server.close()

    def test_real_transport_readonly_probe(self):
        def respond(connection,server):
            for _ in range(5):
                _,data = client_frame(connection); msg = json.loads(data); server.calls.append(msg['method'])
                method = msg['method']
                if method == 'initialized':continue
                result = {'initialize':{},'server/diagnostics':{'process':{'id':987}},
                          'thread/loaded/list':{'data':[THREAD]},
                          'thread/read':{'thread':{'id':THREAD,'status':{'type':'idle'}}}}[method]
                connection.sendall(server_frame(json.dumps({'id':msg['id'],'result':result}).encode()))
        server = FakeServer(respond)
        try:
            result = probe(str(server.path),THREAD,987)
            self.assertEqual(result['status'],'owner_transport_ready')
            self.assertFalse(result['automatic_wakeup_verified'])
        finally:server.close()
        self.assertEqual(server.calls,['initialize','initialized','server/diagnostics','thread/loaded/list','thread/read'])


if __name__ == '__main__':unittest.main()
