#!/bin/bash
set -euo pipefail
set -E
trap 'echo "environment/setup failed at line $LINENO" >&2; exit 2' ERR

AUBE_BIN="${AUBE_BIN:-aube}"
NPM_BIN="${NPM_BIN:-npm}"
for cmd in "$AUBE_BIN" "$NPM_BIN" node python3 cmp; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "missing required command: $cmd" >&2
        exit 2
    fi
done
AUBE_BIN=$(command -v "$AUBE_BIN")
NPM_BIN=$(command -v "$NPM_BIN")
if "$NPM_BIN" --version 2>/dev/null | grep -q aubeshim; then
    echo "NPM_BIN resolves to aubeshim; use a real npm binary" >&2
    exit 2
fi
# Resolve runtimes before isolating HOME, so mise shims cannot inherit it.
node_bin=$(node -p 'process.execPath')
python_bin=$(python3 -c 'import sys; print(sys.executable)')
PATH="$(dirname "$node_bin"):$(dirname "$python_bin"):$PATH"
export PATH
aube_version=$("$AUBE_BIN" --version)
control_version=$("$NPM_BIN" --version)
echo "aube: $aube_version; npm: $control_version; node: $(node --version)"

cd "$(dirname "$0")"
work="$PWD/.repro-work"
rm -rf "${work:?}"
mkdir -p "$work/home" "$work/tmp"
export HOME="$work/home" TMPDIR="$work/tmp"
export XDG_CACHE_HOME="$work/xdg-cache" XDG_CONFIG_HOME="$work/xdg-config"
export XDG_DATA_HOME="$work/xdg-data" XDG_STATE_HOME="$work/xdg-state"
export AUBE_STORE_DIR="$work/aube-store" AUBE_CACHE_DIR="$work/aube-cache"
export AUBE_NO_UPDATE_CHECK=1 AUBE_ADVISORY_CHECK=off AUBE_MINIMUM_RELEASE_AGE=0
export npm_config_cache="$work/npm-cache"
unset CI AUBE_CONFIG AUBE_NODE_LINKER AUBE_ENABLE_GLOBAL_VIRTUAL_STORE

clean() {
    rm -rf "${1:?}/node_modules" "${1:?}/vendor/host/node_modules"
}

runtime() {
    (cd "$1" && node -e 'console.log(require("module").createRequire(process.cwd() + "/package.json")("host"))')
}

seed() {
    local dir=$1
    mkdir -p "$dir"
    echo '{"name":"root","private":true}' > "$dir/package.json"
    (cd "$dir" && "$NPM_BIN" install --package-lock-only --ignore-scripts --no-audit --no-fund >seed.log 2>&1)
    python3 fixture.py "$dir"
}

npm_control() {
    local dir=$1
    (cd "$dir" && "$NPM_BIN" install --ignore-scripts --no-audit --no-fund >fresh.log 2>&1)
    [[ $(runtime "$dir") == "leaf ok" ]]
    node -e 'const p = require(process.argv[1]); console.log("npm vendor/host lock dependency:", p.packages["vendor/host"].dependencies.leaf)' "$dir/package-lock.json"
    clean "$dir"
    (cd "$dir" && "$NPM_BIN" ci --ignore-scripts --no-audit --no-fund >frozen.log 2>&1)
    [[ $(runtime "$dir") == "leaf ok" ]]
    echo "npm $control_version: fresh install and clean npm ci load leaf ok"
}

dir="$work/npm"
seed "$dir"
npm_control "$dir"

dir="$work/aube"
seed "$dir"
(cd "$dir" && "$AUBE_BIN" install --no-frozen-lockfile --ignore-scripts \
    --node-linker=isolated --disable-global-virtual-store >fresh.log 2>&1)
[[ $(runtime "$dir") == "leaf ok" ]]
echo "aube fresh: leaf ok"
cp "$dir/package-lock.json" "$dir/before-frozen.json"
clean "$dir"
(cd "$dir" && "$AUBE_BIN" install --frozen-lockfile --ignore-scripts \
    --node-linker=isolated --disable-global-virtual-store >frozen.log 2>&1)
cmp "$dir/before-frozen.json" "$dir/package-lock.json"
echo "aube frozen: install exited 0, lockfile unchanged"
if runtime "$dir" >"$dir/runtime.log" 2>&1; then
    [[ $(cat "$dir/runtime.log") == "leaf ok" ]]
else
    if grep -q "Cannot find module 'leaf'" "$dir/runtime.log" && grep -q MODULE_NOT_FOUND "$dir/runtime.log"; then
        echo "failed: frozen-linked vendor/host cannot require its tarball child leaf" >&2
        cat "$dir/runtime.log" >&2
        exit 1
    fi
    cat "$dir/runtime.log" >&2
    exit 2
fi
echo "pass: clean frozen install lets the linked host require leaf"
