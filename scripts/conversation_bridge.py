#!/usr/bin/env python3
"""A bounded, explicit relay to the game from the currently running Codex thread.

No desktop private IPC, session resume, credential access or inference. The
desktop wake-up transport is not implemented. inbox/reply run inside the bound
thread, using the game's existing per-resident capability and live session.
"""
import argparse
import json
import os
import re
import sys

from habitat_godot import BridgeError, Reader


def current_thread():
    value = os.environ.get('CODEX_THREAD_ID', '')
    if not re.fullmatch(r'[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}', value):
        raise BridgeError('run_inside_the_bound_codex_conversation')
    return value


def inbox(reader, thread_id):
    return reader.request('read_conversation', {'thread_id': thread_id})


def reply(reader, thread_id, request_id, text):
    if not isinstance(text, str) or not text.strip() or len(text) > 8000:
        raise BridgeError('invalid_reply')
    mailbox = inbox(reader, thread_id)
    if not mailbox.get('ok'):
        return mailbox
    pending = mailbox.get('request', {})
    if pending.get('request_id') != request_id:
        return {'ok': False, 'error': 'message_no_longer_pending',
                'receipt': mailbox.get('receipt', {})}
    fields = ('thread_id', 'request_id', 'session', 'generation', 'world_id', 'resident_id')
    payload = {key: pending[key] for key in fields}
    payload['text'] = text
    # Never retry an uncertain mutation. Read inbox/receipt instead.
    return reader.request('reply_conversation', payload)


def main(argv=None):
    parser = argparse.ArgumentParser(description='有栖原会话转接：不启动模型、不自动唤醒')
    parser.add_argument('--data-dir')
    sub = parser.add_subparsers(dest='operation', required=True)
    sub.add_parser('inbox')
    respond = sub.add_parser('reply')
    respond.add_argument('--request', required=True)
    body = respond.add_mutually_exclusive_group(required=True)
    body.add_argument('--text')
    body.add_argument('--text-file', help='UTF-8 reply; use - to read stdin')
    args = parser.parse_args(argv)
    try:
        thread_id = current_thread()
        reader = Reader(args.data_dir, resident='codex')
        if args.operation == 'inbox':
            result = inbox(reader, thread_id)
        else:
            text = args.text
            if args.text_file:
                if args.text_file == '-': text = sys.stdin.read(32001)
                else:
                    with open(args.text_file, encoding='utf-8') as stream: text = stream.read(32001)
            result = reply(reader, thread_id, args.request, text)
    except (BridgeError, OSError, ValueError) as error:
        result = {'ok': False, 'error': str(error)}
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result.get('ok') else 1


if __name__ == '__main__':
    raise SystemExit(main())
