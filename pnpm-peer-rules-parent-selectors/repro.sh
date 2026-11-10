#!/bin/bash
set -euo pipefail

# peerDependencyRules.allowedVersions keys that name the parent:
#   use-sync-external-store>react: "*"   (parent>peer, found peer is a prerelease)
#   ws@7>utf-8-validate: "6"             (parent@range>peer)
# under strictPeerDependencies: true. pnpm 12.14.0 installs; the control drops
# the ws rule to show pnpm needs it.

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

pnpm_dir="$work/pnpm"
cp -r fixture "$pnpm_dir"
if ! (cd "$pnpm_dir" && "$PNPM_BIN" install --ignore-scripts >"$pnpm_dir.log" 2>&1); then
    echo "control failed: pnpm $("$PNPM_BIN" --version) rejected the rules (see $pnpm_dir.log)" >&2
    exit 2
fi
echo "pnpm $("$PNPM_BIN" --version) install: ok"

no_rule="$work/pnpm-no-ws-rule"
cp -r fixture "$no_rule"
sed -i.bak '/^    ws@7>utf-8-validate:/d' "$no_rule/pnpm-workspace.yaml"
if (cd "$no_rule" && "$PNPM_BIN" install --ignore-scripts >"$no_rule.log" 2>&1); then
    echo "control failed: pnpm installed without the ws@7>utf-8-validate rule" >&2
    exit 2
fi
echo "pnpm $("$PNPM_BIN" --version) install without the ws@7>utf-8-validate rule: rejected"

status=0
run_aube() {
    local label=$1 dir=$2
    shift 2
    if (cd "$dir" && "$AUBE_BIN" install --ignore-scripts "$@" >"$dir.log" 2>&1); then
        echo "aube $label: ok"
    else
        echo "aube $label: rejected"
        grep -E 'expected peer|missing required peer' "$dir.log" | sed 's/^/    /' || true
        status=1
    fi
}

fresh="$work/aube-fresh"
cp -r fixture "$fresh"
run_aube "install (fresh resolve)" "$fresh"

frozen="$work/aube-frozen"
cp -r fixture "$frozen"
cp "$pnpm_dir/pnpm-lock.yaml" "$frozen/"
run_aube "install --frozen-lockfile (pnpm's lockfile)" "$frozen" --frozen-lockfile
if [[ $status -eq 0 ]] && ! cmp -s "$pnpm_dir/pnpm-lock.yaml" "$frozen/pnpm-lock.yaml"; then
    echo "aube install --frozen-lockfile changed pnpm-lock.yaml"
    status=1
fi

if [[ $status -ne 0 ]]; then
    echo "failed: aube $("$AUBE_BIN" --version | head -1) ignores parent-selector peerDependencyRules.allowedVersions that pnpm honors" >&2
    exit 1
fi
echo "pass: aube honors parent-selector peerDependencyRules.allowedVersions"
