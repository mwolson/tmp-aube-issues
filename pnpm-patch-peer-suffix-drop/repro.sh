#!/bin/bash
set -euo pipefail

# The committed pnpm-lock.yaml was written by pnpm before is-positive was added
# to package.json, so both installs below re-resolve against a drifted manifest.
# react is patched, and react-dom peers on it: pnpm records that peer as
# react-dom@19.1.0(react@19.1.0(patch_hash=...)).

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

check_peer_suffix() {
    grep -q '^  react-dom@19\.1\.0(react@19\.1\.0(patch_hash=' pnpm-lock.yaml
}

setup
cd .repro-work
if ! "$PNPM_BIN" install --no-frozen-lockfile --ignore-scripts >/dev/null; then
    echo "native pnpm install failed on the drifted manifest; fix the environment and retry" >&2
    exit 2
fi
if ! check_peer_suffix; then
    echo "native pnpm did not keep the patched peer identity; the control is invalid" >&2
    exit 2
fi
cd ..

setup
cd .repro-work
if ! "$AUBE_BIN" install --no-frozen-lockfile --ignore-scripts --reporter append-only >/dev/null; then
    echo "aube install failed on the drifted manifest" >&2
    exit 1
fi
if ! check_peer_suffix; then
    echo "aube rewrote the peer suffix without the patched peer's patch_hash:" >&2
    grep -n '^  react-dom@19\.1\.0(' pnpm-lock.yaml >&2 || true
    exit 1
fi
echo "pass: aube kept the patched peer identity across the non-frozen re-resolve"
