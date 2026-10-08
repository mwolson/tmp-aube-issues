#!/bin/bash
set -euo pipefail

# The committed pnpm-lock.yaml was written by pnpm 11.10.0 before @x/extra was
# added to packages/app, so both installs below update a drifted lockfile.
# pnpm records workspace packages as link: paths; aube writes their versions.

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
export CI=true

setup() {
    rm -rf .repro-work
    mkdir .repro-work
    cp -r package.json pnpm-workspace.yaml pnpm-lock.yaml packages modules .repro-work/
}

check_links() {
    local missing=0
    local line
    for line in \
        "        version: link:../extra" \
        "        version: link:../shared" \
        "      '@x/shared': link:packages/shared"; do
        if ! grep -qxF "$line" pnpm-lock.yaml; then
            echo "  missing: ${line#"${line%%[! ]*}"}" >&2
            missing=1
        fi
    done
    return "$missing"
}

pnpm_frozen() {
    rm -rf node_modules packages/*/node_modules
    "$PNPM_BIN" install --frozen-lockfile --ignore-scripts 2>&1
}

"$AUBE_BIN" --version | head -1
echo "pnpm $("$PNPM_BIN" --version)"

setup
cd .repro-work
if ! "$PNPM_BIN" install --no-frozen-lockfile --ignore-scripts >/dev/null; then
    echo "native pnpm install failed on the drifted manifest; fix the environment and retry" >&2
    exit 2
fi
if ! check_links; then
    echo "native pnpm did not write link: versions; the control is invalid" >&2
    exit 2
fi
echo "pass: pnpm writes workspace packages as link: versions"
cd ..

setup
cd .repro-work
if ! "$AUBE_BIN" install --no-frozen-lockfile --ignore-scripts --reporter append-only >/dev/null; then
    echo "aube install failed on the drifted manifest" >&2
    exit 1
fi
status=0
if ! check_links; then
    echo "fail: aube wrote workspace packages by version instead of link: path" >&2
    status=1
fi
if ! out="$(pnpm_frozen)"; then
    echo "fail: pnpm --frozen-lockfile rejects aube's lockfile:" >&2
    grep -m1 'ERR_PNPM\|Broken lockfile' <<<"$out" >&2 || echo "$out" | tail -3 >&2
    status=1
fi
if [[ "$status" -ne 0 ]]; then
    echo "--- diff from pnpm's committed lockfile ---" >&2
    diff ../pnpm-lock.yaml pnpm-lock.yaml >&2 || true
    exit 1
fi
echo "pass: aube keeps link: versions and pnpm frozen-installs its lockfile"
