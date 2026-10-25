#!/bin/bash
set -euo pipefail

AUBE_BIN="${AUBE_BIN:-aube}"
NPM_OLD_BIN="${NPM_OLD_BIN:-${NPM_BIN:-npm}}"
NPM_NEW_BIN="${NPM_NEW_BIN:-npm}"
for cmd in "$AUBE_BIN" "$NPM_OLD_BIN" "$NPM_NEW_BIN" node mktemp; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "missing required command: $cmd" >&2
        exit 2
    fi
done
if [[ "$("$NPM_OLD_BIN" --version)" != 11.6.2 || "$("$NPM_NEW_BIN" --version)" != 11.20.0 ]]; then
    echo "controls require real npm 11.6.2 (NPM_OLD_BIN) and 11.20.0 (NPM_NEW_BIN)" >&2
    exit 2
fi
if ! node -e 'process.exit(process.platform === "linux" && process.arch === "x64" && process.report.getReport().header.glibcVersionRuntime ? 0 : 1)'; then
    echo "this case requires Linux x64 with glibc" >&2
    exit 2
fi

cd "$(dirname "$0")"
mkdir -p "${REPRO_WORK_DIR:-$PWD/.repro-work}"
work=$(mktemp -d "${REPRO_WORK_DIR:-$PWD/.repro-work}/run.XXXXXX")
export AUBE_STORE_DIR="$work/aube-store" AUBE_CACHE_DIR="$work/aube-cache"
export AUBE_GLOBAL_VIRTUAL_STORE_DIR="$work/aube-gvs" npm_config_cache="$work/npm-cache"
aube_version=$("$AUBE_BIN" --version) || exit 2
package=@rollup/rollup-linux-x64-gnu@4.53.3

libc_value() {
    node -e '
        const fs = require("fs");
        const entry = JSON.parse(fs.readFileSync(process.argv[1])).packages["node_modules/@rollup/rollup-linux-x64-gnu"];
        if (!entry) process.exit(2);
        console.log(Object.hasOwn(entry, "libc") ? JSON.stringify(entry.libc) : "absent");
    ' "$1/package-lock.json"
}

failed=0
for version in 11.6.2 11.20.0; do
    npm_bin=$NPM_OLD_BIN
    expected=absent
    if [[ "$version" == 11.20.0 ]]; then
        npm_bin=$NPM_NEW_BIN
        expected='["glibc"]'
    fi
    for manager in npm aube; do
        dir="$work/$version-$manager"
        mkdir -p "$dir"
        cp "fixture/npm-$version/package.json" "fixture/npm-$version/package-lock.json" "$dir/"
        if [[ "$manager" == npm ]]; then
            if ! (cd "$dir" && "$npm_bin" install "$package" --package-lock-only \
                --ignore-scripts --no-audit --no-fund > add.log 2>&1); then
                echo "npm $version control add failed: $dir/add.log" >&2
                exit 2
            fi
        elif ! (cd "$dir" && "$AUBE_BIN" add "$package" --ignore-scripts > add.log 2>&1); then
            echo "aube add failed: $dir/add.log" >&2
            exit 2
        fi
        actual=$(libc_value "$dir") || exit 2
        if (cd "$dir" && "$npm_bin" ci --ignore-scripts --no-audit --no-fund > ci.log 2>&1); then
            ci=pass
        else
            ci=FAIL
        fi
        echo "$manager (npm $version fixture): new libc=$actual; npm ci=$ci"
        if [[ "$manager" == npm && ( "$actual" != "$expected" || "$ci" != pass ) ]]; then
            echo "npm control failed: $dir" >&2
            exit 2
        elif [[ "$actual" != "$expected" || "$ci" != pass ]]; then
            failed=1
        fi
    done
done
echo "aube: $aube_version; logs: $work"
if ((failed)); then
    echo "failed: new libc metadata differs from the project's npm" >&2
    exit 1
fi
echo "pass: new libc metadata matches both npm controls, and npm ci accepts both lockfiles"
