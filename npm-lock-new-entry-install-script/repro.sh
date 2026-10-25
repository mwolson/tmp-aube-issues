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
    mkdir -p "$work/$1"
    cp fixture/package.json fixture/package-lock.json "$work/$1/"
    echo "$work/$1"
}

install_script_flag() {
    node -e '
        const lock = JSON.parse(require("fs").readFileSync(process.argv[1]));
        const entry = lock.packages["node_modules/core-js"];
        console.log(entry ? String(entry.hasInstallScript === true) : "missing");
    ' "$1/package-lock.json"
}

ci_runs_postinstall() {
    rm -rf "${1:?}/node_modules"
    if ! (cd "$1" && "$NPM_BIN" ci --ignore-scripts=false --no-audit --no-fund \
        --loglevel info >"$1.ci.log" 2>&1); then
        echo "npm ci failed before checking postinstall (see $1.ci.log)" >&2
        return 2
    elif grep -q 'run core-js@3.46.0 postinstall' "$1.ci.log"; then
        echo yes
    else
        echo no
    fi
}

dir=$(fresh npm)
if ! (cd "$dir" && "$NPM_BIN" install core-js@3.46.0 --package-lock-only \
    --ignore-scripts --no-audit --no-fund >"$dir.log" 2>&1); then
    echo "control failed: npm could not add core-js (see $dir.log)" >&2
    exit 2
fi
npm_flag=$(install_script_flag "$dir") || exit 2
npm_ci=$(ci_runs_postinstall "$dir")
echo "npm $npm_version install core-js: hasInstallScript=$npm_flag, npm ci runs postinstall: $npm_ci"
if [[ "$npm_flag" != true || "$npm_ci" != yes ]]; then
    echo "control failed: npm did not flag or run core-js's postinstall" >&2
    exit 2
fi

dir=$(fresh aube)
if ! (cd "$dir" && "$AUBE_BIN" add core-js@3.46.0 --ignore-scripts >"$dir.log" 2>&1); then
    echo "aube add failed before checking lockfile metadata (see $dir.log)" >&2
    exit 2
fi
aube_flag=$(install_script_flag "$dir") || exit 2
aube_ci=$(ci_runs_postinstall "$dir")
echo "aube $aube_version add core-js: hasInstallScript=$aube_flag, npm ci runs postinstall: $aube_ci"

if [[ "$aube_flag" != true || "$aube_ci" != yes ]]; then
    echo "failed: aube writes new npm lock entries without hasInstallScript, so npm ci skips their install scripts" >&2
    exit 1
fi
echo "pass: aube records hasInstallScript on new npm lock entries"
