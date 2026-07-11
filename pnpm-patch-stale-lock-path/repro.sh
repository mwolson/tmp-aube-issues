#!/bin/bash
set -euo pipefail

PNPM_BIN="${PNPM_BIN:-pnpm}"

for cmd in aube node "$PNPM_BIN"; do
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

setup() {
    rm -rf .repro-work
    mkdir .repro-work
    cp -r package.json pnpm-workspace.yaml pnpm-lock.yaml patches .repro-work/
}

check() {
    node -e 'const pkg = require("is-odd/package.json"); const isOdd = require("is-odd"); if (pkg.version !== "3.0.1" || isOdd.patched !== "v1") process.exit(1)'
}

setup
cd .repro-work
if ! "$PNPM_BIN" install --no-frozen-lockfile --ignore-scripts; then
    echo "native pnpm install failed on the stale lockfile; fix the environment and retry" >&2
    exit 2
fi
if ! check; then
    echo "native pnpm did not re-resolve is-odd to 3.0.1 with the new patch applied" >&2
    exit 2
fi
cd ..

setup
cd .repro-work
if ! aube install --no-frozen-lockfile --ignore-scripts --reporter append-only; then
    echo "aube install failed on the stale lockfile patch path" >&2
    exit 1
fi
if ! check; then
    echo "aube did not re-resolve is-odd to 3.0.1 with the new patch applied" >&2
    exit 1
fi

echo "pass: aube re-resolved past the stale lockfile patch path"
