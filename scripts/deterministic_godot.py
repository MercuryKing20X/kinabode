"""Build a test-only source overlay with reproducible entropy dependencies.

The shipped project is never edited. Only wall-clock reads, Crypto entropy and
unseeded RNG initialization are injected; monotonic timeouts stay real. Explicit
fixture seeds and every gameplay expression/assertion remain unchanged.
"""
from pathlib import Path
import re

CLOCK = 'preload("res://tests/deterministic_environment.gd")'

def materialize(source: Path, destination: Path) -> dict:
    counts = {"clock_reads": 0, "crypto_reads": 0, "rng_initializers": 0, "rng_constructors": 0, "global_rng_reads": 0, "calendar_reads": 0, "protocol_clock_reads_retained": 0, "archive_clock_reads_retained": 0, "archive_calendar_reads_retained": 0}
    for path in sorted([*(source / 'scripts').rglob('*.gd'), *(source / 'tests').rglob('*.gd')]):
        relative = path.relative_to(source)
        if relative.as_posix() == 'tests/deterministic_environment.gd':
            (destination / relative).parent.mkdir(parents=True, exist_ok=True)
            (destination / relative).write_text(path.read_text(encoding='utf-8'), encoding='utf-8')
            continue
        original = path.read_text(encoding='utf-8')
        value = original
        value, count = re.subn(r'RandomNumberGenerator\.new\(\)',
            lambda m: CLOCK + '.new_rng("' + relative.as_posix() + ':' + str(original[:m.start()].count('\n')+1) + '")', value)
        counts['rng_constructors'] += count
        value, count = re.subn(r'(?<![\w.])(?<!func )(randi|randf|randi_range|randf_range|randfn|seed)\(',
            lambda m: CLOCK + ('.global_seed(' if m[1] == 'seed' else '.global_rng().' + m[1] + '('), value)
        counts['global_rng_reads'] += count
        # IPC leases and file mtimes share the host's real wall clock with
        # Python clients. Freezing these would invalidate every bridge request
        # or suppress genuine expiry; they are not simulation randomness.
        transport = relative.as_posix() in {
            'scripts/read_endpoint.gd', 'scripts/companion_link.gd',
            'scripts/conversation_link.gd',
        }
        # Backup order/deduplication is wall-clock filesystem behavior, like
        # transport freshness. Keep archive creation/calendar reads coherent
        # with the real archive fixture, without changing simulation time.
        archive_wall_clock = relative.as_posix() in {
            'scripts/save_backup.gd', 'tests/test_save_backup.gd',
        }
        lines = []
        for line in value.splitlines(keepends=True):
            count = line.count('Time.get_unix_time_from_system()')
            if archive_wall_clock:
                counts['archive_clock_reads_retained'] += count
            elif transport or '"expires"' in line:
                counts['protocol_clock_reads_retained'] += count
            else:
                line = line.replace('Time.get_unix_time_from_system()', CLOCK + '.wall_time()')
                counts['clock_reads'] += count
            lines.append(line)
        value = ''.join(lines)
        for api, method in [('get_date_string_from_system', 'system_date'), ('get_datetime_string_from_system', 'system_datetime'), ('get_time_zone_from_system', 'time_zone')]:
            count = value.count('Time.' + api + '(')
            if archive_wall_clock:
                counts['archive_calendar_reads_retained'] += count
            else:
                value = value.replace('Time.' + api + '(', CLOCK + '.' + method + '(')
                counts['calendar_reads'] += count
        value, count = re.subn(r'Crypto\.new\(\)\.generate_random_bytes\((\d+)\)',
            lambda m: CLOCK + '.random_bytes(' + m[1] + ',"' + relative.as_posix() + '")', value)
        counts['crypto_reads'] += count
        value, count = re.subn(r'\b([a-zA-Z_][a-zA-Z_0-9]*)\.randomize\(\)',
            lambda m: CLOCK + '.seed_rng(' + m[1] + ',"' + relative.as_posix() + ':' + m[1] + '")', value)
        counts['rng_initializers'] += count
        target = destination / relative
        if destination.resolve() not in target.resolve().parents:
            raise ValueError('Test overlay must not write through a source symlink: ' + str(relative))
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(value, encoding='utf-8')
    # Scripts also contain shaders and tests contain JSON fixture data.
    for folder in ['scripts', 'tests']:
        for path in (source / folder).rglob('*'):
            if path.is_file() and path.suffix != '.gd':
                target = destination / path.relative_to(source)
                target.parent.mkdir(parents=True, exist_ok=True)
                if not target.exists(): target.symlink_to(path)
    return counts
