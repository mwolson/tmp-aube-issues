#!/bin/bash
set -euo pipefail

AUBE_BIN="${AUBE_BIN:-aube}"
PNPM_BIN="${PNPM_BIN:-pnpm}"
for cmd in "$AUBE_BIN" "$PNPM_BIN" bash cp node python3; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "missing required command: $cmd" >&2
        exit 2
    fi
done
if "$PNPM_BIN" --version | grep -q aubeshim; then
    echo "PNPM_BIN must point at real pnpm, not aubeshim" >&2
    exit 2
fi
AUBE_BIN=$(command -v "$AUBE_BIN")
PNPM_BIN=$(command -v "$PNPM_BIN")
export AUBE_BIN PNPM_BIN
cd "$(dirname "$0")"
work="$PWD/.repro-work"
rm -rf "${work:?}"
mkdir -p "$work"
export REPRO_WORK="$work"
unset CI
# Each round starts with fresh private stores. Warm mode seeds only the content
# store and metadata cache with GVS disabled, then starts N fresh projects.
# MODE=cold skips seeding; MODE=warm-gvs seeds the shared virtual store too.
# GVS=false and HOIST=false select comparison runs.
python3 - <<'PY'
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

work = Path(os.environ['REPRO_WORK'])
aube = os.environ['AUBE_BIN']
pnpm = os.environ['PNPM_BIN']
try:
    rounds = int(os.environ.get('ROUNDS', '60'))
    projects = int(os.environ.get('PROJECTS', '11'))
    if not 1 <= rounds <= 200 or not 2 <= projects <= 32:
        raise ValueError('require ROUNDS=1..200 and PROJECTS=2..32')
except ValueError as error:
    print(error, file=sys.stderr)
    sys.exit(2)
mode = os.environ.get('MODE', 'warm')
if mode not in ('cold', 'warm', 'warm-gvs'):
    print('MODE must be cold, warm, or warm-gvs', file=sys.stderr)
    sys.exit(2)
gvs = os.environ.get('GVS', 'true') != 'false'
hoist = os.environ.get('HOIST', 'true') != 'false'


def round_install(tool, number):
    base = work / tool / str(number)
    base.mkdir(parents=True)
    env = os.environ.copy()
    for key, name in {
        'AUBE_CACHE_DIR': 'aube-cache', 'AUBE_STORE_DIR': 'aube-store',
        'XDG_CACHE_HOME': 'xdg-cache', 'XDG_DATA_HOME': 'xdg-data',
        'XDG_STATE_HOME': 'xdg-state', 'pnpm_config_store_dir': 'pnpm-store',
        'pnpm_config_cache_dir': 'pnpm-cache',
    }.items():
        env[key] = str(base / name)
    binary = pnpm if tool == 'pnpm' else aube
    args = ['install', '--ignore-scripts']
    if tool == 'aube':
        args += ['--enable-global-virtual-store' if gvs else '--disable-global-virtual-store']
    dirs = []
    for i in range(projects + 1):
        directory = base / str(i)
        shutil.copytree('fixture', directory)
        (directory / '.npmrc').write_text('hoist=' + str(hoist).lower() + '\n')
        dirs.append(directory)
    if mode != 'cold':
        seed_args = ['install', '--ignore-scripts']
        if tool == 'aube':
            seed_args += ['--enable-global-virtual-store' if mode == 'warm-gvs' and gvs
                          else '--disable-global-virtual-store']
        with (base / 'seed.log').open('wb') as log:
            result = subprocess.run([binary, *seed_args], cwd=dirs[0], env=env,
                                    stdout=log, stderr=subprocess.STDOUT, timeout=30)
        if result.returncode:
            raise RuntimeError('seed failed: ' + str(base / 'seed.log'))
    children = []
    try:
        for directory in dirs[1:]:
            log = (directory / 'install.log').open('wb')
            child = subprocess.Popen(['bash', '-c', 'read -r _; exec "$@"',
                                      'repro', binary, *args], cwd=directory, env=env,
                                     stdin=subprocess.PIPE, stdout=log, stderr=subprocess.STDOUT)
            children.append((child, log, directory))
        for child, _, _ in children:
            child.stdin.write(b'go\n')
            child.stdin.close()
        failures = []
        for child, log, directory in children:
            status = child.wait(timeout=30)
            log.close()
            if status:
                text = (directory / 'install.log').read_text()
                failures.append((directory, status, text))
        return failures
    finally:
        for child, log, _ in children:
            if child.poll() is None:
                child.kill()
            child.wait()
            log.close()


try:
    print('aube: ' + subprocess.check_output([aube, '--version'], text=True).strip(), flush=True)
    print('pnpm control: ' + subprocess.check_output([pnpm, '--version'], text=True).strip(), flush=True)
    print(f'{projects} concurrent projects; mode={mode}; GVS={gvs}; hoist={hoist}', flush=True)
    for number in range(1, 4):
        failures = round_install('pnpm', number)
        if failures:
            raise RuntimeError('pnpm control failed: ' + str(failures))
    print('pnpm control: 3 concurrent rounds pass', flush=True)
    start = time.monotonic()
    for number in range(1, rounds + 1):
        failures = round_install('aube', number)
        if failures:
            race = False
            for directory, status, text in failures:
                print(f'round {number}, exit {status}: {directory}/install.log\n{text}', flush=True)
                if 'File exists (os error 17)' in text and 'virtual-store' in text:
                    race = True
                else:
                    raise RuntimeError('unexpected install failure; see log above')
            print(f'race reproduced in round {number}, {time.monotonic() - start:.2f}s', flush=True)
            sys.exit(1 if race else 2)
        if number % 10 == 0:
            print(f'aube: {number} rounds passed', flush=True)
    print(f'No race observed in {rounds} rounds. Exit 0 is not proof that the race is fixed.', flush=True)
except (OSError, RuntimeError, subprocess.SubprocessError) as error:
    print('environment/control failure: ' + str(error), file=sys.stderr)
    sys.exit(2)
PY
