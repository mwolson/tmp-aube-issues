#!/bin/bash
set -euo pipefail

# `aube remove <pkg>` run inside a workspace member fails when that member
# also has a `workspace:` dependency. The member has no peers; the trigger is
# only the sibling dependency. pnpm 12.14.0 is the control, and a member with
# no `workspace:` dependency is the control for the trigger.

AUBE_BIN="${AUBE_BIN:-aube}"
PNPM_BIN="${PNPM_BIN:-pnpm}"

for cmd in "$AUBE_BIN" "$PNPM_BIN" cp node; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "missing required command: $cmd" >&2
        exit 2
    fi
done

if "$PNPM_BIN" --version 2>/dev/null | grep -q aubeshim; then
    echo "PNPM_BIN resolves to the aubeshim shim; point it at a real pnpm binary" >&2
    exit 2
fi
AUBE_BIN=$(command -v "$AUBE_BIN")
PNPM_BIN=$(command -v "$PNPM_BIN")

cd "$(dirname "$0")"
work="$PWD/.repro-work"
rm -rf "${work:?}"
mkdir -p "$work"

unset CI
export AUBE_STORE_DIR="$work/aube-store" AUBE_CACHE_DIR="$work/aube-cache"
export pnpm_config_store_dir="$work/pnpm-store" pnpm_config_cache_dir="$work/pnpm-cache"

status=0

main() {
    echo "aube: $("$AUBE_BIN" --version | head -1)"
    echo "pnpm control: $("$PNPM_BIN" --version)"

    # pnpm writes the starting lockfile, so both tools remove from the same state.
    cp -r fixture "$work/seed"
    if ! (cd "$work/seed" && "$PNPM_BIN" install --ignore-scripts >"$work/seed.log" 2>&1); then
        echo "control failed: pnpm install (see $work/seed.log)" >&2
        exit 2
    fi
    rm -rf "$work/seed/node_modules" "$work/seed/packages/app/node_modules"

    cp -r "$work/seed" "$work/pnpm"
    if ! (cd "$work/pnpm/packages/app" && "$PNPM_BIN" remove picocolors >"$work/pnpm-remove.log" 2>&1); then
        echo "control failed: pnpm remove picocolors (see $work/pnpm-remove.log)" >&2
        exit 2
    fi
    if ! removed "$work/pnpm"; then
        echo "control failed: pnpm left picocolors behind" >&2
        exit 2
    fi
    echo "pnpm remove picocolors in packages/app: ok"

    echo "1. member with a workspace: dependency"
    aube_remove "$work/seed" "$work/aube"
    if removed "$work/aube" && ! cmp -s "$work/pnpm/pnpm-lock.yaml" "$work/aube/pnpm-lock.yaml"; then
        echo "   aube's pnpm-lock.yaml differs from pnpm's after the removal"
        status=1
    fi

    echo "2. same member without the workspace: dependency (trigger control)"
    cp -r "$work/seed" "$work/plain-seed"
    node -e '
const fs = require("fs");
const file = process.argv[1] + "/packages/app/package.json";
const manifest = JSON.parse(fs.readFileSync(file, "utf8"));
delete manifest.dependencies.lib;
fs.writeFileSync(file, JSON.stringify(manifest, null, 2) + "\n");
' "$work/plain-seed"
    if ! (cd "$work/plain-seed" && "$PNPM_BIN" install --ignore-scripts --no-frozen-lockfile >"$work/plain-seed.log" 2>&1); then
        echo "control failed: pnpm install without the workspace dependency" >&2
        exit 2
    fi
    rm -rf "$work/plain-seed/node_modules" "$work/plain-seed/packages/app/node_modules"
    aube_remove "$work/plain-seed" "$work/aube-plain"

    if [[ $status -ne 0 ]]; then
        echo "failed: aube remove does not work in a workspace member (pnpm does)" >&2
        exit 1
    fi
    echo "pass: aube remove works in a workspace member"
}

aube_remove() {
    local src=$1 dir=$2
    cp -r "$src" "$dir"
    if ! (cd "$dir" && "$AUBE_BIN" install --ignore-scripts >"$dir-install.log" 2>&1); then
        echo "   aube install: failed (see $dir-install.log)"
        status=1
        return
    fi
    if (cd "$dir/packages/app" && "$AUBE_BIN" remove picocolors >"$dir-remove.log" 2>&1); then
        if removed "$dir"; then
            echo "   aube remove picocolors in packages/app: ok"
        else
            echo "   aube remove picocolors in packages/app: exit 0, but picocolors remains"
            status=1
        fi
    else
        echo "   aube remove picocolors in packages/app: failed"
        grep -E 'ERR_AUBE|no version of|matches range|not found' "$dir-remove.log" | sed 's/^[ ╰─▶×]*/       /' || true
        if ! grep -q '"picocolors"' "$dir/packages/app/package.json" && grep -q 'picocolors' "$dir/pnpm-lock.yaml"; then
            echo "       package.json was already edited; pnpm-lock.yaml still lists picocolors"
        fi
        status=1
    fi
}

removed() {
    ! grep -q '"picocolors"' "$1/packages/app/package.json" && ! grep -q 'picocolors' "$1/pnpm-lock.yaml"
}

main
