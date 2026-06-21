#!/bin/bash
set -euo pipefail

if ! command -v aube >/dev/null 2>&1; then
    echo "missing required tool: aube" >&2
    exit 2
fi

cd "$(dirname "$0")"

work_dir=".repro-work"
rm -rf "$work_dir"
mkdir -p "$work_dir"

export AUBE_HOME="$PWD/$work_dir/aube-home"
export AUBE_CACHE_DIR="$PWD/$work_dir/aube-cache"

echo "aube: $(aube --version)"
echo

echo "Installing an intentionally old global package..."
aube add -g is-positive@1.0.0 --reporter append-only
echo

echo "Installed global packages:"
aube list -g --json
echo

echo "Checking global outdated support..."
aube_output="$work_dir/aube-outdated-global.out"
set +e
aube outdated -g >"$aube_output" 2>&1
aube_status=$?
set -e
cat "$aube_output"

if grep -q -- "unexpected argument '-g'" "$aube_output"; then
    echo
    echo "Observed issue: aube rejects outdated -g instead of checking global packages."
    exit 1
fi

if [[ "$aube_status" -eq 0 || "$aube_status" -eq 1 ]]; then
    if grep -q -- "Package[[:space:]]\+Current[[:space:]]\+Wanted[[:space:]]\+Latest" "$aube_output"; then
        echo
        echo "aube accepted outdated -g and reported global package versions."
        exit 0
    fi
fi

echo
echo "aube failed for an unexpected reason."
exit "$aube_status"
