#!/bin/bash
set -euo pipefail

if ! command -v aube >/dev/null 2>&1; then
    echo "aube is required" >&2
    exit 2
fi

if ! command -v node >/dev/null 2>&1; then
    echo "node is required" >&2
    exit 2
fi

cd "$(dirname "$0")"

# Private GVS so leftover identities cannot leak into the shared user store.
# The default global virtual store is the layout that keeps stale sibling
# links; --disable-global-virtual-store repairs them and hides the bug.
rm -rf node_modules pnpm-lock.yaml aube-lock.yaml .repro-work .repro-gvs .repro-cache
export AUBE_CACHE_DIR="$PWD/.repro-cache"
export AUBE_GLOBAL_VIRTUAL_STORE_DIR="$PWD/.repro-gvs"

echo "aube: $(aube --version 2>/dev/null | head -1)"

AUBE_NODE_LINKER=isolated aube install \
    --enable-global-virtual-store \
    --ignore-scripts \
    --reporter append-only
if ! node print-ids.js; then
    echo "setup failed: a fresh isolated install already split is-number identity" >&2
    exit 2
fi

range_pkg="$(node -e '
const path = require("path");
const { createRequire } = require("module");
const r = createRequire(path.resolve("package.json"));
process.stdout.write(path.dirname(r.resolve("to-regex-range/package.json")));
')"
range_store="$(dirname "$(dirname "$range_pkg")")"
nested="$range_store/node_modules/is-number"
if [[ ! -L "$nested" ]]; then
    echo "setup failed: expected isolated sibling link at $nested" >&2
    exit 2
fi

src_real="$(readlink -f "$nested")"
src_store="$(dirname "$(dirname "$src_real")")"
dst_store="${src_store}-stale-identity"
rm -rf "$dst_store"
cp -a "$src_store" "$dst_store"
ln -sfn "../../$(basename "$dst_store")/node_modules/is-number" "$nested"

echo "=== after retargeting the isolated sibling link ==="
if node print-ids.js; then
    echo "setup failed: retarget did not split is-number identity" >&2
    exit 2
fi

echo "=== warm aube install ==="
AUBE_NODE_LINKER=isolated aube install \
    --enable-global-virtual-store \
    --ignore-scripts \
    --reporter append-only

if node print-ids.js; then
    echo "pass: warm install repaired the stale isolated sibling identity"
    exit 0
fi

echo "failed: warm isolated install left the project importer and to-regex-range on different is-number realpaths" >&2
echo "expected: one package-root realpath after aube install, even when a GVS/isolated sibling link is stale" >&2
exit 1
