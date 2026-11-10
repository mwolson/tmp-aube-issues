#!/bin/bash
set -euo pipefail

AUBE_BIN="${AUBE_BIN:-aube}"
PNPM_BIN="${PNPM_BIN:-pnpm}"
for cmd in "$AUBE_BIN" "$PNPM_BIN" diff; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "missing required command: $cmd" >&2
        exit 2
    fi
done
if ! pnpm_version=$("$PNPM_BIN" --version) || [[ "$pnpm_version" != 12.14.0 ]]; then
    echo "PNPM_BIN must point to real pnpm 12.14.0" >&2
    exit 2
fi
if ! aube_version=$("$AUBE_BIN" --version); then
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

# pnpm 12.14.0 wrote fixture/pnpm-lock.yaml with:
#   pnpm add fdir@6.5.0 picomatch@4.0.4 --save-exact --lockfile-only --ignore-scripts
#   pnpm remove picomatch --lockfile-only --ignore-scripts
# The provider is now optional-only. No workspace or autoInstallPeers setting
# is needed. A fresh fdir-only install has no provider, so cannot show the loss.
cp -r fixture "$work/pnpm"
cp -r fixture "$work/aube"
(cd "$work/pnpm" && "$PNPM_BIN" add is-number@7.0.0 --lockfile-only --ignore-scripts >"$work/pnpm-add.log" 2>&1)
if ! grep -Fq 'fdir@6.5.0(picomatch@4.0.4):' "$work/pnpm/pnpm-lock.yaml"; then
    echo "control failed: pnpm dropped the existing optional peer suffix" >&2
    exit 2
fi
(cd "$work/pnpm" && "$PNPM_BIN" install --frozen-lockfile --ignore-scripts >"$work/pnpm-frozen.log" 2>&1)
echo "pnpm $pnpm_version control: retains fdir's optional peer; frozen install passes"
if ! (cd "$work/aube" && "$AUBE_BIN" add is-number@7.0.0 >"$work/aube-add.log" 2>&1); then
    echo "aube add failed before comparison (see $work/aube-add.log)" >&2
    exit 2
fi
failed=
if diff -u "$work/pnpm/pnpm-lock.yaml" "$work/aube/pnpm-lock.yaml" >"$work/lockfile.diff"; then
    echo "aube $aube_version: lockfile identical to pnpm"
else
    echo "aube $aube_version: lockfile differs (see $work/lockfile.diff)"
    failed=1
fi
mkdir -p "$work/pnpm-after-aube" "$work/aube-frozen"
for dest in pnpm-after-aube aube-frozen; do
    cp "$work/aube/package.json" "$work/aube/pnpm-lock.yaml" "$work/$dest/"
done
if (cd "$work/pnpm-after-aube" && "$PNPM_BIN" install --frozen-lockfile --ignore-scripts >"$work/pnpm-after-aube.log" 2>&1); then
    echo "pnpm accepts aube's lockfile with --frozen-lockfile"
else
    echo "pnpm rejects aube's lockfile (see $work/pnpm-after-aube.log)"
    failed=1
fi
if (cd "$work/aube-frozen" && "$AUBE_BIN" install --frozen-lockfile --ignore-scripts >"$work/aube-frozen.log" 2>&1); then
    echo "clean aube frozen install passes"
else
    echo "clean aube frozen install fails (see $work/aube-frozen.log)"
    failed=1
fi
cp "$work/aube/pnpm-lock.yaml" "$work/first-add.yaml"
if ! (cd "$work/aube" && "$AUBE_BIN" add is-number@7.0.0 >"$work/aube-second-add.log" 2>&1); then
    echo "second aube add failed (see $work/aube-second-add.log)" >&2
    exit 2
fi
if cmp -s "$work/first-add.yaml" "$work/aube/pnpm-lock.yaml"; then
    echo "second aube add: no further churn"
else
    echo "second aube add: further churn"
    failed=1
fi
if [[ -n "$failed" ]]; then
    exit 1
fi
echo "pass: unrelated add preserves pnpm's optional-only peer binding"
