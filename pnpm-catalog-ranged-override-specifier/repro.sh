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
rm -rf "$work"

# Keep every store and cache inside .repro-work.
export AUBE_STORE_DIR="$work/aube-store" AUBE_CACHE_DIR="$work/aube-cache"
export pnpm_config_store_dir="$work/pnpm-store" pnpm_config_cache_dir="$work/pnpm-cache"

# fixture/pnpm-workspace.yaml catalogs is-odd and overrides `is-odd@^3` back
# to the catalog. The seed lockfile comes from pnpm for package.stale.json,
# which has no dependencies; package.json then adds `"is-odd": "catalog:"`.
seed="$work/seed"
mkdir -p "$seed"
cp fixture/pnpm-workspace.yaml "$seed/"
cp fixture/package.stale.json "$seed/package.json"
if ! (cd "$seed" && "$PNPM_BIN" install --lockfile-only --ignore-scripts >"$seed.log" 2>&1); then
    echo "control failed: pnpm could not write the seed lockfile (see $seed.log)" >&2
    exit 2
fi

fresh() {
    cp -r "$seed" "$work/$1"
    cp fixture/package.json "$work/$1/"
    echo "$work/$1"
}

specifier() {
    awk '/^importers:/{i=1} i && /^      is-odd:/{getline; sub(/^ *specifier: */, ""); print; exit}' "$1/pnpm-lock.yaml"
}

dir=$(fresh pnpm)
(cd "$dir" && "$PNPM_BIN" install --lockfile-only --ignore-scripts >/dev/null 2>&1)
pnpm_spec=$(specifier "$dir")
echo "pnpm $("$PNPM_BIN" --version) install --lockfile-only: is-odd specifier $pnpm_spec"
if [[ "$pnpm_spec" != "'catalog:'" ]]; then
    echo "control failed: pnpm did not keep the catalog: specifier" >&2
    exit 2
fi

dir=$(fresh aube)
(cd "$dir" && "$AUBE_BIN" install --lockfile-only >/dev/null 2>&1)
aube_spec=$(specifier "$dir")
echo "aube $("$AUBE_BIN" --version) install --lockfile-only: is-odd specifier $aube_spec"

if (cd "$dir" && "$PNPM_BIN" install --frozen-lockfile --ignore-scripts >"$dir.frozen.log" 2>&1); then
    frozen=ok
else
    frozen="rejected ($(grep -m1 -o 'ERR_PNPM_[A-Z_]*' "$dir.frozen.log" || echo failed))"
fi
echo "pnpm $("$PNPM_BIN" --version) install --frozen-lockfile on the aube lockfile: $frozen"

if [[ "$aube_spec" != "$pnpm_spec" || "$frozen" != ok ]]; then
    echo "failed: aube writes the catalog version as the specifier of a dependency with a ranged catalog override" >&2
    exit 1
fi
echo "pass: aube keeps the catalog: specifier for a dependency with a ranged catalog override"
