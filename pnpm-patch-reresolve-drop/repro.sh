#!/bin/bash
set -euo pipefail

AUBE_BIN="${AUBE_BIN:-aube}"
PNPM_BIN="${PNPM_BIN:-pnpm}"

for cmd in "$AUBE_BIN" node "$PNPM_BIN"; do
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

check_install() {
    node -e 'const pkg = require("is-odd/package.json"); const isOdd = require("is-odd"); require("is-positive"); if (pkg.version !== "3.0.1" || isOdd.patched !== "v1") process.exit(1)'
}

check_lockfile() {
    grep -q "^patchedDependencies:" pnpm-lock.yaml && grep -q "patch_hash=" pnpm-lock.yaml
}

setup
cd .repro-work
if ! "$PNPM_BIN" install --no-frozen-lockfile --ignore-scripts; then
    echo "native pnpm install failed on the drifted manifest; fix the environment and retry" >&2
    exit 2
fi
if ! check_install; then
    echo "native pnpm did not keep the is-odd patch applied across the re-resolve" >&2
    exit 2
fi
if ! check_lockfile; then
    echo "native pnpm dropped patch metadata from the rewritten lockfile" >&2
    exit 2
fi
cd ..

setup
cd .repro-work
if ! "$AUBE_BIN" install --no-frozen-lockfile --ignore-scripts --reporter append-only; then
    echo "aube install failed on the drifted manifest" >&2
    exit 1
fi

fail=0
if ! check_install; then
    echo "aube dropped the declared is-odd patch during the non-frozen re-resolve" >&2
    fail=1
fi
if ! check_lockfile; then
    echo "aube dropped pnpm-compatible patch metadata from the rewritten lockfile" >&2
    fail=1
fi
rm -rf node_modules
if ! "$PNPM_BIN" install --frozen-lockfile --ignore-scripts; then
    echo "native pnpm rejects aube's rewritten lockfile in frozen mode" >&2
    fail=1
fi

if [[ "$fail" -ne 0 ]]; then
    exit 1
fi
echo "pass: aube kept the declared patch across the non-frozen re-resolve"
