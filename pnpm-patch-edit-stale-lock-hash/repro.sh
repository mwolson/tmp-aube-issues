#!/bin/bash
set -euo pipefail

# patches/ is edited in place by the scenario, so the committed pristine copy
# is materialized per run. The lockfile is created by native pnpm each run so
# the recorded patch hash is canonically pnpm's.

PNPM_BIN="${PNPM_BIN:-pnpm}"

for cmd in aube grep node "$PNPM_BIN"; do
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

PATCH=patches/@isaacs__string-locale-compare@1.1.0.patch
INSTALLED=node_modules/@isaacs/string-locale-compare/index.js

# Handles both lockfile shapes: pnpm 10's nested `hash:` field and the flat
# `'<pkg>': <hash>` form.
lock_hash() {
    awk '/^patchedDependencies:/ { in_block = 1; next }
        in_block && /^[^ ]/ { in_block = 0 }
        in_block' pnpm-lock.yaml | grep -oE '[0-9a-f]{64}' | head -1
}

rm -rf node_modules pnpm-lock.yaml aube-lock.yaml patches
cp -r pristine/patches .

if ! "$PNPM_BIN" install --ignore-scripts; then
    echo "native pnpm install failed; fix the environment and retry" >&2
    exit 2
fi
if ! grep -q 'original patch marker' "$INSTALLED"; then
    echo "native pnpm did not apply the baseline patch; fix the environment and retry" >&2
    exit 2
fi
hash_before="$(lock_hash)"
if [[ -z "$hash_before" ]]; then
    echo "could not read the patch hash from pnpm-lock.yaml; fix the repro" >&2
    exit 2
fi

if ! aube install --ignore-scripts --reporter append-only; then
    echo "aube install failed on the pristine baseline; fix the environment and retry" >&2
    exit 2
fi

sed -i.bak 's/original patch marker/revised patch marker/' "$PATCH" && rm -f "$PATCH.bak"

status=0
if CI=1 aube install --ignore-scripts --reporter append-only; then
    echo "issue: CI=1 aube install accepted a patch file that no longer matches the lockfile hash" >&2
    status=1
fi
if aube install --frozen-lockfile --ignore-scripts --reporter append-only; then
    echo "issue: aube install --frozen-lockfile accepted a patch file that no longer matches the lockfile hash" >&2
    status=1
fi

if ! aube install --ignore-scripts --reporter append-only; then
    echo "issue: plain aube install failed after the patch edit" >&2
    status=1
else
    hash_after="$(lock_hash)"
    if [[ "$hash_after" == "$hash_before" ]]; then
        echo "issue: plain aube install left the stale patch hash $hash_before in pnpm-lock.yaml" >&2
        status=1
    fi
    if grep -q 'revised patch marker' "$INSTALLED"; then
        echo "note: the revised patch content was applied to the installed package"
    else
        echo "note: the installed package still has the previous patch content"
    fi
fi

# A fresh modules dir keeps this about the lockfile check rather than pnpm
# refusing to adopt aube's node_modules layout.
echo "evidence: native pnpm --frozen-lockfile on the aube-left lockfile:"
rm -rf node_modules
if out="$("$PNPM_BIN" install --frozen-lockfile --ignore-scripts 2>&1)"; then
    echo "  pnpm accepted it"
else
    printf '%s\n' "$out" | grep -m1 'ERR_PNPM' | sed 's/^ */  /'
fi

if [[ "$status" -eq 0 ]]; then
    echo "pass: aube either rejected or re-hashed the edited patch"
fi
exit "$status"
