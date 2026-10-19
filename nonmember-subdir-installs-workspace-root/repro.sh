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

# The root has a settings-only workspace file with no packages list, and
# sub/ is a separate project below it, like a vendored checkout.
fresh() {
    mkdir -p "$work/$1"
    cp -R fixture/. "$work/$1/"
    mv "$work/$1/workspace.yaml" "$work/$1/$2"
    echo "$work/$1"
}

# Run `install` in sub/ and print where node_modules landed.
where() {
    local name=$1 bin=$2 wsfile=$3 dir
    dir=$(fresh "$name" "$wsfile")
    if ! (cd "$dir/sub" && "$bin" install >"$dir.log" 2>&1); then
        echo "$name: install failed (see $dir.log)" >&2
        exit 2
    fi
    if [[ -d $dir/sub/node_modules && ! -d $dir/node_modules ]]; then
        echo "sub"
    elif [[ -d $dir/node_modules && ! -d $dir/sub/node_modules ]]; then
        echo "root"
    else
        echo "both"
    fi
}

pnpm_result=$(where pnpm "$PNPM_BIN" pnpm-workspace.yaml)
echo "pnpm $("$PNPM_BIN" --version) install in sub/ under a root pnpm-workspace.yaml: installs $pnpm_result"
if [[ $pnpm_result != sub ]]; then
    echo "control failed: pnpm did not install sub/ on its own" >&2
    exit 2
fi

fail=0
aube_version=$("$AUBE_BIN" --version | head -1)
for wsfile in aube-workspace.yaml pnpm-workspace.yaml; do
    result=$(where "aube-${wsfile%%.*}" "$AUBE_BIN" "$wsfile")
    echo "aube $aube_version install in sub/ under a root $wsfile: installs $result"
    if [[ $result != sub ]]; then
        fail=1
    fi
done
if "$AUBE_BIN" install --help 2>&1 | grep -q -- '--ignore-workspace'; then
    echo "aube install --ignore-workspace: available"
else
    echo "aube install --ignore-workspace: not available (pnpm has it)"
fi

if ((fail)); then
    echo "failed: aube installs the ancestor workspace root instead of the non-member project" >&2
    exit 1
fi
echo "pass: aube installs the non-member project on its own"
