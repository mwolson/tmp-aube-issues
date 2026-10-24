#!/bin/bash
set -euo pipefail

AUBE_BIN="${AUBE_BIN:-aube}"
PNPM_BIN="${PNPM_BIN:-pnpm}"

for cmd in "$AUBE_BIN" "$PNPM_BIN" node; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "missing required command: $cmd" >&2
        exit 2
    fi
done

if "$PNPM_BIN" --version 2>/dev/null | grep -q aubeshim; then
    echo "PNPM_BIN resolves to the aubeshim shim; point it at a real pnpm binary" >&2
    exit 2
fi

if command -v root-bin-probe >/dev/null 2>&1; then
    echo "root-bin-probe is already on PATH; remove it and retry" >&2
    exit 2
fi

cd "$(dirname "$0")"
work="$PWD/.repro-work"
rm -rf "$work"
pnpm_version=$("$PNPM_BIN" --version)
aube_version=$("$AUBE_BIN" --version)

# Keep every store and cache inside .repro-work.
export AUBE_STORE_DIR="$work/aube-store" AUBE_CACHE_DIR="$work/aube-cache"
export pnpm_config_store_dir="$work/pnpm-store" pnpm_config_cache_dir="$work/pnpm-cache"

# fixture: only the workspace root depends on probe, which ships the
# root-bin-probe command. Member app runs that command from a script without
# declaring the dependency.
run_probe() {
    local pm=$1 dir="$work/$1"
    cp -r fixture/. "$dir/"
    if ! (cd "$dir" && "$2" install >"$dir.install.log" 2>&1); then
        echo "$pm install failed (see $dir.install.log)" >&2
        exit 2
    fi
    if (cd "$dir/app" && "$2" run probe >"$dir.run.log" 2>&1); then
        echo ok
    else
        echo "failed ($(grep -m1 -o 'root-bin-probe: .*' "$dir.run.log" || echo "see $dir.run.log"))"
    fi
}

mkdir -p "$work/pnpm" "$work/aube"
pnpm_result=$(run_probe pnpm "$PNPM_BIN")
echo "pnpm $pnpm_version run probe in app: $pnpm_result"
if [[ "$pnpm_result" != ok ]]; then
    echo "control failed: pnpm did not put the workspace root's node_modules/.bin on PATH" >&2
    exit 2
fi

aube_result=$(run_probe aube "$AUBE_BIN")
echo "aube $aube_version run probe in app: $aube_result"

if [[ "$aube_result" != ok ]]; then
    echo "failed: aube run in a workspace member does not put the workspace root's node_modules/.bin on PATH" >&2
    exit 1
fi
echo "pass: aube run in a workspace member finds the workspace root's commands"
