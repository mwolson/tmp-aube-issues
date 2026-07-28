#!/bin/bash
set -euo pipefail

# aube drops foreign-platform optional dependencies from the lockfile when the
# workspace sets `supportedArchitectures` containing `current`.
#
# `current` is resolved per-machine, so a lockfile written on Linux loses every
# darwin/win32 entry. The authoring machine sees nothing wrong. A colleague on
# another platform then installs from that lockfile and silently gets the wrong
# platform binary rather than a hard error, because the entry their platform
# needs is simply not in the file any more.
#
# Native pnpm keeps every platform variant in the lockfile and applies
# `supportedArchitectures` only when deciding what to place in node_modules.
#
# A filtered `add` prunes completely; a plain `install` prunes partially, which
# is why this is easy to miss.

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

FOREIGN_RE='@esbuild/(darwin|win32|freebsd|netbsd|sunos|openbsd|android)'

setup() {
    rm -rf .repro-work
    mkdir .repro-work
    cp -r package.json pnpm-workspace.yaml packages .repro-work/
}

count_foreign() {
    grep -cE "$FOREIGN_RE" pnpm-lock.yaml 2>/dev/null || true
}

# Baseline: what a native pnpm lockfile records for this workspace.
setup
cd .repro-work
if ! "$PNPM_BIN" install --ignore-scripts >/dev/null 2>&1; then
    echo "native pnpm install failed; fix the environment and retry" >&2
    exit 2
fi
baseline="$(count_foreign)"
if [[ "${baseline:-0}" -eq 0 ]]; then
    echo "expected the baseline lockfile to carry foreign-platform entries, got none" >&2
    exit 2
fi
cp pnpm-lock.yaml ../.repro-baseline-lock.yaml

# Control: native pnpm keeps them across the same filtered add.
if ! "$PNPM_BIN" --filter app add is-odd@3.0.1 --ignore-scripts >/dev/null 2>&1; then
    echo "native pnpm filtered add failed" >&2
    exit 2
fi
after_pnpm="$(count_foreign)"
if [[ "${after_pnpm:-0}" -ne "$baseline" ]]; then
    echo "native pnpm changed the foreign-platform entry count ($baseline -> $after_pnpm)" >&2
    exit 2
fi
cd ..

# Subject: the same filtered add through aube.
setup
cp .repro-baseline-lock.yaml .repro-work/pnpm-lock.yaml
cd .repro-work
if ! "$AUBE_BIN" --filter app add is-odd@3.0.1 --ignore-scripts >/dev/null 2>&1; then
    echo "aube filtered add failed" >&2
    exit 1
fi
after_aube="$(count_foreign)"

fail=0
if [[ "${after_aube:-0}" -ne "$baseline" ]]; then
    echo "aube pruned foreign-platform optional deps from the lockfile ($baseline -> ${after_aube:-0})" >&2
    fail=1
fi

# The harm is only visible from another platform: installing the pruned
# lockfile while targeting darwin silently lands the linux binary, because the
# darwin entry no longer exists to be chosen.
rm -rf node_modules packages/app/node_modules
if "$PNPM_BIN" install --frozen-lockfile --ignore-scripts \
    --config.supportedArchitectures.os=darwin \
    --config.supportedArchitectures.cpu=arm64 >/dev/null 2>&1; then
    if ls node_modules/.pnpm 2>/dev/null | grep -q '@esbuild+linux-x64' &&
        ! ls node_modules/.pnpm 2>/dev/null | grep -q '@esbuild+darwin'; then
        echo "a darwin-targeted install from the pruned lockfile placed the linux binary and no darwin binary" >&2
        fail=1
    fi
fi

cd ..
rm -f .repro-baseline-lock.yaml
if [[ "$fail" -ne 0 ]]; then
    exit 1
fi
echo "pass: aube kept foreign-platform optional deps across the filtered add"
