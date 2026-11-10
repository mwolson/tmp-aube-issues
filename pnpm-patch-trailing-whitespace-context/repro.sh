#!/bin/bash
set -euo pipefail

# patches/is-number@7.0.0.patch carries the context line
# "| **Commits** | **Contributor** |" without the trailing space the
# published README.md has, as an editor that strips trailing whitespace
# would save it. pnpm compares patch lines with trailing whitespace trimmed,
# so pnpm 12.14.0 applies it; aube rejects the hunk.

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

patched() {
    grep -q 'jonschlinkert) (patched) |' "$1/node_modules/is-number/README.md" 2>/dev/null
}

pnpm_dir="$work/pnpm"
cp -r fixture "$pnpm_dir"
if ! (cd "$pnpm_dir" && "$PNPM_BIN" install --ignore-scripts >"$pnpm_dir.log" 2>&1) || ! patched "$pnpm_dir"; then
    echo "control failed: pnpm $("$PNPM_BIN" --version) did not apply the patch (see $pnpm_dir.log)" >&2
    exit 2
fi
echo "pnpm $("$PNPM_BIN" --version) install: patch applied"

status=0
run_aube() {
    local label=$1 dir=$2
    shift 2
    if (cd "$dir" && "$AUBE_BIN" install --ignore-scripts "$@" >"$dir.log" 2>&1) && patched "$dir"; then
        echo "aube $label: patch applied"
    else
        echo "aube $label: failed"
        grep -m2 -E 'failed to apply|error applying' "$dir.log" | sed 's/^/    /' || true
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
    echo "failed: aube $("$AUBE_BIN" --version | head -1) rejects a patch whose context lost trailing whitespace" >&2
    exit 1
fi
echo "pass: aube applies patches whose context differs only in trailing whitespace"
