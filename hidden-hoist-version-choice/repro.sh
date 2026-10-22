#!/bin/bash
set -euo pipefail

AUBE_BIN="${AUBE_BIN:-aube}"
PNPM_BIN="${PNPM_BIN:-pnpm}"

for cmd in "$AUBE_BIN" "$PNPM_BIN" node; do
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
work="$PWD/.repro-work"
rm -rf "$work"
mkdir -p "$work"

# Keep every store and cache inside .repro-work. CI=true keeps both managers
# off their global virtual stores, so the hidden hoist lives in the project.
export CI=true
export AUBE_STORE_DIR="$work/aube-store" AUBE_CACHE_DIR="$work/aube-cache"
export pnpm_config_store_dir="$work/pnpm-store" pnpm_config_cache_dir="$work/pnpm-cache"

# fixture/package.json depends on is-even@1.0.0 and is-odd@3.0.1. The graph
# has two is-number versions:
#   is-odd@3.0.1 -> is-number@6.0.0                   (depth 1)
#   is-even@1.0.0 -> is-odd@0.1.2 -> is-number@3.0.0  (depth 2)
# is-even does not declare is-number, so require('is-number') from inside
# is-even resolves through the hidden hoist directory.
resolve_from_is_even() {
    node -e '
        const fs = require("fs");
        const from = fs.realpathSync(process.argv[1] + "/node_modules/is-even");
        const pkg = require.resolve("is-number/package.json", { paths: [from] });
        console.log(require(pkg).version);
    ' "$1"
}

dir="$work/pnpm"
cp -r fixture "$dir"
if ! (cd "$dir" && "$PNPM_BIN" install --ignore-scripts >"$dir.log" 2>&1); then
    echo "control failed: pnpm install failed (see $dir.log)" >&2
    exit 2
fi
pnpm_version=$(resolve_from_is_even "$dir")
echo "pnpm $("$PNPM_BIN" --version): node_modules/.pnpm/node_modules has $(ls "$dir/node_modules/.pnpm/node_modules" | xargs)"
echo "pnpm $("$PNPM_BIN" --version): is-even resolves undeclared is-number to $pnpm_version"
if [[ "$pnpm_version" != 6.0.0 ]]; then
    echo "control failed: pnpm did not hoist the shallowest is-number" >&2
    exit 2
fi

dir="$work/aube"
cp -r fixture "$dir"
cp "$work/pnpm/pnpm-lock.yaml" "$dir/"
if ! (cd "$dir" && "$AUBE_BIN" install --frozen-lockfile >"$dir.log" 2>&1); then
    echo "aube install --frozen-lockfile failed (see $dir.log)" >&2
    exit 2
fi
aube_version=$(resolve_from_is_even "$dir")
echo "aube $("$AUBE_BIN" --version): node_modules/.aube/node_modules has $(ls "$dir/node_modules/.aube/node_modules" | xargs)"
echo "aube $("$AUBE_BIN" --version): is-even resolves undeclared is-number to $aube_version"

if [[ "$aube_version" != "$pnpm_version" ]]; then
    echo "failed: aube hidden-hoists is-number@$aube_version where pnpm hoists is-number@$pnpm_version" >&2
    exit 1
fi
echo "pass: aube hidden-hoists the same is-number version as pnpm"
