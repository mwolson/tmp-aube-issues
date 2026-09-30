#!/bin/bash
set -euo pipefail
trap 'echo "Unexpected setup failure; see preceding error." >&2; exit 2' ERR

AUBE_BIN="${AUBE_BIN:-aube}"
PNPM_BIN="${PNPM_BIN:-pnpm}"
for cmd in "$AUBE_BIN" "$PNPM_BIN" node python3 mktemp; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Missing required command: $cmd" >&2
        exit 2
    fi
done
AUBE_BIN="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$(command -v "$AUBE_BIN")")"
PNPM_BIN="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$(command -v "$PNPM_BIN")")"
NODE_BIN="$(command -v node)"
if [[ "${PNPM_BIN##*/}" == aubeshim || "$PNPM_BIN" == */aubeshim/shims/* ]]; then
    echo "Point PNPM_BIN at real pnpm, not the aubeshim dispatcher." >&2
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_ROOT="${REPRO_TMP_ROOT:-$SCRIPT_DIR/../tmp}"
mkdir -p "$WORK_ROOT"
WORK_ROOT="$(cd "$WORK_ROOT" && pwd)"
WORK="$(mktemp -d "$WORK_ROOT/file-dep-peer.XXXXXX")"
echo "Evidence: $WORK"
"$AUBE_BIN" --version
"$PNPM_BIN" --version

main() {
    local failed=""
    copy_fixture pnpm
    if ! install_case pnpm "$PNPM_BIN"; then
        echo "Native pnpm control failed; inspect $WORK/pnpm/install.log" >&2
        exit 2
    fi
    echo "Pass: pnpm links @x/md to the workspace @x/shared."

    copy_fixture aube-from-pnpm-lock
    cp "$WORK/pnpm/pnpm-lock.yaml" "$WORK/aube-from-pnpm-lock/"
    check_aube aube-from-pnpm-lock --frozen-lockfile || failed=1

    copy_fixture aube-fresh
    check_aube aube-fresh || failed=1

    if [[ -n "$failed" ]]; then
        echo "Reproduced: aube does not link the file: dependency to its workspace peer."
        exit 1
    fi
}

copy_fixture() {
    mkdir -p "$WORK/$1"
    cp -R "$SCRIPT_DIR/fixture/." "$WORK/$1/"
}

check_aube() {
    local name="$1"
    shift
    if ! install_case "$name" "$AUBE_BIN" "$@"; then
        if grep -qE "^(dangling|require)" "$WORK/$name/result.log"; then
            echo "Fail: $name"
            sed 's/^/    /' "$WORK/$name/result.log"
            return 1
        fi
        echo "Unexpected aube failure for $name; inspect $WORK/$name" >&2
        exit 2
    fi
    echo "Pass: $name"
}

install_case() {
    local name="$1"
    local manager="$2"
    shift 2
    local project="$WORK/$name"
    mkdir -p "$WORK/$name-state"/{home,cache,config,data,state}
    if ! (
        cd "$project"
        env -i PATH="$(dirname "$NODE_BIN"):$PATH" CI=1 NO_COLOR=1 \
            HOME="$WORK/$name-state/home" XDG_CACHE_HOME="$WORK/$name-state/cache" \
            XDG_CONFIG_HOME="$WORK/$name-state/config" XDG_DATA_HOME="$WORK/$name-state/data" \
            XDG_STATE_HOME="$WORK/$name-state/state" \
            "$manager" install --ignore-scripts "$@"
    ) >"$project/install.log" 2>&1; then
        echo "install failed" >"$project/result.log"
        return 2
    fi
    (cd "$project/apps/app" && "$NODE_BIN" - "$project" >"$project/result.log" 2>&1) <<'JS'
const fs = require('node:fs');
const path = require('node:path');
const root = process.argv[2];
const md = fs.realpathSync(path.join(root, 'apps/app/node_modules/@x/md'));
const link = path.join(md, '..', 'shared');
if (fs.lstatSync(link, { throwIfNoEntry: false })?.isSymbolicLink() && !fs.existsSync(link)) {
  console.log(`dangling: ${path.relative(root, link)} -> ${fs.readlinkSync(link)}`);
  process.exit(1);
}
try {
  const value = require('@x/md');
  if (value !== 'shared') throw new Error(`unexpected value ${value}`);
} catch (error) {
  console.log(`require('@x/md') failed: ${error.code ?? error.message}`);
  process.exit(1);
}
JS
}

main
