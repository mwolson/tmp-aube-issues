#!/bin/bash
set -euo pipefail

AUBE_BIN="${AUBE_BIN:-aube}"
NPM_BIN="${NPM_BIN:-npm}"
for cmd in "$AUBE_BIN" "$NPM_BIN" node mktemp; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "missing required command: $cmd" >&2
        exit 2
    fi
done
if [[ "$("$NPM_BIN" --version)" != 11.6.2 ]]; then
    echo "use npm 11.6.2 as NPM_BIN (with a supported Node on PATH)" >&2
    exit 2
fi
cd "$(dirname "$0")"
mkdir -p .repro-work
work=$(mktemp -d "$PWD/.repro-work/run.XXXXXX")
export AUBE_STORE_DIR="$work/store" AUBE_CACHE_DIR="$work/cache"
export npm_config_cache="$work/npm-cache"
target='node_modules/vitefu'
extra_target=''

same_entry() {
    node -e '
        const fs = require("fs");
        const {isDeepStrictEqual} = require("util");
        const before = JSON.parse(fs.readFileSync(process.argv[1])).packages;
        const after = JSON.parse(fs.readFileSync(process.argv[2])).packages;
        let failed = false;
        for (const key of process.argv.slice(3).filter(Boolean)) {
            if (!isDeepStrictEqual(before[key], after[key])) {
                console.log(key + ": expected " + JSON.stringify(before[key]) + "; received " + JSON.stringify(after[key]));
                failed = true;
            }
        }
        if (failed) process.exit(1);
    ' fixture/package-lock.json "$1/package-lock.json" "$target" "$extra_target"
}

for tool in npm aube; do
    mkdir -p "$work/$tool"
    cp fixture/package.json fixture/package-lock.json "$work/$tool/"
done
if ! (cd "$work/npm" && "$NPM_BIN" install is-number@7.0.0 --save-exact \
    --package-lock-only --ignore-scripts --no-audit --no-fund >"$work/npm-add.log" 2>&1); then
    echo "npm control add failed; see $work/npm-add.log" >&2
    exit 2
fi
if ! same_entry "$work/npm"; then
    echo "npm control changed the target entry" >&2
    exit 2
fi
if ! (cd "$work/npm" && "$NPM_BIN" ci --ignore-scripts --no-audit --no-fund >"$work/npm-ci.log" 2>&1); then
    echo "npm control ci failed; see $work/npm-ci.log" >&2
    exit 2
fi
echo "control: npm 11.6.2 preserves the entry and ci passes"
if ! (cd "$work/aube" && "$AUBE_BIN" add is-number@7.0.0 --allow-low-downloads >"$work/aube-add.log" 2>&1); then
    echo "bug: aube add failed; see $work/aube-add.log" >&2
    exit 1
fi
failed=
same_entry "$work/aube" || failed=true
if ! (cd "$work/aube" && "$NPM_BIN" ci --ignore-scripts --no-audit --no-fund >"$work/aube-ci.log" 2>&1); then
    echo "bug: npm ci rejects aube's lockfile; see $work/aube-ci.log" >&2
    failed=true
fi
if [[ -n "$failed" ]]; then
    echo "bug: aube rewrites an existing npm entry ($("$AUBE_BIN" --version))" >&2
    exit 1
fi
echo "pass: aube preserves the entry and npm ci accepts the lockfile"
