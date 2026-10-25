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

# Keep every store and cache inside .repro-work.
export AUBE_STORE_DIR="$work/aube-store" AUBE_CACHE_DIR="$work/aube-cache"
export pnpm_config_store_dir="$work/pnpm-store" pnpm_config_cache_dir="$work/pnpm-cache"

# pnpm 12 writes pnpm-lock.yaml as two YAML documents when package.json has
# a packageManager field: a leading one with packageManagerDependencies for
# pnpm itself, then the project lockfile.
seed="$work/seed"
mkdir -p "$seed"
cp fixture/package.json "$seed/"
if ! (cd "$seed" && "$PNPM_BIN" install --lockfile-only --ignore-scripts >"$seed.log" 2>&1); then
    echo "control failed: pnpm could not write the seed lockfile (see $seed.log)" >&2
    exit 2
fi

has_pm_document() {
    grep -q '^    packageManagerDependencies:' "$1/pnpm-lock.yaml"
}

if ! has_pm_document "$seed"; then
    echo "control failed: pnpm $("$PNPM_BIN" --version) did not write a packageManagerDependencies document" >&2
    exit 2
fi

frozen() {
    if (cd "$1" && "$PNPM_BIN" install --frozen-lockfile --ignore-scripts >"$1.frozen.log" 2>&1); then
        echo ok
    else
        echo "rejected ($(grep -m1 -o 'ERR_PNPM_[A-Z_]*' "$1.frozen.log" || echo failed))"
    fi
}

dir="$work/pnpm"
cp -r "$seed" "$dir"
(cd "$dir" && "$PNPM_BIN" add is-number@7.0.0 --lockfile-only --ignore-scripts >/dev/null 2>&1)
has_pm_document "$dir" && pnpm_doc=kept || pnpm_doc=dropped
echo "pnpm $("$PNPM_BIN" --version) add is-number: packageManagerDependencies document $pnpm_doc"
if [[ "$pnpm_doc" != kept ]]; then
    echo "control failed: pnpm dropped its own packageManagerDependencies document" >&2
    exit 2
fi

dir="$work/aube"
cp -r "$seed" "$dir"
(cd "$dir" && "$AUBE_BIN" add is-number@7.0.0 >"$dir.add.log" 2>&1)
has_pm_document "$dir" && aube_doc=kept || aube_doc=dropped
echo "aube $("$AUBE_BIN" --version) add is-number: packageManagerDependencies document $aube_doc"
aube_frozen=$(frozen "$dir")
echo "pnpm $("$PNPM_BIN" --version) install --frozen-lockfile on the aube lockfile: $aube_frozen"

if [[ "$aube_doc" != kept || "$aube_frozen" != ok ]]; then
    echo "failed: aube drops pnpm 12's packageManagerDependencies document when it rewrites pnpm-lock.yaml" >&2
    exit 1
fi
echo "pass: aube keeps pnpm 12's packageManagerDependencies document"
