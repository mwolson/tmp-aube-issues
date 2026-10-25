#!/bin/bash
set -euo pipefail
set -E
trap 'echo "environment/setup failed at line $LINENO" >&2; exit 2' ERR

AUBE_BIN="${AUBE_BIN:-aube}"
NPM_BIN="${NPM_BIN:-npm}"
for cmd in "$AUBE_BIN" "$NPM_BIN" node cmp; do
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
node_bin=$(node -p 'process.execPath')
export PATH="$(dirname "$node_bin"):$PATH"
echo "aube: $("$AUBE_BIN" --version); npm: $("$NPM_BIN" --version); node: $(node --version)"

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

seed() {
    local dir=$1
    mkdir -p "$dir"
    cp -R fixture/child "$dir/child"
    node -e 'const fs=require("fs"),p=process.argv[1]; fs.writeFileSync(p+"/package.json",JSON.stringify({name:"root",private:true,dependencies:{child:"file:"+p+"/child"}}))' "$dir"
    echo '{"lockfileVersion":3,"requires":true,"packages":{}}' > "$dir/package-lock.json"
}

runtime() {
    (cd "$1" && node -e 'if(require("child")!=="child ok")throw Error("wrong child")')
}

seed "$work/npm"
(cd "$work/npm" && "$NPM_BIN" install --ignore-scripts --no-audit --no-fund >fresh.log 2>&1)
runtime "$work/npm"
cp "$work/npm/package-lock.json" "$work/npm/before-ci.json"
rm -rf "${work:?}/npm/node_modules"
(cd "$work/npm" && "$NPM_BIN" ci --ignore-scripts --no-audit --no-fund >frozen.log 2>&1)
runtime "$work/npm"
cmp "$work/npm/before-ci.json" "$work/npm/package-lock.json"
echo "control: npm fresh and clean ci pass"

seed "$work/aube"
if ! (cd "$work/aube" && "$AUBE_BIN" install --no-frozen-lockfile --ignore-scripts --disable-global-virtual-store >fresh.log 2>&1); then
    cat "$work/aube/fresh.log" >&2
    exit 1
fi
if ! runtime "$work/aube"; then
    echo "failed: aube-authored lockfile does not load the local child" >&2
    exit 1
fi
cp "$work/aube/package-lock.json" "$work/aube/before-frozen.json"
rm -rf "${work:?}/aube/node_modules" "${work:?}/aube-store" "${work:?}/xdg-data"
if ! (cd "$work/aube" && "$AUBE_BIN" install --frozen-lockfile --ignore-scripts --disable-global-virtual-store >aube-frozen.log 2>&1); then
    cat "$work/aube/aube-frozen.log" >&2
    exit 1
fi
if ! runtime "$work/aube"; then
    echo "failed: aube-authored lockfile does not load the local child" >&2
    exit 1
fi
if ! cmp "$work/aube/before-frozen.json" "$work/aube/package-lock.json"; then
    echo "failed: frozen install changed the lockfile" >&2
    exit 1
fi
rm -rf "${work:?}/aube/node_modules"
if ! (cd "$work/aube" && "$NPM_BIN" ci --ignore-scripts --no-audit --no-fund >npm-ci.log 2>&1); then
    echo "failed: npm ci rejects aube's absolute-directory lockfile" >&2
    cat "$work/aube/npm-ci.log" >&2
    exit 1
fi
if ! runtime "$work/aube"; then
    echo "failed: aube-authored lockfile does not load the local child" >&2
    exit 1
fi
if ! cmp "$work/aube/before-frozen.json" "$work/aube/package-lock.json"; then
    echo "failed: frozen install changed the lockfile" >&2
    exit 1
fi
if ! node -e 'const p=require(process.argv[1]).packages;if(!p.child||p["node_modules/child"].resolved!=="child"||p["node_modules/child"].link!==true)process.exit(1)' "$work/aube/package-lock.json"; then
    echo "failed: directory target differs from npm's relative link shape" >&2
    exit 1
fi
echo "pass: aube writes a relative directory target that npm ci accepts"
