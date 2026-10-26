#!/bin/bash
set -euo pipefail

AUBE_BIN="${AUBE_BIN:-aube}"
BUN_BIN="${BUN_BIN:-bun}"
for cmd in "$AUBE_BIN" "$BUN_BIN" node mktemp; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "missing required command: $cmd" >&2
        exit 2
    fi
done

cd "$(dirname "$0")"
mkdir -p "${REPRO_WORK_DIR:-$PWD/.repro-work}"
work=$(mktemp -d "${REPRO_WORK_DIR:-$PWD/.repro-work}/run.XXXXXX")
export AUBE_STORE_DIR="$work/aube-store" AUBE_CACHE_DIR="$work/aube-cache"
export AUBE_GLOBAL_VIRTUAL_STORE_DIR="$work/aube-gvs" BUN_INSTALL_CACHE_DIR="$work/bun-cache"
export AUBE_MINIMUM_RELEASE_AGE=0

node registry.cjs > "$work/port" 2> "$work/registry.log" &
registry_pid=$!
trap 'kill "$registry_pid" 2>/dev/null || true' EXIT
for _ in $(seq 1 50); do
    [[ -s "$work/port" ]] && break
    sleep 0.1
done
registry="http://127.0.0.1:$(cat "$work/port")/"

setup() {
    mkdir -p "$1"
    printf '{\n  "name": "bun-lock-npm-bundled-optional-meta",\n  "version": "1.0.0",\n  "dependencies": {\n    "bundler": "1.0.0"\n  }\n}\n' > "$1/package.json"
    printf 'registry=%s\n' "$registry" > "$1/.npmrc"
    printf '[install]\nregistry = "%s"\n' "$registry" > "$1/bunfig.toml"
}

meta() {
    node -e '
        const text = require("fs").readFileSync(process.argv[1], "utf8").replace(/,(\s*[}\]])/g, "$1");
        console.log(JSON.stringify(JSON.parse(text).packages.bundler[2]));
    ' "$1/bun.lock"
}

setup "$work/bun"
(cd "$work/bun" && "$BUN_BIN" install --lockfile-only > install.log 2>&1) || {
    echo "bun control install failed: $work/bun/install.log" >&2
    exit 2
}
echo "bun $("$BUN_BIN" --version): bundler metadata $(meta "$work/bun")"

setup "$work/aube"
# An empty bun.lock tells aube which format to write.
printf '{\n  "lockfileVersion": 1,\n  "workspaces": {},\n  "packages": {}\n}\n' > "$work/aube/bun.lock"
(cd "$work/aube" && "$AUBE_BIN" install --lockfile-only > install.log 2>&1) || {
    echo "aube install failed: $work/aube/install.log" >&2
    exit 1
}
aube_meta=$(meta "$work/aube")
echo "$("$AUBE_BIN" --version | head -n 1): bundler metadata $aube_meta"

cp "$work/aube/bun.lock" "$work/aube/bun.lock.aube"
(cd "$work/aube" && "$BUN_BIN" install --lockfile-only > bun-rewrite.log 2>&1) || true
if cmp -s "$work/aube/bun.lock.aube" "$work/aube/bun.lock"; then
    echo "bun leaves aube's bun.lock unchanged"
else
    echo "bun rewrites aube's bun.lock:"
    diff "$work/aube/bun.lock.aube" "$work/aube/bun.lock" | sed 's/^/  /' || true
fi
echo "logs: $work"

if [[ "$aube_meta" == *__aube* ]]; then
    echo "failed: aube writes its internal npm bundle metadata into bun.lock" >&2
    exit 1
fi
echo "pass: bun.lock carries no aube-internal metadata"
