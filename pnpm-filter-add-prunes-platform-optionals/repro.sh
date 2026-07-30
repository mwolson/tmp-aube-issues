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
# --allow-low-downloads bypasses aube's post-1.35 similar-name gate on is-odd;
# without it the add is refused before the lockfile rewrite under test runs.
setup
cp .repro-baseline-lock.yaml .repro-work/pnpm-lock.yaml
cd .repro-work
if ! "$AUBE_BIN" --filter app add is-odd@3.0.1 --ignore-scripts \
    --allow-low-downloads >/dev/null 2>&1; then
    echo "aube filtered add failed" >&2
    exit 1
fi
after_aube="$(count_foreign)"

if [[ "${after_aube:-0}" -ne "$baseline" ]]; then
    echo "aube pruned foreign-platform optional deps from the lockfile ($baseline -> ${after_aube:-0})" >&2
    # Illustrate the consequence when pruning happened: a colleague on another
    # platform loses the entries their machine needs. Host-side architecture
    # overrides are unreliable as a cross-platform simulation, so the foreign
    # entry count is the authoritative assertion.
    cd ..
    rm -f .repro-baseline-lock.yaml
    exit 1
fi

cd ..
rm -f .repro-baseline-lock.yaml
echo "pass: aube kept foreign-platform optional deps across the filtered add ($baseline entries)"
