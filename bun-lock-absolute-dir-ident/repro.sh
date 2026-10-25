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
    echo "BUN_BIN resolves to aubeshim; use a real Bun binary" >&2
    exit 2
fi
node_bin=$(node -p 'process.execPath')
python_bin=$(python3 -c 'import sys; print(sys.executable)')
export PATH="$(dirname "$node_bin"):$(dirname "$python_bin"):$PATH"
echo "aube: $("$AUBE_BIN" --version); Bun: $("$BUN_BIN" --version); node: $(node --version)"

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

runtime() {
    (cd "$1" && node -e 'if(require("host")!=="child ok")throw Error("wrong child")')
}

python3 fixture.py "$work/bun"
(cd "$work/bun" && "$BUN_BIN" install --ignore-scripts --linker=isolated >fresh.log 2>&1)
runtime "$work/bun"
cp "$work/bun/bun.lock" "$work/bun/before-frozen.lock"
rm -rf "${work:?}/bun/node_modules"
(cd "$work/bun" && "$BUN_BIN" install --ignore-scripts --frozen-lockfile --linker=isolated >frozen.log 2>&1)
runtime "$work/bun"
cmp "$work/bun/before-frozen.lock" "$work/bun/bun.lock"
# Bun's own hoisted layout currently omits this transitive directory at runtime.
# Check lock acceptance there and runtime with its supported isolated layout.
rm -rf "${work:?}/bun/node_modules"
(cd "$work/bun" && "$BUN_BIN" install --ignore-scripts --frozen-lockfile --linker=hoisted >hoisted.log 2>&1)
echo "control: native Bun fresh/frozen isolated runtime and hoisted lock acceptance pass"

python3 fixture.py "$work/aube"
echo '{"lockfileVersion":1,"workspaces":{},"packages":{}}' > "$work/aube/bun.lock"
if ! (cd "$work/aube" && "$AUBE_BIN" install --no-frozen-lockfile --ignore-scripts --disable-global-virtual-store >fresh.log 2>&1); then
    cat "$work/aube/fresh.log" >&2
    exit 1
fi
if ! runtime "$work/aube"; then
    echo "failed: aube-authored lockfile does not load the local child" >&2
    exit 1
fi
cp "$work/aube/bun.lock" "$work/aube/before-frozen.lock"
rm -rf "${work:?}/aube/node_modules" "${work:?}/aube-store" "${work:?}/xdg-data"
if ! (cd "$work/aube" && "$AUBE_BIN" install --frozen-lockfile --ignore-scripts --disable-global-virtual-store >aube-frozen.log 2>&1); then
    cat "$work/aube/aube-frozen.log" >&2
    exit 1
fi
if ! runtime "$work/aube"; then
    echo "failed: aube-authored lockfile does not load the local child" >&2
    exit 1
fi
if ! cmp "$work/aube/before-frozen.lock" "$work/aube/bun.lock"; then
    echo "failed: frozen install changed the lockfile" >&2
    exit 1
fi
rm -rf "${work:?}/aube/node_modules"
if ! (cd "$work/aube" && "$BUN_BIN" install --ignore-scripts --frozen-lockfile --linker=hoisted >bun-hoisted.log 2>&1); then
    echo "failed: Bun rejects aube's transitive absolute directory identifier" >&2
    cat "$work/aube/bun-hoisted.log" >&2
    exit 1
fi
if ! cmp "$work/aube/before-frozen.lock" "$work/aube/bun.lock"; then
    echo "failed: frozen install changed the lockfile" >&2
    exit 1
fi
rm -rf "${work:?}/aube/node_modules"
if ! (cd "$work/aube" && "$BUN_BIN" install --ignore-scripts --frozen-lockfile --linker=isolated >bun-isolated.log 2>&1); then
    cat "$work/aube/bun-isolated.log" >&2
    exit 1
fi
if ! runtime "$work/aube"; then
    echo "failed: aube-authored lockfile does not load the local child" >&2
    exit 1
fi
if ! cmp "$work/aube/before-frozen.lock" "$work/aube/bun.lock"; then
    echo "failed: frozen install changed the lockfile" >&2
    exit 1
fi
echo "pass: Bun accepts the directory identifier and its isolated runtime loads child"
