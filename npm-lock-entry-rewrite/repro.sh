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

# Keep every store and cache inside .repro-work.
export AUBE_STORE_DIR="$work/aube-store" AUBE_CACHE_DIR="$work/aube-cache"
export npm_config_cache="$work/npm-cache"

# fixture/package-lock.json comes from npm 10.8.2:
#   npm install --package-lock-only --ignore-scripts --no-audit --no-fund
# ajv@8.17.1 is the only dependency. Its entries carry "dev": true, a
# funding object with "type", and (fast-uri) a two-entry funding array.
fresh() {
    mkdir -p "$work/$1"
    cp fixture/package.json fixture/package-lock.json "$work/$1/"
    echo "$work/$1"
}

# Count fixture lock entries that the add rewrote (key order or values).
changed_entries() {
    node -e '
        const fs = require("fs");
        const before = JSON.parse(fs.readFileSync(process.argv[1])).packages;
        const after = JSON.parse(fs.readFileSync(process.argv[2])).packages;
        const changed = Object.keys(before).filter(
            (k) => k !== "" && JSON.stringify(before[k]) !== JSON.stringify(after[k]));
        console.log(changed.length + "/" + (Object.keys(before).length - 1));
    ' fixture/package-lock.json "$1/package-lock.json"
}

dir=$(fresh npm)
(cd "$dir" && "$NPM_BIN" install is-number@7.0.0 --package-lock-only \
    --ignore-scripts --no-audit --no-fund >"$dir.log" 2>&1)
npm_result=$(changed_entries "$dir")
echo "npm $npm_version install is-number: existing entries rewritten: $npm_result"
if [[ "$npm_result" != 0/* ]]; then
    echo "control failed: npm itself rewrote existing lock entries" >&2
    exit 2
fi

dir=$(fresh aube)
(cd "$dir" && "$AUBE_BIN" add is-number@7.0.0 --ignore-scripts >"$dir.log" 2>&1)
aube_result=$(changed_entries "$dir")
echo "aube $("$AUBE_BIN" --version) add is-number: existing entries rewritten: $aube_result"
node -e '
    const fs = require("fs");
    const before = JSON.parse(fs.readFileSync(process.argv[1])).packages["node_modules/fast-uri"];
    const after = JSON.parse(fs.readFileSync(process.argv[2])).packages["node_modules/fast-uri"];
    console.log("fast-uri keys before: " + Object.keys(before).join(","));
    console.log("fast-uri keys after:  " + Object.keys(after).join(","));
    console.log("fast-uri funding before: " + JSON.stringify(before.funding));
    console.log("fast-uri funding after:  " + JSON.stringify(after.funding));
' fixture/package-lock.json "$dir/package-lock.json"

if [[ "$aube_result" != 0/* ]]; then
    echo "failed: aube add rewrites existing npm lockfile entries" >&2
    exit 1
fi
echo "pass: aube add leaves existing npm lockfile entries as npm wrote them"
