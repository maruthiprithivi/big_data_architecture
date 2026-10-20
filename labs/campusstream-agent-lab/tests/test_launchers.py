"""Launcher failure checks; developer-only Python, with optional PWSH runtime."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
FAKE = '''#!/usr/bin/env python3
import json, os, pathlib, sys
a = sys.argv[1:]
with open(os.environ['DOCKER_CALLS'], 'a') as f:
    f.write(json.dumps({'args': a, 'cwd': os.getcwd()}) + '\\n')
if a == ['compose', 'version']:
    print('Docker Compose version v2.40.0')
elif a[:1] == ['info']:
    if os.environ.get('ENGINE_DOWN'): sys.exit(1)
    d = {'OSType': os.environ.get('ENGINE_OS', 'linux'), 'Architecture': 'aarch64', 'MemTotal': int(os.environ.get('ENGINE_MEMORY', 8589934592))}
    print(json.dumps(d) if a[-1] == '{{json .}}' else f"{d['OSType']} {d['Architecture']} {d['MemTotal']}")
elif a[:2] == ['compose', 'up'] and os.environ.get('SETUP_FAIL'):
    sys.exit(1)
elif a[:2] == ['compose', 'exec'] and os.environ.get('VERIFY_FAIL'):
    sys.exit(1)
elif a[:2] == ['compose', 'cp']:
    pathlib.Path(a[-1]).write_text('{}')
'''


def main():
    launchers = [('bash', ['bash', 'lab.sh'])]
    if os.environ.get('PWSH'):
        launchers.append(('PowerShell', [os.environ['PWSH'], '-NoProfile', '-File', 'lab.ps1']))
    with tempfile.TemporaryDirectory(prefix='CampusStream path with spaces ') as temporary:
        folder = Path(temporary)
        for name in ('lab.sh', 'lab.ps1', 'compose.yaml'):
            shutil.copy2(ROOT / name, folder / name)
        fake = folder / 'docker'
        fake.write_text(FAKE)
        fake.chmod(0o755)
        for name, command in launchers:
            for action, flags, success in [
                ('preflight', {}, True),
                ('preflight', {'ENGINE_MEMORY': '4026531840'}, True),
                ('preflight', {'ENGINE_DOWN': '1'}, False),
                ('preflight', {'ENGINE_OS': 'windows'}, False),
                ('preflight', {'ENGINE_MEMORY': '2147483648'}, False),
                ('setup', {}, True),
                ('setup', {'SETUP_FAIL': '1'}, False),
                ('postflight', {}, True),
                ('postflight', {'VERIFY_FAIL': '1'}, False),
            ]:
                log = folder / 'calls.jsonl'
                log.write_text('')
                env = {**os.environ, 'PATH': str(folder) + os.pathsep + os.environ['PATH'], 'DOCKER_CALLS': str(log), **flags}
                result = subprocess.run([*command[:-1], str(folder / command[-1]), action], cwd='/tmp', env=env, capture_output=True, text=True, timeout=30)
                assert (result.returncode == 0) == success, (name, action, flags, result.stdout, result.stderr)
                calls = [json.loads(line) for line in log.read_text().splitlines()]
                assert calls and all(Path(c['cwd']).resolve() == folder.resolve() for c in calls)
                if flags:
                    assert not any(c['args'][:2] == ['compose', 'cp'] for c in calls), calls
                    if 'SETUP_FAIL' in flags:
                        assert not any(c['args'][:2] == ['compose', 'exec'] for c in calls), calls
                if action == 'preflight':
                    assert not any(c['args'][1:2] in (['up'], ['exec'], ['cp'], ['down']) for c in calls)
                if action == 'setup' and success:
                    assert any(c['args'][-1:] == ['--ready'] for c in calls)
                if action == 'postflight' and success:
                    assert (folder/'results/postflight.json').is_file() and (folder/'results/dashboard.html').is_file()
                print(f'PASS {name}: {action} {flags or "happy path"}')


if __name__ == '__main__':
    main()
