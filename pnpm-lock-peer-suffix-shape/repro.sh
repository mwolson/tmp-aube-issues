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
rm -rf "${work:?}"
pnpm_version=$("$PNPM_BIN" --version)
aube_version=$("$AUBE_BIN" --version)

# Keep every store and cache inside .repro-work.
export AUBE_STORE_DIR="$work/aube-store" AUBE_CACHE_DIR="$work/aube-cache"
export pnpm_config_store_dir="$work/pnpm-store" pnpm_config_cache_dir="$work/pnpm-cache"

# aliased-peer: ts-api-utils peers on typescript, and the root aliases
# typescript to npm:@tsc-rs/typescript@0.8.0. pnpm names the peer in the
# snapshot key by the alias target.
# out-of-range-peer: ws@7.5.11 has an optional peer utf-8-validate@^5.0.2, and
# the root provides utf-8-validate@6.0.6. pnpm links that version anyway and
# records it in the snapshot key.
# Each seed lockfile comes from pnpm; the comparison is the snapshot key after
# an unrelated add.
package_for() {
    case "$1" in
        aliased-peer) echo ts-api-utils ;;
        out-of-range-peer) echo ws ;;
    esac
}

snapshot_key() {
    awk -v pkg="$2" '/^snapshots:/{s=1; next} s && index($0, "  " pkg "@") == 1 {sub(/^  /, ""); sub(/:$/, ""); print; exit}' "$1/pnpm-lock.yaml"
}

failed=
for case in aliased-peer out-of-range-peer; do
    pkg=$(package_for "$case")
    seed="$work/$case-seed"
    mkdir -p "$seed"
    cp "fixture/$case/package.json" "$seed/"
    if ! (cd "$seed" && "$PNPM_BIN" install --lockfile-only --ignore-scripts >"$seed.log" 2>&1); then
        echo "control failed: pnpm could not write the $case seed lockfile (see $seed.log)" >&2
        exit 2
    fi

    dir="$work/$case-pnpm"
    cp -r "$seed" "$dir"
    (cd "$dir" && "$PNPM_BIN" add is-number@7.0.0 --lockfile-only --ignore-scripts >"$dir.log" 2>&1)
    pnpm_key=$(snapshot_key "$dir" "$pkg")
    echo "$case: pnpm $pnpm_version add is-number: $pnpm_key"
    if [[ "$pnpm_key" != *"("* ]]; then
        echo "control failed: pnpm wrote no peer suffix for $pkg" >&2
        exit 2
    fi

    dir="$work/$case-aube"
    cp -r "$seed" "$dir"
    (cd "$dir" && "$AUBE_BIN" add is-number@7.0.0 >"$dir.log" 2>&1)
    aube_key=$(snapshot_key "$dir" "$pkg")
    echo "$case: aube $aube_version add is-number: $aube_key"
    [[ "$aube_key" == "$pnpm_key" ]] || failed=1
done

if [[ -n "$failed" ]]; then
    echo "failed: aube writes different peer suffixes than pnpm for an aliased peer or an out-of-range optional peer" >&2
    exit 1
fi
echo "pass: aube writes the same peer suffixes as pnpm"
