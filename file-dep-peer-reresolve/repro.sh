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

# fixture: react comes from file:deps/react, and use-sync-external-store
# declares react as a peer dependency.
fresh() {
    mkdir -p "$work/$1"
    cp -r fixture/. "$work/$1/"
    echo "$work/$1"
}

dir=$(fresh pnpm)
(cd "$dir" && "$PNPM_BIN" install --ignore-scripts >/dev/null 2>&1)
if ! (cd "$dir" && "$PNPM_BIN" add is-number@7.0.0 --ignore-scripts >"$dir.log" 2>&1); then
    echo "control failed: pnpm add after pnpm install (see $dir.log)" >&2
    exit 2
fi
echo "pnpm $("$PNPM_BIN" --version): install, then add is-number: ok"

fail=0
run_aube_add() {
    local name=$1 dir=$2
    if (cd "$dir" && "$AUBE_BIN" add is-number@7.0.0 >"$dir.log" 2>&1); then
        echo "aube ($name): add is-number: ok"
    else
        echo "aube ($name): add is-number: $(grep -m1 -o 'ERR_AUBE_[A-Z_]*' "$dir.log" || echo failed)"
        sed -n '/╰─▶/,/help:/p' "$dir.log" | sed '$d' | sed 's/^/    /'
        fail=1
    fi
}

dir=$(fresh aube-lock)
(cd "$dir" && "$AUBE_BIN" install >/dev/null 2>&1)
run_aube_add "after aube install" "$dir"

dir=$(fresh pnpm-lock)
(cd "$dir" && "$PNPM_BIN" install --ignore-scripts >/dev/null 2>&1 && rm -rf node_modules)
(cd "$dir" && "$AUBE_BIN" install --frozen-lockfile >/dev/null 2>&1)
run_aube_add "after pnpm install" "$dir"

dir=$(fresh aube-lock-no-block)
(cd "$dir" && "$AUBE_BIN" install >/dev/null 2>&1)
export AUBE_BLOCK_EXOTIC_SUBDEPS=false
run_aube_add "AUBE_BLOCK_EXOTIC_SUBDEPS=false" "$dir"
unset AUBE_BLOCK_EXOTIC_SUBDEPS

if ((fail)); then
    echo "failed: aube cannot re-resolve once a file: dependency satisfies a peer" >&2
    exit 1
fi
echo "pass: aube re-resolves a tree whose file: dependency satisfies a peer"
