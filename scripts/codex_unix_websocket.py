"""Compatibility import for development probes; canonical transport ships with Godot."""
import importlib.util
from pathlib import Path
_spec = importlib.util.spec_from_file_location('youqi_unix_transport', Path(__file__).resolve().parents[1]/'godot/bridge/codex_unix_websocket.py')
_module = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_module)
UnixWebSocket = _module.UnixWebSocket
MAX_BYTES = _module.MAX_BYTES
