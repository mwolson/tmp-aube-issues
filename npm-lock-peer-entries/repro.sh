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
rm -rf "${work:?}"
npm_version=$("$NPM_BIN" --version)
aube_version=$("$AUBE_BIN" --version)

# Keep every store and cache inside .repro-work.
export AUBE_STORE_DIR="$work/aube-store" AUBE_CACHE_DIR="$work/aube-cache"
export npm_config_cache="$work/npm-cache"

# Both fixture lockfiles come from npm 11.6.2 (use npm 11 as NPM_BIN; npm
# 10.8.2 drops "peer": true from declared-peer's react on its own):
#   npm install --package-lock-only --ignore-scripts --no-audit --no-fund
# peer-only depends on react-dom@19.1.1 alone, so npm auto-installs its react
# peer and marks that entry "peer": true. declared-peer depends on react@19.1.1
# and react-dom@19.1.1; npm still marks react "peer": true, and react-dom's
# entry lists react only under peerDependencies.
fresh() {
    mkdir -p "$work/$1-$2"
    cp "fixture/$1/package.json" "fixture/$1/package-lock.json" "$work/$1-$2/"
    echo "$work/$1-$2"
}

# Print each fixture lock entry that the add changed or removed.
changed_entries() {
    # shellcheck disable=SC2016 # JavaScript template literals, not shell
    node -e '
        const fs = require("fs");
        const before = JSON.parse(fs.readFileSync(process.argv[1])).packages;
        const after = JSON.parse(fs.readFileSync(process.argv[2])).packages;
        for (const k of Object.keys(before)) {
            if (k === "") continue;
            if (!(k in after)) console.log(`${k}: removed`);
            else if (JSON.stringify(before[k]) !== JSON.stringify(after[k]))
                console.log(`${k}: ${JSON.stringify(after[k].dependencies ?? {})} deps, peer=${after[k].peer ?? false}`);
        }
    ' "fixture/$1/package-lock.json" "$2/package-lock.json"
}

npm_ci() {
    rm -rf "${1:?}/node_modules"
    if (cd "$1" && "$NPM_BIN" ci --ignore-scripts --no-audit --no-fund >"$1.ci.log" 2>&1); then
        echo ok
    else
        echo "rejected ($(grep -m1 -o 'Missing: .*' "$1.ci.log" || echo failed))"
    fi
}

failed=
for case in peer-only declared-peer; do
    dir=$(fresh "$case" npm)
    (cd "$dir" && "$NPM_BIN" install is-number@7.0.0 --package-lock-only \
        --ignore-scripts --no-audit --no-fund >"$dir.log" 2>&1)
    npm_changes=$(changed_entries "$case" "$dir")
    if [[ -n "$npm_changes" ]]; then
        echo "control failed: npm $npm_version changed existing $case entries:" >&2
        echo "$npm_changes" >&2
        exit 2
    fi
    echo "$case: npm $npm_version install is-number: existing entries unchanged"

    dir=$(fresh "$case" aube)
    (cd "$dir" && "$AUBE_BIN" add is-number@7.0.0 >"$dir.log" 2>&1)
    aube_changes=$(changed_entries "$case" "$dir")
    ci=$(npm_ci "$dir")
    if [[ -n "$aube_changes" ]]; then
        echo "$case: aube $aube_version add is-number changed existing entries:"
        while IFS= read -r line; do echo "  $line"; done <<<"$aube_changes"
        failed=1
    else
        echo "$case: aube $aube_version add is-number: existing entries unchanged"
    fi
    echo "$case: npm $npm_version ci on the aube lockfile: $ci"
    [[ "$ci" == ok ]] || failed=1
done

if [[ -n "$failed" ]]; then
    echo "failed: aube add drops or rewrites npm lock entries for peer dependencies" >&2
    exit 1
fi
echo "pass: aube add leaves npm lock entries for peer dependencies as npm wrote them"
