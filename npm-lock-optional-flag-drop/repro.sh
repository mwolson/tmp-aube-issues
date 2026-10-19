#!/bin/bash
set -euo pipefail

AUBE_BIN="${AUBE_BIN:-aube}"
NPM_BIN="${NPM_BIN:-npm}"

for cmd in "$AUBE_BIN" "$NPM_BIN" node; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "missing required command: $cmd" >&2
        exit 2
    fi
done

if "$NPM_BIN" --version 2>/dev/null | grep -q aubeshim; then
    echo "NPM_BIN resolves to the aubeshim shim; point it at a real npm binary" >&2
    exit 2
fi

cd "$(dirname "$0")"
work="$PWD/.repro-work"
rm -rf "$work"
npm_version=$("$NPM_BIN" --version)

# fixture/package-lock.json comes from npm 11.19.0:
#   npm install --package-lock-only --ignore-scripts --no-audit --no-fund
# npm 10.8.2 leaves it byte-identical. esbuild's 26 platform packages are
# "optional": true, and esbuild has "hasInstallScript": true.
fresh() {
    mkdir -p "$work/$1"
    cp fixture/package.json fixture/package-lock.json "$work/$1/"
    echo "$work/$1"
}

# Count lock entries that lost a flag npm wrote in the fixture lockfile.
dropped() {
    node -e '
const before = require(process.argv[1]).packages;
const after = require(process.argv[2]).packages;
let optional = 0, install = 0;
for (const [key, entry] of Object.entries(before)) {
  if (!after[key]) continue;
  if (entry.optional && !after[key].optional) optional++;
  if (entry.hasInstallScript && !after[key].hasInstallScript) install++;
}
console.log(`optional dropped: ${optional}, hasInstallScript dropped: ${install}`);
' "$PWD/fixture/package-lock.json" "$1/package-lock.json"
}

npm_ci() {
    if (cd "$1" && "$NPM_BIN" ci --dry-run --no-audit --no-fund >"$1.ci.log" 2>&1); then
        echo "ok"
    else
        grep -m1 -o 'EBADPLATFORM.*\|notsup Unsupported platform.*' "$1.ci.log" || echo "failed"
    fi
}

dir=$(fresh npm)
(cd "$dir" && "$NPM_BIN" install is-number@7.0.0 --package-lock-only \
    --ignore-scripts --no-audit --no-fund >/dev/null 2>&1)
npm_result="$(dropped "$dir")"
echo "npm $npm_version install is-number: $npm_result; npm ci: $(npm_ci "$dir")"
if [[ "$npm_result" != "optional dropped: 0, hasInstallScript dropped: 0" ]]; then
    echo "control failed: npm itself dropped lockfile flags" >&2
    exit 2
fi

fail=0
for linker in isolated hoisted; do
    dir=$(fresh "aube-$linker")
    if ! (cd "$dir" && AUBE_NODE_LINKER=$linker "$AUBE_BIN" add is-number@7.0.0 \
        >"$dir.log" 2>&1); then
        echo "aube add failed with node-linker=$linker (see $dir.log)" >&2
        exit 2
    fi
    result="$(dropped "$dir")"
    echo "aube add is-number (node-linker=$linker): $result; npm $npm_version ci: $(npm_ci "$dir")"
    if [[ "$result" != "$npm_result" ]]; then
        fail=1
    fi
done

if ((fail)); then
    echo "failed: aube drops optional and hasInstallScript from npm lockfile entries" >&2
    exit 1
fi
echo "pass: aube keeps npm's optional and hasInstallScript lockfile flags"
