#!/bin/bash
set -euo pipefail

AUBE_BIN="${AUBE_BIN:-aube}"
PNPM_BIN="${PNPM_BIN:-pnpm}"

for cmd in "$AUBE_BIN" "$PNPM_BIN"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "missing required command: $cmd" >&2
        exit 2
    fi
done

if "$PNPM_BIN" --version 2>/dev/null | grep -q aubeshim; then
    echo "PNPM_BIN resolves to the aubeshim shim; point it at a real pnpm binary" >&2
    exit 2
fi

cd "$(dirname "$0")"
work="$PWD/.repro-work"
rm -rf "$work"
unset CI

# Keep every store and cache inside .repro-work.
export AUBE_STORE_DIR="$work/aube-store" AUBE_CACHE_DIR="$work/aube-cache"
export pnpm_config_store_dir="$work/pnpm-store" pnpm_config_cache_dir="$work/pnpm-cache"

# fixture/pnpm-lock.yaml comes from pnpm 12.14.0:
#   pnpm install --lockfile-only --ignore-scripts
fresh() {
    mkdir -p "$work/$1"
    cp fixture/package.json fixture/pnpm-lock.yaml "$work/$1/"
    echo "$work/$1"
}

# Install, delete one installed file, then run `install --force`. Prints
# whether the file came back. aube uses a project-local virtual store here so
# the deleted file is only the project's copy, matching pnpm's default layout.
force_restores() {
    local name=$1 bin=$2 dir file
    shift 2
    dir=$(fresh "$name")
    if ! (cd "$dir" && "$bin" install --frozen-lockfile "$@" >"$dir.install.log" 2>&1); then
        echo "$name: initial install failed (see $dir.install.log)" >&2
        exit 2
    fi
    file=$(cd "$dir" && realpath node_modules/is-number)/index.js
    if [[ $file != "$dir"/* ]]; then
        echo "$name: is-number resolves outside the project: $file" >&2
        exit 2
    fi
    rm "$file"
    if ! (cd "$dir" && "$bin" install --frozen-lockfile --force "$@" >"$dir.force.log" 2>&1); then
        echo "$name: install --force failed (see $dir.force.log)" >&2
        exit 2
    fi
    if [[ -f $file ]]; then
        echo "restored"
    else
        echo "missing ($(tail -1 "$dir.force.log" | sed 's/\x1b\[[0-9;]*m//g'))"
    fi
}

pnpm_result=$(force_restores pnpm "$PNPM_BIN")
echo "pnpm $("$PNPM_BIN" --version) install --force after deleting is-number/index.js: $pnpm_result"
if [[ $pnpm_result != restored ]]; then
    echo "control failed: pnpm install --force did not restore the file" >&2
    exit 2
fi

aube_result=$(force_restores aube "$AUBE_BIN" --disable-global-virtual-store)
echo "aube $("$AUBE_BIN" --version | head -1) install --force after deleting is-number/index.js: $aube_result"
if [[ $aube_result != restored ]]; then
    echo "failed: aube install --force skips the reinstall when its state looks fresh" >&2
    exit 1
fi
echo "pass: aube install --force reinstalls the project"
