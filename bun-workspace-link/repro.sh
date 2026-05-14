#!/bin/bash
set -euo pipefail

if ! command -v aube >/dev/null 2>&1; then
    echo "aube is required" >&2
    exit 1
fi

rm -rf node_modules packages/app/node_modules packages/contracts/node_modules
aube install --frozen-lockfile --reporter append-only

actual="$(realpath packages/app/node_modules/@repro/contracts)"
expected="$(realpath packages/contracts)"

if [[ "$actual" == "$expected" ]]; then
    echo "bug not reproduced: workspace symlink points to $actual" >&2
    exit 1
fi

echo "reproduced: packages/app/node_modules/@repro/contracts points to $actual"
echo "expected: $expected"
