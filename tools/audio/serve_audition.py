"""Serve only the audition page and manifest audio on localhost; no game data."""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import re
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=0)
    args = parser.parse_args()
    manifest = json.loads((ROOT / 'godot/content/audio/sounds.json').read_text())
    audio = {}
    for event in manifest['events'].values():
        for clip in event['variants'].values():
            path = ROOT / 'godot' / clip['file'].removeprefix('res://')
            audio['/audio/' + path.name] = path

    music=ROOT/'godot/content/audio/user-music.json'
    if music.exists():
        for track in json.loads(music.read_text())['tracks'].values():
            path=ROOT/'godot'/track['file'].removeprefix('res://')
            audio['/audio/'+path.name]=path

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_HEAD(self):
            self.respond(False)

        def do_GET(self):
            self.respond(True)

        def respond(self, body):
            target = unquote(urlsplit(self.path).path)
            if target in ('/', '/audition.html'):
                data = (ROOT / 'production/audio/audition.html').read_bytes().replace(
                    b'../../godot/content/audio/generated/', b'/audio/').replace(b'../../godot/content/audio/user-music/', b'/audio/')
                mime = 'text/html; charset=utf-8'
            elif target in audio:
                path = audio[target]
                data = path.read_bytes()
                mime = 'audio/ogg' if path.suffix == '.ogg' else 'audio/wav'
            else:
                self.send_error(404)
                return
            lo, hi, status = 0, len(data) - 1, 200
            requested = self.headers.get('Range')
            if requested:
                match = re.fullmatch(r'bytes=(\d*)-(\d*)', requested)
                if not match or not any(match.groups()):
                    self.send_error(416)
                    return
                start, end = match.groups()
                if start:
                    lo = int(start)
                    hi = min(int(end), hi) if end else hi
                else:
                    lo = max(0, len(data) - int(end))
                if lo > hi or lo >= len(data):
                    self.send_error(416)
                    return
                status = 206
            self.send_response(status)
            self.send_header('Content-Type', mime)
            self.send_header('Content-Length', str(hi - lo + 1))
            self.send_header('Accept-Ranges', 'bytes')
            self.send_header('Cache-Control', 'no-store')
            if status == 206:
                self.send_header('Content-Range', f'bytes {lo}-{hi}/{len(data)}')
            self.end_headers()
            if body:
                self.wfile.write(data[lo:hi + 1])

    server = ThreadingHTTPServer(('127.0.0.1', args.port), Handler)
    print(f'http://127.0.0.1:{server.server_port}/audition.html', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
