#!/bin/bash
set -euo pipefail

AUBE_BIN="${AUBE_BIN:-aube}"
PNPM_BIN="${PNPM_BIN:-pnpm}"

for cmd in "$AUBE_BIN" "$PNPM_BIN" grep; do
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

# outer/ is a project; outer/staging/ is an empty directory inside it.
setup() {
    rm -rf "$work"
    mkdir "$work"
    cp -r fixture/. "$work/"
    mkdir "$work/outer/staging"
}

# Prints which manifest received the dependency.
landed_in() {
    if grep -q '"dep"' "$work/outer/package.json"; then
        echo "outer/package.json"
    elif grep -qs '"dep"' "$work/outer/staging/package.json"; then
        echo "outer/staging/package.json"
    else
        echo "nowhere"
    fi
}

setup
"$PNPM_BIN" add "file:$work/dep" --dir "$work/outer/staging" >/dev/null
if [[ "$(landed_in)" != "outer/staging/package.json" ]]; then
    echo "control failed: pnpm --dir put the dependency in $(landed_in)" >&2
    exit 2
fi
echo "pnpm $("$PNPM_BIN" --version) add --dir outer/staging: outer/staging/package.json"

fail=0
for flag in -C --dir --prefix; do
    setup
    if ! "$AUBE_BIN" add "file:$work/dep" "$flag" "$work/outer/staging" \
        --reporter append-only >"$work/aube.log" 2>&1; then
        echo "aube add $flag failed:" >&2
        cat "$work/aube.log" >&2
        fail=1
        continue
    fi
    where="$(landed_in)"
    echo "aube add $flag outer/staging: $where"
    if [[ "$where" != "outer/staging/package.json" ]]; then
        fail=1
    fi
done

if ((fail)); then
    echo "failed: aube walked up from the -C/--dir/--prefix directory to an ancestor package.json" >&2
    exit 1
fi
echo "pass: aube adds into the -C/--dir/--prefix directory, like pnpm --dir"
