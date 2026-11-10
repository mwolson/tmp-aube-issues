#!/bin/bash
set -euo pipefail

# A workspace: direct dependency must provide a registry dependency's peer.
# Check fresh strict/non-strict resolves, snapshot edges and runtime links,
# both lockfile filenames, and reuse of the written and pnpm control locks.
AUBE_BIN="${AUBE_BIN:-aube}"
PNPM_BIN="${PNPM_BIN:-pnpm}"
for cmd in "$AUBE_BIN" "$PNPM_BIN" node python3; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "missing required command: $cmd" >&2
        exit 2
    fi
done
if [[ "$("$PNPM_BIN" --version)" != 12.14.0 ]]; then
    echo "PNPM_BIN must point to real pnpm 12.14.0" >&2
    exit 2
fi
AUBE_BIN="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$(command -v "$AUBE_BIN")")"
PNPM_BIN="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$(command -v "$PNPM_BIN")")"
cd "$(dirname "$0")"
work="$PWD/.repro-work"
rm -rf "${work:?}"
mkdir -p "$work"
trap 'echo "environment/control failure at line $LINENO (see $work)" >&2; exit 2' ERR
export AUBE_STORE_DIR="$work/aube-store" AUBE_CACHE_DIR="$work/aube-cache"
export XDG_DATA_HOME="$work/data" XDG_CACHE_HOME="$work/cache" XDG_CONFIG_HOME="$work/config"
export XDG_STATE_HOME="$work/state" HOME="$work/home" CI="" NO_COLOR=1 FORCE_COLOR=0
export pnpm_config_store_dir="$work/pnpm-store" pnpm_config_cache_dir="$work/pnpm-cache"
failed=

main() {
    echo "aube: $("$AUBE_BIN" --version); pnpm: $("$PNPM_BIN" --version)"
    for strict in true false; do
        local control="$work/pnpm-$strict"
        prepare "$control" "$strict"
        if ! install "$control" "$PNPM_BIN" || ! runtime "$control" || ! snapshot "$control/pnpm-lock.yaml" "$control/snapshot"; then
            echo "pnpm control failed: $control" >&2
            exit 2
        fi
        echo "pnpm strict=$strict: install, peer edge and runtime resolution pass"
        for format in aube pnpm; do
            local dir="$work/aube-$strict-$format"
            prepare "$dir" "$strict"
            printf 'default-lockfile-format=%s\n' "$format" >"$dir/.npmrc"
            check "$dir" "$control/snapshot"
            for frozen in plain frozen; do
                local reuse="$dir-$frozen"
                prepare "$reuse" "$strict"
                if [[ -f "$dir/$format-lock.yaml" ]]; then
                    cp "$dir/$format-lock.yaml" "$reuse/"
                    if [[ "$frozen" == frozen ]]; then
                        check "$reuse" "$control/snapshot" --frozen-lockfile
                    else
                        check "$reuse" "$control/snapshot"
                    fi
                else
                    failed=1
                fi
            done
        done
        for mode in plain frozen; do
            local reuse="$work/pnpm-lock-$strict-$mode"
            prepare "$reuse" "$strict"
            cp "$control/pnpm-lock.yaml" "$reuse/"
            if [[ "$mode" == frozen ]]; then
                check "$reuse" "$control/snapshot" --frozen-lockfile
            else
                check "$reuse" "$control/snapshot"
            fi
            if ! cmp -s "$control/pnpm-lock.yaml" "$reuse/pnpm-lock.yaml"; then
                echo "aube changed pnpm's lockfile"
                failed=1
            fi
        done
    done
    [[ -z "$failed" ]] || exit 1
    echo "pass: workspace peer bindings match pnpm"
}

prepare() {
    cp -R fixture "$1"
    if [[ "$2" == false ]]; then
        python3 - "$1/pnpm-workspace.yaml" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
p.write_text(p.read_text().replace('strictPeerDependencies: true', 'strictPeerDependencies: false'))
PY
    fi
}

install() {
    local dir=$1 bin=$2
    shift 2
    (cd "$dir" && "$bin" install --ignore-scripts "$@") >"$dir/install.log" 2>&1
}

runtime() {
    (cd "$1" && node -e 'const fs = require("fs"); const consumer = fs.realpathSync("packages/app/node_modules/use-sync-external-store"); process.chdir(consumer); console.log(require.resolve("react", {paths: [process.cwd()]}));') >"$1/runtime.log" 2>&1
}

snapshot() {
    python3 - "$1" "$2" <<'PY'
from pathlib import Path
import re, sys
p = Path(sys.argv[1])
if not p.exists(): sys.exit(1)
text = p.read_text().split('snapshots:\n', 1)[-1]
blocks = re.findall(r'^  (use-sync-external-store@[^\n]+\n(?:(?:    [^\n]*|)\n?)*)', text, re.M)
blocks = [b.rstrip() for b in blocks]
if len(blocks) != 1 or 'react: link:packages/react' not in blocks[0]: sys.exit(1)
Path(sys.argv[2]).write_text(blocks[0] + '\n')
PY
}

check() {
    local dir=$1 expected=$2
    shift 2
    local ok=true
    if ! install "$dir" "$AUBE_BIN" "$@"; then
        echo "aube install failed: $dir (see install.log)"
        ok=false
    fi
    if ! runtime "$dir"; then
        echo "aube peer cannot resolve from consumer's real path: $dir (see runtime.log)"
        ok=false
    fi
    local lock="$dir/aube-lock.yaml"
    [[ -f "$lock" ]] || lock="$dir/pnpm-lock.yaml"
    if ! snapshot "$lock" "$dir/snapshot" || ! diff -u "$expected" "$dir/snapshot" >"$dir/snapshot.diff"; then
        echo "aube peer snapshot differs from pnpm: $dir"
        ok=false
    fi
    if [[ -f "$lock" ]] && ! diff -u "${expected%/*}/pnpm-lock.yaml" "$lock" >"$dir/lockfile.diff"; then
        echo "aube whole lockfile differs from pnpm: $dir"
        ok=false
    fi
    if [[ "$ok" == false ]]; then failed=1; else echo "aube pass: ${dir##*/}"; fi
}

main
