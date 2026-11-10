#!/bin/bash
set -euo pipefail

# Strict peer checks (strictPeerDependencies: true) that pnpm 12.14.0 passes
# and aube fails. Three scenarios, each with pnpm as the control:
#
#   1. prerelease-in-range: react@19.0.0-rc.1 provides the peer
#      "^16.8.0 || ^17.0.0 || ^18.0.0 || ^19.0.0". No rules needed in pnpm.
#   2. parent-range-selector: allowedVersions "use-sync-external-store@1>react"
#      (parent@range>peer) forgives react@19.2.0 for a "^18" peer. Without the
#      rule pnpm rejects the install too.
#   3. workspace-shape (fixture/): "use-sync-external-store>react: '*'" with a
#      prerelease react, plus "ws@7>utf-8-validate: '6'" for a provided
#      optional peer that is out of range. Without the ws rule pnpm rejects
#      the install. Also run with --frozen-lockfile on pnpm's lockfile.

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
mkdir -p "$work"

export AUBE_STORE_DIR="$work/aube-store" AUBE_CACHE_DIR="$work/aube-cache"
export pnpm_config_store_dir="$work/pnpm-store" pnpm_config_cache_dir="$work/pnpm-cache"

pnpm_version=$("$PNPM_BIN" --version)
status=0

main() {
    scenario_prerelease_in_range
    scenario_parent_range_selector
    scenario_workspace_shape

    if [[ $status -ne 0 ]]; then
        echo "failed: aube $("$AUBE_BIN" --version | head -1) rejects strict peer installs that pnpm $pnpm_version accepts" >&2
        exit 1
    fi
    echo "pass: aube accepts the strict peer installs pnpm accepts"
}

scenario_prerelease_in_range() {
    echo "1. prerelease-in-range"
    local src="$work/s1-src"
    write_project "$src" \
        '{"react":"19.0.0-rc.1","use-sync-external-store":"1.7.0"}' \
        ''
    pnpm_accepts "$src" "$work/s1-pnpm" "install"
    aube_accepts "$src" "$work/s1-aube" "install"
}

scenario_parent_range_selector() {
    echo "2. parent-range-selector"
    local deps='{"react":"19.2.0","use-sync-external-store":"1.2.0"}'
    local with_rule="$work/s2-src" without_rule="$work/s2-src-no-rule"
    write_project "$with_rule" "$deps" \
        'use-sync-external-store@1>react: "19"'
    write_project "$without_rule" "$deps" ''
    pnpm_accepts "$with_rule" "$work/s2-pnpm" "install"
    pnpm_rejects "$without_rule" "$work/s2-pnpm-no-rule" "install without the rule"
    aube_accepts "$with_rule" "$work/s2-aube" "install"
}

scenario_workspace_shape() {
    echo "3. workspace-shape"
    local no_ws_rule="$work/s3-src-no-ws-rule"
    cp -r fixture "$no_ws_rule"
    sed -i.bak '/^    ws@7>utf-8-validate:/d' "$no_ws_rule/pnpm-workspace.yaml"
    rm -f "$no_ws_rule/pnpm-workspace.yaml.bak"
    pnpm_accepts fixture "$work/s3-pnpm" "install"
    pnpm_rejects "$no_ws_rule" "$work/s3-pnpm-no-ws-rule" "install without the ws@7>utf-8-validate rule"
    aube_accepts fixture "$work/s3-aube-fresh" "install (fresh resolve)"

    local frozen="$work/s3-aube-frozen"
    cp -r fixture "$frozen"
    cp "$work/s3-pnpm/pnpm-lock.yaml" "$frozen/"
    if run_install "$AUBE_BIN" "$frozen" --frozen-lockfile; then
        echo "   aube install --frozen-lockfile (pnpm's lockfile): ok"
        if ! cmp -s "$work/s3-pnpm/pnpm-lock.yaml" "$frozen/pnpm-lock.yaml"; then
            echo "   aube install --frozen-lockfile changed pnpm-lock.yaml"
            status=1
        fi
    else
        echo "   aube install --frozen-lockfile (pnpm's lockfile): rejected"
        show_peer_errors "$frozen.log"
        status=1
    fi
}

write_project() {
    local dir=$1 deps=$2 rule=$3
    mkdir -p "$dir"
    printf '{"name":"peer-rules-scenario","private":true,"dependencies":%s}\n' "$deps" \
        >"$dir/package.json"
    printf 'strictPeerDependencies: true\n' >"$dir/pnpm-workspace.yaml"
    if [[ -n "$rule" ]]; then
        printf '\npeerDependencyRules:\n  allowedVersions:\n    %s\n' "$rule" \
            >>"$dir/pnpm-workspace.yaml"
    fi
}

run_install() {
    local bin=$1 dir=$2
    shift 2
    (cd "$dir" && "$bin" install --ignore-scripts "$@" >"$dir.log" 2>&1)
}

pnpm_accepts() {
    local src=$1 dir=$2 label=$3
    cp -r "$src" "$dir"
    if ! run_install "$PNPM_BIN" "$dir"; then
        echo "control failed: pnpm $pnpm_version rejected the $label (see $dir.log)" >&2
        exit 2
    fi
    echo "   pnpm $pnpm_version $label: ok"
}

pnpm_rejects() {
    local src=$1 dir=$2 label=$3
    cp -r "$src" "$dir"
    if run_install "$PNPM_BIN" "$dir"; then
        echo "control failed: pnpm $pnpm_version accepted the $label (see $dir.log)" >&2
        exit 2
    fi
    echo "   pnpm $pnpm_version $label: rejected"
}

aube_accepts() {
    local src=$1 dir=$2 label=$3
    cp -r "$src" "$dir"
    if run_install "$AUBE_BIN" "$dir"; then
        echo "   aube $label: ok"
    else
        echo "   aube $label: rejected"
        show_peer_errors "$dir.log"
        status=1
    fi
}

show_peer_errors() {
    grep -E 'expected peer|missing required peer' "$1" | sed 's/^ *error: */       /' || true
}

main
