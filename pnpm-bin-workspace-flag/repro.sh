#!/bin/bash
set -euo pipefail

if ! command -v aube >/dev/null 2>&1; then
    echo "aube is required" >&2
    exit 1
fi

pnpm_bin="${PNPM_BIN:-pnpm}"
if ! command -v "$pnpm_bin" >/dev/null 2>&1; then
    echo "pnpm is required (set PNPM_BIN to its path)" >&2
    exit 1
fi

root="$(cd "$(dirname "$0")" && pwd)"

rm -rf "$root/node_modules" "$root/packages/app/node_modules"
(cd "$root" && aube install --dir . --reporter append-only)

cd "$root/packages/app"

expected="$(cd "$root" && "$pnpm_bin" bin -w)"
explicit_root="$(aube bin -C "$root" 2>/dev/null || true)"

if [[ -z "$explicit_root" || ! -d "$explicit_root" ]]; then
    echo "failed: could not resolve workspace root bin via aube bin -C" >&2
    exit 1
fi

if [[ "$explicit_root" != "$expected" ]]; then
    echo "failed: aube bin -C root returned $explicit_root" >&2
    echo "expected pnpm bin -w: $expected" >&2
    exit 1
fi

actual="$(aube bin -w 2>/dev/null || true)"
if [[ "$actual" != "$expected" ]]; then
    echo "compat gap: aube bin -w returned ${actual:-no path}" >&2
    echo "expected pnpm bin -w: $expected" >&2
    echo "workaround: aube bin -C <workspace-root> ($explicit_root)" >&2
    exit 1
fi

echo "pass: aube bin -w matches pnpm bin -w ($actual)"
