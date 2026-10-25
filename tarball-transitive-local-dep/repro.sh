#!/bin/bash
set -euo pipefail

AUBE_BIN="${AUBE_BIN:-aube}"
PNPM_BIN="${PNPM_BIN:-pnpm}"
for cmd in "$AUBE_BIN" "$PNPM_BIN" node tar cmp; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "missing required command: $cmd" >&2
        exit 2
    fi
done
if "$PNPM_BIN" --version 2>/dev/null | grep -q aubeshim; then
    echo "PNPM_BIN resolves to aubeshim; use a real pnpm binary" >&2
    exit 2
fi

cd "$(dirname "$0")"
work="$PWD/.repro-work"
rm -rf "${work:?}"
mkdir -p "$work/assets" "$work/package"
export AUBE_STORE_DIR="$work/aube-store" AUBE_CACHE_DIR="$work/aube-cache"
export XDG_DATA_HOME="$work/data" XDG_CACHE_HOME="$work/cache"
export pnpm_config_store_dir="$work/pnpm-store" pnpm_config_cache_dir="$work/pnpm-cache"
export npm_config_cache="$work/npm-cache" BUN_INSTALL_CACHE_DIR="$work/bun-cache"

cp fixture/child/* "$work/package/"
tar -czf "$work/assets/child.tgz" -C "$work" package
cp fixture/host/* "$work/package/"
node -e '
    const fs = require("fs");
    const file = process.argv[1], pkg = JSON.parse(fs.readFileSync(file));
    pkg.dependencies.child = "file:" + process.argv[2];
    fs.writeFileSync(file, JSON.stringify(pkg));
' "$work/package/package.json" "$work/assets/child.tgz"
tar -czf "$work/assets/host.tgz" -C "$work" package

runtime() {
    (cd "$1" && node -e "if (require('host') !== 'child ok') process.exit(1)")
}

for tool in pnpm aube; do
    dir="$work/$tool"
    mkdir -p "$dir"
    cp fixture/package.json "$dir/"
    printf 'block-exotic-subdeps=false\nminimum-release-age=0\n' > "$dir/.npmrc"
    if [[ "$tool" == pnpm ]]; then
        binary="$PNPM_BIN"
    else
        binary="$AUBE_BIN"
    fi
    echo "$tool: $("$binary" --version)"
    if ! (cd "$dir" && "$binary" install --ignore-scripts > "$dir.fresh.log" 2>&1); then
        echo "$tool fresh install failed (see $dir.fresh.log)" >&2
        [[ "$tool" == aube ]] && exit 1
        exit 2
    fi
    if ! runtime "$dir"; then
        echo "$tool could not load host's child" >&2
        [[ "$tool" == aube ]] && exit 1
        exit 2
    fi
    lock=aube-lock.yaml
    [[ "$tool" == pnpm ]] && lock=pnpm-lock.yaml
    cp "$dir/$lock" "$dir.before.lock"
    rm -rf "${dir:?}/node_modules"
    if ! (cd "$dir" && "$binary" install --frozen-lockfile --ignore-scripts > "$dir.frozen.log" 2>&1) || ! runtime "$dir" || ! cmp -s "$dir/$lock" "$dir.before.lock"; then
        echo "$tool clean frozen install failed (see $dir.frozen.log)" >&2
        [[ "$tool" == aube ]] && exit 1
        exit 2
    fi
    echo "$tool: fresh and clean frozen installs load child; lockfile unchanged"
done
echo 'pass: a tarball parent resolves its absolute file: child'
