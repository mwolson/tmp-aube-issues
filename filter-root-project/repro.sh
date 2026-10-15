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

# single/ is a lone project named app; workspace/ is a pnpm workspace whose
# root project is named root, with one member.
setup() {
    rm -rf "$work"
    mkdir "$work"
    cp -r fixture/. "$work/"
}

# Runs `<bin> --filter <name> run hello` in <dir> and checks for <expected>.
check() {
    local bin=$1 dir=$2 name=$3 expected=$4
    setup
    if (cd "$work/$dir" && "$bin" --filter "$name" run hello) >"$work/out.log" 2>&1 &&
        grep -q "$expected" "$work/out.log"; then
        return 0
    fi
    return 1
}

for case in "single app" "workspace root"; do
    read -r dir name <<<"$case"
    if ! check "$PNPM_BIN" "$dir" "$name" "hello from $name"; then
        echo "control failed: pnpm --filter $name run hello in $dir/:" >&2
        cat "$work/out.log" >&2
        exit 2
    fi
    echo "pnpm $("$PNPM_BIN" --version) --filter $name run hello in $dir/: hello from $name"
done

fail=0
for case in "single app" "workspace root"; do
    read -r dir name <<<"$case"
    if check "$AUBE_BIN" "$dir" "$name" "hello from $name"; then
        echo "aube --filter $name run hello in $dir/: hello from $name"
    else
        echo "aube --filter $name run hello in $dir/ failed:" >&2
        grep -v '^$' "$work/out.log" >&2
        fail=1
    fi
done

if ((fail)); then
    echo "failed: aube --filter cannot select the root project by name" >&2
    exit 1
fi
echo "pass: aube --filter selects the root project by name, like pnpm"
