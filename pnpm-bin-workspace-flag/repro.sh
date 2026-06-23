#!/bin/bash
set -euo pipefail

if ! command -v aube >/dev/null 2>&1; then
    echo "aube is required" >&2
    exit 1
fi

if ! command -v pnpm >/dev/null 2>&1; then
    echo "pnpm is required" >&2
    exit 1
fi

root="$(cd "$(dirname "$0")" && pwd)"

rm -rf "$root/node_modules" "$root/packages/app/node_modules"
(cd "$root" && aube install --dir . --reporter append-only)

cd "$root/packages/app"

expected="$(cd "$root" && pnpm bin -w)"
actual="$(aube bin -C "$root" 2>/dev/null || true)"

if [[ -z "$actual" || ! -d "$actual" ]]; then
    echo "failed: could not resolve workspace root bin via aube bin -C" >&2
    exit 1
fi

if [[ "$actual" != "$expected" ]]; then
    echo "failed: aube bin -C root returned $actual" >&2
    echo "expected pnpm bin -w: $expected" >&2
    exit 1
fi

if aube bin -w >/dev/null 2>&1; then
    echo "pass: aube bin -w is supported"
    exit 0
fi

echo "compat gap: pnpm bin -w works ($expected) but aube bin -w is unsupported" >&2
echo "workaround: aube bin -C <workspace-root> ($actual)" >&2
exit 1