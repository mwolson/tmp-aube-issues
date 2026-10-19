#!/bin/bash
set -euo pipefail

AUBE_BIN="${AUBE_BIN:-aube}"
PNPM_BIN="${PNPM_BIN:-pnpm}"

for cmd in "$AUBE_BIN" "$PNPM_BIN"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "missing required command: $cmd" >&2
        exit 2
    fi
done

if "$PNPM_BIN" --version 2>/dev/null | grep -q aubeshim; then
    echo "PNPM_BIN resolves to the aubeshim shim; point it at a real pnpm binary" >&2
    exit 2
fi

cd "$(dirname "$0")"
work="$PWD/.repro-work"
rm -rf "$work"
unset CI

# Keep every store and cache inside .repro-work.
export AUBE_STORE_DIR="$work/aube-store" AUBE_CACHE_DIR="$work/aube-cache"
export pnpm_config_store_dir="$work/pnpm-store" pnpm_config_cache_dir="$work/pnpm-cache"

# fixture/pnpm-lock.yaml comes from pnpm 12.14.0:
#   pnpm install --lockfile-only --ignore-scripts
# fixture/package.stale.json adds kind-of, which the lockfile lacks. A plain
# `install` updates the lockfile locally but fails in CI, where the default
# becomes --frozen-lockfile.
fresh() {
    mkdir -p "$work/$1"
    cp fixture/package.stale.json "$work/$1/package.json"
    cp fixture/pnpm-lock.yaml "$work/$1/"
    echo "$work/$1"
}

# Prints "local" when `install` updates the stale lockfile, "ci" when it
# refuses with the CI default of --frozen-lockfile.
mode() {
    local name=$1 bin=$2 dir
    shift 2
    dir=$(fresh "$name")
    if (cd "$dir" && env "$@" "$bin" install >"$dir.log" 2>&1); then
        echo "local"
    else
        echo "ci"
    fi
}

pnpm_empty=$(mode pnpm-empty "$PNPM_BIN" CI=)
pnpm_one=$(mode pnpm-one "$PNPM_BIN" CI=1)
echo "pnpm $("$PNPM_BIN" --version) install with a stale lockfile: CI='' -> $pnpm_empty, CI=1 -> $pnpm_one"
if [[ $pnpm_empty != local || $pnpm_one != ci ]]; then
    echo "control failed: pnpm did not treat CI='' as local and CI=1 as CI" >&2
    exit 2
fi

aube_unset=$(mode aube-unset "$AUBE_BIN" -u CI)
aube_empty=$(mode aube-empty "$AUBE_BIN" CI=)
echo "aube $("$AUBE_BIN" --version | head -1) install with a stale lockfile: CI unset -> $aube_unset, CI='' -> $aube_empty"
if [[ $aube_unset != local ]]; then
    echo "control failed: aube refused the stale lockfile with CI unset" >&2
    exit 2
fi
if [[ $aube_empty != local ]]; then
    echo "failed: aube treats an empty CI variable as CI" >&2
    exit 1
fi
echo "pass: aube treats an empty CI variable as not CI"
