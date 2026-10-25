#!/bin/bash
set -euo pipefail

AUBE_BIN="${AUBE_BIN:-aube}"
PNPM_BIN="${PNPM_BIN:-pnpm}"
NPM_BIN="${NPM_BIN:-npm}"
BUN_BIN="${BUN_BIN:-bun}"
for cmd in "$AUBE_BIN" "$PNPM_BIN" "$NPM_BIN" "$BUN_BIN" node; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "missing required command: $cmd" >&2
        exit 2
    fi
done
for cmd in "$PNPM_BIN" "$NPM_BIN" "$BUN_BIN"; do
    if "$cmd" --version 2>/dev/null | grep -q aubeshim; then
        echo "control resolves to aubeshim: $cmd" >&2
        exit 2
    fi
done
cd "$(dirname "$0")"
work="$PWD/.repro-work"
rm -rf "${work:?}"
mkdir -p "$work"
export AUBE_STORE_DIR="$work/aube-store" AUBE_CACHE_DIR="$work/aube-cache"
export XDG_CACHE_HOME="$work/cache" npm_config_cache="$work/npm-cache"
export pnpm_config_store_dir="$work/pnpm-store" pnpm_config_cache_dir="$work/pnpm-cache"
export BUN_INSTALL_CACHE_DIR="$work/bun-cache" COREPACK_ENABLE_PROJECT_SPEC=0
printf 'aube: %s\npnpm: %s\nnpm: %s\nbun: %s\n' \
    "$("$AUBE_BIN" --version)" "$("$PNPM_BIN" --version)" \
    "$("$NPM_BIN" --version)" "$("$BUN_BIN" --version)"

runtime() {
    (cd "$1" && node -e 'if (require("is-number")(42) !== true) process.exit(1)')
}

# (a) Fresh relocated workspace writes must be reusable after deleting modules.
control="$work/pnpm-control"
cp -R fixture/workspace "$control"
if ! (cd "$control" && "$PNPM_BIN" install --lockfile-dir=locks --ignore-scripts \
    --no-frozen-lockfile >fresh.log 2>&1); then
    echo 'control failed: native pnpm fresh workspace install' >&2
    exit 2
fi
rm -rf "${control:?}/node_modules" "${control:?}/apps/app/node_modules"
if ! (cd "$control" && "$PNPM_BIN" install --lockfile-dir=locks --ignore-scripts \
    --frozen-lockfile >frozen.log 2>&1) || ! runtime "$control/apps/app"; then
    echo 'control failed: native pnpm clean frozen workspace install/runtime' >&2
    exit 2
fi
echo 'control: native pnpm fresh write and clean frozen workspace runtime pass'

failed=
for format in aube pnpm; do
    dir="$work/workspace-$format"
    cp -R fixture/workspace "$dir"
    echo "default-lockfile-format=$format" >"$dir/.npmrc"
    if ! (cd "$dir" && "$AUBE_BIN" install --lockfile-dir=locks --ignore-scripts \
        --no-frozen-lockfile >fresh.log 2>&1); then
        echo "(a) $format: fresh workspace install failed"
        failed=1
        continue
    fi
    cp "$dir/locks/$format-lock.yaml" "$dir/before.yaml"
    rm -rf "${dir:?}/node_modules" "${dir:?}/apps/app/node_modules"
    if (cd "$dir" && "$AUBE_BIN" install --lockfile-dir=locks --ignore-scripts \
        --frozen-lockfile >frozen.log 2>&1) && runtime "$dir/apps/app" \
        && cmp -s "$dir/before.yaml" "$dir/locks/$format-lock.yaml"; then
        echo "(a) $format: fresh write and clean frozen workspace runtime pass"
    else
        echo "(a) $format: clean frozen workspace install/runtime or byte check failed"
        failed=1
    fi
done

# (b) Native formats retain their implicit root when their lockfile is moved.
for format in npm bun; do
    dir="$work/single-$format"
    cp -R fixture/single "$dir"
    if [[ "$format" == npm ]]; then
        lock=package-lock.json
        if ! (cd "$dir" && "$NPM_BIN" install --package-lock-only --ignore-scripts \
            --no-audit --no-fund >native.log 2>&1); then
            echo 'control failed: native npm lock generation' >&2
            exit 2
        fi
    else
        lock=bun.lock
        if ! (cd "$dir" && "$BUN_BIN" install --lockfile-only --ignore-scripts >native.log 2>&1); then
            echo 'control failed: native Bun lock generation' >&2
            exit 2
        fi
    fi
    mkdir -p "$dir/locks"
    mv "$dir/$lock" "$dir/locks/$lock"
    cp "$dir/locks/$lock" "$dir/before.lock"
    if (cd "$dir" && "$AUBE_BIN" install --lockfile-dir=locks --ignore-scripts \
        --frozen-lockfile >frozen.log 2>&1) && runtime "$dir" \
        && cmp -s "$dir/before.lock" "$dir/locks/$lock"; then
        echo "(b) $format: relocated native root clean frozen install/runtime pass"
    else
        echo "(b) $format: relocated native root frozen install/runtime or byte check failed"
        failed=1
    fi
done
if [[ -n "$failed" ]]; then
    echo 'failed: relocated lockfile importer ownership rejects the current project' >&2
    exit 1
fi
echo 'pass: relocated workspace and native-format roots survive clean frozen installs'
