"""Relay newline-delimited MCP to the Kinabode loopback door."""

import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path


URL = "http://127.0.0.1:17642/mcp"
MAX_LINE = 16384


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def main():
    if len(sys.argv) == 2:
        try:
            with (Path(sys.argv[1]) / "world-door-token").open("r", encoding="ascii") as key_file:
                token = key_file.read(65)
        except (OSError, UnicodeError):
            sys.exit("Open the Kinabode door in the game first.")
    else:
        token = os.environ.get("KINABODE_TOKEN", "")
    if len(token) != 64 or any(char not in "0123456789abcdef" for char in token):
        sys.exit("Set KINABODE_TOKEN using the token from the game.")
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    while line := sys.stdin.buffer.readline(MAX_LINE + 1):
        if len(line) > MAX_LINE:
            sys.exit("MCP message exceeds the game limit.")
        try:
            message = json.loads(line)
        except (ValueError, UnicodeError):
            continue
        if not isinstance(message, dict):
            continue
        request = urllib.request.Request(URL, line, {
            "Authorization": "Bearer " + token,
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
        }, method="POST")
        try:
            with opener.open(request, timeout=24) as response:
                body = response.read(2 * 1024 * 1024 + 1)
                if not body:
                    continue
                if len(body) > 2 * 1024 * 1024:
                    raise ValueError("Response too large")
                reply = json.loads(body)
        except (OSError, ValueError, urllib.error.URLError):
            if "id" not in message:
                continue
            reply = {"jsonrpc": "2.0", "id": message["id"], "error": {
                "code": -32000, "message": "Kinabode door unavailable or request rejected."
            }}
        print(json.dumps(reply, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
