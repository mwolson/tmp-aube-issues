#!/bin/bash
set -euo pipefail

if ! command -v aube >/dev/null 2>&1; then
    echo "aube is required" >&2
    exit 1
fi

rm -rf node_modules

if aube install --omit optional --ignore-scripts --reporter append-only; then
    if [[ -e node_modules/is-odd ]]; then
        echo "failed: --omit optional installed optional dependency is-odd" >&2
        exit 1
    fi

    echo "pass: aube accepted --omit optional and skipped optional dependencies"
    exit 0
fi

echo "failed: aube rejected --omit optional" >&2
exit 1
