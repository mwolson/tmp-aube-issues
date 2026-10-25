#!/bin/bash
set -euo pipefail
set -E
trap 'echo "environment/setup failed at line $LINENO" >&2; exit 2' ERR

AUBE_BIN="${AUBE_BIN:-aube}"
BUN_BIN="${BUN_BIN:-bun}"
for cmd in "$AUBE_BIN" "$BUN_BIN" node python3 cmp; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "missing required command: $cmd" >&2
        exit 2
    fi
done
AUBE_BIN=$(command -v "$AUBE_BIN")
BUN_BIN=$(command -v "$BUN_BIN")
if "$BUN_BIN" --version 2>/dev/null | grep -q aubeshim; then
    echo "BUN_BIN resolves to aubeshim; use a real bun binary" >&2
    exit 2
fi
# Resolve runtimes before isolating HOME, so mise shims cannot inherit it.
node_bin=$(node -p 'process.execPath')
python_bin=$(python3 -c 'import sys; print(sys.executable)')
PATH="$(dirname "$node_bin"):$(dirname "$python_bin"):$PATH"
export PATH
aube_version=$("$AUBE_BIN" --version)
control_version=$("$BUN_BIN" --version)
echo "aube: $aube_version; bun: $control_version; node: $(node --version)"

cd "$(dirname "$0")"
work="$PWD/.repro-work"
rm -rf "${work:?}"
mkdir -p "$work/home" "$work/tmp"
export HOME="$work/home" TMPDIR="$work/tmp"
export XDG_CACHE_HOME="$work/xdg-cache" XDG_CONFIG_HOME="$work/xdg-config"
export XDG_DATA_HOME="$work/xdg-data" XDG_STATE_HOME="$work/xdg-state"
export AUBE_STORE_DIR="$work/aube-store" AUBE_CACHE_DIR="$work/aube-cache"
export AUBE_NO_UPDATE_CHECK=1 AUBE_ADVISORY_CHECK=off AUBE_MINIMUM_RELEASE_AGE=0
export BUN_INSTALL_CACHE_DIR="$work/bun-cache"
unset CI AUBE_CONFIG AUBE_NODE_LINKER AUBE_ENABLE_GLOBAL_VIRTUAL_STORE

clean() {
    rm -rf "${1:?}/node_modules" "${1:?}/apps/app/node_modules"
}

runtime() {
    (cd "$1" && node -e 'console.log(require("module").createRequire(process.cwd() + "/apps/app/package.json")("consumer"))')
}

dir="$work/project"
python3 fixture/create.py "$dir"
(cd "$dir" && "$BUN_BIN" install --ignore-scripts >fresh.log 2>&1)
[[ $(runtime "$dir") == 19.0.0 ]]
cp "$dir/bun.lock" "$dir/native.lock"
clean "$dir"
(cd "$dir" && "$BUN_BIN" install --frozen-lockfile --ignore-scripts >native-frozen.log 2>&1)
[[ $(runtime "$dir") == 19.0.0 ]]
cmp "$dir/native.lock" "$dir/bun.lock"
echo "bun $control_version: fresh and clean frozen installs load the member's React 19.0.0"
clean "$dir"
if ! (cd "$dir" && "$AUBE_BIN" install --frozen-lockfile --ignore-scripts \
    --node-linker=isolated --disable-global-virtual-store >aube-frozen.log 2>&1); then
    cat "$dir/aube-frozen.log"
    echo "failed: aube cannot import Bun's hoisted member-relative tarball" >&2
    exit 1
fi
if ! cmp "$dir/native.lock" "$dir/bun.lock"; then
    echo "failed: aube changed the frozen lockfile" >&2
    exit 1
fi
if ! result=$(runtime "$dir"); then
    echo "failed: the member consumer cannot load its peer" >&2
    exit 1
fi
echo "aube frozen: consumer loads $result (lockfile unchanged)"
if [[ "$result" != 19.0.0 ]]; then
    echo "failed: the member consumer must load React 19.0.0" >&2
    exit 1
fi
echo "pass: native Bun lockfile imports with the member-relative tarball and peer provider"
