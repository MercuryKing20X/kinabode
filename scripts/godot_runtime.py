"""Discover Godot without requiring a platform-specific executable setting."""
import os
from pathlib import Path
import shutil
import sys


def godot_executable():
    configured = os.environ.get('HABITAT_GODOT')
    if configured:
        return configured
    for name in ('godot', 'godot4', 'Godot', 'godot.exe', 'godot4.exe'):
        found = shutil.which(name)
        if found:
            return found
    # macOS GUI installs are not placed on PATH. This is discovery, not a
    # requirement: Windows/Linux use PATH or the same HABITAT_GODOT setting.
    if sys.platform == 'darwin':
        for folder in (Path('/Applications'), Path.home() / 'Applications'):
            for bundle in sorted(folder.glob('Godot*.app')):
                binary = bundle / 'Contents' / 'MacOS' / 'Godot'
                if binary.is_file():
                    return str(binary)
    raise RuntimeError('Godot not found. Add Godot to PATH or set HABITAT_GODOT to its executable.')
