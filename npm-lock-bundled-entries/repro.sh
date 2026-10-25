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

npm_version=$("$NPM_BIN" --version) || exit 2
aube_version=$("$AUBE_BIN" --version) || exit 2
if [[ "$npm_version" == *aubeshim* ]]; then
    echo "NPM_BIN resolves to the aubeshim shim; point it at a real npm binary" >&2
    exit 2
fi

cd "$(dirname "$0")"
work="$PWD/.repro-work"
rm -rf "${work:?}"
export AUBE_STORE_DIR="$work/aube-store" AUBE_CACHE_DIR="$work/aube-cache"
export AUBE_GLOBAL_VIRTUAL_STORE_DIR="$work/aube-gvs"
export npm_config_cache="$work/npm-cache"

fresh() {
    mkdir -p "$work/$1-$2"
    cp "fixture/$1/package.json" "fixture/$1/package-lock.json" "$work/$1-$2/"
    echo "$work/$1-$2"
}

entry_damage() {
    node check-entries.cjs "$1" "fixture/$1/package-lock.json" "$2/package-lock.json"
}

npm_ci() {
    rm -rf "${1:?}/node_modules"
    if (cd "$1" && "$NPM_BIN" ci --ignore-scripts --no-audit --no-fund >"$1.ci.log" 2>&1); then
        echo ok
    elif grep -q 'Missing: .* from lock file' "$1.ci.log"; then
        grep -m1 -o 'Missing: .* from lock file' "$1.ci.log"
    else
        echo "npm ci failed for an unexpected reason (see $1.ci.log)" >&2
        return 2
    fi
}

failed=
for case in bundle nested; do
    dir=$(fresh "$case" npm)
    if ! (cd "$dir" && "$NPM_BIN" install is-number@7.0.0 --package-lock-only \
        --ignore-scripts --no-audit --no-fund >"$dir.log" 2>&1); then
        echo "control failed: npm could not add is-number (see $dir.log)" >&2
        exit 2
    fi
    damage=$(entry_damage "$case" "$dir") || exit 2
    ci=$(npm_ci "$dir")
    if [[ -n "$damage" || "$ci" != ok ]]; then
        echo "control failed: npm $npm_version: $case: $damage; npm ci: $ci" >&2
        exit 2
    fi
    echo "$case: npm $npm_version add: checked metadata and placements preserved; npm ci: ok"

    dir=$(fresh "$case" aube)
    if ! (cd "$dir" && "$AUBE_BIN" add is-number@7.0.0 --ignore-scripts >"$dir.log" 2>&1); then
        echo "aube add failed before checking existing entries (see $dir.log)" >&2
        exit 2
    fi
    damage=$(entry_damage "$case" "$dir") || exit 2
    ci=$(npm_ci "$dir")
    if [[ -n "$damage" ]]; then
        echo "$case: aube $aube_version add changed existing entries:"
        while IFS= read -r line; do echo "  $line"; done <<<"$damage"
        failed=1
    else
        echo "$case: aube $aube_version add: checked metadata and placements preserved"
    fi
    echo "$case: npm $npm_version ci on the aube lockfile: $ci"
    [[ "$ci" == ok ]] || failed=1
done

if [[ -n "$failed" ]]; then
    echo "failed: aube add damages existing npm bundle metadata or nested placements" >&2
    exit 1
fi
echo "pass: aube preserves existing npm entries and npm ci accepts each rewritten lockfile"
