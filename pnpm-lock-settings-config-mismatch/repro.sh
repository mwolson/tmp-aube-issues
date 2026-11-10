#!/bin/bash
set -euo pipefail

AUBE_BIN="${AUBE_BIN:-aube}"
PNPM_BIN="${PNPM_BIN:-pnpm}"
for cmd in "$AUBE_BIN" "$PNPM_BIN" cp grep node python3; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "missing required command: $cmd" >&2
        exit 2
    fi
done
pnpm_version=$("$PNPM_BIN" --version)
if [[ "$pnpm_version" == *aubeshim* || "$pnpm_version" != 12.* ]]; then
    echo "PNPM_BIN must point at real pnpm 12 (tested with 12.14.0)" >&2
    exit 2
fi
AUBE_BIN=$(command -v "$AUBE_BIN")
PNPM_BIN=$(command -v "$PNPM_BIN")
cd "$(dirname "$0")"
work="$PWD/.repro-work"
rm -rf "${work:?}"
mkdir -p "$work"
export AUBE_STORE_DIR="$work/aube-store" AUBE_CACHE_DIR="$work/aube-cache"
export pnpm_config_store_dir="$work/pnpm-store" pnpm_config_cache_dir="$work/pnpm-cache"
export XDG_CACHE_HOME="$work/xdg-cache" XDG_DATA_HOME="$work/xdg-data"
export XDG_STATE_HOME="$work/xdg-state"
unset CI
failed=

configure() {
    local dir=$1 key=$2 value=$3
    printf 'autoInstallPeers: false\nexcludeLinksFromLockfile: true\n' > "$dir/pnpm-workspace.yaml"
    if [[ "$key" == resolution-settings ]]; then
        printf 'lockfile:\n  includeResolutionSettings: true\nautoDedupe: %s\ndedupeInjectedDeps: %s\ndedupePeerDependents: %s\nlinkWorkspacePackages: %s\n' \
            "$value" "$value" "$value" "$value" >> "$dir/pnpm-workspace.yaml"
    else
        printf '%s: %s\n' "$key" "$value" >> "$dir/pnpm-workspace.yaml"
    fi
}

run() {
    local dir=$1 bin=$2 log=$3
    shift 3
    (cd "$dir" && "$bin" "$@" > "$log" 2>&1)
}

frozen() {
    local dir=$1 label=$2 expected=$3 dest="$work/$2-pnpm-frozen"
    mkdir -p "$dest"
    cp "$dir/package.json" "$dir/pnpm-workspace.yaml" "$dir/pnpm-lock.yaml" "$dest/"
    if run "$dest" "$PNPM_BIN" "$dest.log" install --frozen-lockfile --ignore-scripts; then
        echo "$label: pnpm frozen passes"
    elif [[ "$expected" == control ]]; then
        echo "control failed: see $dest.log" >&2
        exit 2
    elif grep -q ERR_PNPM_LOCKFILE_CONFIG_MISMATCH "$dest.log"; then
        echo "$label: pnpm rejects settings with ERR_PNPM_LOCKFILE_CONFIG_MISMATCH"
        failed=true
    else
        echo "unexpected frozen failure: see $dest.log" >&2
        exit 2
    fi
}

for key in dedupePeers peersSuffixMaxLength injectWorkspacePackages addMissingPeerTypes resolution-settings; do
    old=true
    new=false
    if [[ "$key" == peersSuffixMaxLength ]]; then
        old=80
        new=90
    fi
    seed="$work/$key-seed"
    cp -r fixture "$seed"
    configure "$seed" "$key" "$old"
    if ! run "$seed" "$PNPM_BIN" "$seed.log" install --lockfile-only --ignore-scripts; then
        echo "pnpm seed failed: see $seed.log" >&2
        exit 2
    fi
    frozen "$seed" "$key-control" control
    for phase in fresh unchanged changed; do
        dir="$work/$key-$phase"
        cp -r fixture "$dir"
        configure "$dir" "$key" "$old"
        if [[ "$phase" != fresh ]]; then
            cp "$seed/pnpm-lock.yaml" "$dir/"
        fi
        if [[ "$phase" == changed ]]; then
            configure "$dir" "$key" "$new"
        fi
        if [[ "$phase" == fresh ]]; then
            args=(install --ignore-scripts)
        else
            args=(add picocolors@1.1.1 --ignore-scripts)
        fi
        if ! run "$dir" "$AUBE_BIN" "$dir.log" "${args[@]}"; then
            echo "aube write failed before comparison: see $dir.log" >&2
            exit 2
        fi
        frozen "$dir" "$key-$phase" test
        dest="$work/$key-$phase-aube-frozen"
        mkdir -p "$dest"
        cp "$dir/package.json" "$dir/pnpm-workspace.yaml" "$dir/pnpm-lock.yaml" "$dest/"
        if ! run "$dest" "$AUBE_BIN" "$dest.log" install --frozen-lockfile --ignore-scripts; then
            echo "clean aube frozen install failed: see $dest.log" >&2
            exit 2
        fi
    done
done
echo "aube: $("$AUBE_BIN" --version | head -1); pnpm control: $pnpm_version"
if [[ -n "$failed" ]]; then
    exit 1
fi
echo "pass: fresh writes and configuration changes remain pnpm-frozen compatible"
