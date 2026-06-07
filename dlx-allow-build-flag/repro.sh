#!/bin/bash
set -euo pipefail

pnpm_bin="${AUBE_REPRO_PNPM:-pnpm}"

for tool in aube "$pnpm_bin"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "missing required tool: $tool" >&2
        exit 2
    fi
done

work_dir=".repro-work"
rm -rf "$work_dir"
mkdir -p "$work_dir"

echo "aube: $(aube --version 2>/dev/null | head -n 1)"
echo "pnpm: $("$pnpm_bin" --version)"
echo

echo "Checking pnpm accepts the documented dlx flag..."
pnpm_output="$work_dir/pnpm.out"
npm_config_store_dir="$PWD/$work_dir/pnpm-store" \
    "$pnpm_bin" dlx --allow-build=esbuild vite --version >"$pnpm_output" 2>&1
cat "$pnpm_output"
echo

echo "Checking aube accepts the same dlx flag..."
aube_output="$work_dir/aube.out"
set +e
AUBE_CACHE_DIR="$PWD/$work_dir/aube-cache" \
    aube dlx --allow-build=esbuild vite --version >"$aube_output" 2>&1
aube_status=$?
set -e
cat "$aube_output"

if [[ "$aube_status" -eq 0 ]]; then
    echo
    echo "aube accepted the pnpm-compatible dlx flag."
    exit 0
fi

if grep -q -- "registry error for --allow-build=esbuild" "$aube_output"; then
    echo
    echo "Observed issue: aube treated --allow-build=esbuild as the dlx package."
    exit 1
fi

echo
echo "aube failed for an unexpected reason."
exit "$aube_status"
