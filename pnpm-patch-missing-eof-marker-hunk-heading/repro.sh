#!/bin/bash
set -euo pipefail
trap 'echo "Unexpected setup failure; see preceding error." >&2; exit 2' ERR

AUBE_BIN="${AUBE_BIN:-aube}"
PNPM_BIN="${PNPM_BIN:-pnpm}"
for cmd in "$AUBE_BIN" "$PNPM_BIN" node python3 mktemp; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Missing required command: $cmd" >&2
        exit 2
    fi
done
AUBE_BIN="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$(command -v "$AUBE_BIN")")"
PNPM_BIN="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$(command -v "$PNPM_BIN")")"
NODE_BIN="$(command -v node)"
if [[ "${PNPM_BIN##*/}" == aubeshim || "$PNPM_BIN" == */aubeshim/shims/* ]]; then
    echo "Point PNPM_BIN at real pnpm, not the aubeshim dispatcher." >&2
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_ROOT="${REPRO_TMP_ROOT:-$SCRIPT_DIR/../tmp}"
mkdir -p "$WORK_ROOT"
WORK_ROOT="$(cd "$WORK_ROOT" && pwd)"
WORK="$(mktemp -d "$WORK_ROOT/patch-eof-heading.XXXXXX")"
echo "Evidence: $WORK"
"$AUBE_BIN" --version
"$PNPM_BIN" --version

main() {
    create_cases
    local failed=""
    for variant in plain-missing-marker headed-canonical headed-missing-marker; do
        if ! install_case "$WORK/$variant-pnpm" "$PNPM_BIN"; then
            echo "Native pnpm control failed for $variant; inspect $WORK/$variant-pnpm/install.log" >&2
            exit 2
        fi
        if install_case "$WORK/$variant-aube" "$AUBE_BIN"; then
            echo "Pass: aube applied $variant."
        elif grep -q 'error applying hunk' "$WORK/$variant-aube/install.log"; then
            echo "Fail: aube rejected $variant; pnpm applied the same patch."
            failed=1
        else
            echo "Unexpected aube failure for $variant; inspect $WORK/$variant-aube/install.log" >&2
            exit 2
        fi
    done
    if [[ -n "$failed" ]]; then
        echo "Reproduced: missing EOF marker is only tolerated without a hunk section heading."
        exit 1
    fi
}

create_cases() {
    python3 - "$SCRIPT_DIR" "$WORK" <<'PY'
import io
import json
from pathlib import Path
import sys
import tarfile

source, work = map(Path, sys.argv[1:])
with tarfile.open(work / 'patch-target.tgz', 'w:gz') as archive:
    for name in ['package.json', 'index.js']:
        content = (source / 'fixture' / name).read_bytes()
        entry = tarfile.TarInfo('package/' + name)
        entry.size = len(content)
        archive.addfile(entry, io.BytesIO(content))
marker = b'\\ No newline at end of file\n'
variants = {
    'plain-missing-marker': (source / 'plain.patch').read_bytes(),
    'headed-canonical': (source / 'headed.patch').read_bytes() + marker,
    'headed-missing-marker': (source / 'headed.patch').read_bytes(),
}
for variant, patch in variants.items():
    for manager in ['pnpm', 'aube']:
        project = work / f'{variant}-{manager}'
        project.mkdir()
        (project / 'package.json').write_text(json.dumps({
            'name': 'patch-eof-heading-repro', 'private': True,
            'dependencies': {'patch-target': 'file:./patch-target.tgz'}
        }) + '\n')
        (project / 'pnpm-workspace.yaml').write_text(
            'patchedDependencies:\n  patch-target@1.0.0: change.patch\n'
        )
        (project / 'patch-target.tgz').write_bytes((work / 'patch-target.tgz').read_bytes())
        (project / 'change.patch').write_bytes(patch)
PY
}

install_case() {
    local project="$1"
    local manager="$2"
    mkdir -p "$project"/{home,cache,config,data,state}
    if ! (
        cd "$project"
        env -i PATH="$(dirname "$NODE_BIN"):$PATH" CI=1 NO_COLOR=1 \
            HOME="$project/home" XDG_CACHE_HOME="$project/cache" \
            XDG_CONFIG_HOME="$project/config" XDG_DATA_HOME="$project/data" \
            XDG_STATE_HOME="$project/state" \
            "$manager" install --ignore-scripts
    ) >"$project/install.log" 2>&1; then
        return 1
    fi
    "$NODE_BIN" - "$project" <<'JS'
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const target = path.join(process.argv[2], 'node_modules/patch-target/index.js');
assert.equal(
  fs.readFileSync(target, 'utf8'),
  'module.exports = 1;\n// a\n// B\n// c\n// end',
);
JS
}

main
