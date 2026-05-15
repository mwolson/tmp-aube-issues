#!/bin/bash
set -euo pipefail

BUN_BIN="${BUN_BIN:-bun}"

for cmd in aube node "$BUN_BIN"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "missing required command: $cmd" >&2
        exit 2
    fi
done

cd "$(dirname "$0")"

rm -rf node_modules
"$BUN_BIN" install --frozen-lockfile
if ! node -e 'const isNumber = require("is-number"); if (isNumber(41) || !isNumber(42)) process.exit(1)'; then
    echo "native Bun did not apply patchedDependencies" >&2
    exit 2
fi

rm -rf node_modules
aube install --frozen-lockfile --ignore-scripts --reporter append-only
if ! node -e 'const isNumber = require("is-number"); if (isNumber(41) || !isNumber(42)) process.exit(1)'; then
    echo "aube did not apply Bun patchedDependencies" >&2
    exit 1
fi
