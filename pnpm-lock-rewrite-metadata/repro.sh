#!/bin/bash
set -euo pipefail

AUBE_BIN="${AUBE_BIN:-aube}"
PNPM_BIN="${PNPM_BIN:-pnpm}"

for cmd in "$AUBE_BIN" "$PNPM_BIN" python3 tar; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "missing required command: $cmd" >&2
        exit 2
    fi
done

if ! pnpm_version=$("$PNPM_BIN" --version); then
    echo "could not run PNPM_BIN --version" >&2
    exit 2
fi
if [[ "$pnpm_version" != 12.14.0 ]]; then
    echo "PNPM_BIN must point to real pnpm 12.14.0, got: $pnpm_version" >&2
    exit 2
fi
if ! aube_version=$("$AUBE_BIN" --version); then
    echo "could not run AUBE_BIN --version" >&2
    exit 2
fi

cd "$(dirname "$0")"
work="$PWD/.repro-work"
rm -rf "${work:?}"
mkdir -p "$work"
trap 'echo "environment/control failure at line $LINENO (see $work)" >&2; exit 2' ERR

export AUBE_STORE_DIR="$work/aube-store" AUBE_CACHE_DIR="$work/aube-cache"
export pnpm_config_store_dir="$work/pnpm-store" pnpm_config_cache_dir="$work/pnpm-cache"
export XDG_CACHE_HOME="$work/xdg-cache" XDG_DATA_HOME="$work/xdg-data"
export XDG_STATE_HOME="$work/xdg-state"

# pnpm creates the seed from scratch. The archive contains one bundled child;
# is-sorted is an unrelated, dependency-free addition.
seed="$work/seed"
mkdir -p "$seed/deps" "$work/archive/package/node_modules/is-number"
cp fixture/package.json fixture/pnpm-workspace.yaml "$seed/"
cp fixture/bundler/package.json "$work/archive/package/"
cp fixture/bundler/child/package.json "$work/archive/package/node_modules/is-number/"
tar -czf "$seed/deps/bundler.tgz" -C "$work/archive" package
(cd "$seed" && "$PNPM_BIN" install --lockfile-only --ignore-scripts >"$work/seed.log" 2>&1)
echo "pnpm $pnpm_version seed:"
python3 check-lock.py "$seed/pnpm-lock.yaml" "$seed/deps/bundler.tgz"

dir="$work/pnpm"
cp -r "$seed" "$dir"
(cd "$dir" && "$PNPM_BIN" add is-sorted@1.0.5 --save-exact --lockfile-only \
    --ignore-scripts >"$work/pnpm-add.log" 2>&1)
echo "pnpm $pnpm_version add is-sorted@1.0.5:"
python3 check-lock.py "$dir/pnpm-lock.yaml" "$dir/deps/bundler.tgz"
(cd "$dir" && "$PNPM_BIN" install --frozen-lockfile --ignore-scripts >"$work/pnpm-frozen.log" 2>&1)
echo "pnpm control: clean pnpm frozen install passed"

dir="$work/aube"
cp -r "$seed" "$dir"
if ! (cd "$dir" && "$AUBE_BIN" add is-sorted@1.0.5 >"$work/aube-add.log" 2>&1); then
    echo "aube add did not reach the metadata comparison (see $work/aube-add.log)" >&2
    exit 2
fi
failed=
echo "aube $aube_version add is-sorted@1.0.5:"
if python3 check-lock.py "$dir/pnpm-lock.yaml" "$dir/deps/bundler.tgz"; then
    :
else
    result=$?
    if [[ "$result" != 1 ]]; then
        exit 2
    fi
    failed=1
fi

# Copy only source and lockfiles so neither frozen check can reuse node_modules.
for tool in pnpm aube; do
    frozen="$work/$tool-frozen"
    mkdir -p "$frozen"
    cp "$dir/package.json" "$dir/pnpm-workspace.yaml" "$dir/pnpm-lock.yaml" "$frozen/"
    cp -r "$dir/deps" "$frozen/"
done
if (cd "$work/pnpm-frozen" && "$PNPM_BIN" install --frozen-lockfile \
    --ignore-scripts >"$work/aube-then-pnpm-frozen.log" 2>&1); then
    echo "aube rewrite: clean pnpm frozen install passed"
elif grep -q ERR_PNPM_LOCKFILE_CONFIG_MISMATCH "$work/aube-then-pnpm-frozen.log"; then
    echo "aube rewrite: pnpm frozen install rejected with ERR_PNPM_LOCKFILE_CONFIG_MISMATCH"
    failed=1
else
    echo "unexpected pnpm frozen failure (see $work/aube-then-pnpm-frozen.log)" >&2
    exit 2
fi
if (cd "$work/aube-frozen" && AUBE_STORE_DIR="$work/frozen-aube-store" \
    AUBE_CACHE_DIR="$work/frozen-aube-cache" "$AUBE_BIN" install --frozen-lockfile \
    --ignore-scripts >"$work/aube-frozen.log" 2>&1); then
    echo "aube rewrite: clean aube frozen install passed"
else
    echo "aube rewrite: clean aube frozen install failed (see $work/aube-frozen.log)" >&2
    failed=1
fi

if [[ -n "$failed" ]]; then
    echo "failed: aube add loses pnpm settings and local tarball bundle metadata" >&2
    exit 1
fi
echo "pass: aube keeps pnpm metadata and both tools accept clean frozen installs"
