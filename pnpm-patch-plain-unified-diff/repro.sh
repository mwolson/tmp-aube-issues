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

check() {
    node -e 'const isNumber = require("is-number"); if (isNumber(41) || !isNumber(42)) process.exit(1)'
}

rm -rf node_modules pnpm-lock.yaml aube-lock.yaml
if ! "$PNPM_BIN" install --ignore-scripts; then
    echo "native pnpm install failed; fix the environment and retry" >&2
    exit 2
fi
if ! check; then
    echo "native pnpm did not apply the plain unified diff patch" >&2
    exit 2
fi

rm -rf node_modules pnpm-lock.yaml aube-lock.yaml
if ! aube install --ignore-scripts --reporter append-only; then
    echo "aube install failed on the plain unified diff patch" >&2
    exit 1
fi
if ! check; then
    echo "aube did not apply the plain unified diff patch" >&2
    exit 1
fi

echo "pass: aube applied the plain unified diff patch"
