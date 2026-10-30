#!/bin/bash
set -euo pipefail

AUBE_BIN="${AUBE_BIN:-aube}"
NPM_BIN="${NPM_BIN:-npm}"
for cmd in "$AUBE_BIN" "$NPM_BIN" mktemp; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "missing required command: $cmd" >&2
        exit 2
    fi
done
if [[ "$("$NPM_BIN" --version)" != 11.6.2 ]]; then
    echo "use real npm 11.6.2 as NPM_BIN (the fixture's packageManager)" >&2
    exit 2
fi

cd "$(dirname "$0")"
mkdir -p "${REPRO_WORK_DIR:-$PWD/.repro-work}"
work=$(mktemp -d "${REPRO_WORK_DIR:-$PWD/.repro-work}/run.XXXXXX")
export AUBE_STORE_DIR="$work/aube-store" AUBE_CACHE_DIR="$work/aube-cache"
export AUBE_GLOBAL_VIRTUAL_STORE_DIR="$work/aube-gvs" npm_config_cache="$work/npm-cache"
echo "aube: $("$AUBE_BIN" --version | head -n 1); npm: $("$NPM_BIN" --version)"

# Each scenario starts from a lockfile npm wrote, changes the workspace so that
# `npm ci` rejects it, and expects aube's frozen install to reject it too.
seed() {
    local dir=$1 lockfile=$2
    cp -r fixture "$dir"
    (cd "$dir" && "$NPM_BIN" install --package-lock-only --ignore-scripts --no-audit --no-fund > seed.log 2>&1) || {
        echo "npm control install failed: $dir/seed.log" >&2
        exit 2
    }
    [[ "$lockfile" == package-lock.json ]] || mv "$dir/package-lock.json" "$dir/$lockfile"
    if ! (cd "$dir" && "$AUBE_BIN" install --frozen-lockfile > control.log 2>&1); then
        echo "aube frozen install rejected the unchanged lockfile: $dir/control.log" >&2
        exit 2
    fi
    rm -rf "$dir/node_modules" "$dir"/packages/*/node_modules
}

failed=0
check() {
    local name=$1 dir=$2 lockfile=$3
    if (cd "$dir" && "$NPM_BIN" ci --ignore-scripts --no-audit --no-fund > npm-ci.log 2>&1); then
        echo "npm ci accepted the changed lockfile in $name; the scenario is invalid: $dir" >&2
        exit 2
    fi
    echo "$name: npm ci rejects $lockfile: $(grep -m1 -E 'Missing:|Invalid:' "$dir/npm-ci.log" | sed 's/^npm error //')"
    rm -rf "$dir/node_modules" "$dir"/packages/*/node_modules
    if (cd "$dir" && "$AUBE_BIN" install --frozen-lockfile > frozen.log 2>&1); then
        echo "$name: aube install --frozen-lockfile accepted it"
        failed=1
    else
        echo "$name: aube install --frozen-lockfile rejected it"
    fi
}

# A member's name changes while its folder stays.
dir="$work/renamed"
seed "$dir" package-lock.json
printf '{\n  "name": "c",\n  "version": "1.0.0"\n}\n' > "$dir/packages/b/package.json"
check "member renamed in place" "$dir" package-lock.json

# A dependency-free member joins a project that uses npm-shrinkwrap.json.
dir="$work/shrinkwrap"
seed "$dir" npm-shrinkwrap.json
mkdir -p "$dir/packages/c"
printf '{\n  "name": "c",\n  "version": "1.0.0"\n}\n' > "$dir/packages/c/package.json"
check "new member under npm-shrinkwrap.json" "$dir" npm-shrinkwrap.json

if [[ "$failed" != 0 ]]; then
    echo "failed: aube's frozen install accepts npm lockfiles that npm ci rejects (logs: $work)"
    exit 1
fi
